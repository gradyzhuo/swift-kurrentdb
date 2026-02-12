//
//  StreamClient.Append.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/22.
//
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import SwiftProtobuf

extension Streams {
    public struct AppendSession: StreamUnary {
        package typealias ServiceClient = Kurrentdb_Protocol_V2_Streams_StreamsService.Client<HTTP2ClientTransport.Posix>
        package typealias UnderlyingRequest = Kurrentdb_Protocol_V2_Streams_StreamsService.Method.AppendSession.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.AppendSession.Output

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.AppendSession.descriptor
            }
        }

        package static var name: String{
            get{
                "Streams.\(Self.self)"
            }
        }
        
        public let streamEvents: [StreamEvent]

        init(streamEvents: [StreamEvent]) {
            self.streamEvents = streamEvents
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
            return streamEvents.map{ streamEvent in
                return .with{
                    $0.stream = streamEvent.streamIdentifier.name
                    $0.records = streamEvent.records.map{ record in
                        return .with{
                            
                            if let recordId = record.id {
                                $0.recordID = recordId.uuidString
                            }
                            
                            $0.data = record.data
                            $0.properties = record.properties.structValue.fields
                            $0.schema = .with{
                                $0.name = record.schema.name
                                $0.format = .init(rawValue: record.schema.format.rawValue) ?? .unspecified
                            }
                        }
                    }
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: StreamingClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.appendSession(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Streams.AppendSession {
    public struct Response: GRPCResponse {
        public struct Output: Sendable{
            let stream: String
            let revision: UInt64
            let position: StreamPosition
        }
        package typealias UnderlyingMessage = UnderlyingResponse

        public let output: [Output]?
        public let position: StreamPosition?

        init(output: [Output], position: StreamPosition?) {
            self.output = output
            self.position = position
        }

        package init(from message: UnderlyingMessage) throws(KurrentError) {
            let output: [Output] = message.output.map{
                .init(stream: $0.stream, revision: UInt64($0.streamRevision), position: .at(commitPosition: UInt64($0.position)))
            }
            
            self.init(output: output, position: .at(commitPosition: UInt64(message.position)))
        }
    }
}

