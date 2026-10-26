/// The parsed command line: `--name value` and `--name=value` for the declared options,
/// `--name` for the declared flags, everything else positional. `--help` and `-h` throw the
/// usage with status 0; an unknown option, a missing value or the wrong number of positional
/// arguments throw it with status 2.
public struct Arguments: Sendable {
    public let positional: [String]
    private let values: [String: String]
    private let flags: Set<String>
    public let usage: String

    public init(_ raw: [String], usage: String, options: Set<String> = [], flags: Set<String> = []) throws(ToolError) {
        var positional: [String] = []
        var values: [String: String] = [:]
        var seen: Set<String> = []
        var index = 0
        while index < raw.count {
            let argument = raw[index]
            index += 1
            if argument == "--help" || argument == "-h" {
                throw ToolError(status: 0, message: usage)
            }
            guard argument.hasPrefix("--") else {
                positional.append(argument)
                continue
            }
            var name = String(argument.dropFirst(2))
            var value: String?
            if let equals = name.firstIndex(of: "=") {
                value = String(name[name.index(after: equals)...])
                name = String(name[..<equals])
            }
            if flags.contains(name) {
                guard value == nil else { throw ToolError(status: 2, message: "--\(name) takes no value\n\(usage)") }
                seen.insert(name)
                continue
            }
            guard options.contains(name) else {
                throw ToolError(status: 2, message: "unknown option --\(name)\n\(usage)")
            }
            if value == nil {
                guard index < raw.count else { throw ToolError(status: 2, message: "--\(name) needs a value\n\(usage)") }
                value = raw[index]
                index += 1
            }
            values[name] = value
        }
        self.positional = positional
        self.values = values
        self.flags = seen
        self.usage = usage
    }

    public func value(_ name: String) -> String? {
        values[name]
    }

    public func value(_ name: String, default fallback: String) -> String {
        values[name] ?? fallback
    }

    public func flag(_ name: String) -> Bool {
        flags.contains(name)
    }

    /// The positional arguments, which must be exactly `count` of them.
    public func positional(count: Int) throws(ToolError) -> [String] {
        guard positional.count == count else {
            throw ToolError(status: 2, message: "expected \(count) argument\(count == 1 ? "" : "s"), got \(positional.count)\n\(usage)")
        }
        return positional
    }
}
