import Testing
@testable import VACore

/// Records every output event it is asked to perform.
private actor RecordingActor: VAActor {
  private(set) var performed: [VAEvent] = []

  func perform(_ event: VAEvent) {
    performed.append(event)
  }
}

/// The nouns of `events`, in order.
private func nouns(_ events: [VAEvent]) -> [VANoun] {
  events.map(\.noun)
}

@MainActor
@Test func wakeWordAcknowledgesAndListens() {
  let agent = VAAgent(actors: [])
  #expect(nouns(agent.react(to: VAEvent(action: .enable, noun: .voiceAgent)))
    == [.agentEnabled])
  #expect(agent.state == .idle)
  #expect(nouns(agent.react(to: .sensed(.wakeup))) == [.wakeWordHeard, .wakeup])
  #expect(agent.state == .listening)
}

@MainActor
@Test func enableWithoutMicGoesToListening() {
  let agent = VAAgent(actors: [])
  #expect(agent.react(to: VAEvent(action: .set, noun: .micAvailable, value: "false")).isEmpty)
  #expect(nouns(agent.react(to: VAEvent(action: .enable, noun: .voiceAgent)))
    == [.agentEnabled])
  #expect(agent.state == .listening)
}

@MainActor
@Test func inactiveAgentIgnoresWakeWord() {
  let agent = VAAgent(actors: [])
  #expect(agent.react(to: .sensed(.wakeup)).isEmpty)
  #expect(agent.state == .inactive)
}

@MainActor
@Test func agentIgnoresItsOwnOutput() {
  let agent = VAAgent(actors: [])
  #expect(agent.react(to: .done(.wakeup)).isEmpty)
  #expect(agent.state == .inactive)
}

@MainActor
@Test func setEntersNamedStateWithItsNotification() {
  let agent = VAAgent(actors: [])
  let outputs = agent.react(to: VAEvent(
    action: .set,
    noun: .voiceAgentState,
    value: VAState.listening.rawValue,
  ))
  #expect(nouns(outputs) == [.listeningStarted])
  #expect(agent.state == .listening)
}

@MainActor
@Test func setToCurrentStateIsSilent() {
  let agent = VAAgent(actors: [])
  let outputs = agent.react(to: VAEvent(
    action: .set,
    noun: .voiceAgentState,
    value: VAState.inactive.rawValue,
  ))
  #expect(outputs.isEmpty)
  #expect(agent.state == .inactive)
}

@MainActor
@Test func notifyPassesThroughUnchanged() {
  let agent = VAAgent(actors: [])
  let event = VAEvent(action: .notify, noun: .requestFailed)
  #expect(nouns(agent.react(to: event)) == [.requestFailed])
}

@MainActor
@Test func sendPerformsOutputOnEveryActorInOrder() async {
  let first = RecordingActor()
  let second = RecordingActor()
  let agent = VAAgent(actors: [first, second])
  agent.send(VAEvent(action: .enable, noun: .voiceAgent))
  agent.send(.sensed(.wakeup))
  // Enable gives one notification; the wake word gives a notification and an acknowledgement.
  while await first.performed.count < 3 {
    await Task.yield()
  }
  let firstNouns = await nouns(first.performed)
  let secondNouns = await nouns(second.performed)
  #expect(firstNouns == [.agentEnabled, .wakeWordHeard, .wakeup])
  #expect(secondNouns == [.agentEnabled, .wakeWordHeard, .wakeup])
  #expect(agent.state == .listening)
}
