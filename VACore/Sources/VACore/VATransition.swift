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
  switch (state, event) {
  case (.inactive, .hidOn):
    transition(to: .idle, sound: .on)
  case (.idle, .heardWakeWord):
    transition(to: .listening)
  case (.idle, .hidOff):
    transition(to: .inactive)
  case (.listening, .utterance(.quick)), (.listening, .utterance(.valid)):
    transition(to: .thinking)
  case (.listening, .utterance(.invalid)):
    transition(to: .speaking, before: [.speakClarifyRequest])
  case (.listening, .listenTimeout), (.listening, .heardIdleWord):
    transition(to: .idle)
  case (.thinking, .llmResponseReady):
    transition(to: .speaking)
  case (.thinking, .llmFailed):
    transition(to: .idle, sound: .error, before: [.cancelThink])
  case (.thinking, .heardIdleWord):
    transition(to: .idle, before: [.cancelThink])
  case (.speaking, .heardIdleWord):
    transition(to: .idle, before: [.cancelSpeech])
  case (.speaking, .audioFinished):
    transition(to: .listening)
  case (.speaking, .heardWakeWord):
    transition(to: .listening, before: [.cancelSpeech])
  default:
    Step(state: state, effects: [])
  }
}
