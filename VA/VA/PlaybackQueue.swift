//
//  PlaybackQueue.swift
//  VA
//

import AVFoundation

/// Runs audio jobs one at a time, in the order they were enqueued. A job starts only after every earlier job has finished.
@MainActor
final class PlaybackQueue {
    static let shared = PlaybackQueue()

    /// Finishes when the most recently enqueued job finishes.
    private var tail: Task<Void, Never>?

    /// Adds `job` to the end of the queue. It starts once the jobs before it have finished.
    func enqueue(_ job: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await job()
        }
    }

    /// Returns once every job enqueued so far has finished.
    func untilIdle() async {
        await tail?.value
    }
}

/// Plays a bundled audio file and returns when it ends. Use it only from a `PlaybackQueue` job.
@MainActor
enum ClipPlayer {
    /// Plays `resource` (a file in the app bundle, such as `micCheck.m4a`) and returns when it has finished.
    static func play(_ resource: String) async {
        let name = (resource as NSString).deletingPathExtension
        let ext = (resource as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.play()
        // `player` stays alive for the whole sleep, so playback is not cut off.
        try? await Task.sleep(for: .seconds(player.duration))
    }
}
