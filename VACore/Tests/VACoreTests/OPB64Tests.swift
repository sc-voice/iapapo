import Testing
@testable import VACore

// Golden values from nx-nameforma's uuid64.ts (UUID64.toOrderPreservingBase64).
// Keep them in step with that code.

@Test func opb64MatchesTypeScriptVectors() {
  #expect(OPB64.encode([]) == "")
  #expect(OPB64.encode([0x00]) == "00")
  #expect(OPB64.encode([0xFF]) == "_m")
  #expect(OPB64.encode(Array("abc".utf8)) == "OM9Z")
  #expect(OPB64.encode([0xFF, 0xFF]) == "__y")
}

/// The time buffer behind a timeId: the 48-bit millisecond timestamp in the top
/// 48 bits of 8 bytes,
/// so the first 6 characters are the top 36 bits of the timestamp.
@Test func opb64OfTimeBufferGivesTimeIdPrefix() {
  let millis: UInt64 = 1_794_075_830_519
  let value = millis << 16
  let bytes = (0 ..< 8)
    .map { UInt8(truncatingIfNeeded: value >> UInt64(56 - 8 * $0)) }
  #expect(OPB64.encode(bytes) == "0Q6tGAZt000")
  #expect(String(OPB64.encode(bytes).prefix(6)) == "0Q6tGA")
  #expect(String(OPB64.encode(bytes).prefix(8)) == "0Q6tGAZt")
}

@Test func opb64OutputUsesOnlyTheAlphabet() {
  let encoded = OPB64.encode((0 ..< 256).map { UInt8($0) })
  #expect(Set(encoded).isSubset(of: Set(OPB64.alphabet)))
}
