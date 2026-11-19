import Testing
@testable import VACore

// Ported from nx-nameforma's test/opb63_64.ts. Golden values come from that
// implementation.

private let max64: UInt64 = .max

/// Random 64-bit values for round-trip and ordering checks.
private func randomValues(_ n: Int) -> [UInt64] {
  (0 ..< n).map { _ in UInt64.random(in: .min ... .max) }
}

/// Slow reference encoder: repeated division, most significant digit last.
private func referenceEncode(_ value: UInt64) -> String {
  let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
  var out = ""
  var v = value
  for _ in 0 ..< OPB63_64.width {
    out = String(alphabet[Int(v % 63)]) + out
    v /= 63
  }
  return out
}

@Test func opb63HasFixedWidthAndEncodesKnownVectors() {
  #expect(OPB63_64.width == 11)
  #expect(OPB63_64.encode(0) == "00000000000")
  #expect(OPB63_64.encode(1) == "00000000001")
  #expect(OPB63_64.encode(62) == "0000000000z")
  #expect(OPB63_64.encode(63) == "00000000010")
  #expect(OPB63_64.encode(1 << 32) == "000004KddK4")
  #expect(OPB63_64.encode(max64) == "IivLMqoeTYF")
  #expect(OPB63_64.encode(max64) == referenceEncode(max64))
}

@Test func opb63RoundTripsBoundaryValues() throws {
  let edges: [UInt64] = [
    0, 1, 62, 63,
    (1 << 32) - 1, 1 << 32, (1 << 32) + 1,
    63 * 63 * 63 * 63 * 63,
    63 * 63 * 63 * 63 * 63 * 63 * 63 * 63 * 63 * 63 - 1,
    63 * 63 * 63 * 63 * 63 * 63 * 63 * 63 * 63 * 63,
    (1 << 53) + 1,
    1 << 63,
    max64 - 1,
    max64,
  ]
  for v in edges {
    #expect(try OPB63_64.decode(OPB63_64.encode(v)) == v)
  }
}

@Test func opb63RoundTripsRandomValues() throws {
  for v in randomValues(10000) {
    #expect(try OPB63_64.decode(OPB63_64.encode(v)) == v)
  }
}

@Test func opb63MatchesReferenceEncoder() {
  for v in randomValues(2000) {
    #expect(OPB63_64.encode(v) == referenceEncode(v))
  }
}

@Test func opb63PreservesOrderUnderStringComparison() {
  let values = randomValues(2000)
  let byNumber = values.sorted().map { OPB63_64.encode($0) }
  let byString = values.map { OPB63_64.encode($0) }.sorted()
  #expect(byString == byNumber)
}

@Test func opb63RejectsWrongLength() {
  #expect(throws: OPB63_64Error.wrongLength(10)) {
    try OPB63_64.decode("0000000000")
  }
  #expect(throws: OPB63_64Error.wrongLength(12)) {
    try OPB63_64.decode("000000000000")
  }
}

@Test func opb63RejectsCharactersOutsideTheAlphabet() {
  #expect(throws: OPB63_64Error.invalidCharacter("+")) {
    try OPB63_64.decode("0000000000+")
  }
  #expect(throws: OPB63_64Error.invalidCharacter(" ")) {
    try OPB63_64.decode("000000000 0")
  }
  #expect(throws: OPB63_64Error.invalidCharacter("é")) {
    try OPB63_64.decode("0000000000é")
  }
}

@Test func opb63RejectsStringsThatDecodeAbove64Bits() throws {
  // 63^11 - 1 is the largest 11-character string value.
  #expect(throws: OPB63_64Error.self) {
    try OPB63_64.decode("zzzzzzzzzzz")
  }
  #expect(try OPB63_64.decode(referenceEncode(max64)) == max64)
}
