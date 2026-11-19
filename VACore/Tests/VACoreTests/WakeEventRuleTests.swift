import Testing
@testable import VACore

/// A synthetic score at `seconds`, wake word or not.
private func score(_ wake: Bool, at seconds: Double) -> WakeScore {
  WakeScore(
    probability: wake ? 0.95 : 0,
    windowIndex: 0,
    endSeconds: seconds,
    micDb: -30,
    ambientDb: -50,
    windowDb: -30,
    gateOpen: wake,
    wakeWord: wake
  )
}

/// Fires on every score. Used to check that `WakeMonitor` forwards rule events.
private struct AlwaysRule: WakeEventRule {
  mutating func event(for score: WakeScore) -> VAEvent? {
    .sensed(.wakeup)
  }
}

@Test func fourStridesFireOnce() {
  var rule = StrideRunRule(runLength: 4, cooldown: 2)
  let fired = (0 ..< 4).compactMap { rule.event(for: score(true, at: Double($0) * 0.05)) }
  #expect(fired.count == 1 && fired[0].matches(verb: .sensed, noun: .wakeup))
}

@Test func threeStridesDoNotFire() {
  var rule = StrideRunRule(runLength: 4, cooldown: 2)
  let fired = (0 ..< 3).compactMap { rule.event(for: score(true, at: Double($0) * 0.05)) }
  #expect(fired.isEmpty)
}

@Test func nonWakeStrideResetsRun() {
  var rule = StrideRunRule(runLength: 4, cooldown: 2)
  let timeline: [(Bool, Double)] = [
    (true, 0.05), (true, 0.10), (false, 0.15), (true, 0.20), (true, 0.25), (true, 0.30),
  ]
  let fired = timeline.compactMap { rule.event(for: score($0.0, at: $0.1)) }
  #expect(fired.isEmpty)
}

@Test func cooldownBlocksThenAllowsNextRun() {
  var rule = StrideRunRule(runLength: 4, cooldown: 2)
  // A run fires at 0.20. A second run ending at 0.45 is inside the cooldown.
  // A third run ending at 2.65 is past it.
  let timeline: [(Bool, Double)] = [
    (true, 0.05), (true, 0.10), (true, 0.15), (true, 0.20),
    (false, 0.25),
    (true, 0.30), (true, 0.35), (true, 0.40), (true, 0.45),
    (false, 0.50),
    (true, 2.50), (true, 2.55), (true, 2.60), (true, 2.65),
  ]
  var firedAt: [Double] = []
  for (wake, seconds) in timeline where rule.event(for: score(wake, at: seconds)) != nil {
    firedAt.append(seconds)
  }
  #expect(firedAt == [0.20, 2.65])
}

@Test func longRunFiresOnce() {
  var rule = StrideRunRule(runLength: 4, cooldown: 2)
  let fired = (0 ..< 10).compactMap { rule.event(for: score(true, at: Double($0) * 0.05)) }
  #expect(fired.count == 1 && fired[0].matches(verb: .sensed, noun: .wakeup))
}

@Test func monitorStreamsScoresAndRuleEvents() async throws {
  let scorer = try WakeScorer.loadBundled()
  var monitor = WakeMonitor(
    scorer: scorer,
    strideMs: WakeMonitor.productionStrideMs,
    rule: AlwaysRule()
  )
  // One second of silence at 48 kHz. The exact stride count depends on the
  // resampler's latency, so the test checks the streams against `process`.
  let returned = try await monitor.process([Float](repeating: 0, count: 48_000))
  monitor.finish()
  var streamedScores: [WakeScore] = []
  for await value in monitor.scores {
    streamedScores.append(value)
  }
  var streamedEvents: [VAEvent] = []
  for await event in monitor.events {
    streamedEvents.append(event)
  }
  #expect(!returned.isEmpty)
  #expect(streamedScores == returned)
  #expect(streamedEvents.count == returned.count)
  #expect(streamedEvents.allSatisfy { $0.matches(verb: .sensed, noun: .wakeup) })
}
