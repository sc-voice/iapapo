//
//  TrainingWizard.swift
//  VA
//

import SwiftUI
import VACore

/// One prompt the user reads or says while training. Case in `text` cues
/// intonation for positives.
struct TrainingStep: Identifiable {
  let id: Int
  let label: SampleLabel
  let text: String
  /// Whether hearing `text` in the transcript ends the clip early.
  let matchPrompt: Bool
  /// The longest the clip can run, in milliseconds.
  let msTimeout: Int
  /// When true, the panel only shows the live mic level and records nothing;
  /// `label`, `text`, and the timing fields are ignored.
  var monitorOnly: Bool = false
  /// Bundled audio file played when the panel appears, such as `assistant.m4a`.
  /// Nil stays silent.
  var cue: String?
}

/// Shows the live mic level so the user can check the microphone. Records no
/// clip.
private struct MicMonitorView: View {
  let microphoneOn: Bool
  /// Live mic level in dBFS, drawn as the meter.
  let level: Float
  /// Spoken once on entry, when set.
  let cue: String?
  let onNext: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text("Check your microphone")
        .font(.headline)
      Text(microphoneOn
        ? "Speak normally. The meter follows the room. Nothing is recorded here."
        : "The microphone is off.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      ProgressView(value: min(max((level + 60) / 60, 0), 1))
        .frame(width: 200)
      Button("Next", action: onNext)
        .buttonStyle(.borderedProminent)
        .disabled(!microphoneOn)
    }
    .onAppear {
      guard let cue else { return }
      PlaybackQueue.shared.enqueue {
        await ClipPlayer.play(cue)
      }
    }
  }
}

/// Guides the user through wake-word samples: the wake word in three
/// intonations, then long
/// everyday requests with no wake word. Each step records one clip; the next
/// step appears once it is saved.
struct TrainingWizard: View {
  let microphoneOn: Bool
  /// Live mic level in dBFS, drawn as the meter while a clip is open.
  let level: Float
  /// Live transcript from the speech model, watched for each step's prompt.
  let transcript: String
  /// Enters a ChatState through the app's state machine.
  let onEnter: (VAState) -> Void
  /// Opens a clip of the step's label in the current take. Returns once the
  /// clip is recording, or false if it could not start.
  let onBeginClip: (SampleLabel) async -> Bool
  /// Closes the open clip, keeping it when `keep` is true. Returns whether it
  /// was kept.
  let onEndClip: (Bool) -> Bool
  let onDone: () -> Void

  /// The mic check comes first. We train negatives next to warm up the speaker.
  /// WakeWord positives come last.
  static let steps: [TrainingStep] = [
    TrainingStep(
      id: 0,
      label: .negative,
      text: "",
      matchPrompt: false,
      msTimeout: 0,
      monitorOnly: true,
      cue: "assistant.m4a",
    ),
    TrainingStep(
      id: 1,
      label: .negative,
      text: "We are testing the microphone",
      matchPrompt: true,
      msTimeout: 10000,
    ),
    TrainingStep(
      id: 2,
      label: .negative,
      text: "I love Iowa Popovers. Do you have a recipe?",
      matchPrompt: true,
      msTimeout: 10000,
    ),
    TrainingStep(
      id: 3,
      label: .negative,
      text: "I am really worried about the weather tomorrow. What's the forecast?",
      matchPrompt: true,
      msTimeout: 10000,
    ),
    TrainingStep(
      id: 4,
      label: .positive,
      text: "IaPapo",
      matchPrompt: false,
      msTimeout: 2000,
    ),
    TrainingStep(
      id: 5,
      label: .positive,
      text: "IAPAPO!",
      matchPrompt: false,
      msTimeout: 2000,
    ),
    TrainingStep(
      id: 6,
      label: .positive,
      text: "IaPapo?",
      matchPrompt: false,
      msTimeout: 2000,
    ),
  ]

  @State private var index = 0
  @State private var saved = 0
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      titleBar
      VStack(spacing: 16) {
        if index < Self.steps.count, Self.steps[index].monitorOnly {
          MicMonitorView(
            microphoneOn: microphoneOn,
            level: level,
            cue: Self.steps[index].cue,
            onNext: { index += 1 },
          )
          .id(index)
        } else if index < Self.steps.count {
          AudioSampleView(
            step: Self.steps[index],
            microphoneOn: microphoneOn,
            level: level,
            transcript: transcript,
            onBeginClip: beginClip,
            onEndClip: endClip,
            onNext: {
              saved += 1
              index += 1
            },
          )
          .id(index)
        } else {
          Text("\(saved) clips saved.")
          Button("Done", action: onDone)
            .buttonStyle(.borderedProminent)
        }
      }
      .padding(32)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(
      .secondary,
      lineWidth: 1,
    ))
    .padding(16)
    .onAppear {
      // The samples need the mic running, so the chat is IDLE while the wizard
      // is open.
      onEnter(.idle)
    }
    .onDisappear {
      // Covers Done, the close button, and swipe-down. INACTIVE stops the mic.
      onEnter(.inactive)
    }
  }

  /// Moves the chat to LISTENING, since the speech model transcribes while a
  /// clip is open, then opens the clip.
  /// Entering LISTENING plays the listen cue first, and the recorder starts
  /// only after it ends.
  private func beginClip(_ label: SampleLabel) async -> Bool {
    onEnter(.listening)
    guard await onBeginClip(label) else {
      onEnter(.idle)
      return false
    }
    return true
  }

  /// Closes the clip and returns the chat to IDLE. Returns whether the clip was
  /// kept.
  private func endClip(_ keep: Bool) -> Bool {
    let kept = onEndClip(keep)
    onEnter(.idle)
    return kept
  }

  /// Title row: "Train IaPapo" on the left, the step counter centered, and a
  /// close button on the right.
  /// Has its own background so it reads as a bar above the body.
  private var titleBar: some View {
    ZStack {
      let total = Self.steps.count
      let current = min(index + 1, total)
      Text("\(current)/\(total)")
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.secondary)
      HStack {
        Text("Let's train IaPapo")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .accessibilityLabel("Close")
      }
    }
    .padding(.horizontal, 32)
    .padding(.vertical, 12)
    .background(Color(.secondarySystemBackground))
  }
}
