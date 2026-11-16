//
//  Speaker.swift
//  VA
//

import AVFoundation

/// Speaks short confirmations on device with `AVSpeechSynthesizer`.
final class Speaker {
  private let synthesizer = AVSpeechSynthesizer()
  private let log: EventLog
  /// Fallback voice when Settings has none: the Siri en-US female voice, or the
  /// highest-quality installed en-US voice as `scv-app` picks by quality.
  private static let defaultVoice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(
    identifier: "com.apple.ttsbundle.siri_female_en-US_compact",
  )
    ?? AVSpeechSynthesisVoice.speechVoices()
    .filter { $0.language == "en-US" }
    .max { $0.quality.rawValue < $1.quality.rawValue }
    ?? AVSpeechSynthesisVoice(language: "en-US")

  /// The voice `say` uses, read from the Settings voice on each call so changes apply at once.
  var voice: AVSpeechSynthesisVoice? {
    if let id = UserDefaults.standard.string(forKey: "voiceIdentifier"),
      let saved = AVSpeechSynthesisVoice(identifier: id)
    {
      return saved
    }
    return Self.defaultVoice
  }

  /// - Parameter log: records each phrase spoken.
  init(log: EventLog) {
    self.log = log
    // Log every installed voice to the Xcode console, Siri voices first, then
    // highest quality.
    let voices = AVSpeechSynthesisVoice.speechVoices().sorted { a, b in
      let aSiri = Self.isSiri(a)
      let bSiri = Self.isSiri(b)
      if aSiri != bSiri { return aSiri }
      if a.quality.rawValue != b.quality.rawValue {
        return a.quality.rawValue > b.quality.rawValue
      }
      return a.name < b.name
    }
    for voice in voices {
      print("[VA voice] \(voice.name) \(voice.identifier) \(voice.language) quality \(voice.quality.rawValue)")
    }
  }

  /// Every installed English voice, sorted by name, for the voice picklist.
  static var englishVoices: [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("en") }
      .sorted { $0.name < $1.name }
  }

  /// Whether the voice is a Siri voice, by name or identifier.
  private static func isSiri(_ voice: AVSpeechSynthesisVoice) -> Bool {
    voice.name.localizedCaseInsensitiveContains("siri")
      || voice.identifier.localizedCaseInsensitiveContains("siri")
  }
  /// Speaks `text` now, interrupting any speech already playing.
  /// - Parameter text: the words to speak.
  func say(_ text: String) {
    log.info("speak: \(text)")
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    synthesizer.speak(utterance)
  }
}
