import Foundation
import Testing
@testable import VACore

/// Fixed ZUIDs, so tests control identity and ordering.
private let modelZUID = ZUID.create(millis: 1_000, sequence: 1, signature: 1)
private let providerID = ZUID.create(millis: 2_000, sequence: 2, signature: 2).text
private let otherProviderID = ZUID.create(millis: 3_000, sequence: 3, signature: 3).text

private let sampleCost = ModelCost(input: 0.5, output: 1.5, cacheRead: 0.05, cacheWrite: 0.6)

/// Builds a model with fixed identity and pi's required fields, so tests are deterministic.
private func makeModel(
  id: String = "gemma-test",
  name: String = "",
  reasoning: Bool = true,
  input: [ModelInputModality] = [.text, .image],
  cost: ModelCost = sampleCost,
  contextWindow: Int = 262_144,
  maxTokens: Int = 20000,
  zuid: ZUID = modelZUID,
  provider: String = providerID
) -> LLMModel {
  LLMModel(
    id: id,
    name: name,
    api: "openai-completions",
    baseUrl: "http://localhost:8080/v1",
    reasoning: reasoning,
    input: input,
    cost: cost,
    contextWindow: contextWindow,
    maxTokens: maxTokens,
    provider: provider,
    zuid: zuid
  )
}

// MARK: - Identity and names

@Test func llmModelDefaultsToNewZUID() {
  let a = makeModel(zuid: ZUID.create())
  let b = makeModel(zuid: ZUID.create())
  #expect(a.zuid != b.zuid)
}

@Test func llmModelDisplayNameFallsBackToID() {
  #expect(makeModel(id: "gemma-test", name: "").displayName == "gemma-test")
}

@Test func llmModelDisplayNameUsesNameWhenSet() {
  #expect(makeModel(id: "gemma-test", name: "Gemma 4 (home)").displayName == "Gemma 4 (home)")
}

@Test func llmModelLabelIsZUIDPrefixThenDisplayName() {
  let model = makeModel(name: "Gemma 4")
  #expect(model.label == "\(modelZUID.text.prefix(6))-Gemma 4")
}

@Test func llmModelLabelChangesWithNameButIdentityDoesNot() {
  var model = makeModel(name: "Old")
  let before = model.zuid
  model.name = "New"
  #expect(model.zuid == before)
  #expect(model.label.hasSuffix("-New"))
}

// MARK: - Codable (pi-style round trip)

@Test func llmModelRoundTripKeepsAllFields() throws {
  let original = makeModel(
    id: "gemma-4-26B-A4B-it-MLX-8bit",
    name: "Gemma 4",
    reasoning: false,
    input: [.text],
    contextWindow: 131_072,
    maxTokens: 512,
    provider: otherProviderID
  )
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(LLMModel.self, from: data)
  #expect(decoded == original)
  #expect(decoded.zuid == modelZUID)
  #expect(decoded.provider == otherProviderID)
}

@Test func llmModelUsesPiFieldNames() throws {
  let data = try JSONEncoder().encode(makeModel(id: "gemma-test", name: "Gemma", contextWindow: 8192, maxTokens: 256))
  let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(object["id"] as? String == "gemma-test")
  #expect(object["name"] as? String == "Gemma")
  #expect(object["reasoning"] as? Bool == true)
  #expect(object["input"] as? [String] == ["text", "image"])
  #expect(object["contextWindow"] as? Int == 8192)
  #expect(object["maxTokens"] as? Int == 256)
  #expect(object["zuid"] as? String == modelZUID.text)
  #expect(object["provider"] as? String == providerID)
  #expect(object["modelID"] == nil)
}

@Test func modelCostUsesPiRateNames() throws {
  let data = try JSONEncoder().encode(sampleCost)
  let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Double])
  #expect(Set(object.keys) == ["input", "output", "cacheRead", "cacheWrite"])
  #expect(object["cacheWrite"] == 0.6)
}

// MARK: - Validity

@Test func llmModelAcceptsMaxTokensBounds() {
  #expect(makeModel(maxTokens: 1).isValid)
  #expect(makeModel(maxTokens: LLMModel.maxTokensLimit).isValid)
}

@Test func llmModelRejectsMaxTokensOutOfRange() {
  #expect(!makeModel(maxTokens: 0).isValid)
  #expect(!makeModel(maxTokens: -5).isValid)
  #expect(!makeModel(maxTokens: LLMModel.maxTokensLimit + 1).isValid)
}

@Test func llmModelRejectsEmptyID() {
  #expect(!makeModel(id: "").isValid)
}

@Test func llmModelRejectsNonPositiveContextWindow() {
  #expect(!makeModel(contextWindow: 0).isValid)
}

// MARK: - Equality

@Test func llmModelEqualityUsesAllFields() {
  let base = makeModel()
  #expect(base == makeModel())
  #expect(base != makeModel(provider: otherProviderID))
  #expect(base != makeModel(id: "other"))
  #expect(base != makeModel(reasoning: false))
  #expect(base != makeModel(contextWindow: 1))
}

// MARK: - Optional pi fields

/// A model with every optional pi field set, so round trips exercise all of them.
private func fullModel() -> LLMModel {
  LLMModel(
    id: "full",
    api: "openai-completions",
    baseUrl: "http://localhost:8080/v1",
    type: "chat",
    reasoning: true,
    thinkingLevelMap: ["high": "high", "xhigh": nil],
    input: [.text, .image],
    inputLimits: ModelInputLimits(
      maxRequestBytes: 1_000_000,
      images: ModelImageInputLimits(
        resize: ModelImageResizeOptions(maxWidth: 1024, maxHeight: 1024, maxBytes: 500_000, jpegQuality: 85),
        maxPerMessage: 4,
        maxPerRequest: 8
      )
    ),
    cost: ModelCost(
      input: 1, output: 2, cacheRead: 0.1, cacheWrite: 1.25,
      tiers: [ModelCostTier(inputTokensAbove: 200_000, input: 2, output: 4, cacheRead: 0.2, cacheWrite: 2.5)]
    ),
    promptCache: ModelPromptCache(short: 300, long: 3600),
    contextWindow: 262_144,
    maxTokens: 4096,
    samplingParams: ["temperature": .number(0.7), "stop": .array([.string("END")])],
    samplingParamsByThinkingLevel: ["high": ["temperature": .number(1.0)]],
    headers: ["X-Test": "1"],
    compat: ["supportsStore": .bool(false)],
    provider: providerID
  )
}

@Test func llmModelRoundTripKeepsOptionalPiFields() throws {
  let original = fullModel()
  let decoded = try JSONDecoder().decode(LLMModel.self, from: JSONEncoder().encode(original))
  #expect(decoded == original)
  #expect(decoded.cost.tiers?.first?.inputTokensAbove == 200_000)
  #expect(decoded.inputLimits?.images?.resize?.jpegQuality == 85)
  #expect(decoded.samplingParamsByThinkingLevel?["high"]?["temperature"] == .number(1.0))
}

@Test func llmModelDecodesNullThinkingLevelAsHidden() throws {
  let json = Data(#"{"id":"m","name":"m","api":"openai-completions","baseUrl":"http://x","reasoning":true,"thinkingLevelMap":{"xhigh":null,"high":"high"},"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":8192,"maxTokens":256,"provider":"p","zuid":\#(json(modelZUID))}"#.utf8)
  let model = try JSONDecoder().decode(LLMModel.self, from: json)
  #expect(model.thinkingLevelMap?["xhigh"] == .some(nil))
  #expect(model.thinkingLevelMap?["high"] == "high")
}

@Test func llmModelOmittedOptionalFieldsDecodeAsNil() throws {
  let json = Data(#"{"id":"m","name":"m","api":"openai-completions","baseUrl":"http://x","reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":8192,"maxTokens":256,"provider":"p","zuid":\#(json(modelZUID))}"#.utf8)
  let model = try JSONDecoder().decode(LLMModel.self, from: json)
  #expect(model.type == nil)
  #expect(model.inputLimits == nil)
  #expect(model.cost.tiers == nil)
  #expect(model.compat == nil)
}

/// JSON-quotes a ZUID's text for embedding in a literal.
private func json(_ zuid: ZUID) -> String {
  "\"\(zuid.text)\""
}
