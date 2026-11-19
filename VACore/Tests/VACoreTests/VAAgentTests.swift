import Testing
@testable import VACore

/// Whether `events` holds exactly one event with the same content as `expected`.
private func isOnly(_ events: [VAEvent], _ expected: VAEvent) -> Bool {
  events.count == 1 && events[0].matches(verb: expected.verb, noun: expected.noun)
}

/// Records every output event it is asked to perform.
private actor RecordingActor: VAActor {
  private(set) var performed: [VAEvent] = []

  func perform(_ event: VAEvent) {
    performed.append(event)
  }
}

@MainActor
@Test func wakeWordAcknowledgesAndListens() {
  let agent = VAAgent(actors: [])
  #expect(agent.react(to: VAEvent(verb: .enable, noun: .voiceAgent)).isEmpty)
  #expect(agent.state == .idle)
  #expect(isOnly(agent.react(to: .sensed(.wakeup)), .acknowledge(.wakeup)))
  #expect(agent.state == .listening)
}

@MainActor
@Test func wakeWordAcknowledgesEvenWithoutATransition() {
  let agent = VAAgent(actors: [])
  // Inactive has no row for a wake word, but the acknowledgement still fires.
  #expect(isOnly(agent.react(to: .sensed(.wakeup)), .acknowledge(.wakeup)))
  #expect(agent.state == .inactive)
}

@MainActor
@Test func agentIgnoresItsOwnOutput() {
  let agent = VAAgent(actors: [])
  #expect(agent.react(to: .acknowledge(.wakeup)).isEmpty)
  #expect(agent.state == .inactive)
}

@MainActor
@Test func runPerformsOutputOnEveryActorAndWaits() async {
  let first = RecordingActor()
  let second = RecordingActor()
  let agent = VAAgent(actors: [first, second])
  let (events, continuation) = VAEventStream.makeStream()
  continuation.yield(VAEvent(verb: .enable, noun: .voiceAgent))
  continuation.yield(.sensed(.wakeup))
  continuation.finish()
  await agent.run(events)
  let firstPerformed = await first.performed
  let secondPerformed = await second.performed
  #expect(isOnly(firstPerformed, .acknowledge(.wakeup)))
  #expect(isOnly(secondPerformed, .acknowledge(.wakeup)))
  #expect(agent.state == .listening)
}
