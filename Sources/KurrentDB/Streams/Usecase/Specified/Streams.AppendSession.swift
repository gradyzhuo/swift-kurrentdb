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
extension Streams.AppendSession.Response {
    public struct AppendedResult: Sendable{
        let streamIdentifier: StreamIdentifier
        let currentRevision: UInt64
        let position: StreamPosition?
        
        fileprivate init(streamIdentifier: StreamIdentifier, currentRevision: UInt64, position: StreamPosition?) {
            self.streamIdentifier = streamIdentifier
            self.currentRevision = currentRevision
            self.position = position
        }
    }
}


extension Streams.AppendSession {
    public struct Response: GRPCResponse {
        
        package typealias UnderlyingMessage = UnderlyingResponse

        public let results: [AppendedResult]
        public let position: StreamPosition

        init(results: [AppendedResult], position: StreamPosition) {
            self.results = results
            self.position = position
        }

        package init(from message: UnderlyingMessage) throws(KurrentError) {
            let results: [AppendedResult] = message.output.map{
                .init(
                    streamIdentifier: .init(name: $0.stream),
                    currentRevision: UInt64($0.streamRevision),
                    position: $0.hasPosition ?.at(commitPosition: UInt64($0.position)) : nil)
            }
            
            self.init(results: results, position: .at(commitPosition: UInt64(message.position)))
        }
    }
}

