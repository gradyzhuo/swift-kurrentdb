import Testing
@testable import Tooling

@Suite struct ArgumentsTests {
    @Test func optionsFlagsAndPositionalArguments() throws {
        let arguments = try Arguments(["a", "--root", "dir", "--base=x", "--verbose", "b"], usage: "u", options: ["root", "base"], flags: ["verbose"])
        #expect(arguments.positional == ["a", "b"])
        #expect(arguments.value("root") == "dir")
        #expect(arguments.value("base") == "x")
        #expect(arguments.value("missing", default: "d") == "d")
        #expect(arguments.flag("verbose"))
    }

    @Test func helpUnknownOptionsAndMissingValuesAreReported() {
        #expect(failure { try Arguments(["--help"], usage: "u").usage } == ToolError(status: 0, message: "u"))
        #expect(failure { try Arguments(["--nope"], usage: "u").usage }?.status == 2)
        #expect(failure { try Arguments(["--root"], usage: "u", options: ["root"]).usage }?.status == 2)
        #expect(failure { try Arguments(["x"], usage: "u").positional(count: 2).joined() }?.status == 2)
    }
}
