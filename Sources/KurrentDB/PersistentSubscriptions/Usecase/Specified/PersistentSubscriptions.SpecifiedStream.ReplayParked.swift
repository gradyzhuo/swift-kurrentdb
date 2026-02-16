//
//  PersistentSubscriptions.SpecifiedStream.ReplayParked.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
    public struct ReplayParked: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.ReplayParked.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.ReplayParked.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.ReplayParked.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        let streamIdentifier: StreamIdentifier
        let group: String
        let options: Options

        init(stream streamIdentifier: StreamIdentifier, group: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }

        /// Constructs the underlying gRPC request message for replaying parked events on a specified stream.
        ///
        /// - Returns: The constructed gRPC request message.
        /// - Throws: An error if building the stream identifier fails.
        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.replayParked(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.SpecifiedStream.ReplayParked {
    public struct Options: CommandOptions {
        public enum StopAtOption: Sendable {
            case position(position: Int64)
            case noLimit
        }

        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var stopAt: StopAtOption

        public init() {
            stopAt = .noLimit
        }

        /// Returns a copy of the options with the specified stopping position or limit set.
        ///
        /// - Parameter stopAt: The stopping position or limit for replaying parked events.
        /// - Returns: A new `Options` instance with the updated `stopAt` value.
        @discardableResult
        public func stopAt(_ stopAt: StopAtOption) -> Self {
            withCopy { options in
                options.stopAt = stopAt
            }
        }

        /// Constructs the underlying gRPC options message for replaying parked events.
        ///
        /// Sets the `all` field and configures either `noLimit` or `stopAt` based on the current stop option.
        ///
        /// - Returns: The configured gRPC options message.
        package func build() -> UnderlyingMessage {
            .with {
                switch stopAt {
                case .noLimit:
                    $0.noLimit = .init()
                case let .position(position):
                    $0.stopAt = position
                }
            }
        }
    }
}
