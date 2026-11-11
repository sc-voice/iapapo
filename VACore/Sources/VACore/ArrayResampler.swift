import Foundation

/// 3:1 decimation from 48 kHz to 16 kHz, a port of scipy's `resample_poly(x,
/// 16000, 48000)`.
///
/// The filter is `firwin(61, 1/3)` with a Kaiser window (β = 5), normalized to
/// unit DC gain.
/// Output sample `n` is `Σ_j h[j] · x[3n + 30 − j]`, with `x` taken as zero
/// outside the input.
/// `resample(_:)` takes a whole clip and returns `ceil(count / 3)` samples, as
/// scipy does.
/// Reference data: scripts/python/export_resample_reference.py.
public struct ArrayResampler48To16: Sendable {
  /// Input samples per output sample.
  public static let decimation = 3
  /// Half the filter length minus one: taps run from `x[3n + 30]` back to `x[3n
  /// - 30]`.
  public static let halfLength = 30
  /// Kaiser window shape parameter, scipy's default for `resample_poly`.
  public static let kaiserBeta = 5.0

  /// The 61 FIR taps, `h[0]` through `h[60]`.
  public let taps: [Double]

  public init() {
    taps = Self.designTaps()
  }

  /// Resamples a whole clip from 48 kHz to 16 kHz.
  /// - Parameter x: mono samples at 48 kHz.
  /// - Returns: `ceil(x.count / 3)` mono samples at 16 kHz.
  public func resample(_ x: [Float]) -> [Float] {
    let n = x.count
    let outCount = (n + Self.decimation - 1) / Self.decimation
    var y = [Float](repeating: 0, count: outCount)
    for m in 0 ..< outCount {
      var acc = 0.0
      for j in 0 ..< taps.count {
        let i = Self.decimation * m + Self.halfLength - j
        if i >= 0, i < n {
          acc += taps[j] * Double(x[i])
        }
      }
      y[m] = Float(acc)
    }
    return y
  }

  /// `firwin(2·30 + 1, 1/3)` with a Kaiser window: the sinc at cutoff 1/3 of
  /// Nyquist, windowed, then normalized.
  static func designTaps() -> [Double] {
    let count = 2 * halfLength + 1
    let cutoff = 1.0 / Double(decimation)
    let center = Double(count - 1) / 2
    var h = (0 ..< count).map { k -> Double in
      let m = Double(k) - center
      return cutoff * sinc(cutoff * m)
    }
    // Symmetric Kaiser window of length `count`, as scipy's firwin uses.
    let i0Beta = besselI0(kaiserBeta)
    for k in 0 ..< count {
      let r = (Double(k) - center) / center
      h[k] *= besselI0(kaiserBeta * max(0, 1 - r * r).squareRoot()) / i0Beta
    }
    let sum = h.reduce(0, +)
    return h.map { $0 / sum }
  }

  /// numpy's `sinc`: sin(πx) / (πx), with 1 at 0.
  static func sinc(_ x: Double) -> Double {
    x == 0 ? 1 : sin(Double.pi * x) / (Double.pi * x)
  }

  /// Modified Bessel function of the first kind, order 0, from its power
  /// series.
  static func besselI0(_ x: Double) -> Double {
    var sum = 1.0
    var term = 1.0
    var k = 1.0
    while term > 1e-17 * sum {
      let f = x / (2 * k)
      term *= f * f
      sum += term
      k += 1
    }
    return sum
  }
}
