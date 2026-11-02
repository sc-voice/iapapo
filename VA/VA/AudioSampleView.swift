//
//  AudioSampleView.swift
//  VA
//

import SwiftUI

/// Records one clip for a TrainingStep: the prompt, a live level meter while the clip is open,
/// Start before it, and Next once the clip is saved. A clip ends when the prompt is heard (if the step
/// matches its prompt) or when `msTimeout` runs out, whichever comes first. A failed clip returns to Start.
struct AudioSampleView: View {
    let step: TrainingStep
    let microphoneOn: Bool
    /// Live mic level in dBFS, drawn as the meter while the clip is open.
    let level: Float
    /// Live transcript from the speech model, watched for the prompt when `step.matchPrompt` is set.
    let transcript: String
    /// Opens a clip of `label` in the current take. Returns once the clip is recording, after any entry cue,
    /// or false if it could not start.
    let onBeginClip: (SampleLabel) async -> Bool
    /// Closes the open clip, keeping it when `keep` is true. Returns whether it was kept.
    let onEndClip: (Bool) -> Bool
    /// Advances the wizard after the clip is saved.
    let onNext: () -> Void

    /// Ambient level, in dBFS, above which the room is too noisy to record a positive.
    static let noisyDb: Float = -50

    /// True once Start has been pressed. The noise check runs only before this, from the view appearing to the first Start.
    @State private var startPressed = false

    /// True while the mic is on, Start has not yet been pressed, and the room is louder than `noisyDb`.
    private var isNoisy: Bool {
        microphoneOn && !startPressed && level > Self.noisyDb
    }

    /// True while the clip is open.
    @State private var recording = false
    /// True once the clip is saved.
    @State private var saved = false
    /// True when the clip ended on the prompt, false when it ended on the timeout.
    @State private var matchedPrompt = false
    /// Transcript length at Start, so only speech after Start can match the prompt.
    @State private var baseline = 0
    /// Ends the clip at `msTimeout`. Cancelled when the clip ends early.
    @State private var timer: Task<Void, Never>?
    /// True after a clip was rejected for its level, until the next Start.
    @State private var rejected = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Please say:")
                .font(.headline)
            Text(step.text)
                .font(.title3)
                .multilineTextAlignment(.center)
            if recording {
                ProgressView(value: min(max((level + 60) / 60, 0), 1))
                    .frame(width: 200)
                    .transition(.opacity)
                Text("Listening…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if saved {
                Label(matchedPrompt ? "Got it!" : "I hear you!",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Next", action: onNext)
                    .buttonStyle(.borderedProminent)
            } else {
                if rejected {
                    Text("Didn't catch that. Try again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if isNoisy {
                    Text("It is too noisy in here.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Start", action: start)
                    .buttonStyle(.borderedProminent)
                    .disabled(recording || !microphoneOn || isNoisy)
            }
        }
        .animation(.easeIn(duration: 0.3), value: recording)
        .onChange(of: transcript) { _, text in
            guard recording, step.matchPrompt else { return }
            let fresh = text.count > baseline ? String(text.dropFirst(baseline)) : ""
            if Self.contains(fresh, step.text) { finish(matched: true) }
        }
        .onDisappear {
            // Closing the sheet mid-clip discards the partial clip.
            if recording {
                timer?.cancel()
                recording = false
                _ = onEndClip(false)
            }
        }
    }

    /// Opens the clip and starts the timeout.
    private func start() {
        startPressed = true
        rejected = false
        baseline = transcript.count
        recording = true
        Task {
            guard await onBeginClip(step.label) else {
                recording = false
                return
            }
            // The timer starts with the recording, not at the tap, so the entry cue does not use up the clip's time.
            guard recording else { return }
            timer = Task {
                try? await Task.sleep(for: .milliseconds(step.msTimeout))
                guard !Task.isCancelled else { return }
                finish(matched: false)
            }
        }
    }

    /// Keeps the open clip and shows the confirmation. `matched` is true when the prompt ended the clip.
    private func finish(matched: Bool) {
        guard recording else { return }
        timer?.cancel()
        recording = false
        matchedPrompt = matched
        if onEndClip(true) {
            saved = true
        } else {
            rejected = true
        }
    }

    /// Whether `text` contains `phrase` as the same run of words, ignoring case and punctuation.
    private static func contains(_ text: String, _ phrase: String) -> Bool {
        func normalized(_ s: String) -> String {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return " \(normalized(text)) ".contains(" \(normalized(phrase)) ")
    }
}
