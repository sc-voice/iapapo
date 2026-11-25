import Foundation
import Testing
@testable import VACore

// MARK: - Codable encodes as the plain text form

@Test func zuidEncodesAsItsTextString() throws {
  let zuid = ZUID.create(millis: 1_794_182_400_000, sequence: 5, signature: 42)
  let data = try JSONEncoder().encode(zuid)
  let json = try #require(String(data: data, encoding: .utf8))
  #expect(json == "\"\(zuid.text)\"")
}

@Test func zuidDecodesFromPlainTextString() throws {
  let zuid = ZUID.create(millis: 1_794_182_400_000, sequence: 5, signature: 42)
  let data = Data("\"\(zuid.text)\"".utf8)
  let decoded = try JSONDecoder().decode(ZUID.self, from: data)
  #expect(decoded == zuid)
}

@Test func zuidCodableRoundTripKeepsTheValue() throws {
  let zuid = ZUID.create()
  let data = try JSONEncoder().encode(zuid)
  let decoded = try JSONDecoder().decode(ZUID.self, from: data)
  #expect(decoded == zuid)
  #expect(decoded.text == zuid.text)
}

@Test func zuidDecodingRejectsMalformedText() {
  let data = Data("\"not-a-zuid\"".utf8)
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(ZUID.self, from: data)
  }
}

@Test func zuidDecodingRejectsNonStringJSON() {
  let data = Data("42".utf8)
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(ZUID.self, from: data)
  }
}
