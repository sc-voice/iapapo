/// Reasons the chat cannot enter a listening state. Each case has its own fix,
/// which the app presents.
public enum EntryBlock: Equatable, Sendable {
  /// This locale has no speech model on this device.
  case speechUnavailable
  /// The speech model can be downloaded but is not installed yet. Benign: the
  /// app offers the download.
  case speechModelNotInstalled
}

/// Whether the speech model for the current locale is usable now.
public enum SpeechModelState: Equatable, Sendable {
  /// Installed and ready to use.
  case installed
  /// Downloadable, but not on the device yet.
  case notInstalled
  /// No model exists for this locale on this device.
  case unavailable
}

/// Whether each dependency the listening states need is usable right now.
public struct Availability: Equatable, Sendable {
  public let microphone: Bool
  public let speech: SpeechModelState

  public init(microphone: Bool, speech: SpeechModelState) {
    self.microphone = microphone
    self.speech = speech
  }
}

/// The first blocker that prevents entering `state`, checked in a fixed order,
/// or nil if none applies.
/// INACTIVE listens to nothing, so it is never blocked.
public func entryBlock(for state: VAState,
                       availability: Availability) -> EntryBlock?
{
  guard state != .inactive else { return nil }
  switch availability.speech {
  case .installed: return nil
  case .notInstalled: return .speechModelNotInstalled
  case .unavailable: return .speechUnavailable
  }
}

/// Enters `state` if no blocker applies. A blocked entry stays in `current` and
/// returns the blocker,
/// so the app can explain it. Real failures play the error cue. A missing
/// speech model is not a failure,
/// so it plays the attention cue alongside the download prompt.
public func transition(
  to state: VAState,
  from current: VAState,
  availability: Availability,
)
  -> (step: Step, block: EntryBlock?)
{
  guard let block = entryBlock(for: state, availability: availability) else {
    // Re-entering the current state changes nothing, so it plays no cue.
    if state == current {
      return (Step(state: current), nil)
    }
    return (transition(to: state), nil)
  }
  let notice: VANoun = block == .speechModelNotInstalled ? .attentionNeeded : .requestFailed
  return (Step(state: current, notifications: [notice]), block)
}
