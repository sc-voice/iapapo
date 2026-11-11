/// Classes a classifier assigns to a user utterance.
public enum PromptClass: Equatable, Sendable {
  /// Immediate, well-understood request. Skips endPromptTimeout.
  case quick
  /// A question, a demand, or a request for action.
  case valid
  /// Thought babble. Answered with a clarifying request.
  case invalid
}
