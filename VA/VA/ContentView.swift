//
//  ContentView.swift
//  VA
//
//  Created by Visakha on 10/29/26.
//

import AVFoundation
import SwiftUI
import VACore

/// Root view with a Home tab and a Developer tab.
struct ContentView: View {
  @State private var chatState: VAState = .inactive
  @State private var log: EventLog
  @State private var cues: CuePlayer
  @State private var session: AudioSessionModel
  @State private var microphone: Microphone
  @State private var speech: SpeechModel
  @State private var recorder: ClipRecorder
  @State private var wakeScores: WakeScoreModel
  @State private var wake: WakeFeed
  /// The folder for the current recording session, created on the first sample.
  @State private var take: URL?
  /// The clip being written between `beginClip` and `endClip`, if any.
  @State private var openClip: URL?
  /// The reason the last entry was refused, shown in the alert until dismissed.
  @State private var block: EntryBlock?
  /// Shows the speech model download sheet when entry is refused only for a
  /// missing model.
  @State private var showDownload = false
  /// The state the user tried to enter, retried once the model is installed.
  @State private var pendingState: VAState?
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let log = EventLog()
    let session = AudioSessionModel(log: log)
    let speech = SpeechModel(log: log)
    let microphone = Microphone(log: log, session: session)
    let recorder = ClipRecorder(log: log)
    let wakeScores = WakeScoreModel()
    let wake = WakeFeed(model: wakeScores, log: log)
    // Every captured buffer goes to the analyzer, the sample recorder and the
    // wake scorer. Each drops it when idle.
    microphone.onBuffer = { [weak microphone] buffer in
      speech.feed(buffer)
      recorder.capture(buffer)
      wake.feed(buffer)
      wakeScores.ringDb = microphone?.level ?? -160
    }
    _log = State(initialValue: log)
    _cues = State(initialValue: CuePlayer(log: log))
    _session = State(initialValue: session)
    _speech = State(initialValue: speech)
    _microphone = State(initialValue: microphone)
    _recorder = State(initialValue: recorder)
    _wakeScores = State(initialValue: wakeScores)
    _wake = State(initialValue: wake)
  }

  /// Arms the recorder for one clip of `label` in the current take. The clip
  /// stays open until `endClip`.
  /// Audio is captured only once the mic is running, so an entry cue played
  /// before that is not recorded.
  private func beginClip(_ label: SampleLabel) async -> Bool {
    do {
      let store = SampleStore()
      let current: URL
      if let existing = take {
        current = existing
      } else {
        current = try store.newTake()
        recorder.resetFloor()
      }
      take = current
      let url = try store.nextClipURL(label, in: current)
      openClip = url
      // The listening cue is playing now. Record only after it ends, so the cue
      // is not in the sample.
      await cues.untilSilent()
      guard openClip == url else { return false }
      recorder.start(writingTo: url, label: label)
      return true
    } catch {
      log.info("sample error: \(error.localizedDescription)")
      return false
    }
  }

  /// Closes the open clip. Keeps the file when `keep` is true and it passes
  /// `ClipCheck`, otherwise deletes it.
  /// Returns whether the clip was kept.
  private func endClip(keep: Bool) -> Bool {
    let reason = keep ? recorder.rejectionReason() : nil
    if keep, reason == nil {
      recorder.keepClipFrames()
    }
    recorder.stop()
    guard let url = openClip else { return false }
    openClip = nil
    if keep, reason == nil {
      log.info("sample saved: \(url.lastPathComponent)")
      return true
    }
    if let reason {
      log.info("sample rejected: \(reason)")
    }
    try? FileManager.default.removeItem(at: url)
    return false
  }

  /// The name the user sees under the app icon. Read from the bundle, not the
  /// internal target name.
  private var appName: String {
    Bundle.main
      .object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "this app"
  }

  /// Alert title for a refused entry.
  private func blockTitle(_ block: EntryBlock) -> String {
    switch block {
    case .microphoneDenied: "Microphone denied"
    case .speechUnavailable: "Speech model unavailable"
    case .speechModelNotInstalled: "Speech model needed"
    }
  }

  /// Alert message for a refused entry, with the fix for that blocker.
  private func blockMessage(_ block: EntryBlock) -> String {
    switch block {
    case .microphoneDenied:
      "\(appName) stays inactive without microphone access. Enable it in Settings → \(appName) → Microphone."
    case .speechUnavailable:
      "Speech recognition isn't available for \(speech.locale.identifier) on this device. Change the device language in Settings → General → Language & Region."
    case .speechModelNotInstalled:
      "The \(speech.locale.identifier) speech model needs to be downloaded before \(appName) can listen."
    }
  }

  /// Enters `state` if the state machine allows it. The mic stops before the
  /// session changes and
  /// starts after, so the category change never happens while capture is
  /// running. Then performs the cues.
  private func enter(_ state: VAState) {
    let availability = Availability(
      microphone: !microphone.isDenied,
      speech: speech.availability,
    )
    let result = VACore.transition(
      to: state,
      from: chatState,
      availability: availability,
    )
    if let refused = result.block {
      log.info("blocked: \(refused)")
      if refused == .speechModelNotInstalled {
        pendingState = state
        showDownload = true
      } else {
        block = refused
      }
    }
    let step = result.step
    log.info("state \(chatState) -> \(step.state)")
    chatState = step.state
    if step.state == .inactive {
      microphone.stop()
      speech.stop()
      wake.stop()
    }
    session.apply(step.state)
    VACore.perform(step, with: cues)
    guard step.state != .inactive else { return }
    // The mic opens after the entry cue ends, so the recognizer doesn't hear
    // the cue's own speech.
    Task {
      await cues.untilSilent()
      // Skip if the chat has moved on while the cue played.
      guard chatState == step.state else { return }
      microphone.start()
      speech.start()
      wake.start()
    }
  }

  var body: some View {
    TabView {
      Tab("Home", systemImage: "house") {
        HomeView()
      }
      Tab("Developer", systemImage: "hammer") {
        DeveloperView(
          chatState: chatState,
          microphone: microphone,
          cues: cues,
          log: log,
          session: session,
          speech: speech,
          wakeScores: wakeScores,
          prompt: speech.transcript,
          onSelect: enter,
          onBeginClip: beginClip,
          onEndClip: endClip,
        )
      }
    }
    .onReceive(NotificationCenter.default
      .publisher(for: AVAudioSession.routeChangeNotification))
    { note in
      let raw = note
        .userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
      let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        .map { String(describing: $0) } ?? "\(raw)"
      log.info("route change: \(reason)")
      session.refresh()
    }
    .onReceive(NotificationCenter.default
      .publisher(for: AVAudioSession.interruptionNotification))
    { note in
      let raw = note
        .userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
      let type = AVAudioSession.InterruptionType(rawValue: raw)
        .map { String(describing: $0) } ?? "\(raw)"
      log.info("interruption: \(type)")
      session
        .setInterrupted(AVAudioSession
          .InterruptionType(rawValue: raw) == .began)
    }
    .onReceive(NotificationCenter.default
      .publisher(for: AVAudioSession.mediaServicesWereResetNotification))
    { _ in
      session.mediaServicesWereReset()
    }
    .task {
      await speech.refreshStatus()
    }
    .onChange(of: scenePhase) { _, phase in
      // Permission can change in Settings while the app is away, so re-read on
      // return.
      if phase == .active {
        session.refresh()
      }
    }
    .alert(
      block.map(blockTitle) ?? "",
      isPresented: Binding(
        get: { block != nil },
        set: { if !$0 { block = nil } },
      ),
    ) {
      Button("OK") {}
    } message: {
      Text(block.map(blockMessage) ?? "")
    }
    .sheet(isPresented: $showDownload) {
      SpeechDownloadView(
        speech: speech,
        message: blockMessage(.speechModelNotInstalled),
      ) {
        showDownload = false
        if let target = pendingState {
          pendingState = nil
          enter(target)
        }
      }
    }
  }
}

/// Shows the agent name as a large title.
struct HomeView: View {
  var body: some View {
    Text(VAConfig().agentName)
      .font(.system(size: 72, weight: .bold))
      .minimumScaleFactor(0.5)
      .padding()
  }
}

/// Live view of the state machine, microphone, speaker, and current prompt.
/// The ChatState picker enters the chosen state through `transition(to:)`.
struct DeveloperView: View {
  let chatState: VAState
  let microphone: Microphone
  let cues: CuePlayer
  let log: EventLog
  let session: AudioSessionModel
  let speech: SpeechModel
  let wakeScores: WakeScoreModel
  let prompt: String
  let onSelect: (VAState) -> Void
  let onBeginClip: (SampleLabel) async -> Bool
  let onEndClip: (Bool) -> Bool
  /// Whether the training wizard sheet is open.
  @State private var showWizard = false

  /// Green while capturing, gray when off. Off is a normal state, not an error.
  private var micColor: Color {
    microphone.isOn ? .green : .gray
  }

  /// Green when installed or available, red when this locale has no model, gray
  /// while unknown or downloading.
  private var speechModelColor: Color {
    switch speech.modelStatus {
    case "installed", "supported": .green
    case "unsupported": .red
    default: .gray
    }
  }

  /// Green when granted, red when denied since that blocks listening, gray when
  /// not yet answered.
  private var micPermissionColor: Color {
    switch session.micPermission {
    case "granted": .green
    case "denied": .red
    default: .gray
    }
  }

  /// Every ChatState the developer can enter.
  private static let states: [VAState] = [
    .inactive,
    .idle,
    .listening,
    .thinking,
    .speaking,
  ]

  var body: some View {
    HStack(alignment: .top) {
      Form {
        stateSection
        samplesSection
      }
      .frame(maxWidth: .infinity)
      // Log and prompt share the right side equally.
      VStack(spacing: 0) {
        logSection
          .frame(maxHeight: .infinity)
        promptSection
          .frame(maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity)
    }
    .blur(radius: showWizard ? 4 : 0)
    .animation(.default, value: showWizard)
    .sheet(isPresented: $showWizard) {
      TrainingWizard(
        microphoneOn: microphone.isOn,
        level: microphone.level,
        wakeScore: wakeScores.shown,
        ambientDb: wakeScores.ambientDb,
        micHistory: wakeScores.micHistory,
        scoreHistory: wakeScores.scoreHistory,
        transcript: prompt,
        onEnter: onSelect,
        onBeginClip: onBeginClip,
        onEndClip: onEndClip,
      ) {
        showWizard = false
      }
      .presentationSizing(.fitted)
    }
  }

  private var logSection: some View {
    VStack(alignment: .leading) {
      Text("Event Log")
        .font(.headline)
        .padding(.top)
      // Oldest entry at the top; keeps the newest entry in view at the bottom.
      ScrollViewReader { proxy in
        List(log.entries) { entry in
          Text(
            "\(entry.sequence) \(entry.time.formatted(date: .omitted, time: .standard)) \(entry.text)",
          )
          .font(.caption.monospaced())
        }
        .onChange(of: log.entries.last?.id) { _, newID in
          if let newID {
            proxy.scrollTo(newID, anchor: .bottom)
          }
        }
      }
    }
  }

  private var promptSection: some View {
    VStack(alignment: .leading) {
      Text("Prompt")
        .font(.headline)
        .padding(.top)
      ScrollView {
        Text(prompt.isEmpty ? "—" : prompt)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
    }
    .padding(.horizontal)
  }

  /// Opens the training wizard, which records wake-word samples. Needs the mic
  /// on.
  private var samplesSection: some View {
    Section("Wake Word") {
      Button("Train IaPapo") {
        // The wizard opens INACTIVE, so only check that IDLE would be allowed.
        // A blocked entry enters IDLE to show its own sheet or alert instead,
        // and the wizard stays closed so the two sheets do not collide.
        let availability = Availability(
          microphone: !microphone.isDenied,
          speech: speech.availability,
        )
        if entryBlock(for: .idle, availability: availability) == nil {
          showWizard = true
        } else {
          onSelect(.idle)
        }
      }
    }
  }

  private var stateSection: some View {
    Section("State") {
      LabeledContent("Audio Session") {
        // Red on any failure or interruption. Green when the app's session is
        // active (playAndRecord).
        // Gray for the soloAmbient default.
        Text(session.category)
          .foregroundStyle(session.isBad ? .red : session
            .isPlayAndRecord ? .green : .gray)
      }
      LabeledContent("Microphone Permission") {
        Text(session.micPermission)
          .foregroundStyle(micPermissionColor)
      }
      LabeledContent("Speech Permission", value: session.speechPermission)
      LabeledContent("Speech Model (\(speech.locale.identifier))") {
        Text(speech.modelStatus)
          .foregroundStyle(speechModelColor)
      }
      Picker(
        "ChatState",
        selection: Binding(get: { chatState }, set: onSelect),
      ) {
        ForEach(Self.states, id: \.self) { state in
          Text(String(describing: state)).tag(state)
        }
      }
      .pickerStyle(.menu)
      LabeledContent("Audio Input") {
        VStack(alignment: .trailing) {
          Text("\(session.inputName): \(microphone.isOn ? "ON" : "OFF")")
            .foregroundStyle(micColor)
          // Bar spans −60 dBFS (empty) to 0 dBFS (full).
          ProgressView(value: min(max((microphone.level + 60) / 60, 0), 1))
            .frame(width: 160)
          Text(microphone
            .isOn ? String(format: "%.0f dBFS", microphone.level) : "—")
            .font(.caption.monospaced())
        }
      }
      LabeledContent("Audio Output") {
        // Shows the cue while it plays, then fades back to OFF when it ends.
        Text(
          "\(session.outputName): \(cues.nowPlaying.map { String(describing: $0) } ?? "OFF")",
        )
        .foregroundStyle(cues.nowPlaying == nil ? .gray : .green)
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.6), value: cues.nowPlaying)
      }
      LabeledContent(
        "Last cue",
        value: cues.lastCue.map { String(describing: $0) } ?? "—",
      )
    }
  }
}

#Preview {
  ContentView()
}
