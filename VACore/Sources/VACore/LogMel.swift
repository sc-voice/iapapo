import Foundation

/// Log-mel front end matching `log_mel` in scripts/train.py.
///
/// Input is 16 kHz mono float samples. The steps, in the order train.py runs
/// them:
/// - reflect-pad 200 samples at each end (torch.stft with center=True)
/// - periodic Hann window of 400 samples, hop 160 (25 ms frames, 10 ms hop)
/// - power spectrum, bins 0 to 200
/// - 40-band triangular mel filterbank on the HTK mel scale, band edges floored
/// as in train.py
/// - log(mel + 1e-6)
///
/// Output is row-major, `nMels` rows by `frames` columns, where `frames == 1 +
/// samples.count / hop`.
///
/// Ported from the Python front end with `frontendID` below. That id is
/// `train.frontend_id()` in
/// scripts/train.py, hashing the source of `log_mel` and `mel_filterbank` with
/// the audio constants.
/// If the Python front end changes, its id changes, and the reference test
/// fails until this port is updated.
public struct LogMelFrontEnd {
  public static let frontendID = "ICCfT6m86s3LNJs66W6P8Hm3QhUu0tURoylfYdgVZWe"
  public static let sampleRate = 16000
  public static let nFFT = 400
  public static let hop = 160
  public static let nMels = 40
  public static let nBins = nFFT / 2 + 1

  private let window: [Float]
  private let filterbank: [Float] // nMels x nBins, row-major
  private let cosTable: [Float] // nBins x nFFT: cos(2 pi k n / N)
  private let sinTable: [Float] // nBins x nFFT: sin(2 pi k n / N)

  public init() {
    window = (0 ..< Self.nFFT)
      .map {
        Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(Self.nFFT)))
      }
    filterbank = Self.makeFilterbank()
    var cosT = [Float](repeating: 0, count: Self.nBins * Self.nFFT)
    var sinT = [Float](repeating: 0, count: Self.nBins * Self.nFFT)
    for k in 0 ..< Self.nBins {
      for n in 0 ..< Self.nFFT {
        let angle = 2 * Double
          .pi * Double(k * n % Self.nFFT) / Double(Self.nFFT)
        cosT[k * Self.nFFT + n] = Float(cos(angle))
        sinT[k * Self.nFFT + n] = Float(sin(angle))
      }
    }
    cosTable = cosT
    sinTable = sinT
  }

  /// Log-mel features for one window of samples, row-major (nMels x frames),
  /// with the frame count.
  public func features(_ samples: [Float]) -> (values: [Float], frames: Int) {
    let pad = Self.nFFT / 2
    let n = samples.count
    precondition(n > pad, "window must be longer than \(pad) samples")
    let frames = 1 + n / Self.hop

    // Reflect padding, as torch.stft uses by default.
    func padded(_ i: Int) -> Float {
      var j = i - pad
      if j < 0 { j = -j }
      if j >= n { j = 2 * (n - 1) - j }
      return samples[j]
    }

    var power = [Float](repeating: 0,
                        count: Self.nBins * frames) // nBins x frames
    var frame = [Float](repeating: 0, count: Self.nFFT)
    for t in 0 ..< frames {
      for k in 0 ..< Self.nFFT {
        frame[k] = padded(t * Self.hop + k) * window[k]
      }
      for k in 0 ..< Self.nBins {
        var re: Float = 0
        var im: Float = 0
        let row = k * Self.nFFT
        for m in 0 ..< Self.nFFT {
          re += frame[m] * cosTable[row + m]
          im -= frame[m] * sinTable[row + m]
        }
        power[k * frames + t] = re * re + im * im
      }
    }

    var values = [Float](repeating: 0, count: Self.nMels * frames)
    for m in 0 ..< Self.nMels {
      for k in 0 ..< Self.nBins {
        let w = filterbank[m * Self.nBins + k]
        if w == 0 { continue }
        for t in 0 ..< frames {
          values[m * frames + t] += w * power[k * frames + t]
        }
      }
    }
    for i in values.indices {
      values[i] = logf(values[i] + 1e-6)
    }
    return (values, frames)
  }

  /// Triangular mel filterbank, row-major (nMels x nBins), built the way
  /// train.py's mel_filterbank does.
  static func makeFilterbank() -> [Float] {
    func hzToMel(_ f: Double) -> Double { 2595 * log10(1 + f / 700) }
    func melToHz(_ m: Double) -> Double { 700 * (pow(10, m / 2595) - 1) }

    let lo = hzToMel(0)
    let hi = hzToMel(Double(sampleRate) / 2)
    let mels = (0 ..< (nMels + 2))
      .map { lo + (hi - lo) * Double($0) / Double(nMels + 1) }
    let bins = mels
      .map { Int(floor(Double(nFFT + 1) * melToHz($0) / Double(sampleRate))) }

    var fb = [Float](repeating: 0, count: nMels * nBins)
    for m in 1 ... nMels {
      let l = bins[m - 1], c = bins[m], r = bins[m + 1]
      if l < c {
        for k in l ..< c where k < nBins {
          fb[(m - 1) * nBins + k] = Float(k - l) / Float(max(1, c - l))
        }
      }
      if c < r {
        for k in c ..< r where k < nBins {
          fb[(m - 1) * nBins + k] = Float(r - k) / Float(max(1, r - c))
        }
      }
    }
    return fb
  }
}
