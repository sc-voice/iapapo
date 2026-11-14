//
//  WakeHistoryView.swift
//  VA
//

import SwiftUI

/// Two bar charts of the last two seconds of wake events, one bar per event with
/// the newest on the left. Top: microphone level from -80 to 0 dBFS. Bottom: raw
/// wake score from 0 to 1.
struct WakeHistoryView: View {
  /// Microphone level in dBFS per event, newest first.
  let micHistory: [Float]
  /// Raw score per event, newest first.
  let scoreHistory: [Float]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      BarChart(
        label: "Microphone level, -80 to 0 dBFS",
        values: micHistory,
        scale: { ($0 + 80) / 80 },
        fill: Color(red: 0.5, green: 0.5, blue: 0.74),
      )
      BarChart(
        label: "Raw wake score, 0 to 1",
        values: scoreHistory,
        scale: { $0 },
        fill: .green,
      )
    }
    .padding(.horizontal)
  }
}

/// Up to `WakeScoreModel.historyCount` vertical bars, newest at the left edge.
/// Values are mapped to a height from 0 to 1 by `scale` and clamped.
private struct BarChart: View {
  let label: String
  /// Newest first.
  let values: [Float]
  /// Maps a value to a fraction of full height.
  let scale: (Float) -> Float
  let fill: Color

  /// Height of the full-scale bar in points.
  private static let height: CGFloat = 60

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(alignment: .bottom, spacing: 2) {
        ForEach(0 ..< WakeScoreModel.historyCount, id: \.self) { index in
          let fraction = index < values.count
            ? CGFloat(min(max(scale(values[index]), 0), 1))
            : 0
          Rectangle()
            .fill(fill)
            .frame(height: Self.height * fraction)
            .frame(maxWidth: .infinity, maxHeight: Self.height, alignment: .bottom)
        }
      }
      .accessibilityElement()
      .accessibilityLabel(label)
    }
  }
}
