//
//  StreamClient.ReadAll.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/3.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

extension Streams {
    public struct ReadAll: UnaryStream {
        package typealias ServiceClient = Client
        public typealias Options = Read.Options
        package typealias UnderlyingRequest = Read.UnderlyingRequest
        package typealias UnderlyingResponse = Read.UnderlyingResponse
        package typealias Response = Read.Response
        package typealias Responses = AsyncThrowingStream<Response, Error>
        
        public let cursor: Cursor<CursorPointer>
        public let options: Options
        
        internal init(cursor: Cursor<CursorPointer>, options: Options) {
            self.cursor = cursor
            self.options = options
        }
        
        package func requestMessage() throws -> UnderlyingRequest {
            return .with {
                $0.options = options.build()
                
                switch cursor {
                case .start:
                    $0.options.all.start = .init()
                    $0.options.readDirection = .forwards
                case .end:
                    $0.options.all.end = .init()
                    $0.options.readDirection = .backwards
                case let .specified(pointer):
                    $0.options.all.position = .with {
                        $0.commitPosition = pointer.position.commit
                        $0.preparePosition = pointer.position.prepare
                    }

                    if case .forward = pointer.direction {
                        $0.options.readDirection = .forwards
                    } else {
                        $0.options.readDirection = .backwards
                    }
                }
            }
        }

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
            return try await withThrowingDiscardingTaskGroup { group in
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
                try await client.read(request: request, options: callOptions) {
                    for try await message in $0.messages {
                        try continuation.yield(handle(message: message))
                    }
                }
                return stream
            }
        }

    }
}

extension Streams.ReadAll {
    public struct CursorPointer: Sendable {
        let position: StreamPosition
        let direction: Direction

        public static func forwardOn(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .forward)
        }

        public static func backwardFrom(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .backward)
        }
    }
}
