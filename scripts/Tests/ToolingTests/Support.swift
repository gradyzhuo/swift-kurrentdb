import Foundation
@testable import Tooling

/// A throwaway directory, removed when the test ends.
final class TemporaryDirectory: @unchecked Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("tooling-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ relative: String, _ text: String) {
        let file = url.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! text.write(to: file, atomically: true, encoding: .utf8)
    }

    func read(_ relative: String) -> String {
        try! String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
    }
}

/// The `ToolError` a call throws, or nil when it succeeds (or throws something else).
func failure(_ body: () throws -> Any) -> ToolError? {
    do {
        _ = try body()
        return nil
    } catch {
        return error as? ToolError
    }
}
