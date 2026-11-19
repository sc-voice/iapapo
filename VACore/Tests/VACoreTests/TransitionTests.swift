import Testing
@testable import VACore

@Test func inactiveEnablesVoiceAgent() {
  #expect(transition(from: .inactive, on: VAEvent(verb: .enable, noun: .voiceAgent))
    == Step(state: .idle, effects: [.sound(.on)]))
}

@Test func idleHandlesWakeWordAndDisablesVoiceAgent() {
  #expect(transition(from: .idle, on: .sensed(.wakeup))
    == Step(state: .listening, effects: [.sound(.assistant)]))
  #expect(transition(from: .idle, on: VAEvent(verb: .disable, noun: .voiceAgent))
    == Step(state: .inactive, effects: [.sound(.off)]))
}

@Test func listeningDisablesVoiceAgent() {
  #expect(transition(from: .listening, on: VAEvent(verb: .disable, noun: .voiceAgent))
    == Step(state: .inactive, effects: [.sound(.off)]))
}

@Test func listeningRoutesPrompts() {
  #expect(transition(from: .listening, on: .sensed(.quickPrompt))
    == Step(state: .thinking, effects: [.sound(.thinking)]))
  #expect(transition(from: .listening, on: .sensed(.validPrompt))
    == Step(state: .thinking, effects: [.sound(.thinking)]))
  #expect(transition(from: .listening, on: .sensed(.invalidPrompt))
    == Step(
      state: .speaking,
      effects: [.speakClarifyRequest, .sound(.speaking)],
    ))
}

@Test func listeningReturnsToIdle() {
  #expect(transition(from: .listening, on: .sensed(.listenTimeout))
    == Step(state: .idle, effects: [.sound(.idle)]))
  #expect(transition(from: .listening, on: .sensed(.idleWord))
    == Step(state: .idle, effects: [.sound(.idle)]))
}

@Test func thinkingHandlesResponseFailureAndIdleWord() {
  #expect(transition(from: .thinking, on: .sensed(.llmResponseReady))
    == Step(state: .speaking, effects: [.sound(.speaking)]))
  #expect(transition(from: .thinking, on: .sensed(.llmFailed))
    == Step(state: .idle, effects: [.cancelThink, .sound(.error)]))
  #expect(transition(from: .thinking, on: .sensed(.idleWord))
    == Step(state: .idle, effects: [.cancelThink, .sound(.idle)]))
}

@Test func speakingHandlesIdleWordFinishAndWakeWord() {
  #expect(transition(from: .speaking, on: .sensed(.idleWord))
    == Step(state: .idle, effects: [.cancelSpeech, .sound(.idle)]))
  #expect(transition(from: .speaking, on: .sensed(.audioFinished))
    == Step(state: .listening, effects: [.sound(.listen)]))
  #expect(transition(from: .speaking, on: .sensed(.wakeup))
    == Step(state: .listening, effects: [.cancelSpeech, .sound(.assistant)]))
}

@Test func entryToListeningAlwaysGivesFeedback() {
  #expect(transition(to: .listening)
    == Step(state: .listening, effects: [.sound(.listen)]))
  #expect(transition(to: .thinking)
    == Step(state: .thinking, effects: [.sound(.thinking)]))
}

@Test func unlistedEventsLeaveStateUnchanged() {
  #expect(transition(from: .inactive, on: .sensed(.wakeup))
    == Step(state: .inactive, effects: []))
  #expect(transition(from: .idle, on: .sensed(.audioFinished))
    == Step(state: .idle, effects: []))
  #expect(transition(from: .idle, on: .acknowledge(.wakeup))
    == Step(state: .idle, effects: []))
}

/// Test double that records effects instead of playing sounds.
final class RecordingFeedback: Feedback {
  var effects: [Effect] = []

  func perform(_ effect: Effect) {
    effects.append(effect)
  }
}

@Test func wakeWordCuesListeningThroughFeedback() {
  let feedback = RecordingFeedback()
  perform(transition(from: .idle, on: .sensed(.wakeup)), with: feedback)
  #expect(feedback.effects == [.sound(.assistant)])
}
