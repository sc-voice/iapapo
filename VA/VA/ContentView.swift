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
    /// Prompt as it is being spoken and processed.
    @State private var prompt: String = ""
    @State private var log: EventLog
    @State private var cues: CuePlayer
    @State private var session: AudioSessionModel
    @State private var microphone: Microphone
    @State private var speech = SpeechModel()
    /// The reason the last entry was refused, shown in the alert until dismissed.
    @State private var block: EntryBlock?
    /// Shows the speech model download sheet when entry is refused only for a missing model.
    @State private var showDownload = false
    /// The state the user tried to enter, retried once the model is installed.
    @State private var pendingState: VAState?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let log = EventLog()
        let session = AudioSessionModel(log: log)
        _log = State(initialValue: log)
        _cues = State(initialValue: CuePlayer(log: log))
        _session = State(initialValue: session)
        _microphone = State(initialValue: Microphone(log: log, session: session))
    }

    /// The name the user sees under the app icon. Read from the bundle, not the internal target name.
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "this app"
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

    /// Enters `state` if the state machine allows it. The mic stops before the session changes and
    /// starts after, so the category change never happens while capture is running. Then performs the cues.
    private func enter(_ state: VAState) {
        let availability = Availability(microphone: !microphone.isDenied, speech: speech.availability)
        let result = VACore.transition(to: state, from: chatState, availability: availability)
        if let refused = result.block {
            log.record("blocked: \(refused)")
            if refused == .speechModelNotInstalled {
                pendingState = state
                showDownload = true
            } else {
                block = refused
            }
        }
        let step = result.step
        chatState = step.state
        if step.state == .inactive {
            microphone.stop()
        }
        session.apply(step.state)
        if step.state != .inactive {
            microphone.start()
        }
        VACore.perform(step, with: cues)
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
                    prompt: prompt,
                    onSelect: enter
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw).map { String(describing: $0) } ?? "\(raw)"
            log.record("route change: \(reason)")
            session.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let type = AVAudioSession.InterruptionType(rawValue: raw).map { String(describing: $0) } ?? "\(raw)"
            log.record("interruption: \(type)")
            session.setInterrupted(AVAudioSession.InterruptionType(rawValue: raw) == .began)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
            session.mediaServicesWereReset()
        }
        .task {
            await speech.refreshStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            // Permission can change in Settings while the app is away, so re-read on return.
            if phase == .active {
                session.refresh()
            }
        }
        .alert(block.map(blockTitle) ?? "", isPresented: Binding(get: { block != nil }, set: { if !$0 { block = nil } })) {
            Button("OK") {}
        } message: {
            Text(block.map(blockMessage) ?? "")
        }
        .sheet(isPresented: $showDownload) {
            SpeechDownloadView(speech: speech, message: blockMessage(.speechModelNotInstalled)) {
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
    let prompt: String
    let onSelect: (VAState) -> Void

    /// Green while capturing, gray when off. Off is a normal state, not an error.
    private var micColor: Color {
        microphone.isOn ? .green : .gray
    }

    /// Green when installed or available, red when this locale has no model, gray while unknown or downloading.
    private var speechModelColor: Color {
        switch speech.modelStatus {
        case "installed", "supported": .green
        case "unsupported": .red
        default: .gray
        }
    }

    /// Green when granted, red when denied since that blocks listening, gray when not yet answered.
    private var micPermissionColor: Color {
        switch session.micPermission {
        case "granted": .green
        case "denied": .red
        default: .gray
        }
    }

    /// Every ChatState the developer can enter.
    private static let states: [VAState] = [.inactive, .idle, .listening, .thinking, .speaking]

    var body: some View {
        HStack(alignment: .top) {
            Form {
                stateSection
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
    }

    private var logSection: some View {
        VStack(alignment: .leading) {
            Text("Event Log")
                .font(.headline)
                .padding(.top)
            // Oldest entry at the top; keeps the newest entry in view at the bottom.
            ScrollViewReader { proxy in
                List(log.entries) { entry in
                    Text("\(entry.sequence) \(entry.time.formatted(date: .omitted, time: .standard)) \(entry.text)")
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

    private var stateSection: some View {
        Section("State") {
            LabeledContent("Audio Session") {
                // Red on any failure or interruption. Green when the app's session is active (playAndRecord).
                // Gray for the soloAmbient default.
                Text(session.category)
                    .foregroundStyle(session.isBad ? .red : session.isPlayAndRecord ? .green : .gray)
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
            Picker("ChatState", selection: Binding(get: { chatState }, set: onSelect)) {
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
                    Text(microphone.isOn ? String(format: "%.0f dBFS", microphone.level) : "—")
                        .font(.caption.monospaced())
                }
            }
            LabeledContent("Audio Output") {
                // Shows the cue while it plays, then fades back to OFF when it ends.
                Text("\(session.outputName): \(cues.nowPlaying.map { String(describing: $0) } ?? "OFF")")
                    .foregroundStyle(cues.nowPlaying == nil ? .gray : .green)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.6), value: cues.nowPlaying)
            }
            LabeledContent("Last cue", value: cues.lastCue.map { String(describing: $0) } ?? "—")
        }
    }
}

#Preview {
    ContentView()
}
