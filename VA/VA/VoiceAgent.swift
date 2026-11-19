import VACore

/// The app's shared event log, for every component that records events.
@MainActor
let appLog = EventLog()

/// The app's settings, read from UserDefaults.
let appSettings: any AppSettings = UserDefaultsSettings()

/// The app's speaker, which speaks the voice agent's replies aloud.
@MainActor
let voiceSpeaker = Speaker(log: appLog, settings: appSettings)

/// The voice agent the user talks to: the app's one `VAAgent`, with the speaker
/// as its actor.
@MainActor
let voiceAgent = VAAgent(actors: [voiceSpeaker])
