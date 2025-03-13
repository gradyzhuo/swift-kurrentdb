//
//  ProjectionsTests.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/13.
//
import Foundation
import Testing
@testable import KurrentDB

@Suite("EventStoreDB Projections Tests", .serialized)
struct ProjectionsTests: Sendable {
    
    let client: KurrentDBClient

    init() {
        client = .init(settings: .localhost())
    }
    
    
    
    @Test("Testing create a projection", arguments: [
        ("countEvents_Create", true)
    ])
    func createProjection(name: String, delete: Bool) async throws {
        
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
""";

        let projections = client.projections(mode: .continuous(name: name))
        try await projections.create(query: js)
        let details = try #require(await projections.details)
        #expect(details.name == name)
        #expect(details.mode == .continuous)
        
        
        if delete {
            try await projections.delete()
        }
    }
    
    @Test
    func disableProjection() async throws {
        let projectionName = "testProjection"
        try await createProjection(name: projectionName, delete: false)
        
        let projections = client.projections(mode: .continuous(name: projectionName))
        try await projections.disable()
        
        let details = try #require(await projections.details)
        #expect(details.status == "Faulted" || details.status == "Stopped/Faulted")
        
        try await projections.delete()
    }
    
    @Test
    func enableProjection() async throws {
        let projectionName = "testProjection_\(UUID())"
        try await createProjection(name: projectionName, delete: false)
        
        let projections = client.projections(mode: .continuous(name: projectionName))
        try await projections.disable()
        
        let details = try #require(await projections.details)
        #expect(details.status == "Aborted/Stopped" || details.status == "Stopped")
        
        try await projections.enable()
        
        let enabledDetails = try #require(await projections.details)
        #expect(enabledDetails.status == "Running")
        
        try await projections.disable()
        try await projections.delete()
    }
}
