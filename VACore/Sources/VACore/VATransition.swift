/// Sound cues the app can play. The app's notifier maps notifications to these.
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

/// Commands the app carries out after a transition, such as stopping speech.
public enum Effect: Equatable, Sendable {
  case cancelThink
  case cancelSpeech
}

/// The result of applying one event: the next state, then the commands to carry
/// out and the notifications to give, each in order.
public struct Step: Equatable, Sendable {
  public let state: VAState
  public let notifications: [VANoun]
  public let effects: [Effect]

  public init(state: VAState, notifications: [VANoun] = [], effects: [Effect] = []) {
    self.state = state
    self.notifications = notifications
    self.effects = effects
  }
}

/// Unconditionally enters `state`, so every entry gives feedback.
/// `before` holds commands for leaving the previous state or for the path taken.
/// `notify` replaces the entry notification for `state` when a path needs its own.
public func transition(
  to state: VAState,
  notify: [VANoun]? = nil,
  before: [Effect] = [],
) -> Step {
  let notifications = notify ?? entryNotification(for: state).map { [$0] } ?? []
  return Step(state: state, notifications: notifications, effects: before)
}

/// The default notification for entering each state.
private func entryNotification(for state: VAState) -> VANoun? {
  switch state {
  case .inactive: .agentDisabled
  case .idle: .idleStarted
  case .listening: .listeningStarted
  case .thinking: .thinkingStarted
  case .speaking: .speakingStarted
  }
}

/// Applies one event to the state machine, following the transition table in
/// the article.
/// Events with no row for the current state leave the state unchanged and
/// produce no effects or notifications.
public func transition(from state: VAState, on event: VAEvent) -> Step {
  switch (state, event.action, event.noun) {
  case (.inactive, .enable, .voiceAgent):
    transition(to: .idle, notify: [.agentEnabled])
  case (.idle, .sensed, .wakeup):
    transition(to: .listening, notify: [.wakeWordHeard])
  case (.idle, .disable, .voiceAgent), (.listening, .disable, .voiceAgent):
    transition(to: .inactive)
  case (.listening, .sensed, .quickPrompt), (.listening, .sensed, .validPrompt):
    transition(to: .thinking)
  case (.listening, .sensed, .invalidPrompt):
    transition(to: .speaking, notify: [.clarifyRequested, .speakingStarted])
  case (.listening, .sensed, .listenTimeout), (.listening, .sensed, .idleWord):
    transition(to: .idle)
  case (.thinking, .sensed, .llmResponseReady):
    transition(to: .speaking)
  case (.thinking, .sensed, .llmFailed):
    transition(to: .idle, notify: [.requestFailed], before: [.cancelThink])
  case (.thinking, .sensed, .idleWord):
    transition(to: .idle, before: [.cancelThink])
  case (.speaking, .sensed, .idleWord):
    transition(to: .idle, before: [.cancelSpeech])
  case (.speaking, .sensed, .audioFinished):
    transition(to: .listening)
  case (.speaking, .sensed, .wakeup):
    transition(to: .listening, notify: [.wakeWordHeard], before: [.cancelSpeech])
  default:
    Step(state: state)
  }
}
