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
}

/// Shows the live mic level so the user can check the microphone. Records no
/// clip.
private struct MicMonitorView: View {
  let microphoneOn: Bool
  /// Live mic level in dBFS, drawn as the meter.
  let level: Float
  /// Smoothed wake-word score, from 0 to 1, drawn as the score ring.
  let wakeScore: Float
  /// Whether the latest event was a wake word; the score ring is green when true.
  let wakeWord: Bool
  /// Ambient floor in dBFS, or nil before the first hop.
  let ambientDb: Float?
  /// Smoothed window level in dBFS, shown beside the ambient floor, or nil before the first hop.
  let windowDb: Float?
  /// Whether the window level is clearly above the ambient floor. The mic ring
  /// is green when true and gray when false.
  let gateOpen: Bool
  /// Microphone level in dBFS per event, newest first, for the history chart.
  let micHistory: [Float]
  /// Raw wake score per event, newest first, for the history chart.
  let scoreHistory: [Float]
  /// Wake-word flag per event, newest first, parallel to `scoreHistory`.
  let wakeHistory: [Bool]
  let onNext: () -> Void
  /// Toggles the microphone: enters IDLE to start it, or INACTIVE to stop it.
  let onMicTap: () -> Void

  /// The wake score ring with its ambient reading, shown beside the wake score
  /// bar chart.
  private var wakeRing: some View {
    VStack(spacing: 4) {
      LevelRing(value: microphoneOn ? Double(wakeScore) : 0, fill: wakeWord ? .green : .gray)
        .background {
          // The gradient turns through 360 degrees every 4 seconds.
          TimelineView(.animation) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let radians = seconds.truncatingRemainder(dividingBy: 4) / 4
              * 2 * Double.pi
            let dx = 0.5 * cos(radians)
            let dy = 0.5 * sin(radians)
            Circle()
              .fill(
                LinearGradient(
                  colors: microphoneOn
                    ? [Color(red: 0, green: 0.39, blue: 0), Color(red: 0.584, green: 0.271, blue: 0.208)]
                    : [.gray, .gray],
                  startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                  endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
                )
              )
          }
        }
        .overlay {
          Image(systemName: "ear")
            .resizable()
            .scaledToFit()
            .foregroundStyle(
              microphoneOn ? Color(red: 0.5, green: 0.5, blue: 0.74) : Color(white: 0.25)
            )
            .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Wake word score")
    }
  }

  /// The mic level ring with its button and current level, shown beside the
  /// microphone bar chart.
  private var micRing: some View {
    VStack(spacing: 4) {
      LevelRing(
        value: microphoneOn
          ? Double((level - WakeMonitor.ambientSilenceDb) / -WakeMonitor.ambientSilenceDb)
          : 0,
        track: microphoneOn
          ? Color(.quaternarySystemFill)
          : Color(red: 0.5, green: 0.5, blue: 0.5),
        fill: gateOpen ? .green : .gray
      )
      .overlay {
        Button(action: onMicTap) {
          Image(systemName: "mic.fill")
            .font(.title)
        }
        .accessibilityLabel(
          microphoneOn ? "Microphone is on" : "Turn on microphone"
        )
      }
    }
  }

  var body: some View {
    VStack(spacing: 16) {
      Text(microphoneOn
        ? "Please say: \"IaPapo\""
        : "Turn on the microphone")
        .font(.headline)
      Text(microphoneOn
        ? "I-AH-PAH-POH"
        : "The microphone is off.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      WakeHistoryView(
        micRing: micRing,
        wakeRing: wakeRing,
        micHistory: micHistory,
        scoreHistory: scoreHistory,
        wakeHistory: wakeHistory,
        isOn: microphoneOn,
        ambientDb: ambientDb,
        windowDb: windowDb,
        gateOpen: gateOpen
      )
      Button("Next", action: onNext)
        .buttonStyle(.borderedProminent)
        .disabled(!microphoneOn)
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
  /// Smoothed wake-word score, from 0 to 1, drawn on the mic check page.
  let wakeScore: Float
  /// Whether the latest event was a wake word, for the score ring's color.
  let wakeWord: Bool
  /// Ambient floor in dBFS, shown under the wake score ring, or nil before the first hop.
  let ambientDb: Float?
  /// Smoothed window level in dBFS, shown beside the ambient floor, or nil before the first hop.
  let windowDb: Float?
  /// Whether the window level is clearly above the ambient floor, for the mic ring's color.
  let gateOpen: Bool
  /// Microphone level in dBFS per event, newest first, for the mic check charts.
  let micHistory: [Float]
  /// Raw wake score per event, newest first, for the mic check charts.
  let scoreHistory: [Float]
  /// Wake-word flag per event, newest first, for the mic check charts.
  let wakeHistory: [Bool]
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
            wakeScore: wakeScore,
            wakeWord: wakeWord,
            ambientDb: ambientDb,
            windowDb: windowDb,
            gateOpen: gateOpen,
            micHistory: micHistory,
            scoreHistory: scoreHistory,
            wakeHistory: wakeHistory,
            onNext: { index += 1 },
            onMicTap: { onEnter(microphoneOn ? .inactive : .idle) },
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
    .frame(minWidth: 350)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .onAppear {
      // The wizard opens INACTIVE. The mic panel's button enters IDLE to start the mic.
      onEnter(.inactive)
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
    VStack {
      let total = Self.steps.count
      let current = min(index + 1, total)
      HStack {
        Text("Wake-Word")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Text("\(current)/\(total)")
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .accessibilityLabel("Close")
      }
      Rectangle()
        .fill(.gray)
        .frame(height: 1);
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    //.background(Color(.secondarySystemBackground))
  }
}
