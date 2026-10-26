import Foundation

/// A command that exited non-zero (or could not be launched).
struct ShellError: Error, CustomStringConvertible {
    var command: [String]
    var status: Int32
    var stderr: String

    var description: String {
        "`\(command.joined(separator: " "))` exited \(status): \(stderr.suffix(2000))"
    }
}

/// Runs external tools (docker, cp, sudo, ...) found on `PATH`.
enum Shell {
    /// Runs `tool arguments…` to completion and returns its stdout; throws `ShellError` with the stderr tail on a
    /// non-zero exit. Output goes through temporary files, so a chatty command cannot block on a full pipe.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let result = try capture(tool, arguments)
        guard result.status == 0 else {
            throw ShellError(command: [tool] + arguments, status: result.status, stderr: result.stderr)
        }
        return result.stdout
    }

    /// Runs `tool arguments…` to completion and returns its exit status, stdout and stderr without judging them.
    static func capture(_ tool: String, _ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("live-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw ShellError(command: [tool] + arguments, status: -1, stderr: "\(error)")
        }
        process.waitUntilExit()
        return (
            process.terminationStatus,
            (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? "",
            (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        )
    }
}
