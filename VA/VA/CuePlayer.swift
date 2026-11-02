//
//  CuePlayer.swift
//  VA
//

import AVFoundation
import Observation
import VACore

/// Plays cue sounds from the app bundle and publishes the cue that is audible now.
@Observable
final class CuePlayer: Feedback {
    /// The cue currently audible, or nil when silent.
    private(set) var nowPlaying: Sound?
    /// The most recent cue, kept so its name can fade out after it stops.
    private(set) var lastCue: Sound?
    private var player: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private let log: EventLog

    init(log: EventLog) {
        self.log = log
    }

    func perform(_ effect: Effect) {
        guard case .sound(let sound) = effect else { return }
        play(sound)
    }

    /// Returns when the cue started by the latest `perform` has finished, or at once if none is playing.
    func untilSilent() async {
        await fadeTask?.value
    }

    private func play(_ sound: Sound) {
        guard let url = Bundle.main.url(forResource: sound.resourceName, withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        let duration = player.duration
        self.player = player
        player.play()
        nowPlaying = sound
        lastCue = sound
        log.record("cue \(sound.resourceName)")
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled {
                self?.nowPlaying = nil
            }
        }
    }
}

extension Sound {
    /// Base name of the cue file in `Cues/`, such as `listen` for `listen.m4a`.
    var resourceName: String {
        String(describing: self)
    }
}
