//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/3.
//

import XCTest
@testable import EventStoreDB

final class StreamAclTests: XCTestCase {
    func testSystemStreamAclEncodeAndDecode() throws {
        let acl = Stream.Acl.systemStream
        let encoder = JSONEncoder()
        XCTAssertEqual(try acl.rawValue, try encoder.encode("$systemStreamAcl"))
        
        let decoder = JSONDecoder()
        let deserializedAcl = try decoder.decode(Stream.Acl, from: acl.rawValue)
        XCTAssertEqual(deserializedAcl, acl)
    }
    
    func testUserStreamAclEncodeAndDecode() throws {
        let acl = Stream.Acl.userStream
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(acl)
    
        XCTAssertEqual(jsonData, try encoder.encode("$userStreamAcl"))
        
        let decoder = JSONDecoder()
        let deserializedAcl = try decoder.decode(Stream.Acl, from: jsonData)
        XCTAssertEqual(deserializedAcl, acl)
    }
}


