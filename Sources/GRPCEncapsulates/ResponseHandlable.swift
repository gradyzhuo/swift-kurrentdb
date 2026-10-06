//
//  ResponseHandlable.swift
//  GRPCEncapsulates
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import SwiftProtobuf

package protocol ResponseHandlable: Sendable {
    associatedtype UnderlyingResponse: Message
    associatedtype Response: Sendable
}

package protocol UnaryResponseHandlable: ResponseHandlable where Self: Usecase {}

extension UnaryResponseHandlable where Response: GRPCResponse<UnderlyingResponse> {
    @discardableResult
    package func handle(message: Response.UnderlyingMessage) throws -> Response {
        try Response(from: message)
    }

    @discardableResult
    package func handle(response: ClientResponse<Response.UnderlyingMessage>) throws -> Response {
        try handle(message: response.message)
    }
}

package protocol StreamResponseHandlable: UnaryResponseHandlable where Self: Usecase {
    associatedtype Responses: Sendable
}

/// A ``StreamResponseHandlable`` whose `send()` consumes the entire response **before
/// returning**: inside gRPC's response closure it iterates `for try await` to the end, yields
/// each message to the continuation, calls `continuation.finish()` / `finish(throwing:)`, and
/// only then does `return stream`.
///
/// There is exactly one criterion: is `continuation.finish()` guaranteed to run before
/// `return stream`? Yes — add this conformance; the RPC ends inside `perform(node:)` and the
/// connection never leaves that scope. No (`send()` spawns a `Task {}` that carries the stream
/// out, e.g. `Streams.Subscribe`) — leave it off and keep the dedicated connection.
///
/// Draining inline means building each `Response` from its underlying message as it arrives,
/// which is what `handle(message:)` does — hence the `Response: GRPCResponse` requirement.
///
/// Current conformers: `Streams.Read`, `Streams.ReadAll`, `Projections.Statistics`,
/// `Users.Details`. The connection policy itself lives in KurrentDB's
/// `UnaryStream where Self: BufferedStreamResponse` extension.
///
/// Note: constrained extensions are statically dispatched. Any helper generic over
/// `UnaryStream` that does not also constrain `Self: BufferedStreamResponse` binds to the
/// dedicated-connection `perform`. No such helper exists under Sources/ today; add the
/// constraint if one is introduced.
package protocol BufferedStreamResponse: StreamResponseHandlable
    where Response: GRPCResponse<UnderlyingResponse> {}

/// A buffered stream usecase that can also hand its server-streaming call to a caller-owned
/// handler. KurrentDB's lazy read (`ReadCall.lazy`) drives the call from its own iterator.
///
/// `call` must invoke this usecase's generated client method and pass `onResponse` through
/// unchanged; the caller owns iteration, backpressure and the RPC's lifetime.
package protocol ScopedStreamResponse: UnaryStream, BufferedStreamResponse {
    func call<Result: Sendable>(
        connection: GRPCClient<Transport>,
        request: ClientRequest<UnderlyingRequest>,
        callOptions: CallOptions,
        onResponse: @Sendable @escaping (StreamingClientResponse<UnderlyingResponse>) async throws -> Result
    ) async throws -> Result
}
