//
//  SpeechModel.swift
//  VA
//

import Observation
import Speech
import VACore

/// Observable status of the on-device speech model for SpeechTranscriber.
@Observable
final class SpeechModel {
    /// Model status for the transcriber's locale, such as "installed" or "supported".
    private(set) var modelStatus = "—"
    /// The locale the transcriber is built for. Each speech model covers one locale.
    let locale: Locale
    private let transcriber: SpeechTranscriber

    init(locale: Locale = .current) {
        self.locale = locale
        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    /// Whether the model is usable, not installed but downloadable, or absent for this locale.
    var availability: SpeechModelState {
        switch modelStatus {
        case "installed": .installed
        case "supported", "downloading": .notInstalled
        default: .unavailable
        }
    }

    /// True while `download()` runs.
    private(set) var isDownloading = false
    /// Message from the last failed download, or nil.
    private(set) var downloadError: String?

    /// Requests and installs the model, then re-reads its status. A download error is kept for the sheet.
    func download() async {
        isDownloading = true
        downloadError = nil
        defer { isDownloading = false }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            downloadError = error.localizedDescription
        }
        await refreshStatus()
    }

    /// Reads whether the model for the transcriber's locale is on the device.
    func refreshStatus() async {
        modelStatus = switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: "installed"
        case .supported: "supported"
        case .downloading: "downloading"
        case .unsupported: "unsupported"
        @unknown default: "unknown"
        }
    }
}
