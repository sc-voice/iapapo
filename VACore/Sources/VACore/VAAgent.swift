import Observation

/// A reacting orchestrator: it turns input events into output events, keeps the
/// conversation state across them, and performs each output on every actor. The
/// policy in `react(to:)` is synchronous and deterministic (a fixed transition
/// table, not a model's choice). `send(_:)` queues an event; a loop started at
/// construction reacts to queued events in order. Observable, so views follow
/// `state`.
@MainActor
@Observable
public final class VAAgent {
  /// The conversation state after the last input event.
  public private(set) var state: VAState = .inactive
  private let actors: [any VAActor]
  /// The primary input stream, created with the agent. `send` yields into it.
  private let inputStream: VAEventStream
  private let inputContinuation: VAEventStream.Continuation
  /// Whether the mic can be used. Without it, enabling goes to listening, not idle.
  private var micAvailable = true
  /// Read on each start of the listen timeout, so Settings changes apply at once.
  private let settings: any AppSettings
  /// Sends idle when the listen timeout ends. Replaced on each signal.
  private var listenWatch: Task<Void, Never>?

  /// Creates the agent and starts reacting to queued events.
  /// - Parameters:
  ///   - actors: every actor that receives each output event.
  ///   - settings: supplies the listen timeout.
  public init(actors: [any VAActor], settings: any AppSettings = FixedSettings()) {
    self.actors = actors
    self.settings = settings
    let (stream, continuation) = VAEventStream.makeStream()
    inputStream = stream
    inputContinuation = continuation
    Task { await self.consume(self.inputStream) }
  }

  /// Queues one event. Returns at once; the agent reacts in order.
  /// - Parameter event: the event to react to.
  public func send(_ event: VAEvent) {
    inputContinuation.yield(event)
  }

  /// Reacts to each queued event in order, performing each output on every actor
  /// before the next event. Runs for the life of the agent.
  /// - Parameter events: the queued input.
  private func consume(_ events: VAEventStream) async {
    for await event in events {
      for output in react(to: event) {
        for actor in actors {
          await actor.perform(output)
        }
      }
    }
  }

  /// The output events one input event produces, and the state it leaves.
  /// - `set` moves to the state named by its value, with that state's entry
  ///   notification. Setting the current state does nothing.
  /// - `notify` is passed to the actors unchanged.
  /// - `sensed`, `enable` and `disable` follow the transition table. An inactive
  ///   agent ignores `sensed`, so only `enable` activates it. A wake word
  ///   acknowledges in any state where it is heard.
  /// - `done` is an output, so it is ignored: the agent never answers its own output.
  /// - Parameter event: the next event.
  /// - Returns: the output events to perform, possibly none.
  func react(to event: VAEvent) -> [VAEvent] {
    switch event.action {
    case .notify:
      return [event]
    case .set:
      if event.noun == .micAvailable {
        micAvailable = event.value == "true"
        return []
      }
      guard event.noun == .voiceAgentState,
            let value = event.value,
            let target = VAState(rawValue: value),
            target != state
      else { return [] }
      return apply(transition(to: target))
    case .sensed, .enable, .disable:
      if state == .inactive && event.action == .sensed { return [] }
      if state == .inactive && event.action == .enable && !micAvailable {
        return apply(transition(to: .listening, notify: [.agentEnabled]))
      }
      var outputs = apply(transition(from: state, on: event))
      if event.noun == .wakeup {
        outputs.append(.done(.wakeup))
      }
      return outputs
    case .done:
      return []
    }
  }

  /// Records a signal above the wake threshold. While listening, it restarts the
  /// listen timeout.
  public func heard() {
    guard state == .listening else { return }
    startListenWatch()
  }

  /// Moves to the step's state and returns its notifications as outputs. Entering
  /// listening starts the listen timeout; leaving it cancels the timeout.
  /// - Parameter step: the transition to apply.
  /// - Returns: one `notify` event per notification, in order.
  private func apply(_ step: Step) -> [VAEvent] {
    state = step.state
    if state == .listening {
      startListenWatch()
    } else {
      listenWatch?.cancel()
    }
    return step.notifications.map { VAEvent(action: .notify, noun: $0) }
  }

  /// Restarts the listen timeout. When it ends, the agent sends itself a `set` to
  /// idle.
  private func startListenWatch() {
    listenWatch?.cancel()
    let timeout = Duration.seconds(settings.listenTimeout)
    listenWatch = Task {
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled else { return }
      send(VAEvent(action: .set, noun: .voiceAgentState, value: VAState.idle.rawValue))
    }
  }
}
