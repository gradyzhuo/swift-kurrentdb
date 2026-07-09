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

/// Errors thrown by KurrentDB client operations.
public enum KurrentError: Error, Sendable {
    /// The server returned an error message not mapped to a specific case.
    case serverError(String)
    /// A leader-only command was sent to a follower node.
    case notLeaderException
    /// The gRPC connection was closed before the operation completed.
    case connectionClosed
    /// An unmapped gRPC status code was received from the server.
    case grpc(code: GoogleRPCStatus?, reason: String)
    /// A gRPC-level error occurred that is not mapped to a domain-specific case.
    case grpcError(cause: RPCError)
    /// A gRPC runtime error occurred outside of a specific RPC call.
    case grpcRuntimeError(cause: RuntimeError)
    /// The underlying transport connection to the server failed.
    case grpcConnectionError(cause: RPCError)
    /// An internal error occurred while parsing a server response.
    case internalParsingError(reason: String)
    /// The caller does not have permission to perform the requested operation.
    case accessDenied
    /// The resource (stream, projection, subscription) already exists.
    case resourceAlreadyExists
    /// The requested resource was not found on the server.
    case resourceNotFound(reason: String)
    /// The requested stream or resource has been deleted.
    case resourceDeleted(resource: String)
    /// A linked event could not be resolved, typically because it was deleted.
    case unservicableEventLink(link: RecordedEvent)
    /// The server does not support the requested gRPC method.
    case unsupportedFeature(GRPCCore.MethodDescriptor)
    /// An unexpected client-side error occurred; please file an issue on GitHub.
    case internalClientError(reason: String)
    /// The operation deadline was exceeded before the server responded.
    case deadlineExceeded
    /// Client initialization failed before any request could be made.
    case initializationError(reason: String)
    /// The client or server is in an invalid state for the requested operation.
    case illegalStateError(reason: String)
    /// The append was rejected because the stream revision did not match the expectation.
    case wrongExpectedVersion(expected: ExpectedRevisionOption, current: CurrentRevisionOption)
    /// An `AppendRecords` transaction was rejected because one or more pre-commit consistency checks
    /// failed. All failing checks are reported so stale state can be refreshed in a single round trip.
    case consistencyViolation(violations: [ConsistencyViolation])
    /// The subscription was terminated by an explicit user call.
    case subscriptionTerminated(subscriptionId: String?)
    /// The server dropped the subscription unexpectedly.
    case subscriptionDropped(reason: String, lastRevision: UInt64?, lastPosition: StreamPosition?)
    /// A string could not be encoded using the specified encoding.
    case encodingError(message: String, encoding: String.Encoding)
    /// A value could not be decoded from the server response.
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
        case let .resourceDeleted(resource):
            "The resource \(resource) you asked for was deleted"
        case let .unservicableEventLink(link):
            "The linked event \(link.id) you asked is unservicable, may be because it was deleted."
        case let .unsupportedFeature(methodDescriptor):
            "The operation \(methodDescriptor.fullyQualifiedMethod) is unsupported by the server."
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
        case let .consistencyViolation(violations):
            "AppendRecords consistency violation: \(violations.map(\.description).joined(separator: "; "))."
        case let .subscriptionTerminated(subscriptionId):
            "User terminate subscription manually with subscriptionId: \(String(describing: subscriptionId))"
        case let .subscriptionDropped(reason, lastRevision, lastPosition):
            "Subscription dropped: \(reason). Last received revision: \(lastRevision.map { String($0) } ?? "none"), position: \(lastPosition.map { "(\($0.commit), \($0.prepare))" } ?? "none")"
        case let .encodingError(message: message, encoding: encoding):
            "Encoding error \(message) by encoding: \(encoding)"
        case let .decodingError(cause):
            "Decoding error: \(cause)"
        }
    }
}

extension KurrentError {
    /// Returns `true` when the error indicates the selected node is unavailable or no longer suitable,
    /// meaning the caller should invalidate the cached node and re-discover.
    var isNodeFailure: Bool {
        switch self {
        case .grpcConnectionError, .notLeaderException, .deadlineExceeded, .grpcError, .grpcRuntimeError:
            true
        default:
            false
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
        case .subscriptionDropped:
            "SubscriptionDropped"
        case .wrongExpectedVersion:
            "WrongExpectedVersion"
        case .consistencyViolation:
            "ConsistencyViolation"
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
        try error.rethrow(usage: usage)
    } catch {
        logger.debug("'\(usage)' failed with unexpected error: \(error)")
        throw .internalClientError(reason: "`\(usage)` failed.")
    }
    throw .internalClientError(reason: "`\(usage)` failed.")
}

func withRethrowingError<T>(usage: String, action: @Sendable () throws -> T) throws(KurrentError) -> T {
    do {
        return try action()
    } catch let error as KurrentError {
        throw error
    } catch let error as RPCError {
        try error.rethrow(usage: usage)
    } catch {
        logger.debug("'\(usage)' failed with unexpected error: \(error)")
        throw .internalClientError(reason: "`\(usage)` failed.")
    }
    throw .internalClientError(reason: "`\(usage)` failed.")
}

extension Error where Self: Equatable {
    public func rethrow(usage: String) throws(KurrentError) {
        throw .internalClientError(reason: "\(usage) failed.")
    }
}

extension RPCError {
    func rethrow(usage: String) throws(KurrentError) {
        // 0. AppendRecords (v2) reports failed consistency checks as packed status details.
        if let violation = KurrentError.consistencyViolation(from: self) {
            throw violation
        }

        // 1. Check metadata exception (server-specific error types)
        if let exception = metadata.first(where: { $0.key == "exception" })?.value {
            switch exception {
            case "stream-deleted":
                let streamName = metadata.first(where: { $0.key == "stream-name" })?.value.encoded() ?? "unknown"
                throw .resourceDeleted(resource: streamName)
            default:
                break
            }
        }

        // 2. Map gRPC status codes to specific KurrentError cases
        switch code {
        case .deadlineExceeded:
            throw .deadlineExceeded
        case .unauthenticated, .permissionDenied:
            throw .accessDenied
        case .notFound:
            throw .resourceNotFound(reason: message)
        case .alreadyExists:
            throw .resourceAlreadyExists
        case .unavailable:
            if let ioError = cause as? NIOCore.IOError {
                try ioError.rethrow(usage: usage, origin: self)
            }
            throw .grpcConnectionError(cause: self)
        case .cancelled:
            throw .connectionClosed
        case .invalidArgument, .outOfRange:
            throw .illegalStateError(reason: message)
        case .internalError, .dataLoss:
            throw .serverError(message)
        default:
            // Fallback: check message content for server-embedded error type
            if message.contains("NotFound") {
                throw .resourceNotFound(reason: message)
            }
            if message.contains("Conflict") || message.contains("AlreadyExists") {
                throw .resourceAlreadyExists
            }
            // Check IOError cause (connection refused etc.)
            if let ioError = cause as? NIOCore.IOError {
                try ioError.rethrow(usage: usage, origin: self)
            }
            throw .grpcError(cause: self)
        }
    }
}

extension IOError {
    func rethrow(usage: String, origin: RPCError) throws(KurrentError) {
        switch errnoCode {
        case 61,   // macOS: ECONNREFUSED
             111:  // Linux: ECONNREFUSED
            throw .grpcConnectionError(cause: origin)
        default:
            logger.debug("'\(usage)' failed with IO error (errno: \(errnoCode)): \(origin)")
            throw .internalClientError(reason: "`\(usage)` failed.")
        }
    }
}
