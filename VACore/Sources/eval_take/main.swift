/// Scores one take with a run's Core ML model and writes eval-<id>.json into
/// the run folder.
/// The record has the same fields as the one scripts/python/eval_take.py
/// writes, with "pipeline": "swift",
/// so scripts/eval-table.py reads both.
///
/// Usage: eval_take <run folder> <take folder> [--threshold T]
///
/// The take must be 48 kHz, the only rate the Swift resampler handles. Clips
/// are scored untrimmed, as live audio would be.
/// Build and run in release mode: a debug build is about 130 times slower.

import AVFoundation
import CryptoKit
import Foundation
import VACore

/// An error that stops the run, with the message to print.
struct EvalError: Error, CustomStringConvertible {
  let description: String
}

/// The repo root, four folders above this file
/// (VACore/Sources/eval_take/main.swift).
let repoRoot: URL = {
  var url = URL(fileURLWithPath: #filePath)
  for _ in 0 ..< 4 {
    url.deleteLastPathComponent()
  }
  return url
}()

/// Prints the message to stderr and exits with status 1.
func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

/// Git's blob ID for a file: SHA-1 over "blob <size>\0" plus the bytes, the
/// same as `git hash-object`.
func gitBlobID(_ url: URL) throws -> String {
  let data = try Data(contentsOf: url)
  var blob = Data("blob \(data.count)\0".utf8)
  blob.append(data)
  return Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }
    .joined()
}

/// A path relative to the repo root, so the record reads the same on any
/// machine.
func repoRelative(_ url: URL) -> String {
  let path = url.standardizedFileURL.path
  let prefix = repoRoot.standardizedFileURL.path + "/"
  return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
}

/// A new 10-character evaluation id from `nf id`, as eval_take.py makes.
func newEvalID() throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["nf", "id"]
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0
  else { throw EvalError(description: "nf id failed") }
  let id = String(decoding: data, as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  return String(id.prefix(10))
}

/// Mono samples of a 48 kHz WAV, averaging channels as train.load_clip does.
func loadClip(_ url: URL) throws -> [Float] {
  let file = try AVAudioFile(forReading: url)
  let format = file.processingFormat
  guard format.sampleRate == 48000 else {
    throw EvalError(
      description: "\(url.lastPathComponent) is \(Int(format.sampleRate)) Hz; eval_take needs 48 kHz",
    )
  }
  guard let buffer = AVAudioPCMBuffer(
    pcmFormat: format,
    frameCapacity: AVAudioFrameCount(file.length),
  ) else {
    throw EvalError(
      description: "cannot allocate a buffer for \(url.lastPathComponent)",
    )
  }
  try file.read(into: buffer)
  guard let channels = buffer.floatChannelData else {
    throw EvalError(
      description: "\(url.lastPathComponent) has no float samples",
    )
  }
  let frames = Int(buffer.frameLength)
  let count = Int(format.channelCount)
  var mono = [Float](repeating: 0, count: frames)
  for c in 0 ..< count {
    for i in 0 ..< frames {
      mono[i] += channels[c][i]
    }
  }
  if count > 1 {
    let scale = 1 / Float(count)
    for i in 0 ..< frames {
      mono[i] *= scale
    }
  }
  return mono
}

/// Scores every WAV in the take and writes the eval record into the run folder.
func evaluate(
  runDir: URL,
  takeDir: URL,
  thresholdOverride: Double?,
) async throws {
  let runJSON = try JSONSerialization.jsonObject(
    with: Data(contentsOf: runDir
      .appendingPathComponent("run.json"))) as? [String: Any] ?? [:]
  guard let windowLen = runJSON["window_len"] as? Int else {
    throw EvalError(
      description: "run.json has no window_len; this run predates the current train.py",
    )
  }
  guard let trainArgs =
    (runJSON["train_args"] ?? runJSON["args"]) as? [String: Any],
    let modelRunID = trainArgs["run_id"] as? String,
    let trainedThreshold = trainArgs["threshold"] as? Double
  else {
    throw EvalError(
      description: "run.json has no train_args with run_id and threshold",
    )
  }
  let threshold = thresholdOverride ?? trainedThreshold

  let evalID = try newEvalID()
  let out = runDir.appendingPathComponent("eval-\(evalID).json")
  guard !FileManager.default.fileExists(atPath: out.path) else {
    throw EvalError(description: "\(out.lastPathComponent) already exists")
  }

  let scorer = try await WakeScorer.load(runFolder: runDir)
  guard scorer.windowLength == windowLen else {
    throw EvalError(
      description: "model window_len \(scorer.windowLength) differs from run.json \(windowLen)",
    )
  }
  let takeFiles = try FileManager.default.contentsOfDirectory(
    at: takeDir,
    includingPropertiesForKeys: nil,
  )
  .filter { $0.pathExtension == "wav" }
  .sorted { $0.path < $1.path }

  var clips: [[String: Any]] = []
  var takeInputs: [String: String] = [:]
  let chunkSize = 4096
  for file in takeFiles {
    let name = file.deletingPathExtension().lastPathComponent
    let label = name.hasPrefix("positive") ? "positive" : "negative"
    let samples = try loadClip(file)
    let chunks = stride(from: 0, to: samples.count, by: chunkSize).map {
      Array(samples[$0 ..< min($0 + chunkSize, samples.count)])
    }
    let (peak, _) = try await scorer.maxProbability(chunks: chunks)
    // A clip triggers when any window reaches the threshold, which is the same
    // as its maximum reaching it.
    let triggered = Double(peak) >= threshold
    clips.append([
      "clip": name,
      "label": label,
      "max_prob": (Double(peak) * 10000).rounded() / 10000,
      "triggered": triggered,
    ])
    takeInputs[repoRelative(file)] = try gitBlobID(file)
  }

  func count(_ label: String, triggered: Bool?) -> Int {
    clips.count(where: { clip in
      (clip["label"] as? String) == label &&
        (triggered == nil || (clip["triggered"] as? Bool) == triggered)
    })
  }
  let summary: [String: Any] = [
    "positives_triggered": count("positive", triggered: true),
    "positives": count("positive", triggered: nil),
    "false_triggers": count("negative", triggered: true),
    "negatives": count("negative", triggered: nil),
  ]
  let record: [String: Any] = try [
    "run_id": evalID,
    "pipeline": "swift",
    "model_run_id": modelRunID,
    "model_run": repoRelative(runDir),
    "take": repoRelative(takeDir),
    "take_inputs": takeInputs,
    "weights_blob": gitBlobID(runDir.appendingPathComponent("wakenet.pt")),
    "window_len": windowLen,
    "threshold": threshold,
    "script_blob": gitBlobID(URL(fileURLWithPath: #filePath)),
    "env": ["os": ProcessInfo.processInfo.operatingSystemVersionString],
    "summary": summary,
    "clips": clips,
  ]
  let data = try JSONSerialization.data(
    withJSONObject: record,
    options: [.prettyPrinted, .sortedKeys],
  )
  try data.write(to: out)

  print(
    "take \(takeDir.lastPathComponent) with run \(runDir.lastPathComponent)  threshold \(threshold)",
  )
  print(
    "positives triggered: \(count("positive", triggered: true))/\(count("positive", triggered: nil))",
  )
  print(
    "false triggers:      \(count("negative", triggered: true))/\(count("negative", triggered: nil))",
  )
  print("saved: \(out.path)")
}

// MARK: - Command line

let arguments = Array(CommandLine.arguments.dropFirst())
var positional: [String] = []
var thresholdOverride: Double?
var index = 0
while index < arguments.count {
  if arguments[index] == "--threshold" {
    guard index + 1 < arguments.count,
          let value = Double(arguments[index + 1])
    else {
      fail("--threshold needs a number")
    }
    thresholdOverride = value
    index += 2
  } else {
    positional.append(arguments[index])
    index += 1
  }
}

guard positional.count == 2 else {
  fail("usage: eval_take <run folder> <take folder> [--threshold T]")
}

do {
  try await evaluate(
    runDir: URL(fileURLWithPath: positional[0]).standardizedFileURL,
    takeDir: URL(fileURLWithPath: positional[1]).standardizedFileURL,
    thresholdOverride: thresholdOverride,
  )
} catch {
  fail("\(error)")
}
