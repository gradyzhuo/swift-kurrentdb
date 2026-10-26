import Foundation

public enum Text {
    /// The file's lines without their line breaks (`\n` or `\r\n`); a trailing line break does
    /// not produce an empty last line.
    public static func lines(of text: String) -> [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// The file's text, or "" when it does not exist.
    public static func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Replaces the HTML character references the landing page uses (named and numeric) in one pass.
    public static func unescapingHTML(_ html: String) -> String {
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "middot": "·",
        ]
        var result = ""
        var rest = Substring(html)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let after = rest[rest.index(after: ampersand)...]
            guard let semicolon = after.firstIndex(of: ";"), after[..<semicolon].count <= 10 else {
                result.append("&")
                rest = after
                continue
            }
            let name = after[..<semicolon]
            let replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst(1)).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = named[String(name)]
            }
            if let replacement {
                result += replacement
                rest = after[after.index(after: semicolon)...]
            } else {
                result.append("&")
                rest = after
            }
        }
        result += rest
        return result
    }
}

public enum Files {
    /// Every regular file under `directory` whose name ends in `suffix`, ordered by path components.
    public static func files(under directory: URL, suffix: String) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var found: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(suffix),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            found.append(url)
        }
        return found.sorted { lhs, rhs in
            lhs.pathComponents.lexicographicallyPrecedes(rhs.pathComponents) { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        }
    }

    /// The canonical absolute path of `url` (every symlink resolved, like `realpath`), so that
    /// paths built from it match the ones a directory enumeration returns.
    public static func realPath(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    /// `url` relative to `root`, as a path string.
    public static func relativePath(of url: URL, to root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return url.path }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
