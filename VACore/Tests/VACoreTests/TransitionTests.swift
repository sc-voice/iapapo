import Testing
@testable import VACore

@Test func inactiveWakesOnHIDOn() {
  #expect(transition(from: .inactive, on: .hidOn)
    == Step(state: .idle, effects: [.sound(.on)]))
}

@Test func idleHandlesWakeWordAndHIDOff() {
  #expect(transition(from: .idle, on: .heardWakeWord)
    == Step(state: .listening, effects: [.sound(.listen)]))
  #expect(transition(from: .idle, on: .hidOff)
    == Step(state: .inactive, effects: [.sound(.off)]))
}

@Test func listeningRoutesPrompts() {
  #expect(transition(from: .listening, on: .utterance(.quick))
    == Step(state: .thinking, effects: [.sound(.thinking)]))
  #expect(transition(from: .listening, on: .utterance(.valid))
    == Step(state: .thinking, effects: [.sound(.thinking)]))
  #expect(transition(from: .listening, on: .utterance(.invalid))
    == Step(
      state: .speaking,
      effects: [.speakClarifyRequest, .sound(.speaking)],
    ))
}

@Test func listeningReturnsToIdle() {
  #expect(transition(from: .listening, on: .listenTimeout)
    == Step(state: .idle, effects: [.sound(.idle)]))
  #expect(transition(from: .listening, on: .heardIdleWord)
    == Step(state: .idle, effects: [.sound(.idle)]))
}

@Test func thinkingHandlesResponseFailureAndIdleWord() {
  #expect(transition(from: .thinking, on: .llmResponseReady)
    == Step(state: .speaking, effects: [.sound(.speaking)]))
  #expect(transition(from: .thinking, on: .llmFailed)
    == Step(state: .idle, effects: [.cancelThink, .sound(.error)]))
  #expect(transition(from: .thinking, on: .heardIdleWord)
    == Step(state: .idle, effects: [.cancelThink, .sound(.idle)]))
}

@Test func speakingHandlesIdleWordFinishAndWakeWord() {
  #expect(transition(from: .speaking, on: .heardIdleWord)
    == Step(state: .idle, effects: [.cancelSpeech, .sound(.idle)]))
  #expect(transition(from: .speaking, on: .audioFinished)
    == Step(state: .listening, effects: [.sound(.listen)]))
  #expect(transition(from: .speaking, on: .heardWakeWord)
    == Step(state: .listening, effects: [.cancelSpeech, .sound(.listen)]))
}

@Test func entryToListeningAlwaysGivesFeedback() {
  #expect(transition(to: .listening)
    == Step(state: .listening, effects: [.sound(.listen)]))
  #expect(transition(to: .thinking)
    == Step(state: .thinking, effects: [.sound(.thinking)]))
}

@Test func unlistedEventsLeaveStateUnchanged() {
  #expect(transition(from: .inactive, on: .heardWakeWord)
    == Step(state: .inactive, effects: []))
  #expect(transition(from: .idle, on: .audioFinished)
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
  perform(transition(from: .idle, on: .heardWakeWord), with: feedback)
  #expect(feedback.effects == [.sound(.listen)])
}
