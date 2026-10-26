import Foundation

public enum ScenarioKind: String, Codable, Sendable, CaseIterable {
    case appendLatency
    case appendThroughput
    case rebuild
    case persistentSubscription
    case catchUp
}

public enum Tier: String, Codable, Sendable {
    case headline
    case appendix
}

/// One comparison cell: a scenario at one event size, run as a single CI job.
public struct Cell: Codable, Sendable, Identifiable {
    public var id: String
    public var kind: ScenarioKind
    public var eventSize: Int
    public var tls: Bool
    public var streamLength: Int?
    public var tier: Tier
    public var rates: [Double]
    public var rounds: Int

    public init(id: String, kind: ScenarioKind, eventSize: Int, tls: Bool, streamLength: Int?, tier: Tier, rates: [Double], rounds: Int) {
        self.id = id
        self.kind = kind
        self.eventSize = eventSize
        self.tls = tls
        self.streamLength = streamLength
        self.tier = tier
        self.rates = rates
        self.rounds = rounds
    }
}

/// What a driver receives: one cell resolved to a single rate step with all fixed parameters.
public struct EffectiveScenario: Codable, Sendable {
    public var cellId: String
    public var kind: ScenarioKind
    public var eventSize: Int
    public var metadataSize: Int
    public var batchSize: Int
    public var streamCount: Int
    public var streamPrefix: String
    public var category: String
    public var groupName: String?
    public var streamLength: Int?
    public var rebuildStreams: [String]?
    public var catchUpExpectedEvents: Int?
    public var rate: Double
    public var warmupSeconds: Double
    public var measureSeconds: Double
    public var drainSeconds: Double
    public var deadlineMillis: Int
    public var inFlightCap: Int
    public var seed: UInt64

    public init(
        cellId: String, kind: ScenarioKind, eventSize: Int, metadataSize: Int, batchSize: Int,
        streamCount: Int, streamPrefix: String, category: String, groupName: String?,
        streamLength: Int?, rebuildStreams: [String]?, catchUpExpectedEvents: Int?,
        rate: Double, warmupSeconds: Double, measureSeconds: Double, drainSeconds: Double,
        deadlineMillis: Int, inFlightCap: Int, seed: UInt64
    ) {
        self.cellId = cellId
        self.kind = kind
        self.eventSize = eventSize
        self.metadataSize = metadataSize
        self.batchSize = batchSize
        self.streamCount = streamCount
        self.streamPrefix = streamPrefix
        self.category = category
        self.groupName = groupName
        self.streamLength = streamLength
        self.rebuildStreams = rebuildStreams
        self.catchUpExpectedEvents = catchUpExpectedEvents
        self.rate = rate
        self.warmupSeconds = warmupSeconds
        self.measureSeconds = measureSeconds
        self.drainSeconds = drainSeconds
        self.deadlineMillis = deadlineMillis
        self.inFlightCap = inFlightCap
        self.seed = seed
    }
}

private struct CellsFile: Codable {
    var cells: [Cell]
}

public func loadCells(from url: URL) throws -> [Cell] {
    try JSONDecoder().decode(CellsFile.self, from: Data(contentsOf: url)).cells
}
