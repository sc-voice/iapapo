//
//  AudioSessionModel.swift
//  VA
//

import AVFoundation
import Observation
import Speech
import VACore

/// Observable snapshot of the shared audio session, refreshed when a session
/// event arrives.
@Observable
final class AudioSessionModel {
  /// Current category without the `AVAudioSessionCategory` prefix, such as
  /// "playAndRecord".
  private(set) var category = ""
  /// Name of the active output route, such as "Speaker" or a Bluetooth device.
  private(set) var outputName = "—"
  /// Name of the active input route, such as the built-in microphone.
  private(set) var inputName = "—"
  /// Microphone grant from `AVAudioApplication`, such as "granted" or
  /// "undetermined".
  private(set) var micPermission = ""
  /// Speech-recognition grant from `SFSpeechRecognizer`, such as "authorized"
  /// or "notDetermined".
  private(set) var speechPermission = ""
  /// Message from the last failed activation or category change. Nil after a
  /// successful apply.
  private(set) var lastError: String?
  /// True between an interruption's begin and end, such as a call.
  private(set) var isInterrupted = false
  /// True after the system reset media services, until the next successful
  /// apply.
  private(set) var mediaReset = false
  private let log: EventLog
  /// Whether this model has activated the session. Avoids redundant `setActive`
  /// calls.
  private var isActive = false

  /// Whether the session is in `.playAndRecord`. Compared on the enum, not the
  /// display string.
  private(set) var isPlayAndRecord = false

  /// True when any session state needs attention: a failed apply, an
  /// interruption, a media reset,
  /// or a `playAndRecord` session with no input route.
  var isBad: Bool {
    lastError != nil || isInterrupted || mediaReset
      || (isPlayAndRecord && inputName == "—")
  }

  init(log: EventLog) {
    self.log = log
    refresh()
  }

  /// Applies the VACore session policy for `state` to the shared
  /// `AVAudioSession`.
  func apply(_ state: VAState) {
    let policy = sessionPolicy(for: state)
    let session = AVAudioSession.sharedInstance()
    do {
      let category = avCategory(for: policy.category)
      if session.category != category {
        try session.setCategory(
          category,
          mode: .default,
          options: avOptions(for: policy.category),
        )
      }
      if policy.active != isActive {
        try session.setActive(policy.active)
        isActive = policy.active
        log
          .info(
            "session \(policy.active ? "activated" : "deactivated"): \(policy.category)",
          )
      }
      lastError = nil
      mediaReset = false
    } catch {
      lastError = error.localizedDescription
      log.info("session error: \(error.localizedDescription)")
    }
    refresh()
  }

  /// Maps a VACore category to its `AVAudioSession` equivalent.
  private func avCategory(for category: AudioCategory) -> AVAudioSession
    .Category
  {
    switch category {
    case .soloAmbient: .soloAmbient
    case .playAndRecord: .playAndRecord
    }
  }

  /// Route options for each category. Speaker over receiver, and Bluetooth
  /// headphones allowed.
  private func avOptions(for category: AudioCategory) -> AVAudioSession
    .CategoryOptions
  {
    switch category {
    case .soloAmbient: []
    case .playAndRecord: [.defaultToSpeaker, .allowBluetoothA2DP]
    }
  }

  /// Records whether an interruption is in progress, then re-reads the session.
  func setInterrupted(_ on: Bool) {
    isInterrupted = on
    refresh()
  }

  /// Records a media services reset. The session needs a fresh `apply` to
  /// recover.
  func mediaServicesWereReset() {
    mediaReset = true
    log.info("media services reset")
    refresh()
  }

  /// Re-reads the session's category and routes.
  func refresh() {
    let session = AVAudioSession.sharedInstance()
    isPlayAndRecord = session.category == .playAndRecord
    category = session.category.rawValue
      .replacingOccurrences(of: "AVAudioSessionCategory", with: "")
    outputName = session.currentRoute.outputs.first?.portName ?? "—"
    inputName = session.currentRoute.inputs.first?.portName ?? "—"
    micPermission = switch AVAudioApplication.shared.recordPermission {
    case .granted: "granted"
    case .denied: "denied"
    case .undetermined: "unknown"
    @unknown default: "unknown"
    }
    speechPermission = switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: "authorized"
    case .denied: "denied"
    case .restricted: "restricted"
    case .notDetermined: "unknown"
    @unknown default: "unknown"
    }
  }
}
