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

        let projections = client.projections(mode: .continuous(name: name))
        try await projections.create(query: js)
        
        let details = try #require(await projections.detail())
        #expect(details.name == name)
        #expect(details.mode == .continuous)
        
        try await projections.disable()
        try await projections.delete(deleteCheckpointStream: true, deleteEmittedStreams: true, deleteStateStream: true)
    }
    
    @Test
    func disableProjection() async throws {
        let projectionName = "testDisableProjection_\(UUID())"
        let projections = client.projections(mode: .continuous(name: projectionName))
        try await projections.create(query: "fromAll().outputState()")
        
        try await projections.disable()
        
        let details = try #require(await projections.detail())
        #expect(details.status.contains(.stopped))
        
        try await projections.delete(deleteCheckpointStream: true, deleteEmittedStreams: true, deleteStateStream: true)
    }
    
    @Test
    func enableProjection() async throws {
        let projectionName = "testEnableProjection_\(UUID())"
        let projections = client.projections(mode: .continuous(name: projectionName))
        try await projections.create(query: "fromAll().outputState()")
        
        
        try await projections.disable()
        
        let details = try #require(await projections.detail())
        #expect(details.status.contains(.stopped))
        
        try await projections.enable()
        
        let enabledDetails = try #require(await projections.detail())
        #expect(enabledDetails.status == .running)
        
        try await projections.disable()
        try await projections.delete(deleteCheckpointStream: true, deleteEmittedStreams: true, deleteStateStream: true)
        
//        try await client.streams(of: "$projections-\(projectionName)").delete()
    }
    
    @Test
    func getStatusExample() async throws {
        // by name
        let projectionClient = client.projections(mode: .continuous(name: "$by_category"))
        let detail = try #require(await projectionClient.detail())
        print("\(detail.name), \(detail.status), \(detail.checkpointStatus), \(detail.mode), \(detail.progress)")
    }
    
    @Test
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
        
        let stream = client.streams(of: .specified(streamName))
        try await stream.append(events: [
            .init(eventType: "ProjectionEventCreated", payload: ["hello":"world"])
        ])

        let projectionClient = client.projections(mode: .continuous(name: name))
        try await projectionClient.create(query: js)

        try await Task.sleep(for: .microseconds(500)) //give it some time to process and have a state.
        
        let state = try #require(await projectionClient.state(of: CountResult.self))
        #expect(state.count == 1)
        
        try await stream.delete()
        try await projectionClient.disable()
        try await projectionClient.delete(deleteCheckpointStream: true, deleteEmittedStreams: true, deleteStateStream: true)
    }
    
    @Test func getResultExample() async throws {
        let name = "get_result_example"
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

        let stream = client.streams(of: .specified(streamName))
        try await stream.append(events: [
            .init(eventType: "ProjectionEventCreated", payload: ["hello":"world"])
        ])
        
        let projection = client.projections(mode: .continuous(name: name))
        try await projection.create(query: js)

        try await Task.sleep(for: .microseconds(500)) //give it some time to process and have a state.
        
        let result = try #require(await projection.result(of: Int.self))
        #expect(result == 1)
        
        try await stream.delete()
        try await projection.disable()
        try await projection.delete(deleteCheckpointStream: true, deleteEmittedStreams: true, deleteStateStream: true)
    }
    
    @Test("status from string", arguments: [
        ("Aborted/Stopped", Projection.Status([Projection.Status.aborted, Projection.Status.stopped]) ),
        ("Stopped/Faulted", Projection.Status([Projection.Status.stopped, Projection.Status.faulted])),
        ("Stopped", Projection.Status.stopped)
    ])
    func multistatus(name: String, status: Projection.Status) async throws {
        let status = try #require(Projection.Status(name: name))
        #expect(status.contains(status))
    }

}
