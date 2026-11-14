//
//  CuePlayer.swift
//  VA
//

import AVFoundation
import Observation
import VACore

/// Plays cue sounds from the app bundle and publishes the cue that is audible
/// now.
@Observable
final class CuePlayer: Feedback {
  /// The cue currently audible, or nil when silent.
  private(set) var nowPlaying: Sound?
  /// The most recent cue, kept so its name can fade out after it stops.
  private(set) var lastCue: Sound?
  private var player: AVAudioPlayer?
  private let log: EventLog

  init(log: EventLog) {
    self.log = log
  }

  func perform(_ effect: Effect) {
    guard case let .sound(sound) = effect else { return }
    PlaybackQueue.shared.enqueue { [weak self] in
      await self?.play(sound)
    }
  }

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
