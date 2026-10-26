/// A script's failure: the exit status, the message for stderr and the report, if any, that
/// still belongs on stdout before it (a check that lists its rows and then fails).
public struct ToolError: Error, Equatable, Sendable {
    public var status: Int32
    public var message: String
    public var output: String

    public init(status: Int32 = 1, message: String, output: String = "") {
        self.status = status
        self.message = message
        self.output = output
    }
}
