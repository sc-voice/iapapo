//
//  CuePlayer.swift
//  VA
//

import AVFoundation
import Observation
import VACore

/// Plays cue sounds from the app bundle and publishes the cue that is audible
/// now.
@MainActor
@Observable
final class CuePlayer: VAActor {
  /// The cue currently audible, or nil when silent.
  private(set) var nowPlaying: Sound?
  /// The most recent cue, kept so its name can fade out after it stops.
  private(set) var lastCue: Sound?
  private var player: AVAudioPlayer?
  private let log: EventLog

  init(log: EventLog) {
    self.log = log
  }

  /// Plays the cue for each `notify` event. Nouns with no cue, and other
  /// actions, are silent.
  func perform(_ event: VAEvent) async {
    guard event.action == .notify, let sound = Self.cues[event.noun] else { return }
    PlaybackQueue.shared.enqueue { [weak self] in
      await self?.play(sound)
    }
  }

  /// The cue each notification plays by default. User settings will choose the
  /// channel later.
  private static let cues: [VANoun: Sound] = [
    .agentEnabled: .on,
    .agentDisabled: .off,
    .wakeWordHeard: .assistant,
    .listeningStarted: .listen,
    .thinkingStarted: .thinking,
    .speakingStarted: .speaking,
    .idleStarted: .idle,
    .requestFailed: .error,
    .attentionNeeded: .attention,
  ]

  /// Returns when every cue queued so far has finished, or at once if none is
  /// playing.
  func untilSilent() async {
    await PlaybackQueue.shared.untilIdle()
  }

  /// Plays one cue and returns when it has finished. Runs only from the
  /// `PlaybackQueue`.
  private func play(_ sound: Sound) async {
    guard let url = Bundle.main.url(
      forResource: sound.resourceName,
      withExtension: "m4a",
    ),
      let player = try? AVAudioPlayer(contentsOf: url) else { return }
    self.player = player
    player.play()
    nowPlaying = sound
    lastCue = sound
    log.info("cue \(sound.resourceName)")
    try? await Task.sleep(for: .seconds(player.duration))
    nowPlaying = nil
  }
}

extension Sound {
  /// Base name of the cue file in `Cues/`, such as `listen` for `listen.m4a`.
  var resourceName: String {
    String(describing: self)
  }
}
