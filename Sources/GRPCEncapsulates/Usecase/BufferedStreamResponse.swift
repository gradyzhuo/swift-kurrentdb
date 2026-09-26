//
//  BufferedStreamResponse.swift
//  GRPCEncapsulates
//

/// 標記一個 ``UnaryStream`` usecase 的 `send()` 會在**回傳前**把整個回應消費完:
/// 它在 gRPC 的 response closure 裡 `for try await` 到底,對每則訊息 `continuation.yield`,
/// 然後 `continuation.finish()` / `finish(throwing:)`,最後才 `return stream`。
///
/// 判斷標準只有一條:`continuation.finish()` 是否在 `return stream` 之前必定被呼叫。
/// 是 —— 加上這個 marker,RPC 在 `perform(node:)` 內就結束,連線不會逃出作用域。
/// 否(`send()` 裡 spawn 了 `Task {}` 把 stream 帶出去,例如 `Streams.Subscribe`)——
/// 不要加,讓它維持獨立連線。
///
/// 目前的 conformer:`Streams.Read`、`Streams.ReadAll`、`Projections.Statistics`、
/// `Users.Details`。連線策略本身由 KurrentDB 的
/// `UnaryStream where Self: BufferedStreamResponse` extension 決定。
///
/// 注意:constrained extension 是靜態分派。任何 generic over `UnaryStream` 的 helper
/// 若沒有同時約束 `Self: BufferedStreamResponse`,會綁到獨立連線那一版的 `perform`。
/// 目前 Sources/ 內沒有這種 helper;新增時必須一併加上約束。
package protocol BufferedStreamResponse {}
