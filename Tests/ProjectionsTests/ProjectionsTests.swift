//
//  ProjectionsTests.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/13.
//

import Foundation
import GRPCCore
@testable import KurrentDB
import Testing

struct CountResult: Codable {
    let count: Int
}

@Suite("EventStoreDB Projections Tests", .serialized)
struct ProjectionsTests: Sendable {
    let client: KurrentDBClient

    init() {
        let settings: ClientSettings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        client = .init(settings: settings)
    }

    @Test("Testing create a continuous projection")
    func createContinuousProjection() async throws {
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

        try await client.projections(of: .continuous(name: name)).create(query: js)
        let details = try #require(try await client.projections(of: NameTarget(name: name)).detail())
        #expect(details.name == name)
        #expect(details.mode == .continuous)

        try await client.projections(of: NameTarget(name: name)).disable()
        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    @Test("Testing create a onetime projection")
    func createOneTimeProjection() async throws {
        let projection = client.projections(of: .onetime)
        let originOneTimeProjections = try await projection.list()
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

        try await projection.create(query: js)

        let projections = try await projection.list()
        #expect(projections.count == (originOneTimeProjections.count + 1))
    }

    @Test("Disable a projection")
    func disableProjection() async throws {
        let projectionName = "testDisableProjection_\(UUID())"
        try await client.projections(of: .continuous(name: projectionName)).create(query: "fromAll().outputState()")

        try await client.projections(of: NameTarget(name: projectionName)).disable()

        let details = try #require(try await client.projections(of: NameTarget(name: projectionName)).detail())
        #expect(details.status.contains(.stopped))

        try await client.projections(of: NameTarget(name: projectionName)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    @Test("Enable a projection")
    func enableProjection() async throws {
        let projectionName = "testEnableProjection_\(UUID())"
        try await client.projections(of: .continuous(name: projectionName)).create(query: "fromAll().outputState()")

        try await client.projections(of: NameTarget(name: projectionName)).disable()

        let details = try #require(try await client.projections(of: NameTarget(name: projectionName)).detail())
        #expect(details.status.contains(.stopped))

        try await client.projections(of: NameTarget(name: projectionName)).enable()

        let enabledDetails = try #require(try await client.projections(of: NameTarget(name: projectionName)).detail())
        #expect(enabledDetails.status.contains(.running))

        try await client.projections(of: NameTarget(name: projectionName)).disable()
        try await client.projections(of: NameTarget(name: projectionName)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    @Test("Abort a projection")
    func abortProjection() async throws {
        let projectionName = "testEnableProjection_\(UUID())"
        try await client.projections(of: .continuous(name: projectionName)).create(query: "fromAll().outputState()")

        try await client.projections(of: NameTarget(name: projectionName)).abort()

        let details = try #require(try await client.projections(of: NameTarget(name: projectionName)).detail())
        #expect(details.status.contains(.aborted))

        try await client.projections(of: NameTarget(name: projectionName)).reset()

        let enabledDetails = try #require(try await client.projections(of: NameTarget(name: projectionName)).detail())
        #expect(enabledDetails.status.contains(.stopped))

        try await client.projections(of: NameTarget(name: projectionName)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    @Test("Get projection status for a system projection")
    func getStatusExample() async throws {
        let detail = try #require(try await client.projections(of: NameTarget(predefined: .byCategory)).detail())
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

        try await client.streams(specified: streamName).append(events: [
            .init(eventType: "ProjectionEventCreated", model: ["hello": "world"]),
        ]) { $0.expectedRevision = .any }

        try await client.projections(of: .continuous(name: name)).create(query: js)

        try await Task.sleep(for: .microseconds(500)) // Give it some time to process and have a state.

        let state = try #require(try await client.projections(of: NameTarget(name: name)).state(of: CountResult.self))
        #expect(state.count == 1)

        try await client.streams(specified: streamName).delete()
        try await client.projections(of: NameTarget(name: name)).disable()
        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
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

        try await client.streams(specified: streamName).append(events: [
            .init(eventType: "ProjectionEventCreated", model: ["hello": "world"]),
        ]) { $0.expectedRevision = .any }

        try await client.projections(of: .continuous(name: name)).create(query: js)

        try await Task.sleep(for: .microseconds(500)) // Give it some time to process and have a result.

        let result = try #require(try await client.projections(of: NameTarget(name: name)).result(of: Int.self))
        #expect(result == 1)

        try await client.streams(specified: streamName).delete()
        try await client.projections(of: NameTarget(name: name)).disable()
        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    @Test("List continuous projections via UnspecifiedContinuousProjectionTarget")
    func listContinuousProjections() async throws {
        let name = "test_listContinuous_\(UUID())"
        try await client.projections(of: .continuous(name: name)).create(query: "fromAll().outputState()")

        let projections = try await client.projections(of: .anyContinuous).list()
        #expect(projections.contains { $0.name == name })

        try await client.projections(of: NameTarget(name: name)).disable()
        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    @Test("List transient projections via UnspecifiedTransientProjectionTarget")
    func listTransientProjections() async throws {
        let name = "test_listTransient_\(UUID())"
        try await client.projections(of: .transient(name: name)).create(query: "fromAll().outputState()")

        let projections = try await client.projections(of: .anyTransient).list()
        #expect(projections.contains { $0.name == name })
    }

    @Test("Status parsing from string", arguments: [
        ("Aborted/Stopped", [Projection.Status.Name.aborted, Projection.Status.Name.stopped]),
        ("Stopped/Faulted", [Projection.Status.Name.stopped, Projection.Status.Name.faulted]),
        ("Stopped", [Projection.Status.Name.stopped]),
    ])
    func multistatus(status: String, names: [Projection.Status.Name]) async throws {
        #expect(Projection.Status(rawValue: status).contains(names))
    }
}
