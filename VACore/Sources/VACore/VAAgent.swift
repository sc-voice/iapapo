import Observation

/// Turns input events into output events and keeps the conversation state. The
/// reaction logic in `react(to:)` is synchronous and deterministic; `run(_:)`
/// only connects it to streams and actors. Observable, so views follow `state`.
@MainActor
@Observable
public final class VAAgent {
  /// The conversation state after the last input event.
  public private(set) var state: VAState = .inactive
  private let actors: [any VAActor]

  /// - Parameter actors: every actor that receives each output event.
  public init(actors: [any VAActor]) {
    self.actors = actors
  }

  /// Sets the state directly. The app's entry transition uses this, so the
  /// agent stays the one source of state.
  /// - Parameter state: the state to enter.
  public func setState(_ state: VAState) {
    self.state = state
  }

  /// Reacts to each input event in order until `events` finishes. Each output
  /// event runs in its own task, so a slow actor does not hold up later input.
  /// Returns once every output event has been performed.
  public func run(_ events: VAEventStream) async {
    var pending: [Task<Void, Never>] = []
    for await event in events {
      for output in react(to: event) {
        pending.append(Task {
          for actor in self.actors {
            await actor.perform(output)
          }
        })
      }
    }
    for task in pending {
      await task.value
    }
  }

  /// Reacts to one event sent from the UI, performing its outputs on every actor.
  /// - Parameter event: the event to react to.
  public func send(_ event: VAEvent) async {
    for output in react(to: event) {
      for actor in actors {
        await actor.perform(output)
      }
    }
  }

  /// The output events one input event produces, and the state it leaves. Only
  /// `sensed`, `enable` and `disable` events are reactions: output events are
  /// ignored, so the agent never answers its own output. A wake word always
  /// acknowledges, whatever the state, as the feed did before.
  /// - Parameter event: the next input event.
  /// - Returns: the output events to perform, possibly none.
  func react(to event: VAEvent) -> [VAEvent] {
    guard event.verb == .sensed || event.verb == .enable || event.verb == .disable
    else { return [] }
    state = transition(from: state, on: event).state
    if event.noun == .wakeup {
      return [.acknowledge(.wakeup)]
    }
    return []
  }
}
