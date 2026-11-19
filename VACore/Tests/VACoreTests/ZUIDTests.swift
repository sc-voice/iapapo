import Testing
@testable import VACore

// Ported from nx-nameforma's test/zuid.ts. Golden text values come from that
// implementation.

/// Fixed test time: 2026-11-09T00:00:00Z, so assertions are deterministic.
private let testMillis: UInt64 = 1_794_182_400_000

/// 62 bits with every other bit set (0101...01), so bits span the whole field.
private let denseSignature: UInt64 = ((1 << 62) - 1) / 3

private let signatureLimit: UInt64 = 1 << 62
private let textLength = 22
private let blockLength = 11

/// Replaces the version nibble of a hi block (bits 12-15 of the value).
private func withVersionNibble(_ hi: UInt64, _ nibble: UInt64) -> UInt64 {
  (hi & ~(0xF << 12)) | (nibble << 12)
}

// MARK: - Binary form is a UUIDv7

@Test func zuidCreateSetsVersion7AndVariant10() {
  let bytes = ZUID.create(millis: testMillis, sequence: 5, signature: denseSignature).bytes
  #expect(bytes.count == 16)
  #expect(bytes[6] >> 4 == 7)
  #expect(bytes[8] >> 6 == 0b10)
}

@Test func zuidRejectsBufferThatIsNotUUIDv7() {
  var bad = (0 ..< 16).map { _ in UInt8.random(in: .min ... .max) }
  bad[6] = 0x40 // version 4
  #expect(throws: ZUIDError.notUUIDv7) {
    try ZUID(bytes: bad)
  }
}

@Test func zuidRejectsBufferThatIsNot16Bytes() {
  #expect(throws: ZUIDError.wrongByteCount(8)) {
    try ZUID(bytes: [UInt8](repeating: 0, count: 8))
  }
}

// MARK: - Accessors read the layout

@Test func zuidTimestampIsThe48BitUnixTime() {
  let millis = testMillis + 123
  #expect(ZUID.create(millis: millis).timestamp == millis)
}

@Test func zuidSequenceIsThe12BitCounter() {
  #expect(ZUID.create(millis: testMillis, sequence: 4095).sequence == 4095)
}

@Test func zuidSignatureIsThe62BitsAfterTheVariant() {
  let z = ZUID.create(millis: testMillis, sequence: 0, signature: denseSignature)
  #expect(z.signature == denseSignature)
}

@Test func zuidTruncatesA64BitSignatureTo62Bits() {
  let z = ZUID.create(millis: testMillis, sequence: 0, signature: .max)
  #expect(z.signature == signatureLimit - 1)
  #expect(z.bytes[8] >> 6 == 0b10)
}

// MARK: - Text form

@Test func zuidTextIs22AlphabetCharactersWithNoHyphen() {
  for _ in 0 ..< 1000 {
    let s = ZUID.create().description
    #expect(s.count == textLength)
    #expect(s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
  }
}

@Test func zuidTextHiBlockCarriesVersion15() throws {
  let s = ZUID.create(millis: testMillis, sequence: 1, signature: 1).description
  let textHi = try OPB63_64.decode(String(s.prefix(blockLength)))
  #expect((textHi >> 12) & 0xF == 15)
}

@Test func zuidBinaryBehindTheTextStillHasVersion7() {
  let z = ZUID.create(millis: testMillis, sequence: 1, signature: 1)
  #expect(z.bytes[6] >> 4 == 7)
}

@Test func zuidParsingMapsTextVersion15BackToVersion7() throws {
  let z = ZUID.create(millis: testMillis, sequence: 1, signature: 1)
  #expect(try ZUID.fromString(z.description).bytes == z.bytes)
}

@Test func zuidTimeIdIsTheFirst11Characters() {
  let z = ZUID.create()
  #expect(z.timeId == String(z.description.prefix(blockLength)))
}

@Test func zuidGoldenTextMatchesTypeScript() {
  #expect(ZUID.create(millis: testMillis, sequence: 5, signature: denseSignature).description
    == "07WpGQXTo5tAvIHhpOsgUU")
  #expect(ZUID.create(millis: testMillis, sequence: 1, signature: 1).description
    == "07WpGQXTo5p9MxfBQuKjH9")
  #expect(ZUID.create(millis: testMillis, sequence: 4095, signature: signatureLimit - 1).description
    == "07WpGQXTp7oE2wVldMzauB")
  #expect(ZUID.create(millis: 0, sequence: 0, signature: 0).description
    == "00000000FUF9MxfBQuKjH8")
}

// MARK: - Round-trips

@Test func zuidTextRoundTripsThroughFromString() throws {
  for _ in 0 ..< 5000 {
    let z = ZUID.create()
    #expect(try ZUID.fromString(z.description) == z)
  }
}

@Test func zuidBinaryRoundTripsThroughInit() throws {
  for _ in 0 ..< 1000 {
    let z = ZUID.create()
    #expect(try ZUID(bytes: z.bytes) == z)
  }
}

// MARK: - Ordering

@Test func zuidSortingByTextEqualsSortingByBinary() {
  let zs = (0 ..< 2000).map { _ in ZUID.create() }
  let byBinary = zs.sorted().map(\.description)
  let byText = zs.map(\.description).sorted()
  #expect(byText == byBinary)
}

// MARK: - Malformed text is rejected

@Test func zuidRejectsWrongTextLength() {
  let s = ZUID.create().description
  #expect(throws: ZUIDError.self) {
    try ZUID.fromString(String(s.dropFirst()))
  }
  #expect(throws: ZUIDError.self) {
    try ZUID.fromString(s + "A")
  }
}

@Test func zuidRejectsTimeBlockWhoseVersionIsNot15() throws {
  let s = ZUID.create(millis: testMillis, sequence: 1, signature: 1).description
  let hi = try OPB63_64.decode(String(s.prefix(blockLength)))
  let version7Block = OPB63_64.encode(withVersionNibble(hi, 7))
  #expect(throws: ZUIDError.self) {
    try ZUID.fromString(version7Block + String(s.dropFirst(blockLength)))
  }
}

@Test func zuidRejectsCharactersOutsideTheAlphabet() {
  let s = ZUID.create().description
  #expect(throws: OPB63_64Error.invalidCharacter("+")) {
    try ZUID.fromString("+" + String(s.dropFirst()))
  }
}

// MARK: - forSignature()

@Test func zuidForSignatureUsesTheCurrentTime() {
  let before = ZUID.nowMillis()
  let z = ZUID.forSignature(denseSignature)
  let after = ZUID.nowMillis()
  #expect(z.timestamp >= before)
  #expect(z.timestamp <= after)
}

@Test func zuidForSignatureCarriesTheGivenSignature() {
  #expect(ZUID.forSignature(denseSignature).signature == denseSignature)
}

// MARK: - after()

@Test func zuidAfterLaterTimeGivesNewTimeSequence0() {
  let z = ZUID.create(millis: testMillis, sequence: 7, signature: denseSignature)
  let next = z.after(msSys: testMillis + 1000)
  #expect(next.timestamp == testMillis + 1000)
  #expect(next.sequence == 0)
  #expect(next.signature == denseSignature)
  #expect(next > z)
  #expect(next.description == "07WpGQacu3mAvIHhpOsgUU")
}

@Test func zuidAfterSameMillisecondGivesSequencePlusOne() {
  let z = ZUID.create(millis: testMillis, sequence: 7, signature: denseSignature)
  let next = z.after(msSys: testMillis)
  #expect(next.timestamp == testMillis)
  #expect(next.sequence == 8)
  #expect(next > z)
}

@Test func zuidAfterEarlierSystemTimeIsStillLaterThanThisID() {
  let z = ZUID.create(millis: testMillis, sequence: 7, signature: denseSignature)
  let next = z.after(msSys: testMillis - 5000)
  #expect(next.timestamp == testMillis)
  #expect(next.sequence == 8)
  #expect(next > z)
}

@Test func zuidAfterFullSequenceRollsOverToNextMillisecond() {
  let z = ZUID.create(millis: testMillis, sequence: 4095, signature: denseSignature)
  let next = z.after(msSys: testMillis)
  #expect(next.timestamp == testMillis + 1)
  #expect(next.sequence == 0)
  #expect(next > z)
  #expect(next.description == "07WpGQXU4b4AvIHhpOsgUU")
}

@Test func zuidAfterChainIsStrictlyIncreasing() {
  var z = ZUID.create(millis: testMillis, sequence: 0, signature: denseSignature)
  var chain = [z]
  for _ in 0 ..< 5000 {
    z = z.after(msSys: testMillis)
    chain.append(z)
  }
  for i in 1 ..< chain.count {
    #expect(chain[i] > chain[i - 1])
  }
}

// MARK: - timeRangeOf()

@Test func zuidTimeRangeContainsEveryZUIDWithThePrefix() throws {
  for _ in 0 ..< 2000 {
    let offset = UInt64.random(in: 0 ..< 1_000_000_000)
    let z = ZUID.create(millis: testMillis + offset)
    let text = z.description
    for n in 1 ... blockLength {
      let (start, end) = try ZUID.timeRangeOf(String(text.prefix(n)))
      #expect(z.timestamp >= start)
      #expect(z.timestamp < end)
    }
  }
}

@Test func zuidLongerPrefixGivesWindowNestedInShorterOne() throws {
  let text = ZUID.create(millis: testMillis).description
  for n in 1 ..< blockLength {
    let outer = try ZUID.timeRangeOf(String(text.prefix(n)))
    let inner = try ZUID.timeRangeOf(String(text.prefix(n + 1)))
    #expect(inner.start >= outer.start)
    #expect(inner.end <= outer.end)
  }
}

@Test func zuidSixCharactersSpanAboutFifteenSeconds() throws {
  let text = ZUID.create(millis: testMillis).description
  let (start, end) = try ZUID.timeRangeOf(String(text.prefix(6)))
  #expect(end - start >= 15000)
  #expect(end - start <= 16000)
}

@Test func zuidSevenCharactersSpanAbout240Ms() throws {
  let text = ZUID.create(millis: testMillis).description
  let (start, end) = try ZUID.timeRangeOf(String(text.prefix(7)))
  #expect(end - start >= 240)
  #expect(end - start <= 242)
}

@Test func zuidEightCharactersSpanAbout4Ms() throws {
  let text = ZUID.create(millis: testMillis).description
  let (start, end) = try ZUID.timeRangeOf(String(text.prefix(8)))
  #expect(end - start >= 3)
  #expect(end - start <= 5)
}

@Test func zuidGoldenTimeRangesMatchTypeScript() throws {
  let text = ZUID.create(millis: testMillis, sequence: 0, signature: 0).description
  let six = try ZUID.timeRangeOf(String(text.prefix(6)))
  #expect(six.start == 1_794_182_391_954 && six.end == 1_794_182_407_099)
  let seven = try ZUID.timeRangeOf(String(text.prefix(7)))
  #expect(seven.start == 1_794_182_399_887 && seven.end == 1_794_182_400_128)
  let eleven = try ZUID.timeRangeOf(String(text.prefix(11)))
  #expect(eleven.start == testMillis && eleven.end == testMillis + 1)
}

@Test func zuidAllZeroPrefixStartsAtTimeZero() throws {
  #expect(try ZUID.timeRangeOf("0").start == 0)
}

@Test func zuidTimeRangeRejectsEmptyTooLongOrInvalidPrefixes() {
  #expect(throws: ZUIDError.self) { try ZUID.timeRangeOf("") }
  #expect(throws: ZUIDError.self) { try ZUID.timeRangeOf(String(repeating: "0", count: 12)) }
  #expect(throws: ZUIDError.invalidCharacter("+")) { try ZUID.timeRangeOf("0+") }
}

@Test func zuidTimeRangeRejectsPrefixesThatNameNo64BitValue() {
  #expect(throws: ZUIDError.self) {
    try ZUID.timeRangeOf(String(repeating: "z", count: 10))
  }
}
