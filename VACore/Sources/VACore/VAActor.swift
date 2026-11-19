/// A hand that acts on the world: speech, a cue, a light. `VAAgent` hands every
/// output event to every injected actor, so each actor ignores the events it
/// does not handle.
public protocol VAActor: Sendable {
  /// Performs one output event and returns when it completes.
  func perform(_ event: VAEvent) async
}
