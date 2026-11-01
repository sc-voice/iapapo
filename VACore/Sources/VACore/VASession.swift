/// Audio session categories the policy can request. Each platform adapter maps these
/// to its own audio API, such as `AVAudioSession` on Apple platforms.
public enum AudioCategory: Equatable, Sendable {
    /// Plays sound alongside the mute switch and other apps' audio rules. The idle default.
    case soloAmbient
    /// Plays sound and records from the microphone.
    case playAndRecord
}

/// What the audio session should be for a given chat state.
public struct SessionPolicy: Equatable, Sendable {
    public let category: AudioCategory
    public let active: Bool

    public init(category: AudioCategory, active: Bool) {
        self.category = category
        self.active = active
    }
}

/// The audio session policy for `state`. INACTIVE releases the session and restores
/// `.soloAmbient`. Every other state uses `.playAndRecord` and keeps the session active.
public func sessionPolicy(for state: VAState) -> SessionPolicy {
    switch state {
    case .inactive:
        SessionPolicy(category: .soloAmbient, active: false)
    case .idle, .listening, .thinking, .speaking:
        SessionPolicy(category: .playAndRecord, active: true)
    }
}
