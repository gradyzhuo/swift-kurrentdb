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

public enum KurrentError: Error, Sendable {
    case serverError(String, cause: any Error)
    case notLeaderException(endpoint: Endpoint)
    case connectionClosed
    case grpc(code: GoogleRPCStatus?, reason: String)
    case grpcRuntimeError(cause: RuntimeError)
    case grpcConnectionError(error: GoogleRPCStatus)
    case internalParsingError(reason: String)
    case accessDenied
    case resourceAlreadyExists
    case resourceNotFound(reason: String)
    case resourceDeleted
    case unsupportedFeature
    case internalClientError(reasone: String, cause: any Error)
    case deadlineExceeded
    case initializationError(reason: String)
    case illegalStateError(reason: String)
    case WrongExpectedVersion(expected: StreamRevision, current: StreamRevision)
    case subscriptionTerminated(subscriptionId: String?, origin: (any Error)?)
    case encodingError(message: String, encoding: String.Encoding)
    case decodingError(cause: DecodingError)
}

extension KurrentError: CustomStringConvertible, CustomDebugStringConvertible {
    public var debugDescription: String {
        description
    }

    public var description: String {
        switch self {
        case let .serverError(reason, cause):
            "Server-side \(reason) error: \(cause)"
        case let .notLeaderException(endpoint):
            "You tried to execute a command that requires a leader node on a follower node. New leader: \(endpoint.host):\(endpoint.port)"
        case .connectionClosed:
            "Connection is closed."
        case let .grpc(code, reason):
            "Unmapped gRPC error: code: \(String(describing: code)), reason: \(reason)."
        case .grpcRuntimeError(let cause):
            "Unmapped gRPC error: \(cause)."
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
        case .subscriptionTerminated(let subscriptionId, let originError):
            "User terminate subscription manually with subscriptionId: \(String(describing: subscriptionId)), originError: \(String(describing: originError))"
        case .encodingError(message: let message, encoding: let encoding):
            "Encoding error \(message) by encoding: \(encoding)"
        case .decodingError(let cause):
            "Decoding error: \(cause)"
        }
    }
}
