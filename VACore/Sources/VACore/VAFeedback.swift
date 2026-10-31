/// Carries out effects as user feedback. The app supplies the real sounds and display;
/// tests supply a recorder that captures the effects instead.
public protocol Feedback {
    /// Performs one effect, such as playing a cue or cancelling speech.
    func perform(_ effect: Effect)
}

/// Performs each effect of `step` in order.
public func perform(_ step: Step, with feedback: Feedback) {
    for effect in step.effects {
        feedback.perform(effect)
    }
}
