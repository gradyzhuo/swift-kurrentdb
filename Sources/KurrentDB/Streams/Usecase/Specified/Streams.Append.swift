//
//  StreamClient.Append.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/22.
//
import GRPCCore
import GRPCEncapsulates

extension Streams {
    public struct Append: StreamUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Append.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Append.Output

        public let events: [EventData]
        public let identifier: StreamIdentifier
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

        package func send(client: ServiceClient, request: StreamingClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.append(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Streams.Append {
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        public let currentRevision: UInt64?
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
                let response = WrongExpectedVersionResponse(from: wrongResult)
                throw .wrongExpectedVersion(expected: response.excepted, current: response.current, requested: response.requested)
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
    public struct WrongExpectedVersionResponse: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse.WrongExpectedVersion

        public enum ExpectedRevisionOption: Sendable {
            case any
            case streamExists
            case noStream
            case revision(UInt64)
        }

        public let current: UInt64
        public let excepted: UInt64
        public let requested: StreamRevision

        init(current: UInt64, excepted: UInt64, requested: StreamRevision) {
            self.current = current
            self.excepted = excepted
            self.requested = requested
        }

        package init(from message: UnderlyingMessage) {
            let requestedRevision: StreamRevision? = message.expectedRevisionOption.map {
                switch $0 {
                case .expectedAny:
                    .any
                case .expectedNoStream:
                    .noStream
                case .expectedStreamExists:
                    .streamExists
                case let .expectedRevision(revision):
                    .at(revision)
                }
            }

            self.init(
                current: message.currentRevision,
                excepted: message.expectedRevision,
                requested: requestedRevision ?? .any
            )
        }
    }
}

extension Streams.Append {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public fileprivate(set) var expectedRevision: StreamRevision

        public init() {
            expectedRevision = .any
        }

        public func revision(expected: StreamRevision) -> Self {
            withCopy { options in
                options.expectedRevision = expected
            }
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
