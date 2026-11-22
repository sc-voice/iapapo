import AVFoundation
import SwiftUI
import VACore

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

/// Vertical spacing inside each accordion section, shared so the sections line up.
private let vstackSpacing: CGFloat = 8
private let vstackLPadding: CGFloat = 20

/// The accordion sections in the Settings dialog. At most one is open at a time.
enum SettingsSection: Hashable {
  case llm
  case listening
  case speaking
  case other
}

/// Settings screen: voice selection grouped by quality, with a preview button per voice.
struct SettingsView: View {
  @AppStorage(UserDefaultsSettings.voiceIdentifierKey) private var voiceID = ""
  @AppStorage(UserDefaultsSettings.ambientWakeDbKey) private var ambientWakeDb = UserDefaultsSettings.defaultAmbientWakeDb
  @AppStorage(UserDefaultsSettings.listenTimeoutKey) private var listenTimeout = UserDefaultsSettings.defaultListenTimeout
  @AppStorage(LLMConfigStore.activeKey) private var activeLLMZUID = ""
  @State private var previewer = VoicePreviewer()
  /// The saved LLM configs, loaded when the screen appears and after the config sheet closes.
  @State private var llmConfigs: [String: LLMConfig] = [:]
  @State private var showingLLMs = false
  /// The one accordion section that is open, or nil when all are closed.
  @State private var openSection: SettingsSection? = .llm

  /// The collection the Settings picker reads: the saved configs plus the stored choice.
  private var llmCollection: LLMConfigCollection {
    LLMConfigCollection(
      configs: llmConfigs,
      activeLLMZUID: activeLLMZUID.isEmpty ? nil : activeLLMZUID)
  }

  /// Picker selection. Shows the config that actually applies, so a stale choice never looks selected.
  private var activeSelection: Binding<String> {
    Binding(
      get: { llmCollection.activeConfig?.zuid ?? "" },
      set: { activeLLMZUID = $0 })
  }

  /// The listen timeout as minutes, for the slider. Stored in seconds.
  private var listenMinutes: Binding<Double> {
    Binding(
      get: { listenTimeout / 60 },
      set: { listenTimeout = $0 * 60 }
    )
  }

  /// Binds one accordion row to `openSection`, so opening a row closes the others.
  private func expanded(_ section: SettingsSection) -> Binding<Bool> {
    Binding(
      get: { openSection == section },
      set: { isOpen in
        if isOpen {
          openSection = section
        } else if openSection == section {
          openSection = nil
        }
      })
  }

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
    GeometryReader { geometry in
      NavigationStack {
        Form {
          Section {
            DisclosureGroup(
              isExpanded: expanded(.llm),
              content: {
                VStack(alignment: .leading, spacing: vstackSpacing) {
                  HStack {
                    if llmConfigs.isEmpty {
                      Text("No LLM configured")
                        .foregroundStyle(.secondary)
                    } else {
                      Picker("Active LLM", selection: activeSelection) {
                        ForEach(llmConfigs.values.sorted { $0.zuid < $1.zuid }) { config in
                          Text(config.name).tag(config.zuid)
                        }
                      }
                    }
                    Button {
                      showingLLMs = true
                    } label: {
                      Image(systemName: "pencil")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Add or edit LLM")
                    }
                    .buttonStyle(.plain)
                  } // HStack
                } // VStack
                .padding(.leading, vstackLPadding)
              }, // conent
              label: {
                HStack {
                Label("Inference", systemImage: "puzzlepiece.extension")
                }
              } // label
            ) // DisclosureGroupo
            DisclosureGroup(
              isExpanded: expanded(.listening), 
              content: {
                VStack(alignment: .leading, spacing: vstackSpacing) {
                  Text("Sleep when idle")
                  HStack {
                    Slider(value: listenMinutes, in: 1 ... 60, step: 1)
                    Text("\(Int(listenTimeout / 60)) min")
                      .monospacedDigit()
                      .frame(width: 60, alignment: .trailing)
                  }
                  Text("Listening returns to idle after this long without a signal above the wake margin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                  Text("Ignore ambient noise")
                  HStack {
                    Slider(value: $ambientWakeDb, in: 0 ... 10, step: 0.5)
                    Text(ambientWakeDb.formatted(.number.precision(.fractionLength(1))))
                      .monospacedDigit()
                      .frame(width: 40, alignment: .trailing)
                  }
                  Text("The window level must rise this far above the ambient floor to open the wake gate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } // VStack
                .padding(.leading, vstackLPadding)
              }, // content
              label: { 
                Label("Agent: Listening", systemImage: "ear") 
              }
            ) // DisclosureGroup 
            DisclosureGroup(
              isExpanded: expanded(.speaking),
              content: {
                VStack(alignment: .leading, spacing: vstackSpacing) {
                  Picker("Voice", selection: $voiceID) {
                    ForEach(groups, id: \.label) { group in
                      Section(group.label) {
                        ForEach(group.voices, id: \.identifier) { voice in
                          Text(voice.name).tag(voice.identifier)
                        }
                      }
                    }
                  }
                } // VStack
                .padding(.leading, vstackLPadding)
              }, // content
              label : {
                Label("Agent: Speaking", systemImage: "character.bubble") 
              } // label
            ) // DisclosureGroup
            DisclosureGroup(
              isExpanded: expanded(.other), 
              content: {
                VStack(alignment: .leading, spacing: vstackSpacing) {
                  Section {
                    Text("Home background: a night forest with a tent under stars. Rawpixel, CC0.")
                      .font(.footnote)
                      .foregroundStyle(.secondary)
                  } header: {
                    Text("Credits")
                  }
                } // VStack
                .padding(.leading, vstackLPadding)
              }, // content
              label: {
                Label("Other", systemImage: "document") 
              }
            ) // DisclosureGroup
          }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .onAppear { llmConfigs = LLMConfigStore.load() }
        .sheet(isPresented: $showingLLMs, onDismiss: { llmConfigs = LLMConfigStore.load() }) {
          LLMConfigSheet()
        }
        .onChange(of: voiceID) { _, identifier in
          // Play a sample in the newly selected voice.
          if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            previewer.play(voice)
          }
        }
      }
      .frame(maxWidth: 750)
      .frame(maxHeight: geometry.size.height * 0.8) // Always 80% of the device height
      .clipShape(RoundedRectangle(cornerRadius: 24))
      .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

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

#Preview {
  BackgroundWrapper(blur: 10) {
    SettingsView()
  }
}
