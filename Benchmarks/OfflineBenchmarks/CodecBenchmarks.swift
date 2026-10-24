import Benchmark
import Foundation
import GRPCEncapsulates
import KurrentDB
import SwiftProtobuf

// Wire codec benchmarks: what the client spends turning events into append requests and
// read responses back into events, without a server. The gRPC serializer does the same
// `serializedBytes()` / `init(serializedBytes:)` calls on every message.

private typealias ReadResp = EventStore_Client_Streams_ReadResp

/// Event counts and payload sizes of the codec matrix.
private let eventCounts = [1, 100, 1000]
private let payloadSizes: [(label: String, bytes: Int)] = [
    ("100B", 100),
    ("4KB", 4 * 1024),
    ("64KB", 64 * 1024),
]

private let orderPlacedJSON = Data(#"{"orderId":"abc-123","amount":99.99,"items":3}"#.utf8)

/// One serialized `ReadResp` per event, as the server streams them.
private func serializedReadResponses(count: Int, payload: Data) throws -> [[UInt8]] {
    try (0 ..< count).map { index in
        let message = ReadResp.with {
            $0.event = .with {
                $0.event = .with {
                    $0.id = .with { $0.value = .string(UUID().uuidString) }
                    $0.streamIdentifier = .with { $0.streamName = Data("orders-abc-123".utf8) }
                    $0.streamRevision = UInt64(index)
                    $0.preparePosition = UInt64(index * 512)
                    $0.commitPosition = UInt64(index * 512)
                    $0.metadata = [
                        "type": "OrderPlaced",
                        "content-type": "application/json",
                        "created": "17612345678901234",
                    ]
                    $0.data = payload
                }
                $0.commitPosition = UInt64(index * 512)
            }
        }
        return try message.serializedBytes()
    }
}

func codecBenchmarks() {
    for count in eventCounts {
        for size in payloadSizes {
            let shape = "\(count)x\(size.label)"
            let payload = Data(repeating: 0x61, count: size.bytes)

            // MARK: Append — [EventData] → request messages → wire bytes

            Benchmark("Append/encode-request/\(shape)") { (benchmark, usecase: Streams<SpecifiedStream>.Append) in
                for _ in benchmark.scaledIterations {
                    for message in try usecase.requestMessages() {
                        let bytes: [UInt8] = try message.serializedBytes()
                        blackHole(bytes)
                    }
                }
            } setup: {
                let events = (0 ..< count).map { _ in
                    EventData(eventType: "OrderPlaced", data: payload)
                }
                return Streams<SpecifiedStream>.Append(to: "orders-abc-123", events: events)
            }

            // MARK: Read — wire bytes → ReadResp → ReadResponse

            Benchmark("Read/decode-response/\(shape)") { (benchmark, responses: [[UInt8]]) in
                for _ in benchmark.scaledIterations {
                    for bytes in responses {
                        let message = try ReadResp(serializedBytes: bytes)
                        blackHole(try Streams<SpecifiedStream>.ReadResponse(from: message))
                    }
                }
            } setup: {
                try serializedReadResponses(count: count, payload: payload)
            }
        }

        // MARK: Read — RecordedEvent → Codable model (aggregate rebuild)

        Benchmark("Read/decode-model/\(count)") { (benchmark, records: [RecordedEvent]) in
            for _ in benchmark.scaledIterations {
                for record in records {
                    blackHole(try record.decode(to: OrderPlaced.self))
                }
            }
        } setup: {
            try serializedReadResponses(count: count, payload: orderPlacedJSON).map { bytes in
                try Streams<SpecifiedStream>.ReadResponse(from: ReadResp(serializedBytes: bytes)).event.record
            }
        }
    }
}
