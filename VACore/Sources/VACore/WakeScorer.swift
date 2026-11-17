import CoreML
import Foundation

/// Errors from `WakeScorer`.
public enum WakeScorerError: Error {
  /// The model returned no `prob` output.
  case missingProbability
  /// The package has no bundled `wakenet.mlmodelc`. Run `make build-model`.
  case missingBundledModel
  /// The model's user metadata has no valid `window_len`. Re-export the model.
  case missingWindowLength
}

/// Scores 48 kHz audio with the wake-word Core ML model, through the same chain
/// as live audio:
/// `Resampler48To16`, `HopCutter`, `SlidingWindow`, `LogMelFrontEnd`, then the
/// model.
///
/// The offline checks and the live matcher share this type, so a score means
/// the same thing in both.
public struct WakeScorer {
  private let model: MLModel
  private let frontEnd = LogMelFrontEnd()
  /// Samples per 16 kHz window, read from the model's `window_len` metadata.
  public let windowLength: Int

  /// - Parameter model: a loaded `wakenet.mlpackage` with input `logmel`, output
  /// `prob`, and `window_len` in its user metadata.
  /// - Throws: `WakeScorerError.missingWindowLength` if the metadata lacks it.
  public init(model: MLModel) throws {
    let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
    guard let value = metadata?["window_len"], let length = Int(value), length > 0 else {
      throw WakeScorerError.missingWindowLength
    }
    self.model = model
    windowLength = length
  }

  /// The compiled model bundled as a VACore resource (see `make build-model`).
  /// - Returns: the bundled model's URL, or nil if it is not in the bundle.
  public static func bundledModelURL() -> URL? {
    Bundle.module.url(forResource: "wakenet", withExtension: "mlmodelc")
  }

  /// Loads the compiled model bundled as a VACore resource (see `make
  /// build-model`).
  /// - Returns: a scorer for the bundled model.
  public static func loadBundled() throws -> WakeScorer {
    guard let url = bundledModelURL() else {
      throw WakeScorerError.missingBundledModel
    }
    return try WakeScorer(model: MLModel(contentsOf: url))
  }

  /// Compiles and loads the `wakenet.mlpackage` in a run folder.
  /// - Parameter runFolder: a run folder, such as
  /// `lab/wakeword/out/<version>/no-take-<run id>`.
  /// - Returns: a scorer for that model.
  public static func load(runFolder: URL) async throws -> WakeScorer {
    let compiled = try await MLModel
      .compileModel(at: runFolder.appendingPathComponent("wakenet.mlpackage"))
    return try WakeScorer(model: MLModel(contentsOf: compiled))
  }

  /// Scores one clip. Every window the stream completes is scored, then the
  /// tails the test harness flushes.
  /// - Parameter chunks: 48 kHz mono samples, in order, in any chunk sizes.
  /// - Returns: the highest window probability, and how many windows were
  /// scored.
  public func maxProbability(chunks: [[Float]]) async throws
    -> (maxProb: Float, windows: Int)
  {
    var monitor = WakeMonitor(scorer: self)
    var scores: [WakeScore] = []
    for chunk in chunks {
      scores += try await monitor.process(chunk)
    }
    scores += try await monitor.flush()
    return (scores.map(\.probability).max() ?? 0, scores.count)
  }

  /// Model probability for one 16 kHz window of `windowLength` samples.
  /// - Parameter samples: the window's samples.
  /// - Returns: the probability that the window contains the wake word.
  public func probability(of samples: [Float]) async throws -> Float {
    let (values, frames) = frontEnd.features(samples)
    let shape = [
      1,
      1,
      NSNumber(value: LogMelFrontEnd.nMels),
      NSNumber(value: frames),
    ]
    let input = try MLMultiArray(shape: shape, dataType: .float32)
    let ptr = input.dataPointer.bindMemory(
      to: Float.self,
      capacity: values.count,
    )
    values.withUnsafeBufferPointer { buf in
      ptr.update(from: buf.baseAddress!, count: values.count)
    }
    let provider =
      try MLDictionaryFeatureProvider(
        dictionary: ["logmel": MLFeatureValue(multiArray: input)],
      )
    let out = try await model.prediction(from: provider)
    guard let prob = out.featureValue(for: "prob")?.multiArrayValue else {
      throw WakeScorerError.missingProbability
    }
    return prob[0].floatValue
  }
}
