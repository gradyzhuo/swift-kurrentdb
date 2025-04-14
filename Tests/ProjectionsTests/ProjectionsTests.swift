//
//  ProjectionsTests.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/13.
//

import Foundation
import Testing
import GRPCCore
@testable import KurrentDB

struct CountResult: Codable {
    let count: Int
}

@Suite("EventStoreDB Projections Tests", .serialized)
struct ProjectionsTests: Sendable {
    let client: KurrentDBClient

    init() {
        client = .init(settings: .localhost())
    }
    
    @Test("Testing create a projection")
    func createProjection() async throws {
        let name = "test_countEvents_Create_\(UUID())"
        let js = """
fromAll()
    .when({
        $init: function() {
            return {
                count: 0
            };
        },
        $any: function(s, e) {
            s.count += 1;
        }
    })
    .outputState();
"""
        
        try await client.createContinuousProjection(name: name, query: js)
        
        let details = try #require(await client.getProjectionDetail(name: name))
        #expect(details.name == name)
        #expect(details.mode == .continuous)
        
        try await client.disableProjection(name: name)
        try await client.deleteProjection(name: name) {
            $0.delete(checkpointStream: true).delete(stateStream: true).delete(emittedStreams: true)
        }
    }
    
    @Test("Disable a projection")
    func disableProjection() async throws {
        let projectionName = "testDisableProjection_\(UUID())"
        try await client.createContinuousProjection(name: projectionName, query: "fromAll().outputState()")
        
        try await client.disableProjection(name: projectionName)
        
        let details = try #require(await client.getProjectionDetail(name: projectionName))
        #expect(details.status.contains(.stopped))
        
        try await client.deleteProjection(name: projectionName) {
            $0.delete(checkpointStream: true).delete(stateStream: true).delete(emittedStreams: true)
        }
    }
    
    @Test("Enable a projection")
    func enableProjection() async throws {
        let projectionName = "testEnableProjection_\(UUID())"
        try await client.createContinuousProjection(name: projectionName, query: "fromAll().outputState()")
        
        try await client.disableProjection(name: projectionName)
        
        let details = try #require(await client.getProjectionDetail(name: projectionName))
        #expect(details.status.contains(.stopped))
        
        try await client.enableProjection(name: projectionName)
        
        let enabledDetails = try #require(await client.getProjectionDetail(name: projectionName))
        #expect(enabledDetails.status == .running)
        
        try await client.disableProjection(name: projectionName)
        try await client.deleteProjection(name: projectionName) {
            $0.delete(checkpointStream: true).delete(stateStream: true).delete(emittedStreams: true)
        }
    }
    
    @Test("Abort a projection")
    func abortProjection() async throws {
        let projectionName = "testEnableProjection_\(UUID())"
        try await client.createContinuousProjection(name: projectionName, query: "fromAll().outputState()")
        
        try await client.abortProjection(name: projectionName)
        
        let details = try #require(await client.getProjectionDetail(name: projectionName))
        #expect(details.status.contains(.aborted))
        
        try await client.resetProjection(name: projectionName)
        
        let enabledDetails = try #require(await client.getProjectionDetail(name: projectionName))
        #expect(enabledDetails.status == .stopped)
    
        try await client.deleteProjection(name: projectionName) {
            $0.delete(checkpointStream: true).delete(stateStream: true).delete(emittedStreams: true)
        }
    }
    
    @Test("Get projection status for a system projection")
    func getStatusExample() async throws {
        let detail = try #require(await client.getProjectionDetail(name: SystemProjectionTarget.Predefined.byCategory.rawValue))
        print("\(detail.name), \(detail.status), \(detail.checkpointStatus), \(detail.mode), \(detail.progress)")
    }
    
    @Test("Get projection state")
    func getStateExample() async throws {
        let name = "get_state_example_\(UUID())"
        let streamName = "test-forProjection"
        let js = """
        fromStream('\(streamName)')
            .when({
                $init: function() {
                    return {
                        count: 0
                    };
                },
                $any: function(s, e) {
                    s.count += 1;
                }
            })
            .outputState();
        """
        
        try await client.appendStream(on: StreamIdentifier(name: streamName), events: [
            .init(eventType: "ProjectionEventCreated", model: ["hello":"world"])
        ])

        try await client.createContinuousProjection(name: name, query: js)

        try await Task.sleep(for: .microseconds(500)) // Give it some time to process and have a state.
        
        let state = try #require(await client.getProjectionState(of: CountResult.self, name: name))
        #expect(state.count == 1)
        
        try await client.deleteStream(on: StreamIdentifier(name: streamName))
        try await client.disableProjection(name: name)
        try await client.deleteProjection(name: name) {
            $0.delete(checkpointStream: true).delete(stateStream: true).delete(emittedStreams: true)
        }
    }
    
    @Test("Get projection result")
    func getResultExample() async throws {
        let name = "get_result_example_\(UUID())"
        let streamName = "test-forProjection"
        let js = """
            fromStream('\(streamName)')
            .when({
                $init() {
                    return {
                        count: 0,
                    };
                },
                $any(s, e) {
                    s.count += 1;
                }
            })
            .transformBy((state) => state.count)
            .outputState();
        """

        try await client.appendStream(on: StreamIdentifier(name: streamName), events: [
            .init(eventType: "ProjectionEventCreated", model: ["hello":"world"])
        ])
        
        try await client.createContinuousProjection(name: name, query: js)
        
        try await Task.sleep(for: .microseconds(500)) // Give it some time to process and have a result.
        
        let result = try #require(await client.getProjectionResult(of: Int.self, name: name))
        #expect(result == 1)
        
        try await client.deleteStream(on: StreamIdentifier(name: streamName))
        try await client.disableProjection(name: name)
        try await client.deleteProjection(name: name) {
            $0.delete(checkpointStream: true).delete(stateStream: true).delete(emittedStreams: true)
        }
    }
    
    @Test("Status parsing from string", arguments: [
        ("Aborted/Stopped", Projection.Status([Projection.Status.aborted, Projection.Status.stopped])),
        ("Stopped/Faulted", Projection.Status([Projection.Status.stopped, Projection.Status.faulted])),
        ("Stopped", Projection.Status.stopped)
    ])
    func multistatus(name: String, status: Projection.Status) async throws {
        let status = try #require(Projection.Status(name: name))
        #expect(status.contains(status))
    }
}
