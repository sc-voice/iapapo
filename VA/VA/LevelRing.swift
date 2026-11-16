//
//  LevelRing.swift
//  VA
//

import SwiftUI

/// Circular meter for a value from 0 to 1. The ring fills clockwise from the top as the value rises.
struct LevelRing: View {
  /// Fraction to show, from 0 (empty) to 1 (full). Values outside the range are clamped.
  let value: Double
  /// Color of the empty part of the ring behind the fill.
  var track: Color = Color(.quaternarySystemFill)
  /// Color of the filled part of the ring.
  var fill: Color = .accentColor
  /// Width and height of the ring in points.
  static let diameter: CGFloat = 64

  var body: some View {
    let fraction = min(max(value, 0), 1)
    ZStack {
      Circle()
        .stroke(track, lineWidth: 10)
      Circle()
        .trim(from: 0, to: fraction)
        .stroke(fill, style: StrokeStyle(lineWidth: 10, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .frame(width: Self.diameter, height: Self.diameter)
    .animation(.linear(duration: 0.1), value: fraction)
    .accessibilityElement()
    .accessibilityLabel("Microphone level")
    .accessibilityValue("\(Int(fraction * 100)) percent")
  }
}
