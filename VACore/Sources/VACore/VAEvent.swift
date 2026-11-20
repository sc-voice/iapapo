/// The action of an event. A closed set: every `switch` on it must cover each action.
public enum VAAction: Equatable, Sendable {
  /// Something was perceived: a wake word, a button press, a finished
  /// utterance.
  case sensed
  /// The agent finished handling `noun`. `value`, when present, is the result.
  case done
  /// Notify user of somthing described by `noun`
  case notify
  /// Enable/Activate 
  case enable
  /// Disable/Deactivate
  case disable
  /// Assign value to direct object of event
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
  /// The singleton voiceAgent: `enable` turns it on, `disable` turns it off.
  public static let voiceAgent = VANoun("voiceAgent")
  /// State of voice agent
  public static let voiceAgentState = VANoun("voiceAgent.state")
  /// Whether the mic can be used, carried as the value of a `set` event: "true" or "false".
  public static let micAvailable = VANoun("micAvailable")
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
  /// The voice agent turned on.
  public static let agentEnabled = VANoun("agentEnabled")
  /// The voice agent turned off.
  public static let agentDisabled = VANoun("agentDisabled")
  /// The wake word was heard.
  public static let wakeWordHeard = VANoun("wakeWordHeard")
  /// The agent started listening.
  public static let listeningStarted = VANoun("listeningStarted")
  /// The agent started working on a request.
  public static let thinkingStarted = VANoun("thinkingStarted")
  /// The agent started speaking.
  public static let speakingStarted = VANoun("speakingStarted")
  /// The agent returned to idle.
  public static let idleStarted = VANoun("idleStarted")
  /// A request failed.
  public static let requestFailed = VANoun("requestFailed")
  /// The agent needs the user to rephrase the request.
  public static let clarifyRequested = VANoun("clarifyRequested")
  /// Something needs the user's attention, but nothing has failed.
  public static let attentionNeeded = VANoun("attentionNeeded")
}

/// One event in the form `{ action, noun, value }`. Direction comes from the
/// stream that carries the event, not from its action.
///
/// Equality compares every field, including `zuid`, so two events are equal only
/// when they are the same occurrence. Use `matches(_:)` to compare content.
public struct VAEvent: Equatable, Sendable {
  public let action: VAAction
  /// Direct object of noun
  public let noun: VANoun
  /// Informational text for listeners. Nothing depends on it; nil when unused.
  public let value: String?
  /// Time-ordered identifier for this event, set when the event is created.
  public let zuid: ZUID

  /// - Parameters:
  ///   - action: what happened.
  ///   - noun: what it happened to.
  ///   - value: optional informational text.
  ///   - zuid: identifier for the event. Defaults to a new ZUID for now.
  public init(action: VAAction, noun: VANoun, value: String? = nil, zuid: ZUID = .create()) {
    self.action = action
    self.noun = noun
    self.value = value
    self.zuid = zuid
  }

  /// Whether this event has `action`, and `noun` when one is given. Value and
  /// `zuid` are not compared.
  public func matches(action: VAAction, noun: VANoun? = nil) -> Bool {
    self.action == action && (noun == nil || self.noun == noun)
  }

  /// Reports that `noun` was perceived.
  public static func sensed(_ noun: VANoun, value: String? = nil) -> VAEvent {
    VAEvent(action: .sensed, noun: noun, value: value)
  }

  /// Reports that the agent accepts `noun`.
  public static func done(_ noun: VANoun, value: String? = nil) -> VAEvent {
    VAEvent(action: .done, noun: noun, value: value)
  }
}

/// A stream of events from one source.
public typealias VAEventStream = AsyncStream<VAEvent>
