//
//  ServerError.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/15.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCProtobuf

public enum EventStoreError: Error, Sendable {
    case serverError(String)
    case notLeaderException(endpoint: Endpoint)
    case connectionClosed
    case grpc(code: GoogleRPCStatus, reason: String)
    case grpcConnectionError(error: GoogleRPCStatus)
    case internalParsingError(reason: String)
    case accessDenied
    case resourceAlreadyExists
    case resourceNotFound(reason: String)
    case resourceDeleted
    case unsupportedFeature
    case internalClientError
    case deadlineExceeded
    case initializationError(reason: String)
    case illegalStateError(reason: String)
    case WrongExpectedVersion(expected: StreamRevision, current: StreamRevision)
}

extension EventStoreError: CustomStringConvertible, CustomDebugStringConvertible {
    public var debugDescription: String {
        description
    }

    public var description: String {
        switch self {
        case let .serverError(reason):
            "Server-side error: \(reason)"
        case let .notLeaderException(endpoint):
            "You tried to execute a command that requires a leader node on a follower node. New leader: \(endpoint.host):\(endpoint.port)"
        case .connectionClosed:
            "Connection is closed."
        case let .grpc(code, reason):
            "Unmapped gRPC error: code: \(code), reason: \(reason)."
        case let .grpcConnectionError(error):
            "gRPC connection error: \(error)"
        case let .internalParsingError(reason):
            "Internal parsing error: \(reason)"
        case .accessDenied:
            "Access denied error"
        case .resourceAlreadyExists:
            "The resource you tried to create already exists"
        case let .resourceNotFound(reason):
            "The resource you asked for doesn't exist, reason: \(reason)"
        case .resourceDeleted:
            "The resource you asked for was deleted"
        case .unsupportedFeature:
            "The operation is unsupported by the server"
        case .internalClientError:
            "Unexpected internal client error. Please fill an issue on GitHub"
        case .deadlineExceeded:
            "Deadline exceeded"
        case let .initializationError(reason):
            "Initialization error: \(reason)"
        case let .illegalStateError(reason):
            "Illegal state error: \(reason)"
        case let .WrongExpectedVersion(expected, current):
            "Wrong expected version: expected '\(expected)' but got '\(current)'"
        }
    }
}
