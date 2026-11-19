/// Sound cues played on state changes.
public enum Sound: Equatable, Sendable {
  case on
  case off
  case listen
  case idle
  case thinking
  case speaking
  /// Something needs the user's attention, but nothing has failed.
  case attention
  case error
  /// Played when the training wizard opens. File: `trainIapapo.m4a`.
  case trainIapapo
  /// Played when the wake word is heard. File: `assistant.m4a`.
  case assistant
}

/// Side effects the app performs after a transition.
public enum Effect: Equatable, Sendable {
  case sound(Sound)
  case speakClarifyRequest
  case cancelThink
  case cancelSpeech
}

/// The result of applying one event: the next state and its effects, in order.
public struct Step: Equatable, Sendable {
  public let state: VAState
  public let effects: [Effect]

  public init(state: VAState, effects: [Effect]) {
    self.state = state
    self.effects = effects
  }
}

/// Unconditionally enters `state`, so every entry gives feedback.
/// `before` holds effects for leaving the previous state or for the path taken.
/// `sound` replaces the entry sound for `state` when a path needs its own cue.
public func transition(
  to state: VAState,
  sound: Sound? = nil,
  before: [Effect] = [],
) -> Step {
  let feedback = sound ?? entrySound(for: state)
  return Step(
    state: state,
    effects: before + (feedback.map { [.sound($0)] } ?? []),
  )
}

/// The default feedback for entering each state.
private func entrySound(for state: VAState) -> Sound? {
  switch state {
  case .inactive: .off
  case .idle: .idle
  case .listening: .listen
  case .thinking: .thinking
  case .speaking: .speaking
  }
}

/// Applies one event to the state machine, following the transition table in
/// the article.
/// Events with no row for the current state leave the state unchanged and
/// produce no effects.
public func transition(from state: VAState, on event: VAEvent) -> Step {
  switch (state, event.verb, event.noun) {
  case (.inactive, .enable, .voiceAgent):
    transition(to: .idle, sound: .on)
  case (.idle, .sensed, .wakeup):
    transition(to: .listening, sound: .assistant)
  case (.idle, .disable, .voiceAgent), (.listening, .disable, .voiceAgent):
    transition(to: .inactive, sound: .off)
  case (.listening, .sensed, .quickPrompt), (.listening, .sensed, .validPrompt):
    transition(to: .thinking)
  case (.listening, .sensed, .invalidPrompt):
    transition(to: .speaking, before: [.speakClarifyRequest])
  case (.listening, .sensed, .listenTimeout), (.listening, .sensed, .idleWord):
    transition(to: .idle)
  case (.thinking, .sensed, .llmResponseReady):
    transition(to: .speaking)
  case (.thinking, .sensed, .llmFailed):
    transition(to: .idle, sound: .error, before: [.cancelThink])
  case (.thinking, .sensed, .idleWord):
    transition(to: .idle, before: [.cancelThink])
  case (.speaking, .sensed, .idleWord):
    transition(to: .idle, before: [.cancelSpeech])
  case (.speaking, .sensed, .audioFinished):
    transition(to: .listening)
  case (.speaking, .sensed, .wakeup):
    transition(to: .listening, sound: .assistant, before: [.cancelSpeech])
  default:
    Step(state: state, effects: [])
  }
}
