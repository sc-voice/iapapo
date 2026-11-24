import Testing
@testable import VACore

@Test func inactiveEnablesVoiceAgent() {
  #expect(transition(from: .inactive, on: VAEvent(action: .enable, noun: .voiceAgent))
    == Step(state: .listening, notifications: [.agentEnabled]))
}

@Test func idleHandlesWakeWordAndDisablesVoiceAgent() {
  #expect(transition(from: .idle, on: .sensed(.wakeup))
    == Step(state: .listening, notifications: [.wakeWordHeard]))
  #expect(transition(from: .idle, on: VAEvent(action: .disable, noun: .voiceAgent))
    == Step(state: .inactive, notifications: [.agentDisabled]))
}

@Test func listeningDisablesVoiceAgent() {
  #expect(transition(from: .listening, on: VAEvent(action: .disable, noun: .voiceAgent))
    == Step(state: .inactive, notifications: [.agentDisabled]))
}

@Test func listeningRoutesPrompts() {
  #expect(transition(from: .listening, on: .sensed(.quickPrompt))
    == Step(state: .thinking, notifications: [.thinkingStarted]))
  #expect(transition(from: .listening, on: .sensed(.validPrompt))
    == Step(state: .thinking, notifications: [.thinkingStarted]))
  #expect(transition(from: .listening, on: .sensed(.invalidPrompt))
    == Step(
      state: .speaking,
      notifications: [.clarifyRequested, .speakingStarted],
    ))
}

@Test func listeningReturnsToIdle() {
  #expect(transition(from: .listening, on: .sensed(.listenTimeout))
    == Step(state: .idle, notifications: [.idleStarted]))
  #expect(transition(from: .listening, on: .sensed(.idleWord))
    == Step(state: .idle, notifications: [.idleStarted]))
}

@Test func thinkingHandlesResponseFailureAndIdleWord() {
  #expect(transition(from: .thinking, on: .sensed(.llmResponseReady))
    == Step(state: .speaking, notifications: [.speakingStarted]))
  #expect(transition(from: .thinking, on: .sensed(.llmFailed))
    == Step(state: .idle, notifications: [.requestFailed], effects: [.cancelThink]))
  #expect(transition(from: .thinking, on: .sensed(.idleWord))
    == Step(state: .idle, notifications: [.idleStarted], effects: [.cancelThink]))
}

@Test func speakingHandlesIdleWordFinishAndWakeWord() {
  #expect(transition(from: .speaking, on: .sensed(.idleWord))
    == Step(state: .idle, notifications: [.idleStarted], effects: [.cancelSpeech]))
  #expect(transition(from: .speaking, on: .sensed(.audioFinished))
    == Step(state: .listening, notifications: [.listeningStarted]))
  #expect(transition(from: .speaking, on: .sensed(.wakeup))
    == Step(state: .listening, notifications: [.wakeWordHeard], effects: [.cancelSpeech]))
}

@Test func entryToListeningAlwaysGivesFeedback() {
  #expect(transition(to: .listening)
    == Step(state: .listening, notifications: [.listeningStarted]))
  #expect(transition(to: .thinking)
    == Step(state: .thinking, notifications: [.thinkingStarted]))
}

@Test func unlistedEventsLeaveStateUnchanged() {
  #expect(transition(from: .inactive, on: .sensed(.wakeup))
    == Step(state: .inactive))
  #expect(transition(from: .idle, on: .sensed(.audioFinished))
    == Step(state: .idle))
  #expect(transition(from: .idle, on: .done(.wakeup))
    == Step(state: .idle))
}

@Test func reachableListsTargetsInTableOrder() {
  #expect(reachable(from: .inactive) == [.listening])
  #expect(reachable(from: .idle) == [.listening, .inactive])
  #expect(reachable(from: .listening) == [.speaking, .thinking, .idle, .inactive])
  #expect(reachable(from: .thinking) == [.speaking, .idle])
  #expect(reachable(from: .speaking) == [.listening, .idle])
}

