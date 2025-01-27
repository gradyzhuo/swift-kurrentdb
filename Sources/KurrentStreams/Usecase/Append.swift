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

extension Streams {
    
    public struct Append: StreamUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Append.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Append.Output

        public let events: [EventData]
        public let identifier: StreamIdentifier
        public private(set) var options: Options
        
        internal init(to identifier: StreamIdentifier, events: [EventData], options: Options = .init()) {
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

        package func send(client: ServiceClient, request: StreamingClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.append(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Streams.Append {
    public enum Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        case success(Success)
        case wrong(Wrong)

        package init(from message: UnderlyingMessage) throws {
            switch message.result! {
            case let .success(successResult):
                self = try .success(.init(from: successResult))
            case let .wrongExpectedVersion(wrongResult):
                self = .wrong(Response.Wrong(from: wrongResult))
            }
        }

        public struct Success: GRPCResponse {
            package typealias UnderlyingMessage = UnderlyingResponse.Success

            public internal(set) var currentRevision: UInt64?
            public internal(set) var position: StreamPosition?

            init(currentRevision: UInt64?, position: StreamPosition?) {
                self.currentRevision = currentRevision
                self.position = position
            }

            package init(from message: UnderlyingMessage) throws {
                
                let currentRevision: UInt64? = message.currentRevisionOption.flatMap{
                    return switch $0 {
                    case let .currentRevision(revision):
                        revision
                    case .noStream:
                        nil
                    }
                }
                let position: StreamPosition? = message.positionOption.flatMap{
                    return switch $0 {
                    case let .position(position):
                            .at(commitPosition: position.commitPosition, preparePosition: position.preparePosition)
                    case .noPosition:
                        nil
                    }
                }
                

                self.init(
                    currentRevision: currentRevision,
                    position: position)
            }
        }

        public struct Wrong: GRPCResponse, Error {
            package typealias UnderlyingMessage = UnderlyingResponse.WrongExpectedVersion

            public enum ExpectedRevisionOption: Sendable {
                case any
                case streamExists
                case noStream
                case revision(UInt64)
            }

            public internal(set) var currentRevision: UInt64?
            public internal(set) var excepted: ExpectedRevisionOption

            init(currentRevision: UInt64?, excepted: ExpectedRevisionOption) {
                self.currentRevision = currentRevision
                self.excepted = excepted
            }

            package init(from message: UnderlyingMessage) {
                
                let currentRevision: UInt64? = message.currentRevisionOption2060.flatMap {
                    return switch $0 {
                    case let .currentRevision2060(revision):
                        revision
                    case .noStream2060(_):
                        nil
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
                    currentRevision: currentRevision,
                    excepted: expectedRevision ?? .any)
            }
        }
    }
}

extension Streams.Append {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public fileprivate(set) var expectedRevision: StreamRevision.Rule

        public init() {
            expectedRevision = .any
        }

        public func revision(expected: StreamRevision.Rule) -> Self {
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

