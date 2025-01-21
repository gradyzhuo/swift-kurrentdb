//
//  StreamClient.Append.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2023/10/22.
//
import KurrentCore
import GRPCCore
import SwiftProtobuf
import GRPCEncapsulates

public struct Append: StreamUnary, Buildable {
    public typealias Client = Streams.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Append.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Append.Output

    public let events: [EventData]
    public let identifier: Stream.Identifier
    public private(set) var options: Options
    
    internal init(to identifier: Stream.Identifier, events: [EventData], options: Options = .init()) {
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
        
        try messages.append(contentsOf: events.map{ event in
            try UnderlyingRequest.with {
                $0.proposedMessage = try .with{
                    $0.id = .with {
                        $0.value = .string(event.id.uuidString)
                    }
                    $0.metadata = event.metadata
                    $0.data = try  event.payload.data
                    
                    if let customMetaData = event.customMetadata {
                        $0.customMetadata = customMetaData
                    }
                }
            }
        })
        
        return messages
    }

    public func send(client: Client.UnderlyingClient, request: StreamingClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.append(request: request, options: callOptions) {
            try handle(response: $0)
        }
    }
}

extension Append {
    public enum CurrentRevisionOption {
        case noStream
        case revision(UInt64)
    }

    public enum Response: GRPCResponse {
        public enum CurrentRevisionOption: Sendable {
            case noStream
            case revision(UInt64)

            public var revision: UInt64? {
                switch self {
                case let .revision(rev): rev
                case .noStream: nil
                }
            }
        }

        public typealias UnderlyingMessage = UnderlyingResponse

        case success(Success)
        case wrong(Wrong)

        public init(from message: UnderlyingMessage) throws {
            switch message.result! {
            case let .success(successResult):
                self = try .success(.init(from: successResult))
            case let .wrongExpectedVersion(wrongResult):
                self = .wrong(Append.Response.Wrong(from: wrongResult))
            }
        }

        public struct Success: GRPCResponse {
            public typealias UnderlyingMessage = UnderlyingResponse.Success

            public internal(set) var current: CurrentRevisionOption
            public internal(set) var position: Stream.Position.Option

            init(current: CurrentRevisionOption, position: Stream.Position.Option) {
                self.current = current
                self.position = position
            }

            public init(from message: UnderlyingMessage) throws {
                
                let currentRevision: CurrentRevisionOption? = message.currentRevisionOption.map {
                    return switch $0 {
                    case let .currentRevision(revision):
                        .revision(revision)
                    case .noStream:
                        .noStream
                    }
                }
                let position: Stream.Position.Option? = message.positionOption.map{
                    return switch $0 {
                    case let .position(position):
                        .position(.at(commitPosition: position.commitPosition, preparePosition: position.preparePosition))
                    case .noPosition:
                        .noPosition
                    }
                }

                self.init(
                    current: currentRevision ?? .noStream,
                    position: position ?? .noPosition)
            }
        }

        public struct Wrong: GRPCResponse, Error {
            public typealias UnderlyingMessage = UnderlyingResponse.WrongExpectedVersion

            public enum ExpectedRevisionOption: Sendable {
                case any
                case streamExists
                case noStream
                case revision(UInt64)
            }

            public internal(set) var current: CurrentRevisionOption
            public internal(set) var excepted: ExpectedRevisionOption

            init(current: CurrentRevisionOption, excepted: ExpectedRevisionOption) {
                self.current = current
                self.excepted = excepted
            }

            public init(from message: UnderlyingMessage) {
                let currentRevision: CurrentRevisionOption? = message.currentRevisionOption.map {
                    return switch $0 {
                    case let .currentRevision(revision):
                        .revision(revision)
                    case .currentNoStream:
                        .noStream
                    }
                }
                
                let expectedRevision: ExpectedRevisionOption?  = message.expectedRevisionOption.map{
                    return switch $0 {
                    case .expectedAny:
                        .any
                    case .expectedNoStream:
                        .noStream
                    case .expectedStreamExists:
                        .streamExists
                    case let .expectedRevision(revision):
                        .revision(revision)
                    }
                }

                self.init(
                    current: currentRevision ?? .noStream,
                    excepted: expectedRevision ?? .any)
            }
        }
    }
}

extension Stream.Identifier {
    func build(options: inout Append.UnderlyingRequest.Options) throws {
        options.streamIdentifier = try build()
    }
}

extension Append {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public fileprivate(set) var expectedRevision: Stream.RevisionRule

        public init() {
            expectedRevision = .any
        }

        public func revision(expected: Stream.RevisionRule) -> Self {
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
                case let .revision(rev):
                    $0.revision = rev
                }
            }
        }
    }
}

extension Append {
    public func revision(expected revision: Stream.RevisionRule) -> Self {
        withCopy { usecase in
            usecase.options.expectedRevision = revision
        }
    }
}
