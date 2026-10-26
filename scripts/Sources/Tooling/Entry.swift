import Foundation

public enum Entry {
    /// Runs a script's `run` on the process arguments: its text goes to stdout, a `ToolError`'s
    /// report to stdout and message to stderr, and the process exits with the status.
    public static func main(_ run: ([String]) throws(ToolError) -> String) -> Never {
        do {
            let output = try run(Array(CommandLine.arguments.dropFirst()))
            if !output.isEmpty { Swift.print(output) }
            exit(0)
        } catch {
            if !error.output.isEmpty { Swift.print(error.output) }
            if error.status == 0 {
                Swift.print(error.message)
            } else {
                FileHandle.standardError.write(Data((error.message + "\n").utf8))
            }
            exit(error.status)
        }
    }
}
