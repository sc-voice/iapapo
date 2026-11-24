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

/// One row of the transition table: in `from`, an event with `action` and `noun`
/// enters `to`, with the `notify` and `before` lists `transition(to:)` takes.
struct TransitionRow: Sendable {
  let from: VAState
  let action: VAAction
  let noun: VANoun
  let to: VAState
  var notify: [VANoun]?
  var before: [Effect] = []
}

/// The transition table, following the article. Row order within a state is the
/// order `reachable(from:)` returns its targets.
private let transitionTable: [TransitionRow] = [
  TransitionRow(from: .inactive, action: .enable, noun: .voiceAgent, to: .listening, notify: [.agentEnabled]),
  TransitionRow(from: .idle, action: .sensed, noun: .wakeup, to: .listening, notify: [.wakeWordHeard]),
  TransitionRow(from: .idle, action: .disable, noun: .voiceAgent, to: .inactive),
  TransitionRow(from: .listening, action: .sensed, noun: .invalidPrompt, to: .speaking, notify: [.clarifyRequested, .speakingStarted]),
  TransitionRow(from: .listening, action: .sensed, noun: .quickPrompt, to: .thinking),
  TransitionRow(from: .listening, action: .sensed, noun: .validPrompt, to: .thinking),
  TransitionRow(from: .listening, action: .sensed, noun: .listenTimeout, to: .idle),
  TransitionRow(from: .listening, action: .sensed, noun: .idleWord, to: .idle),
  TransitionRow(from: .listening, action: .disable, noun: .voiceAgent, to: .inactive),
  TransitionRow(from: .thinking, action: .sensed, noun: .llmResponseReady, to: .speaking),
  TransitionRow(from: .thinking, action: .sensed, noun: .llmFailed, to: .idle, notify: [.requestFailed], before: [.cancelThink]),
  TransitionRow(from: .thinking, action: .sensed, noun: .idleWord, to: .idle, before: [.cancelThink]),
  TransitionRow(from: .speaking, action: .sensed, noun: .audioFinished, to: .listening),
  TransitionRow(from: .speaking, action: .sensed, noun: .idleWord, to: .idle, before: [.cancelSpeech]),
  TransitionRow(from: .speaking, action: .sensed, noun: .wakeup, to: .listening, notify: [.wakeWordHeard], before: [.cancelSpeech]),
]

/// Applies one event to the state machine.
/// Events with no row for the current state leave the state unchanged and
/// produce no effects or notifications.
public func transition(from state: VAState, on event: VAEvent) -> Step {
  guard let row = transitionTable.first(where: {
    $0.from == state && $0.action == event.action && $0.noun == event.noun
  }) else {
    return Step(state: state)
  }
  return transition(to: row.to, notify: row.notify, before: row.before)
}

/// The states one event can reach from `state`, in table order, without repeats.
/// `state` itself is never included.
public func reachable(from state: VAState) -> [VAState] {
  var targets: [VAState] = []
  for row in transitionTable where row.from == state && row.to != state {
    if !targets.contains(row.to) { targets.append(row.to) }
  }
  return targets
}
