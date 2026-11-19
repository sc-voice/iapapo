/// Fixed-width, order-preserving base-63 codec for 64-bit values: the Swift
/// counterpart of `OPB63_64` in nx-nameforma's `opb63_64.ts`.
///
/// Every value encodes to exactly `width` (11) characters, since 63^10 < 2^64
/// <= 63^11. The alphabet is in ASCII code-point order (`0-9`, `A-Z`, `_`,
/// `a-z`), so string comparison of encodings equals numeric comparison.
public enum OPB63_64 {
  /// Number of characters in every encoded block.
  public static let width = 11

  /// Digit alphabet: the value of each character is its index here.
  static let alphabet: [UInt8] = Array(
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz".utf8
  )

  /// ASCII code -> digit value, or -1 when the code is not in the alphabet.
  private static let digitOf: [Int8] = {
    var table = [Int8](repeating: -1, count: 128)
    for (digit, code) in alphabet.enumerated() {
      table[Int(code)] = Int8(digit)
    }
    return table
  }()

  /// Encodes a 64-bit value as `width` base-63 characters.
  ///
  /// - Parameter value: any `UInt64`; every value is in range.
  /// - Returns: a fixed-width string of `width` characters.
  public static func encode(_ value: UInt64) -> String {
    var rest = value
    var chars = [UInt8](repeating: 0, count: width)
    for i in stride(from: width - 1, through: 0, by: -1) {
      chars[i] = alphabet[Int(rest % 63)]
      rest /= 63
    }
    return String(decoding: chars, as: UTF8.self)
  }

  /// Decodes a base-63 block back to its 64-bit value.
  ///
  /// - Parameter encoded: exactly `width` characters from the alphabet.
  /// - Throws: `OPB63_64Error` if the length is wrong, a character is outside
  ///   the alphabet, or the value exceeds 64 bits.
  public static func decode(_ encoded: String) throws -> UInt64 {
    guard encoded.count == width else {
      throw OPB63_64Error.wrongLength(encoded.count)
    }
    var value: UInt64 = 0
    for c in encoded {
      guard let digit = digitValue(c) else {
        throw OPB63_64Error.invalidCharacter(c)
      }
      let (scaled, scaleOverflow) = value.multipliedReportingOverflow(by: 63)
      let (sum, sumOverflow) = scaled.addingReportingOverflow(UInt64(digit))
      guard !scaleOverflow && !sumOverflow else {
        throw OPB63_64Error.exceeds64Bits(encoded)
      }
      value = sum
    }
    return value
  }

  /// Digit value of one character, or nil when it is outside the alphabet.
  static func digitValue(_ c: Character) -> UInt64? {
    guard let code = c.asciiValue, code < 128, digitOf[Int(code)] >= 0 else {
      return nil
    }
    return UInt64(digitOf[Int(code)])
  }
}

/// Errors thrown by `OPB63_64.decode`.
public enum OPB63_64Error: Error, Equatable {
  case wrongLength(Int)
  case invalidCharacter(Character)
  case exceeds64Bits(String)
}
