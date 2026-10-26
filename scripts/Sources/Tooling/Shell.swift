import Foundation

public enum Shell {
    /// Runs `command` (looked up on PATH) in `directory` and returns its stdout, or "" when
    /// `capturingOutput` is false and stdout passes through like stderr. A non-zero exit is a
    /// `ToolError`.
    @discardableResult
    public static func run(_ command: [String], in directory: URL? = nil, capturingOutput: Bool = true) throws(ToolError) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        if let directory { process.currentDirectoryURL = directory }
        let pipe = Pipe()
        if capturingOutput { process.standardOutput = pipe }
        do {
            try process.run()
        } catch {
            throw ToolError(message: "cannot run \(command.joined(separator: " ")): \(error)")
        }
        let data = capturingOutput ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ToolError(message: "\(command.joined(separator: " ")) exited with status \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum Git {
    public static func tags(in root: URL) throws(ToolError) -> [String] {
        try Shell.run(["git", "tag", "--list"], in: root).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public static func commit(of ref: String, in root: URL) throws(ToolError) -> String {
        try Shell.run(["git", "rev-list", "-n", "1", ref], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The repository that contains `directory`, with symlinks resolved.
    public static func topLevel(of directory: URL) throws(ToolError) -> URL {
        let path = try Shell.run(["git", "rev-parse", "--show-toplevel"], in: directory).trimmingCharacters(in: .whitespacesAndNewlines)
        return Files.realPath(URL(fileURLWithPath: path))
    }
}
