//
//  ContentView.swift
//  VA
//
//  Created by Visakha on 10/29/26.
//

import SwiftUI
import VACore

/// Microphone state shown on the Developer tab.
enum InputState: String {
    case on = "ON"
    case off = "OFF"
}

/// Root view with a Home tab and a Developer tab.
struct ContentView: View {
    @State private var chatState: VAState = .inactive
    @State private var inputState: InputState = .off
    /// Prompt as it is being spoken and processed.
    @State private var prompt: String = ""
    @State private var cues = CuePlayer()

    /// Enters `state` unconditionally and performs its entry effects as cues.
    private func enter(_ state: VAState) {
        let step = VACore.transition(to: state)
        chatState = step.state
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
                    inputState: inputState,
                    cues: cues,
                    prompt: prompt,
                    onSelect: enter
                )
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
    let inputState: InputState
    let cues: CuePlayer
    let prompt: String
    let onSelect: (VAState) -> Void

    /// Every ChatState the developer can enter.
    private static let states: [VAState] = [.inactive, .idle, .listening, .thinking, .speaking]

    var body: some View {
        Form {
            Section("State") {
                Picker("ChatState", selection: Binding(get: { chatState }, set: onSelect)) {
                    ForEach(Self.states, id: \.self) { state in
                        Text(String(describing: state)).tag(state)
                    }
                }
                .pickerStyle(.menu)
                LabeledContent("Microphone", value: inputState.rawValue)
                LabeledContent("Speaker") {
                    // Shows the cue while it plays, then fades its name out when it ends.
                    Text(cues.lastCue.map { String(describing: $0) } ?? "—")
                        .opacity(cues.nowPlaying == nil ? 0 : 1)
                        .animation(.easeOut(duration: 0.6), value: cues.nowPlaying)
                }
                LabeledContent("Last cue", value: cues.lastCue.map { String(describing: $0) } ?? "—")
            }
            Section("Prompt") {
                Text(prompt.isEmpty ? "—" : prompt)
                    .textSelection(.enabled)
            }
        }
    }
}

#Preview {
    ContentView()
}
