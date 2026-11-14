//
//  EventLog.swift
//  VA
//

import Foundation
import Observation

/// One line in the Developer tab's event log.
struct LogEntry: Identifiable {
  let id = UUID()
  let sequence: Int
  let time: Date
  let text: String
}

/// In-memory record of audio and cue events, newest first. Not serialized yet.
@Observable
final class EventLog {
  /// Oldest entries first, capped at `limit`, so the newest is at the bottom.
  private(set) var entries: [LogEntry] = []
  private var count = 0
  private let limit = 200

  /// Records an ordinary event.
  /// - Parameter text: the line shown in the log.
  func info(_ text: String) {
    append(text)
  }

  /// Records a problem, marked with a red X.
  /// - Parameter text: the line shown in the log, after the X.
  func warn(_ text: String) {
    append("❌ \(text)")
  }

  private func append(_ text: String) {
    // print always reaches the Xcode console; os.Logger messages can be dropped
    // there.
    print("[VA] \(text)")
    count += 1
    entries.append(LogEntry(sequence: count, time: .now, text: text))
    if entries.count > limit {
      entries.removeFirst()
    }
  }
}
