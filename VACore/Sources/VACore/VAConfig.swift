/// Default names and timings from the article. Apps can override them.
/// Times are in seconds.
public struct VAConfig: Sendable {
    /// Agent name. Also the wake word and idle word.
    public var agentName = "IaPapo"
    public var llmTimeout: Double = 60
    public var listenTimeout: Double = 60
    public var endPromptTimeout: Double = 3
    public var wakePause: Double = 0.5

    public init() {}
}
