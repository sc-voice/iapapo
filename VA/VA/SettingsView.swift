import AVFoundation
import SwiftUI

/// Speaks a short sample in a chosen voice so the user can audition it.
@MainActor
final class VoicePreviewer {
  private let synthesizer = AVSpeechSynthesizer()

  /// Speaks "This is VOICE. The time is TIME." in `voice`, replacing any sample in progress.
  func play(_ voice: AVSpeechSynthesisVoice) {
    let time = DateFormatter.localizedString(
      from: Date(), dateStyle: .none, timeStyle: .short)
    let utterance = AVSpeechUtterance(
      string: "This is \(voice.name). The time is \(time).")
    utterance.voice = voice
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(utterance)
  }
}

/// Settings screen: voice selection grouped by quality, with a preview button per voice.
struct SettingsView: View {
  @AppStorage("voiceIdentifier") private var voiceID = ""
  @State private var previewer = VoicePreviewer()

  /// Voices for the system locale's language, grouped by quality (highest first) and sorted by name.
  private var groups: [(label: String, voices: [AVSpeechSynthesisVoice])] {
    let language = Locale.current.language.languageCode?.identifier ?? "en"
    let voices = AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix(language) }
    let tiers: [AVSpeechSynthesisVoiceQuality] = [.premium, .enhanced, .default]
    return tiers.compactMap { quality in
      let matches = voices
        .filter { $0.quality == quality }
        .sorted { $0.name < $1.name }
      return matches.isEmpty ? nil : (qualityLabel(quality), matches)
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        HStack {
          Picker("Voice", selection: $voiceID) {
            ForEach(groups, id: \.label) { group in
              Section(group.label) {
                ForEach(group.voices, id: \.identifier) { voice in
                  Text(voice.name).tag(voice.identifier)
                }
              }
            }
          }
        }
      }
      .navigationTitle("Settings")
      .onChange(of: voiceID) { _, identifier in
        // Play a sample in the newly selected voice.
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
          previewer.play(voice)
        }
      }
    }
  }

  /// Display label for a voice quality tier.
  private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
    switch quality {
    case .premium: "Premium"
    case .enhanced: "Enhanced"
    default: "Default"
    }
  }
}
