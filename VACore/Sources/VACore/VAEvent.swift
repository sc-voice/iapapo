/// Inputs to the state machine. Audio, timers, and LLM calls live outside
/// VACore and report back through these events.
public enum VAEvent: Equatable, Sendable {
    case hidOn
    case hidOff
    case heardWakeWord
    case heardIdleWord
    /// An utterance is complete and classified. The caller applies
    /// endPromptTimeout for valid and invalid prompts before sending this.
    case utterance(PromptClass)
    case listenTimeout
    case llmResponseReady
    /// LLM timeout or error.
    case llmFailed
    case audioFinished
}
