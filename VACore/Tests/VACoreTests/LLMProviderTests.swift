import Foundation
import Testing

@testable import VACore

@Test func providerEncodingOmitsAPIKey() throws {
  let provider = LLMProvider(name: "Local", baseUrl: "http://localhost:8080/v1", api: "openai-completions", apiKey: "secret")
  let data = try JSONEncoder().encode(provider)
  let text = String(decoding: data, as: UTF8.self)
  #expect(!text.contains("secret"))
  #expect(!text.contains("apiKey"))
}

@Test func providerRoundTripKeepsFieldsExceptAPIKey() throws {
  let original = LLMProvider(name: "Local", baseUrl: "http://localhost:8080/v1", api: "openai-completions", apiKey: "secret")
  let decoded = try JSONDecoder().decode(LLMProvider.self, from: JSONEncoder().encode(original))
  #expect(decoded.zuid == original.zuid)
  #expect(decoded.name == "Local")
  #expect(decoded.baseUrl == original.baseUrl)
  #expect(decoded.api == original.api)
  #expect(decoded.apiKey == nil)
}

@Test func discoveredModelUsesPiFallbacks() {
  var provider = LLMProvider(baseUrl: "http://localhost:8080/v1", api: "openai-completions")
  provider.addDiscoveredModel(DiscoveredModel(id: "gemma-test"))
  let model = provider.model(id: "gemma-test")
  #expect(model?.contextWindow == 4096)
  #expect(model?.maxTokens == 4096)
  #expect(model?.input == [.text])
  #expect(model?.reasoning == false)
  #expect(model?.baseUrl == provider.baseUrl)
  #expect(model?.api == provider.api)
  #expect(model?.provider == provider.id)
}

@Test func discoveredModelUsesServerContextWindowWhenReported() {
  var provider = LLMProvider(baseUrl: "http://localhost:8080/v1", api: "openai-completions")
  provider.addDiscoveredModel(DiscoveredModel(id: "m", maxModelLen: 131_072))
  #expect(provider.model(id: "m")?.contextWindow == 131_072)
  #expect(provider.model(id: "m")?.maxTokens == 4096)
}

@Test func discoveringTheSameModelTwiceAddsOnce() {
  var provider = LLMProvider(baseUrl: "http://localhost:8080/v1", api: "openai-completions")
  provider.addDiscoveredModel(DiscoveredModel(id: "m"))
  provider.addDiscoveredModel(DiscoveredModel(id: "m"))
  #expect(provider.models.count == 1)
}

@Test func userOverrideSurvivesRoundTrip() throws {
  var provider = LLMProvider(baseUrl: "http://localhost:8080/v1", api: "openai-completions")
  provider.addDiscoveredModel(DiscoveredModel(id: "m"))
  provider.models[0].contextWindow = 131_072
  let decoded = try JSONDecoder().decode(LLMProvider.self, from: JSONEncoder().encode(provider))
  #expect(decoded.model(id: "m")?.contextWindow == 131_072)
}

@Test func appleFoundationModelsDefaultIsFixed() {
  let provider = LLMProvider.appleFoundationModels
  #expect(provider.api == "apple-foundation-models")
  #expect(provider.name == "apple-foundation-model")
  #expect(provider.baseUrl.isEmpty)
  #expect(provider.apiKey == nil)
  #expect(provider.model(id: "system") != nil)
  #expect(LLMProvider.appleFoundationModels.id == provider.id)
}
