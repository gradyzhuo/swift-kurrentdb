//
//  KurrentError.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/15.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCProtobuf
import NIO

public enum KurrentError: Error, Sendable {
    case serverError(String)
    case notLeaderException
    case connectionClosed
    case grpc(code: GoogleRPCStatus?, reason: String)
    case grpcError(cause: RPCError)
    case grpcRuntimeError(cause: RuntimeError)
    case grpcConnectionError(cause: RPCError)
    case internalParsingError(reason: String)
    case accessDenied
    case resourceAlreadyExists
    case resourceNotFound(reason: String)
    case resourceDeleted
    case unservicableEventLink(link: RecordedEvent)
    case unsupportedFeature
    case internalClientError(reason: String)
    case deadlineExceeded
    case initializationError(reason: String)
    case illegalStateError(reason: String)
    case wrongExpectedVersion(expected: ExpectedRevisionOption, current: CurrentRevisionOption)
    case subscriptionTerminated(subscriptionId: String?)
    case encodingError(message: String, encoding: String.Encoding)
    case decodingError(cause: DecodingError)
}

extension KurrentError: CustomStringConvertible, CustomDebugStringConvertible {
    public var debugDescription: String {
        description
    }

    public var description: String {
        switch self {
        case let .serverError(reason):
            "Server-side \(reason)"
        case .notLeaderException:
            "You tried to execute a command that requires a leader node on a follower node."
        case .connectionClosed:
            "Connection is closed."
        case let .grpc(code, reason):
            "Unmapped gRPC error: code: \(String(describing: code)), reason: \(reason)."
        case let .grpcError(cause):
            "Unmapped gRPC error. \(cause.message)"
        case let .grpcRuntimeError(cause):
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
        case let .unservicableEventLink(link):
            "The linked event \(link.id) you asked is unservicable, may be because it was deleted."
        case .unsupportedFeature:
            "The operation is unsupported by the server"
        case let .internalClientError(reason):
            "Unexpected internal client error. Please fill an issue on GitHub. reason: \(reason)"
        case .deadlineExceeded:
            "Deadline exceeded"
        case let .initializationError(reason):
            "Initialization error: \(reason)"
        case let .illegalStateError(reason):
            "Illegal state error: \(reason)"
        case let .wrongExpectedVersion(expected, current):
            "Wrong expected version '\(expected)' but got '\(current)'."
        case let .subscriptionTerminated(subscriptionId):
            "User terminate subscription manually with subscriptionId: \(String(describing: subscriptionId))"
        case let .encodingError(message: message, encoding: encoding):
            "Encoding error \(message) by encoding: \(encoding)"
        case let .decodingError(cause):
            "Decoding error: \(cause)"
        }
    }
}

extension KurrentError: Equatable {
    public static func == (lhs: KurrentError, rhs: KurrentError) -> Bool {
        lhs.description == rhs.description
    }

    var name: String {
        switch self {
        case .accessDenied:
            "AccessDenied"
        case .internalClientError:
            "InternalClientError"
        case .connectionClosed:
            "ConnectionClosed"
        case .unsupportedFeature:
            "UnsupportedFeature"
        case .deadlineExceeded:
            "DeadlineExceeded"
        case .decodingError:
            "DecodingError"
        case .encodingError:
            "EncodingError"
        case .grpc:
            "GRPC"
        case .grpcConnectionError:
            "GRPCConnectionError"
        case .grpcError:
            "GRPCError"
        case .grpcRuntimeError:
            "GRPCRuntimeError"
        case .illegalStateError:
            "IllegalStateError"
        case .notLeaderException:
            "NotLeaderException"
        case .initializationError:
            "InitializationError"
        case .internalParsingError:
            "InternalParsingError"
        case .resourceAlreadyExists:
            "ResourceAlreadyExists"
        case .resourceNotFound:
            "ResourceNotFound"
        case .serverError:
            "ServerError"
        case .subscriptionTerminated:
            "SubscriptionTerminated"
        case .wrongExpectedVersion:
            "WrongExpectedVersion"
        case .resourceDeleted:
            "ResourceDeleted"
        case .unservicableEventLink:
            "UnservicableEventLink"
        }
    }
}

func withRethrowingError<T>(usage: String, action: @Sendable () async throws -> T) async throws(KurrentError) -> T {
    do {
        return try await action()
    } catch let error as KurrentError {
        throw error
    } catch let error as RPCError {
        try error.rethrow(usage: usage, origin: error)
    } catch {
        throw .internalClientError(reason: "`\(usage)` failed. full error: \(error)")
    }
    throw .internalClientError(reason: "`\(usage)` failed.")
}

func withRethrowingError<T>(usage: String, action: @Sendable () throws -> T) throws(KurrentError) -> T {
    do {
        return try action()
    } catch let error as KurrentError {
        throw error
    } catch let error as RPCError {
        try error.rethrow(usage: usage, origin: error)
    } catch {
        throw .internalClientError(reason: "`\(usage)` failed. full error: \(error).")
    }
    throw .internalClientError(reason: "`\(usage)` failed.")
}

extension Error where Self: Equatable {
    public func rethrow(usage: String) throws(KurrentError) {
        throw .internalClientError(reason: "\(usage) failed.")
    }
}

extension RPCError {
    func rethrow(usage: String, origin _: any Error) throws(KurrentError) {
        if let cause = cause as? NIOCore.IOError {
            try cause.rethrow(usage: usage, origin: self)
        } else {
            throw .grpcError(cause: self)
        }
    }
}

extension IOError {
    func rethrow(usage: String, origin: RPCError) throws(KurrentError) {
        switch errnoCode {
        case 61:
            throw .grpcConnectionError(cause: origin)
        default:
            throw .internalClientError(reason: "`\(usage)` failed, full error: \(origin).")
        }
    }
}
