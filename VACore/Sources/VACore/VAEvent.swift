/// The verb of an event. A closed set: every `switch` on it must cover each verb.
public enum VAVerb: Equatable, Sendable {
  /// Something was perceived: a wake word, a button press, a finished
  /// utterance.
  case sensed
  /// The agent accepts a request for `noun`.
  case acknowledge
  /// Enable/Activate 
  case enable
  /// Disable/Deactivate
  case disable
  /// Assign payload value to direct object of event
  case set
}

/// The noun of an event. An open set of named constants, so new nouns need no
/// change to the enum. Listeners match the nouns they know and ignore the rest.
public struct VANoun: Hashable, Sendable {
  public let name: String

  public init(_ name: String) {
    self.name = name
  }

  /// A wake word was heard, or an acknowledgement of one.
  public static let wakeup = VANoun("wakeup")
  /// The voice agent as a whole: `enable` turns it on, `disable` turns it off.
  public static let voiceAgent = VANoun("voice-agent")
  /// An idle word was heard.
  public static let idleWord = VANoun("idleWord")
  /// A prompt was classified as quick.
  public static let quickPrompt = VANoun("quickPrompt")
  /// A prompt was classified as valid.
  public static let validPrompt = VANoun("validPrompt")
  /// A prompt was classified as invalid.
  public static let invalidPrompt = VANoun("invalidPrompt")
  /// The listening window ran out.
  public static let listenTimeout = VANoun("listenTimeout")
  /// The LLM response is ready.
  public static let llmResponseReady = VANoun("llmResponseReady")
  /// The LLM timed out or failed.
  public static let llmFailed = VANoun("llmFailed")
  /// Playback finished.
  public static let audioFinished = VANoun("audioFinished")
}

/// One event in the form `{ verb, noun, payload }`. Direction comes from the
/// stream that carries the event, not from its verb.
///
/// Equality compares every field, including `zuid`, so two events are equal only
/// when they are the same occurrence. Use `matches(_:)` to compare content.
public struct VAEvent: Equatable, Sendable {
  public let verb: VAVerb
  /// Direct object of noun
  public let noun: VANoun
  /// Informational text for listeners. Nothing depends on it; nil when unused.
  public let payload: String?
  /// Time-ordered identifier for this event, set when the event is created.
  public let zuid: ZUID

  /// - Parameters:
  ///   - verb: what happened.
  ///   - noun: what it happened to.
  ///   - payload: optional informational text.
  ///   - zuid: identifier for the event. Defaults to a new ZUID for now.
  public init(verb: VAVerb, noun: VANoun, payload: String? = nil, zuid: ZUID = .create()) {
    self.verb = verb
    self.noun = noun
    self.payload = payload
    self.zuid = zuid
  }

  /// Whether this event has `verb`, and `noun` when one is given. Payload and
  /// `zuid` are not compared.
  public func matches(verb: VAVerb, noun: VANoun? = nil) -> Bool {
    self.verb == verb && (noun == nil || self.noun == noun)
  }

  /// Reports that `noun` was perceived.
  public static func sensed(_ noun: VANoun, payload: String? = nil) -> VAEvent {
    VAEvent(verb: .sensed, noun: noun, payload: payload)
  }

  /// Reports that the agent accepts `noun`.
  public static func acknowledge(_ noun: VANoun, payload: String? = nil) -> VAEvent {
    VAEvent(verb: .acknowledge, noun: noun, payload: payload)
  }
}

/// A stream of events from one source.
public typealias VAEventStream = AsyncStream<VAEvent>
