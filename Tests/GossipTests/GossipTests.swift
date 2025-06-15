//
//  GossipTests.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation
@testable import KurrentDB
import NIO
import Testing

@Suite("Gossip Tests")
struct GossipTests {
    @Test func connection() async throws {
        let address = try SocketAddress(ipAddress: "fd28:8756:87af:2:488:e1f2:820:e7d1", port: 80)
        print(address)
//        let path = Bundle.module.path(forResource: "ca", ofType: "crt")!
//        var clientSettings = try "esdb+discover://localhost:2113?tls=true&tlsCaFile=\(path)".parse()
//        print(clientSettings)
//        clientSettings.cerificate(source: .crtInBundle("ca")!)

//        let features = ServerFeatures(node: try .init(endpoint: .init(host: "localhost", port: 2111), settings: clientSettings))
//        let serviceInfo = try await features.getSupportedMethods()
//        print(serviceInfo)
//
//
//        let client = KurrentDBClient(settings: clientSettings)
//        try await client.test()

//        let gossipClient = Gossip(settings: clientSettings)
//        let members = try await gossipClient.read()
//        print("done")
//        print(members)

//        ServerFeatures(node: .init(endpoint: <#T##Endpoint#>, settings: <#T##ClientSettings#>))
    }
}
