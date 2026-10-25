import Benchmark
import Foundation
import KurrentDB

// MARK: - Helpers

struct OrderPlaced: Codable, Sendable {
    let orderId: String
    let amount: Double
    let items: Int
}

let samplePayload = #"{"orderId":"abc-123","amount":99.99,"items":3}"#.data(using: .utf8)!
let sampleModel = OrderPlaced(orderId: "abc-123", amount: 99.99, items: 3)

// MARK: - Benchmarks

let benchmarks: @Sendable () -> Void = {

    // MARK: EventData — raw Data payload

    Benchmark("EventData/create-raw-data") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                EventData(eventType: "OrderPlaced", data: samplePayload)
            )
        }
    }

    // MARK: EventData — Codable model (triggers JSONEncoder)

    Benchmark("EventData/create-codable-model") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                EventData(eventType: "OrderPlaced", model: sampleModel)
            )
        }
    }

    // MARK: EventData — batch 100 events (raw)

    Benchmark("EventData/create-batch-100-raw") { benchmark in
        for _ in benchmark.scaledIterations {
            let events = (0 ..< 100).map { i in
                EventData(
                    eventType: "OrderPlaced",
                    data: "{\"orderId\":\"\(i)\",\"amount\":9.99,\"items\":1}".data(using: .utf8)!
                )
            }
            blackHole(events)
        }
    }

    // MARK: EventData — batch 100 events (Codable)

    Benchmark("EventData/create-batch-100-codable") { benchmark in
        for _ in benchmark.scaledIterations {
            let events = (0 ..< 100).map { i in
                EventData(
                    eventType: "OrderPlaced",
                    model: OrderPlaced(orderId: "\(i)", amount: Double(i), items: i)
                )
            }
            blackHole(events)
        }
    }

    // MARK: EventData — payload encoding (Data extraction from .json case)

    Benchmark("EventData/encode-codable-payload") { benchmark in
        let event = EventData(eventType: "OrderPlaced", model: sampleModel)
        for _ in benchmark.scaledIterations {
            blackHole(try event.payload.data)
        }
    }

    // MARK: ClientSettings — parse single-node connection string

    Benchmark("ClientSettings/parse-single-node") { benchmark in
        let connStr = "esdb://admin:changeit@localhost:2113?tls=false"
        for _ in benchmark.scaledIterations {
            blackHole(try ClientSettings.parse(connectionString: connStr))
        }
    }

    // MARK: ClientSettings — parse cluster connection string (3 seeds)

    Benchmark("ClientSettings/parse-cluster-seeds") { benchmark in
        let connStr = "esdb://admin:changeit@node1:2113,node2:2113,node3:2113?tls=true&tlsVerifyCert=false&nodePreference=leader"
        for _ in benchmark.scaledIterations {
            blackHole(try ClientSettings.parse(connectionString: connStr))
        }
    }

    codecBenchmarks()
    clientBenchmarks()
}
