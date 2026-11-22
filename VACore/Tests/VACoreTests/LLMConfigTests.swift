import Foundation
import Testing
@testable import VACore

/// Builds a config with a fixed zuid, so tests control ordering.
private func makeConfig(zuid: String, name: String = "", maxTokens: Int = 20000, url: String = "http://example.test:8000/v1") -> LLMConfig {
  LLMConfig(
    zuid: zuid,
    name: name,
    baseURL: URL(string: url)!,
    api: "openai-completions",
    apiKey: "secret-key",
    model: "test-model",
    maxTokens: maxTokens
  )
}

// MARK: - Identity and display name

@Test func llmConfigDefaultsToNewZUID() {
  let a = LLMConfig(baseURL: URL(string: "http://a.test")!, api: "openai-completions", model: "m", maxTokens: 1)
  let b = LLMConfig(baseURL: URL(string: "http://a.test")!, api: "openai-completions", model: "m", maxTokens: 1)
  #expect(a.zuid != b.zuid)
  #expect((try? ZUID.fromString(a.zuid)) != nil)
}

@Test func displayNameUsesNameWhenSet() {
  let config = makeConfig(zuid: "zuid-1", name: "Home server")
  #expect(config.displayName == "Home server")
}

@Test func displayNameFallsBackToZUIDWhenNameEmpty() {
  let config = makeConfig(zuid: "zuid-1", name: "")
  #expect(config.displayName == "zuid-1")
}

// MARK: - Validity

@Test func isValidAcceptsHTTPAndHTTPS() {
  #expect(makeConfig(zuid: "z", url: "http://a.test/v1").isValid)
  #expect(makeConfig(zuid: "z", url: "https://a.test/v1").isValid)
}

@Test func isValidRejectsNonPositiveMaxTokens() {
  #expect(!makeConfig(zuid: "z", maxTokens: 0).isValid)
  #expect(!makeConfig(zuid: "z", maxTokens: -5).isValid)
}

@Test func isValidAcceptsReasonableHighMaxTokens() {
  #expect(makeConfig(zuid: "z", maxTokens: 20000).isValid)
}

@Test func isValidAcceptsMillionTokenModels() {
  #expect(makeConfig(zuid: "z", maxTokens: 262_144).isValid)
  #expect(makeConfig(zuid: "z", maxTokens: LLMConfig.maxTokensLimit).isValid)
}

@Test func isValidRejectsAboveCeiling() {
  #expect(!makeConfig(zuid: "z", maxTokens: LLMConfig.maxTokensLimit + 1).isValid)
}

@Test func isValidRejectsIntMax() {
  #expect(!makeConfig(zuid: "z", maxTokens: Int.max).isValid)
}

@Test func isValidRejectsOtherSchemes() {
  #expect(!makeConfig(zuid: "z", url: "ftp://a.test/v1").isValid)
}

// MARK: - Storage

@Test func apiKeyIsNotEncoded() throws {
  let data = try JSONEncoder().encode(makeConfig(zuid: "z"))
  let json = String(decoding: data, as: UTF8.self)
  #expect(!json.contains("apiKey"))
  #expect(!json.contains("secret-key"))
}

@Test func decodedConfigHasNoAPIKey() throws {
  let data = try JSONEncoder().encode(makeConfig(zuid: "z"))
  let decoded = try JSONDecoder().decode(LLMConfig.self, from: data)
  #expect(decoded.apiKey == nil)
  #expect(decoded.zuid == "z")
}

@Test func collectionRoundTripsWithoutKeys() throws {
  let original = LLMConfigCollection(
    configs: ["z1": makeConfig(zuid: "z1", name: "One")],
    activeLLMZUID: "z1"
  )
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(LLMConfigCollection.self, from: data)
  #expect(decoded.activeLLMZUID == "z1")
  #expect(decoded.configs["z1"]?.name == "One")
  #expect(decoded.configs["z1"]?.apiKey == nil)
}

// MARK: - Active config

@Test func activeConfigIsNilWhenEmpty() {
  #expect(LLMConfigCollection().activeConfig == nil)
}

@Test func activeConfigUsesActiveLLMZUID() {
  let collection = LLMConfigCollection(
    configs: ["aaa": makeConfig(zuid: "aaa"), "bbb": makeConfig(zuid: "bbb")],
    activeLLMZUID: "bbb"
  )
  #expect(collection.activeConfig?.zuid == "bbb")
}

@Test func activeConfigFallsBackToFirstSortedZUIDWhenUnset() {
  let collection = LLMConfigCollection(
    configs: ["bbb": makeConfig(zuid: "bbb"), "aaa": makeConfig(zuid: "aaa")]
  )
  #expect(collection.activeConfig?.zuid == "aaa")
}

@Test func activeConfigFallsBackWhenActiveLLMZUIDIsStale() {
  let collection = LLMConfigCollection(
    configs: ["bbb": makeConfig(zuid: "bbb")],
    activeLLMZUID: "deleted"
  )
  #expect(collection.activeConfig?.zuid == "bbb")
}

// MARK: - Sort order assumption

/// The fallback assumes that sorting zuid strings matches creation order.
@Test func zuidStringSortMatchesCreationOrder() {
  let earlier = ZUID.create(millis: 1_794_182_400_000).description
  let later = ZUID.create(millis: 1_794_182_401_000).description
  #expect(earlier < later)
}
