//
//  SpeechDownloadView.swift
//  VA
//

import SwiftUI
import VACore

/// Modal sheet that offers the speech model download when listening is blocked by a missing model.
/// Not an error: the chat stays inactive until the model is installed, then retries the entry.
struct SpeechDownloadView: View {
    let speech: SpeechModel
    let message: String
    let onInstalled: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Speech model needed")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .multilineTextAlignment(.center)
            Text("Status: \(speech.modelStatus)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if speech.isDownloading {
                ProgressView()
            }
            if let error = speech.downloadError {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button(speech.downloadError == nil ? "Download" : "Retry") {
                Task {
                    await speech.download()
                    if speech.availability == .installed {
                        onInstalled()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(speech.isDownloading)
        }
        .padding(32)
        .interactiveDismissDisabled(speech.isDownloading)
        .presentationDetents([.medium])
    }
}
