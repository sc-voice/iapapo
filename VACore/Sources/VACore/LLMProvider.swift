import Foundation

/// Fallback values for models discovered from a server, matching pi's catalog fallbacks (`ai/catalog/define.ts`).
/// Pi has no per-API table, so the same values apply to every `api`. The user can override any field.
public enum LLMModelDefaults {
  /// Context window used when the server does not say. Matches pi's fallback of 4096.
  public static let contextWindow = 4096
  /// Reply cap used when the server does not say. Matches pi's fallback of 4096.
  public static let maxTokens = 4096

  /// Builds a discovered model with pi's fallback metadata: text input, no reasoning, zero cost, no prompt cache.
  /// - Parameters:
  ///   - id: model id, as returned by `/v1/models`.
  ///   - api: wire protocol of the provider.
  ///   - baseUrl: base URL of the provider.
  ///   - provider: `zuid` text of the provider that serves the model.
  ///   - contextWindow: context window reported by the server. Nil uses the fallback.
  /// - Returns: a model with every required pi field set.
  public static func model(
    id: String, api: String, baseUrl: String, provider: String, contextWindow reported: Int? = nil
  ) -> LLMModel {
    LLMModel(
      id: id,
      api: api,
      baseUrl: baseUrl,
      reasoning: false,
      input: [.text],
      cost: ModelCost(input: 0, output: 0, cacheRead: 0, cacheWrite: 0),
      contextWindow: reported ?? contextWindow,
      maxTokens: maxTokens,
      provider: provider
    )
  }
}

/// A configured endpoint and the models it serves. Matches pi's `providers.<id>` entry.
/// The API key is not encoded. It is stored in the Keychain, keyed by `zuid`.
public struct LLMProvider: Codable, Equatable, Hashable, Sendable, Identifiable {
  /// IaPapo identity, generated once with `ZUID.create()`. Never changes. Keys the Keychain item.
  public let zuid: ZUID
  /// Same as `zuid.text`, for SwiftUI and for the `provider` field of its models.
  public var id: String { zuid.text }
  /// pi `name`: display name. Empty means use `id` (see `displayName`).
  public var name: String
  /// pi `baseUrl`: endpoint base URL.
  public var baseUrl: String
  /// pi `api`: wire protocol, such as `openai-completions`.
  public var api: String
  /// pi `apiKey`: bearer key. Not encoded; the store fills it from the Keychain by `zuid`.
  public var apiKey: String?
  /// pi `models`: models this provider serves. Discovered ids start with `LLMModelDefaults` metadata.
  public var models: [LLMModel]

  /// Keys written to storage. `apiKey` is deliberately absent.
  enum CodingKeys: String, CodingKey {
    case zuid, name, baseUrl, api, models
  }

  /// Creates a provider.
  /// - Parameters:
  ///   - zuid: identity. Defaults to a new `ZUID`; pass one only when restoring.
  ///   - name: display name. Empty falls back to `id`.
  ///   - baseUrl: endpoint base URL.
  ///   - api: wire protocol.
  ///   - apiKey: optional bearer key.
  ///   - models: models served by this provider.
  public init(
    zuid: ZUID = ZUID.create(),
    name: String = "",
    baseUrl: String,
    api: String,
    apiKey: String? = nil,
    models: [LLMModel] = []
  ) {
    self.zuid = zuid
    self.name = name
    self.baseUrl = baseUrl
    self.api = api
    self.apiKey = apiKey
    self.models = models
  }

  /// The default provider: Apple's on-device Foundation Models, with one fixed model `system`.
  /// It has no endpoint (`baseUrl` is empty) and no key. Its `zuid` is fixed so the identity is stable across launches.
  /// The model's context window comes from `AppleFoundationModelsClient.contextSize`; `maxTokens` uses `LLMModelDefaults`.
  /// Requires iOS 27.0 or later.
  public static var appleFoundationModels: LLMProvider {
    let zuid = try! ZUID.fromString("07XD5vl_57JAKovSmUMuVu")
    let api = "apple-foundation-models"
    return LLMProvider(
      zuid: zuid,
      name: "apple-foundation-model",
      baseUrl: "",
      api: api,
      models: [
        LLMModelDefaults.model(
          id: "system", api: api, baseUrl: "", provider: zuid.text,
          contextWindow: AppleFoundationModelsClient.contextSize)
      ])
  }

  /// System instruction sent by `testChat()`. Asks the model to repeat a fact in every reply, which shows whether it follows instructions.
  public static let testSystemInstruction = "Include the capital of France in every response"
  /// User question sent by `testChat()`.
  public static let testUserQuestion = "Hello! What is the capital of Italy?"

  /// Sends the test conversation (`testSystemInstruction`, `testUserQuestion`) through this provider's client.
  /// Uses the first model, or `system` when the provider has none. Requires `apiKey` to be set for keyed servers.
  /// - Returns: the model's reply text.
  public func testChat() async throws -> String {
    let model = models.first?.id ?? "system"
    VALogger.log.info("test provider=\(displayName) model=\(model)")
    let client: any LLMClient
    if api == "apple-foundation-models" {
      client = AppleFoundationModelsClient()
    } else {
      client = OpenAICompletionsClient(baseUrl: baseUrl, apiKey: apiKey)
    }
    let messages = [
      LLMMessage(role: .system, content: Self.testSystemInstruction),
      LLMMessage(role: .user, content: Self.testUserQuestion),
    ]
    return try await client.chat(messages, model: model)
  }

  /// The name to show: `name` when set, otherwise `id`.
  public var displayName: String {
    name.isEmpty ? id : name
  }

  /// Adds a model discovered from the server, unless a model with the same id exists.
  /// The server's context window is used when reported; otherwise pi's fallbacks apply.
  /// - Parameter discovered: the model as listed by `/v1/models`.
  public mutating func addDiscoveredModel(_ discovered: DiscoveredModel) {
    guard !models.contains(where: { $0.id == discovered.id }) else { return }
    models.append(
      LLMModelDefaults.model(
        id: discovered.id, api: api, baseUrl: baseUrl, provider: id, contextWindow: discovered.maxModelLen))
  }

  /// The model with the given id, if this provider serves it.
  /// - Parameter modelID: model id to find.
  public func model(id modelID: String) -> LLMModel? {
    models.first { $0.id == modelID }
  }
}
