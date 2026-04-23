//
//  StreamClient.Append.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/22.
//
import GRPCCore
import GRPCEncapsulates

extension Streams {
    /// Usecase that appends one or more events to a single named stream.
    public struct Append: StreamUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Append.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Append.Output

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Append.descriptor
        }

        package static var name: String {
            "Streams.\(Self.self)"
        }

        /// Events to be appended to the stream.
        public let events: [EventData]
        /// Identifier of the target stream.
        public let identifier: StreamIdentifier
        /// Options controlling the append behaviour (e.g. expected revision).
        public private(set) var options: Options

        init(to identifier: StreamIdentifier, events: [EventData], options: Options = .init()) {
            self.events = events
            self.options = options
            self.identifier = identifier
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
            var messages: [UnderlyingRequest] = []
            let optionMessage = try UnderlyingRequest.with {
                $0.options = options.build()
                $0.options.streamIdentifier = try identifier.build()
            }
            messages.append(optionMessage)

            try messages.append(contentsOf: events.map { event in
                try UnderlyingRequest.with {
                    $0.proposedMessage = try .with {
                        $0.id = .with {
                            $0.value = .string(event.id.uuidString)
                        }
                        $0.metadata = event.metadata
                        $0.data = try event.payload.data

                        if let customMetaData = event.customMetadata {
                            $0.customMetadata = customMetaData
                        }
                    }
                }
            })

            return messages
        }

        package func send(connection: GRPCClient<Transport>, request: StreamingClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.append(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Streams.Append {
    /// Response returned after a successful append operation.
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        /// Revision of the stream after the append, or `nil` if the stream no longer exists.
        public let currentRevision: UInt64?
        /// Global log position of the append, or `nil` when unavailable.
        public let position: StreamPosition?

        init(currentRevision: UInt64?, position: StreamPosition?) {
            self.currentRevision = currentRevision
            self.position = position
        }

        package init(from message: UnderlyingMessage) throws(KurrentError) {
            guard let result = message.result else {
                throw .initializationError(reason: "The result of appending usecase is missing.")
            }
            switch result {
            case let .success(successResult):
                self.init(from: successResult)
            case let .wrongExpectedVersion(wrongResult):
                throw .wrongExpectedVersion(wrongResult)
            }
        }

        package init(from message: UnderlyingMessage.Success) {
            let currentRevision: UInt64? = message.currentRevisionOption.flatMap {
                switch $0 {
                case let .currentRevision(revision):
                    revision
                case .noStream:
                    nil
                }
            }
            let position: StreamPosition? = message.positionOption.flatMap {
                switch $0 {
                case let .position(position):
                    .at(commitPosition: position.commitPosition, preparePosition: position.preparePosition)
                case .noPosition:
                    nil
                }
            }

            self.init(
                currentRevision: currentRevision,
                position: position
            )
        }
    }
}

extension Streams.Append {
    /// Options that control append behaviour.
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// Expected stream revision used for optimistic concurrency checks.
        public var expectedRevision: StreamRevision

        /// Initialises options with `expectedRevision` set to `.any`.
        public init() {
            expectedRevision = .any
        }

        package func build() -> UnderlyingMessage {
            .with {
                switch expectedRevision {
                case .any:
                    $0.any = .init()
                case .noStream:
                    $0.noStream = .init()
                case .streamExists:
                    $0.streamExists = .init()
                case let .at(revision):
                    $0.revision = revision
                }
            }
        }
    }
}
