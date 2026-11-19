import Foundation

/// ZUID: a UUIDv7 with a base-63 text form. Swift counterpart of `ZUID` in
/// nx-nameforma's `zuid.ts`.
///
/// Specification:
/// - Binary: a standard 16-byte UUIDv7 (version 7 in byte 6, variant `10` in
///   byte 8). `bytes` is the UUIDv7 buffer unchanged.
/// - Text: two 11-character `OPB63_64` blocks, hi (bytes 0-7) then lo (bytes
///   8-15), for 22 characters with no hyphens. The version nibble is 15 in
///   text only.
/// - Time block (hi): 48-bit Unix ms, 4-bit version, 12-bit sequence. The
///   version sits below the timestamp, so it never changes a prefix's time
///   window. This is why `timeRangeOf` is within 1 ms of the exact bounds.
/// - Signature (lo): 62 free bits; the top 2 bits are the pinned variant `10`.
///
/// Ordering compares the 16 bytes, so sorting by `<` is chronological, then by
/// sequence, then by signature.
///
/// ```swift
/// let z = ZUID.create()
/// try ZUID.fromString(z.description) == z  // true
/// ```
public struct ZUID: Hashable, Comparable, Sendable, CustomStringConvertible {
  /// Largest 48-bit Unix time in ms.
  static let maxMillis: UInt64 = (1 << 48) - 1
  /// Largest 12-bit sequence.
  public static let maxSequence: UInt16 = 0xFFF
  /// Largest 62-bit signature.
  public static let maxSignature: UInt64 = (1 << 62) - 1

  private static let versionBinary: UInt64 = 7
  private static let versionText: UInt64 = 15
  /// The version nibble occupies bits 12-15 of the hi block value.
  private static let versionShift: UInt64 = 12
  private static let versionMask: UInt64 = 0xF << 12
  private static let variantBits: UInt64 = 2 << 62
  private static let blockWidth = OPB63_64.width

  /// The 16-byte UUIDv7, big-endian.
  public let bytes: [UInt8]

  /// Creates a ZUID from a 16-byte UUIDv7 buffer.
  ///
  /// - Throws: `ZUIDError` if the buffer is not 16 bytes, or is not UUIDv7
  ///   (version 7, variant `10`).
  public init(bytes: [UInt8]) throws {
    guard bytes.count == 16 else {
      throw ZUIDError.wrongByteCount(bytes.count)
    }
    guard bytes[6] >> 4 == 7, bytes[8] >> 6 == 2 else {
      throw ZUIDError.notUUIDv7
    }
    self.bytes = bytes
  }

  /// Creates a ZUID for the given time.
  ///
  /// - Parameters:
  ///   - millis: Unix time in milliseconds, at most 48 bits (default: now).
  ///   - sequence: 12-bit sequence (random if omitted).
  ///   - signature: 62-bit signature (random if omitted). Bits above 62 are
  ///     dropped.
  public static func create(
    millis: UInt64 = nowMillis(),
    sequence: UInt16? = nil,
    signature: UInt64? = nil
  ) -> ZUID {
    precondition(millis <= maxMillis, "ZUID time exceeds 48 bits: \(millis)")
    var buf = (0 ..< 16).map { _ in UInt8.random(in: .min ... .max) }
    let seq = sequence ?? (UInt16(buf[6]) << 8 | UInt16(buf[7])) & maxSequence
    precondition(seq <= maxSequence, "ZUID sequence exceeds 12 bits: \(seq)")
    let sig = signature ?? readUInt64(buf, 8) & maxSignature
    for i in 0 ..< 6 {
      buf[i] = UInt8(truncatingIfNeeded: millis >> UInt64(40 - 8 * i))
    }
    buf[6] = 0x70 | UInt8((seq >> 8) & 0x0F)
    buf[7] = UInt8(seq & 0xFF)
    writeUInt64(&buf, 8, (sig & maxSignature) | variantBits)
    return ZUID(validated: buf)
  }

  /// Parses a 22-character ZUID string. The text version (15) is mapped to 7.
  ///
  /// - Throws: `ZUIDError` if the length or text version is wrong, or
  ///   `OPB63_64Error` if a character is outside the alphabet.
  public static func fromString(_ text: String) throws -> ZUID {
    guard text.count == 2 * blockWidth else {
      throw ZUIDError.wrongTextLength(text)
    }
    var hi = try OPB63_64.decode(String(text.prefix(blockWidth)))
    let lo = try OPB63_64.decode(String(text.suffix(blockWidth)))
    guard (hi & versionMask) >> versionShift == versionText else {
      throw ZUIDError.textVersionNot15(text)
    }
    hi = (hi & ~versionMask) | (versionBinary << versionShift)
    var buf = [UInt8](repeating: 0, count: 16)
    writeUInt64(&buf, 0, hi)
    writeUInt64(&buf, 8, lo)
    return try ZUID(bytes: buf)
  }

  /// Text form: 22 characters, with the version nibble set to 15.
  public var description: String {
    let textHi = (hi & ~Self.versionMask) | (Self.versionText << Self.versionShift)
    return OPB63_64.encode(textHi) + OPB63_64.encode(lo)
  }

  /// First 11 characters of the text form: the time block.
  public var timeId: String {
    String(description.prefix(Self.blockWidth))
  }

  /// Unix time in milliseconds.
  public var timestamp: UInt64 {
    hi >> 16
  }

  /// 12-bit sequence counter.
  public var sequence: UInt16 {
    UInt16(hi & 0xFFF)
  }

  /// 62-bit signature (variant bits excluded).
  public var signature: UInt64 {
    lo & Self.maxSignature
  }

  /// Creates a ZUID at the current time carrying the given signature.
  ///
  /// - Parameter signature: 62-bit signature (variant bits are added
  ///   automatically).
  public static func forSignature(_ signature: UInt64) -> ZUID {
    create(millis: nowMillis(), signature: signature)
  }

  /// Time window covered by a text prefix, rounded outward to whole
  /// milliseconds.
  ///
  /// Every ZUID whose text starts with `prefix` has a timestamp in
  /// `[start, end)`. The window can be wider than the exact bounds by up to
  /// 1 ms at each end, because the version nibble sits below the timestamp.
  /// Approximate widths: 6 characters ≈ 15 s, 7 ≈ 240 ms, 8 ≈ 3.8 ms.
  ///
  /// - Parameter prefix: 1 to 11 characters of the time block.
  /// - Returns: `start` inclusive and `end` exclusive, in Unix ms.
  /// - Throws: `ZUIDError` if the prefix length is wrong, a character is
  ///   outside the alphabet, or the prefix cannot name any 64-bit value.
  public static func timeRangeOf(
    _ prefix: String
  ) throws -> (start: UInt64, end: UInt64) {
    let n = prefix.count
    guard (1 ... blockWidth).contains(n) else {
      throw ZUIDError.timePrefixLength(prefix)
    }
    var p: UInt64 = 0
    var overflow = false
    for c in prefix {
      guard let digit = OPB63_64.digitValue(c) else {
        throw ZUIDError.invalidCharacter(c)
      }
      let (scaled, scaleOverflow) = p.multipliedReportingOverflow(by: 63)
      let (sum, sumOverflow) = scaled.addingReportingOverflow(digit)
      overflow = overflow || scaleOverflow || sumOverflow
      p = sum
    }
    var scale: UInt64 = 1
    for _ in 0 ..< (blockWidth - n) {
      scale *= 63
    }
    let (lo, loOverflow) = p.multipliedReportingOverflow(by: scale)
    guard !overflow && !loOverflow else {
      throw ZUIDError.prefixExceeds64Bits(prefix)
    }
    let (top, topOverflow) = lo.addingReportingOverflow(scale - 1)
    let hi = topOverflow ? UInt64.max : top
    return (start: lo >> 16, end: (hi >> 16) + 1)
  }

  /// Creates a ZUID that sorts strictly after this one, keeping its signature.
  ///
  /// - Time is the later of `msSys` and this ID's time.
  /// - Same millisecond: sequence + 1.
  /// - Sequence full (4095): time + 1 ms, sequence 0.
  ///
  /// - Parameter msSys: system time in ms (default: now).
  public func after(msSys: UInt64 = ZUID.nowMillis()) -> ZUID {
    let ts = timestamp
    if msSys > ts {
      return ZUID.create(millis: msSys, sequence: 0, signature: signature)
    }
    if sequence < Self.maxSequence {
      return ZUID.create(millis: ts, sequence: sequence + 1, signature: signature)
    }
    return ZUID.create(millis: ts + 1, sequence: 0, signature: signature)
  }

  /// Orders by the 16 bytes: time, then sequence, then signature.
  public static func < (lhs: ZUID, rhs: ZUID) -> Bool {
    lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
  }

  /// Current Unix time in milliseconds.
  public static func nowMillis() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000)
  }

  private init(validated bytes: [UInt8]) {
    self.bytes = bytes
  }

  private var hi: UInt64 { Self.readUInt64(bytes, 0) }
  private var lo: UInt64 { Self.readUInt64(bytes, 8) }

  private static func readUInt64(_ buf: [UInt8], _ offset: Int) -> UInt64 {
    buf[offset ..< offset + 8].reduce(0) { ($0 << 8) | UInt64($1) }
  }

  private static func writeUInt64(_ buf: inout [UInt8], _ offset: Int, _ value: UInt64) {
    for i in 0 ..< 8 {
      buf[offset + i] = UInt8(truncatingIfNeeded: value >> UInt64(56 - 8 * i))
    }
  }
}

/// Errors thrown by `ZUID`.
public enum ZUIDError: Error, Equatable {
  case wrongByteCount(Int)
  case notUUIDv7
  case wrongTextLength(String)
  case textVersionNot15(String)
  case timePrefixLength(String)
  case invalidCharacter(Character)
  case prefixExceeds64Bits(String)
}
