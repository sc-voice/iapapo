//
//  Microphone.swift
//  VA
//

import AVFoundation
import Observation

/// Owns microphone capture. Capture starts when the chat leaves INACTIVE and stops when it returns.
/// The first start requests permission. Buffers are discarded until speech-to-text consumes them.
@Observable
final class Microphone {
    /// Whether the input is capturing.
    private(set) var isOn = false
    /// Receives each captured buffer on the main actor, in capture order. Set before `start`.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Input level in dBFS: 0 is full scale, and silence floors at −160.
    private(set) var level: Float = -160
    private var lastLevelUpdate = Date.distantPast
    /// Whether the chat currently wants the mic. Guards against a permission reply that arrives after stop.
    private var wanted = false
    private let engine = AVAudioEngine()
    private let log: EventLog
    private let session: AudioSessionModel

    init(log: EventLog, session: AudioSessionModel) {
        self.log = log
        self.session = session
    }

    /// Whether the user has denied microphone access. Only Settings can change a denial.
    var isDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// Starts capture, requesting permission if the user has not answered yet.
    func start() {
        guard !isOn, !wanted else { return }
        wanted = true
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor [weak self] in
                self?.open(granted: granted)
            }
        }
    }

    /// Stops capture and releases the input tap.
    func stop() {
        wanted = false
        guard isOn else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isOn = false
        level = -160
        log.record("microphone off")
    }

    /// RMS level of the first channel in dBFS. Runs on the audio thread, so it reads no actor state.
    nonisolated static func decibels(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -160 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        return rms > 0 ? max(20 * log10(rms), -160) : -160
    }

    /// Publishes a level at most every 0.1 s, so the Dev tab stays responsive.
    private func publish(_ dB: Float) {
        let now = Date.now
        guard now.timeIntervalSince(lastLevelUpdate) >= 0.1 else { return }
        lastLevelUpdate = now
        level = dB
    }

    private func open(granted: Bool) {
        session.refresh()
        guard wanted else { return }
        guard granted else {
            wanted = false
            log.record("microphone denied")
            return
        }
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            let dB = Microphone.decibels(of: buffer)
            Task { @MainActor in
                self?.publish(dB)
                self?.onBuffer?(buffer)
            }
        }
        do {
            try engine.start()
            isOn = true
            log.record("microphone on")
        } catch {
            wanted = false
            log.record("microphone error: \(error.localizedDescription)")
        }
    }
}
