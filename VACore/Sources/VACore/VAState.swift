/// Conversation states of the Voice Assistant (tactical, not final).
/// Named `VAState` rather than `State` to avoid colliding with SwiftUI's `@State`.
public enum VAState: Equatable, Sendable {
    case inactive
    case idle
    case listening
    case thinking
    case speaking
}
