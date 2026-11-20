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
  /// The app's one conversation state, owned by the global voice agent.
  private var chatState: VAState { voiceAgent.state }
  /// Whether the mic and speech model can be used right now.
  private var availability: Availability {
    Availability(microphone: !microphone.isDenied, speech: speech.availability)
  }
  @State private var log: EventLog
  @State private var cues: CuePlayer
  @State private var session: AudioSessionModel
  @State private var microphone: Microphone
  @State private var speech: SpeechModel
  @State private var recorder: ClipRecorder
  @State private var wakeScores: WakeScoreModel
  @State private var wake: WakeFeed
  @State private var speaker: Speaker
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
    let log = appLog
    let session = AudioSessionModel(log: log)
    let speech = SpeechModel(log: log)
    let microphone = Microphone(log: log, session: session)
    let recorder = ClipRecorder(log: log)
    let wakeScores = WakeScoreModel()
    let cues = voiceCues
    let speaker = voiceSpeaker
    let agent = voiceAgent
    wakeScores.onAboveAmbient = { agent.heard() }
    agent.send(VAEvent(action: .set, noun: .micAvailable,
                       value: microphone.isDenied ? "false" : "true"))
    let wake = WakeFeed(model: wakeScores, log: log, agent: agent, settings: appSettings)
    // Every captured buffer goes to the analyzer, the sample recorder and the
    // wake scorer. Each drops it when idle.
    microphone.onBuffer = { [weak microphone] buffer in
      speech.feed(buffer)
      recorder.capture(buffer)
      wake.feed(buffer)
      wakeScores.ringDb = microphone?.level ?? -160
    }
    _log = State(initialValue: log)
    _cues = State(initialValue: cues)
    _session = State(initialValue: session)
    _speech = State(initialValue: speech)
    _microphone = State(initialValue: microphone)
    _recorder = State(initialValue: recorder)
    _wakeScores = State(initialValue: wakeScores)
    _wake = State(initialValue: wake)
    _speaker = State(initialValue: speaker)
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
    case .speechUnavailable: "Speech model unavailable"
    case .speechModelNotInstalled: "Speech model needed"
    }
  }

  /// Alert message for a refused entry, with the fix for that blocker.
  private func blockMessage(_ block: EntryBlock) -> String {
    switch block {
    case .speechUnavailable:
      "Speech recognition isn't available for \(speech.locale.identifier) on this device. Change the device language in Settings → General → Language & Region."
    case .speechModelNotInstalled:
      "The \(speech.locale.identifier) speech model needs to be downloaded before \(appName) can listen."
    }
  }

  /// Moves to a state picked from the icon bar. Inactive goes through the mic
  /// button's path so the agent is disabled too.
  private func select(_ target: VAState) {
    if target == .inactive {
      toggleAgent()
    } else {
      enter(target)
    }
  }

  /// Disables or enables the voice agent, then enters the matching state so the
  /// mic and cues follow. Enabling is skipped when entry is refused, so the agent
  /// stays inactive.
  private func toggleAgent() {
    if chatState != .inactive {
      voiceAgent.send(VAEvent(action: .disable, noun: .voiceAgent))
      enter(.inactive)
      return
    }
    // Without the mic the agent goes straight to listening, where typing works.
    let target: VAState = microphone.isDenied ? .listening : .idle
    let entry = VACore.transition(to: target, from: chatState, availability: availability)
    if entry.block == nil {
      voiceAgent.send(VAEvent(action: .enable, noun: .voiceAgent))
    }
    enter(target)
  }

  /// Enters `state` if the state machine allows it. The mic stops before the
  /// session changes and
  /// starts after, so the category change never happens while capture is
  /// running. Then performs the cues.
  private func enter(_ state: VAState) {
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
      // A refused entry keeps the state and plays only its notice.
      for notification in result.step.notifications {
        voiceAgent.send(VAEvent(action: .notify, noun: notification))
      }
    } else {
      voiceAgent.send(VAEvent(
        action: .set,
        noun: .voiceAgentState,
        value: result.step.state.rawValue,
      ))
    }
    let step = result.step
    log.info("state \(chatState) -> \(step.state)")
    if step.state == .inactive {
      microphone.stop()
      speech.stop()
      wake.stop()
    }
    session.apply(step.state)
    guard step.state != .inactive else { return }
    // The mic opens after the entry cue ends, so the recognizer doesn't hear
    // the cue's own speech.
    Task {
      await cues.untilSilent()
      // Skip if the chat has moved on while the cue played.
      guard chatState == step.state else { return }
      microphone.start()
      speech.start()
      // The wake word needs the mic, so it stays off when the mic is denied.
      if !microphone.isDenied { wake.start() }
    }
  }

  var body: some View {
    TabView {
      Tab("Home", systemImage: "house") {
        HomeView(
          state: chatState,
          microphone: microphone,
          speech: speech,
          wakeScores: wakeScores,
          onMicTap: toggleAgent,
          onSelect: select,
        )
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
          speaker: speaker,
          prompt: speech.transcript,
          onSelect: enter,
          onBeginClip: beginClip,
          onEndClip: endClip,
        )
      }
      Tab("Settings", systemImage: "gear") {
        SettingsView()
      }
    }
    .onChange(of: microphone.isDenied) { _, denied in
      voiceAgent.send(VAEvent(action: .set, noun: .micAvailable,
                              value: denied ? "false" : "true"))
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

/// Shows the agent name as a large title, with the microphone button and the
/// agent view under it.
struct HomeView: View {
  let state: VAState
  let microphone: Microphone
  let speech: SpeechModel
  let wakeScores: WakeScoreModel
  let onMicTap: () -> Void
  let onSelect: (VAState) -> Void
  /// Whether the arrow and icon bar are visible.
  @State private var barShown = true
  /// Whether the pointer is over the mic button while the agent is inactive. The
  /// bar then shows the one state the user can enter: idle.
  @State private var barHovered = false
  /// The 10-second countdown that hides the icon bar. Any show restarts it.
  @State private var iconbarCountdown: Task<Void, Never>?
  /// The state a bar tap asked for. Its state change does not show the bar again.
  @State private var tappedTarget: VAState?

  /// How long the icon bar stays visible after the last show, in seconds.
  static let iconbarTimeout = Duration.seconds(2)

  /// Shows the icon bar and restarts the countdown. When the countdown ends, the
  /// bar hides.
  private func showBar() {
    iconbarCountdown?.cancel()
    withAnimation(.easeIn(duration: 0.3)) { barShown = true }
    iconbarCountdown = Task {
      try? await Task.sleep(for: Self.iconbarTimeout)
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.5)) { barShown = false }
      barHovered = false
    }
  }

  /// Hides the icon bar at once and cancels the countdown. Used when a bar button
  /// is tapped.
  private func hideBar() {
    iconbarCountdown?.cancel()
    withAnimation(.easeOut(duration: 0.5)) { barShown = false }
    barHovered = false
  }

  var body: some View {
    VStack(spacing: 32) {
      Text(VAConfig().agentName)
        .font(.system(size: 72, weight: .bold))
        .minimumScaleFactor(0.5)
      HStack(spacing: 0) {
        MicButton(
          state: state,
          micOn: microphone.isOn,
          level: microphone.level,
          denied: microphone.isDenied,
          waiting: (state != .inactive && !microphone.isOn)
            || speech.modelStatus == "downloading",
          action: {
            showBar()
            if state == .inactive { onMicTap() }
          },
          ringOpen: wakeScores.windowAboveAmbient(by: appSettings.ambientWakeDb),
        )
        // Hovering the mic button always shows the icon bar.
        .onHover { hovering in
          guard hovering else { return }
          if state == .inactive { barHovered = true }
          showBar()
        }
        // The gap sits inside the bar, so a hidden bar adds no width and the
        // button stays centered.
        // Faded-out bars leave the layout, so the button recenters.
        if barShown && (state != .inactive || barHovered) {
          HStack(spacing: 24) {
            Image(systemName: "arrow.right")
              .font(.system(size: 36))
            AgentView(state: state, micAvailable: !microphone.isDenied, onSelect: { target in
              tappedTarget = target
              hideBar()
              onSelect(target)
            })
          }
          .padding(.leading, 24)
          .transition(.opacity)
          // While the pointer is over the bar, the countdown is paused. It restarts
          // at the full timeout when the pointer leaves.
          .onHover { hovering in
            if hovering {
              iconbarCountdown?.cancel()
            } else {
              showBar()
            }
          }
        }
      }
      .animation(.easeInOut(duration: 0.3), value: state != .inactive)
    }
    .padding()
    .onAppear { showBar() }
    .onChange(of: state) { _, new in
      // A bar tap already hid the bar; its state change must not show it again.
      if new == tappedTarget {
        tappedTarget = nil
        return
      }
      showBar()
    }
  }
}

/// The microphone button that turns the voice agent on and off. The ring shows
/// the mic level while the mic is on. A spinner replaces the icon while waiting.
/// When permission is denied the button is disabled and shows a red outline.
struct MicButton: View {
  /// The current agent state. The icon follows it while active.
  let state: VAState
  /// Whether the microphone is capturing.
  let micOn: Bool
  /// Microphone level in dBFS.
  let level: Float
  /// Whether microphone permission is denied.
  let denied: Bool
  /// Whether the button must wait, such as while the mic starts or a speech
  /// model downloads.
  let waiting: Bool
  /// Called when the user taps the button.
  let action: () -> Void
  /// Whether the window level is above the ambient floor by the gate margin. Only
  /// idle uses it: the ring is green when true and gray otherwise.
  let ringOpen: Bool

  /// The symbol at `tick`: the moon when inactive, a red ladybug slash when idle
  /// without the mic, a keyboard when listening without the mic (typing replaces
  /// speech), and the current state's symbol otherwise.
  /// - Parameter tick: the whole second, passed to `AgentView.symbol`.
  private func icon(tick: Int) -> String {
    if state == .inactive { return "moon.zzz" }
    if denied && state == .idle { return "ladybug.slash" }
    if denied && state == .listening { return "keyboard" }
    return AgentView.symbol(for: state, tick: tick)
  }

  var body: some View {
    Button(action: action) {
      TimelineView(.animation) { context in
        let seconds = context.date.timeIntervalSinceReferenceDate
        let tick = Int(seconds)
        ZStack {
          // Inactive shows no ring.
          if state != .inactive {
            LevelRing(
              // Idle shows the level only while the window rule holds.
              value: micOn && (state != .idle || ringOpen)
                ? Double((level - WakeMonitor.ambientSilenceDb) / -WakeMonitor.ambientSilenceDb)
                : 0,
              fill: state == .idle && !ringOpen ? .gray : .green,
            )
          }
          if waiting && !denied {
            ProgressView()
          } else {
            Image(systemName: icon(tick: tick))
              .font(.system(size: 36))
              .foregroundStyle(
                denied && state == .idle ? .red
                  : state == .inactive || denied ? .primary : AgentView.idleColor(at: seconds)
              )
          }
        }
      }
    }
    .buttonStyle(.plain)
    .disabled(waiting)
  }
}

/// A bar of icons for the states the user can move to next. Tapping one enters
/// that state. Paired symbols flip every second with a fade.
struct AgentView: View {
  let state: VAState
  /// Whether the mic can be used. When it cannot, listening is typed, so its
  /// icon is a keyboard.
  let micAvailable: Bool
  /// Called with the state the user taps.
  let onSelect: (VAState) -> Void

  /// The states reachable from `state` in one step, per the state diagram in
  /// the design doc. The current state is never included.
  /// - Parameter state: the current state.
  /// Without the mic, idle is never offered, and inactive offers listening, since
  /// the user types.
  /// - Parameters:
  ///   - state: the current state.
  ///   - micAvailable: whether the mic can be used.
  static func permittedNext(from state: VAState, micAvailable: Bool) -> [VAState] {
    let table: [VAState]
    switch state {
    case .inactive: table = [.listening]
    case .idle: table = [.listening, .inactive]
    case .listening: table = [.speaking, .idle, .inactive]
    case .thinking: table = [.speaking, .idle]
    case .speaking: table = [.listening, .idle]
    }
    if micAvailable { return table }
    return table.filter { $0 != .idle }
  }

  var body: some View {
    TimelineView(.animation) { context in
      let seconds = context.date.timeIntervalSinceReferenceDate
      let tick = Int(seconds)
      // One full turn every 4 seconds.
      let spin = Angle.degrees(seconds.truncatingRemainder(dividingBy: 4) / 4 * 360)
      let idleColor = AgentView.idleColor(at: seconds)
      HStack(spacing: 24) {
        ForEach(Self.permittedNext(from: state, micAvailable: micAvailable), id: \.self) { icon in
          Button {
            onSelect(icon)
          } label: {
            Image(systemName: Self.barSymbol(for: icon, tick: tick, micAvailable: micAvailable))
              .font(.system(size: 36))
              .contentTransition(.opacity)
              .rotationEffect(icon == .thinking ? spin : .zero)
              .foregroundStyle(icon == .idle ? idleColor : .primary)
          }
          .buttonStyle(.plain)
        }
      }
      .animation(.easeInOut(duration: 0.5), value: tick)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .overlay {
        // The cartouche: a rounded outline around the state icons.
        RoundedRectangle(cornerRadius: 28)
          .stroke(.secondary, lineWidth: 2)
      }
    }
  }

  /// The idle icon color at `seconds`. Fades to green over 2 seconds, holds 2
  /// seconds, and fades back over 2 seconds, repeating every 6 seconds.
  /// - Parameter seconds: time since the reference date.
  static func idleColor(at seconds: Double) -> Color {
    let phase = seconds.truncatingRemainder(dividingBy: 6)
    let breathe = phase < 2 ? phase / 2 : phase < 4 ? 1 : (6 - phase) / 2
    return Color(.systemBackground).mix(with: .green, by: breathe)
  }

  /// The symbol for one icon-bar button. Without the mic, inactive shows a moon
  /// and listening shows a keyboard, since the user types.
  /// - Parameters:
  ///   - state: the state the button enters.
  ///   - tick: the whole second, passed to `symbol(for:tick:)`.
  ///   - micAvailable: whether the mic can be used.
  static func barSymbol(for state: VAState, tick: Int, micAvailable: Bool) -> String {
    if micAvailable { return symbol(for: state, tick: tick) }
    switch state {
    case .inactive: return "moon.zzz"
    case .listening: return "keyboard"
    default: return symbol(for: state, tick: tick)
    }
  }

  /// The SF Symbol for `state`. Paired symbols alternate on each tick.
  /// - Parameters:
  ///   - state: the state to draw.
  ///   - tick: the whole second, used to pick the filled or outline variant.
  static func symbol(for state: VAState, tick: Int) -> String {
    let filled = (tick / 2).isMultiple(of: 2)
    switch state {
    case .inactive: return "moon.zzz"
    case .idle: return "apple.meditate"
    case .listening: return filled ? "ear.fill" : "ear"
    case .thinking: return filled ? "puzzlepiece.extension.fill" : "puzzlepiece.extension"
    case .speaking: return filled ? "speaker.wave.2.bubble.fill" : "speaker.wave.2.bubble"
    }
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
  let speaker: Speaker
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
        wakeWord: wakeScores.wakeWord,
        ambientDb: wakeScores.ambientDb,
        windowDb: wakeScores.windowDb,
        gateOpen: wakeScores.gateOpen,
        micHistory: wakeScores.micHistory,
        scoreHistory: wakeScores.scoreHistory,
        wakeHistory: wakeScores.wakeHistory,
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
