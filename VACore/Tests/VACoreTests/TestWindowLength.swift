import Foundation
@testable import VACore

/// Samples per window of the bundled model, from its `window_len` metadata.
/// Tests use this in place of a hardcoded length.
let testWindowLength: Int = {
  do {
    return try WakeScorer.loadBundled().windowLength
  } catch {
    fatalError("bundled model has no window_len metadata: \(error)")
  }
}()
