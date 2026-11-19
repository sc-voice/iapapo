//
//  WakeHistoryView.swift
//  VA
//

import SwiftUI

/// Display width of each bar chart and its time axis, in points.
private let chartWidth: CGFloat = 200

/// Two bar charts of the last two seconds of wake events, one bar per event with
/// the newest on the left. Top: microphone level from -80 to 0 dBFS. Bottom: raw
/// wake score from 0 to 1.
struct WakeHistoryView<MicRing: View, WakeRing: View>: View {
  /// Mic level ring, shown to the left of the microphone bar chart.
  let micRing: MicRing
  /// Wake score ring, shown to the left of the wake score bar chart.
  let wakeRing: WakeRing
  /// Microphone level in dBFS per event, newest first.
  let micHistory: [Float]
  /// Raw score per event, newest first.
  let scoreHistory: [Float]
  /// Whether each event was a wake word, newest first, parallel to `scoreHistory`.
  let wakeHistory: [Bool]
  /// Whether the microphone is on. When off, only the mic ring shows.
  let isOn: Bool
  /// Ambient floor in dBFS, or nil before the first hop. Shown faintly over the
  /// microphone bar chart.
  let ambientDb: Float?
  /// Smoothed window level in dBFS, shown to the right of the ambient floor, or nil before the first hop.
  let windowDb: Float?
  /// Whether the window level is clearly above the ambient floor. The window
  /// level shows green when true.
  let gateOpen: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isOn {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .top, spacing: 12) {
          micRing
          BarChart(
            label: "Microphone level, -80 to 0 dBFS",
            values: micHistory,
            scale: { ($0 + 80) / 80 },
            colorFor: { _ in Color(red: 0.5, green: 0.5, blue: 0.74) },
            height: LevelRing.diameter,
          )
          .overlay(alignment: .topLeading) {
            HStack(spacing: 16) {
              Text(ambientDb.map { String(format: "%.1f", $0) } ?? "—")
              Text(windowDb.map { String(format: "%.1f", $0) } ?? "—")
                .foregroundStyle(gateOpen ? .green : .secondary)
            }
            .font(.system(size: 25))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .opacity(1)
            .padding(.leading, 4)
            .allowsHitTesting(false)
          }
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .top, spacing: 12) {
          wakeRing
          BarChart(
            label: "Raw wake score, 0 to 1",
            values: scoreHistory,
            scale: { $0 },
            colorFor: { index in
              index < wakeHistory.count && wakeHistory[index] ? .green : .gray
            },
            height: LevelRing.diameter,
          )
          .overlay(alignment: .topLeading) {
            Text(scoreHistory.max().map { String(format: "%.2f", $0) } ?? "—")
              .font(.system(size: 25))
              .monospacedDigit()
              .foregroundStyle(wakeHistory.contains(true) ? .green : .gray)
              .opacity(1)
              .padding(.leading, 4)
              .allowsHitTesting(false)
          }
        }
      }
      } else {
        micRing
      }
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
  /// Fill for the bar at each index, newest first.
  let colorFor: (Int) -> Color

  /// Height of the bar area and of a full-scale bar, in points.
  let height: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .bottom, spacing: 2) {
        ForEach(0 ..< WakeScoreModel.historyCount, id: \.self) { index in
          let fraction = index < values.count
            ? CGFloat(min(max(scale(values[index]), 0), 1))
            : 0
          Rectangle()
            .fill(colorFor(index))
            .frame(height: height * fraction)
            .frame(maxWidth: .infinity, maxHeight: height, alignment: .bottom)
        }
      }
      .frame(width: chartWidth)
      .accessibilityElement()
      .accessibilityLabel(label)
      TimeAxis()
    }
  }
}

/// A thin horizontal time axis under a bar chart. The arrowhead sits at the
/// right end, so it points toward increasing time.
private struct TimeAxis: View {
  var body: some View {
    Canvas { context, size in
      let y = size.height / 2
      var line = Path()
      line.move(to: CGPoint(x: 0, y: y))
      line.addLine(to: CGPoint(x: size.width, y: y))
      var head = Path()
      head.move(to: CGPoint(x: size.width - 6, y: y - 4))
      head.addLine(to: CGPoint(x: size.width, y: y))
      head.addLine(to: CGPoint(x: size.width - 6, y: y + 4))
      context.stroke(line, with: .color(.secondary), lineWidth: 1)
      context.stroke(head, with: .color(.secondary), lineWidth: 1)
    }
    .frame(width: chartWidth, height: 8)
  }
}
