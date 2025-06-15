//
//  KurrentError+WrongExpectedVersion.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/11.
//

import GRPCEncapsulates

extension KurrentError {
    package static func wrongExpectedVersion(_ wrongResult: EventStore_Client_Streams_AppendResp.WrongExpectedVersion) -> Self {
        let expectedRevision: ExpectedRevisionOption = wrongResult.expectedRevisionOption.map {
            switch $0 {
            case .expectedAny:
                .any
            case .expectedNoStream:
                .noStream
            case .expectedStreamExists:
                .streamExists
            case let .expectedRevision(revision):
                .revision(revision)
            }
        } ?? .any

        let currentRevision: CurrentRevisionOption = wrongResult.currentRevisionOption.map {
            switch $0 {
            case .currentNoStream:
                .noStream
            case let .currentRevision(revision):
                .revision(revision)
            }
        } ?? .noStream

        return .wrongExpectedVersion(expected: expectedRevision, current: currentRevision)
    }
}
