// Adapted from pi-coding-agent (https://github.com/earendil-works/pi, MIT License, Copyright (c) 2025 Mario Zechner)
// for compatibility with pi's model config, and extended for IaPapo's application use (zuid).
// The full MIT license text is in THIRD_PARTY_LICENSES.md at the repo root.

import Foundation

/// Input modality, matching pi's `ModelInputModality`.
public enum ModelInputModality: String, Codable, Equatable, Hashable, Sendable {
  case text
  case image
}

/// One request-wide pricing tier, matching pi's `ModelCostTier`. Applies when input tokens exceed `inputTokensAbove`.
public struct ModelCostTier: Codable, Equatable, Hashable, Sendable {
  /// Use this tier when total request input exceeds this token count.
  public var inputTokensAbove: Double
  /// Input cost, USD per million tokens.
  public var input: Double
  /// Output cost, USD per million tokens.
  public var output: Double
  /// Cache-read cost, USD per million tokens.
  public var cacheRead: Double
  /// Cache-write cost, USD per million tokens.
  public var cacheWrite: Double

  /// Creates a tier. All rates are USD per million tokens.
  public init(inputTokensAbove: Double, input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
    self.inputTokensAbove = inputTokensAbove
    self.input = input
    self.output = output
    self.cacheRead = cacheRead
    self.cacheWrite = cacheWrite
  }
}

/// Prices in USD per million tokens, matching pi's `ModelCost`.
public struct ModelCost: Codable, Equatable, Hashable, Sendable {
  /// Input cost, USD per million tokens.
  public var input: Double
  /// Output cost, USD per million tokens.
  public var output: Double
  /// Cache-read cost, USD per million tokens.
  public var cacheRead: Double
  /// Cache-write cost, USD per million tokens.
  public var cacheWrite: Double
  /// Request-wide pricing tiers. The highest matching input threshold applies to the full request. Nil when absent.
  public var tiers: [ModelCostTier]?

  /// Creates a cost record. All rates are USD per million tokens.
  public init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double, tiers: [ModelCostTier]? = nil) {
    self.input = input
    self.output = output
    self.cacheRead = cacheRead
    self.cacheWrite = cacheWrite
    self.tiers = tiers
  }
}

/// Best-effort prompt cache lifetime in seconds for each retention tier, matching pi's `ModelPromptCache`.
public struct ModelPromptCache: Codable, Equatable, Hashable, Sendable {
  /// Lifetime of the short tier, in seconds.
  public var short: Double?
  /// Lifetime of the long tier, in seconds.
  public var long: Double?

  /// Creates a prompt cache record. Nil tiers have no known lifetime.
  public init(short: Double? = nil, long: Double? = nil) {
    self.short = short
    self.long = long
  }
}

/// Resize profile applied to an image before it enters history, matching pi's `ModelImageResizeOptions`.
public struct ModelImageResizeOptions: Codable, Equatable, Hashable, Sendable {
  /// Maximum width in pixels.
  public var maxWidth: Int?
  /// Maximum height in pixels.
  public var maxHeight: Int?
  /// Maximum base64-encoded payload size in bytes.
  public var maxBytes: Int?
  /// JPEG quality, 1 ... 100.
  public var jpegQuality: Int?

  /// Creates resize options. Nil fields are not applied.
  public init(maxWidth: Int? = nil, maxHeight: Int? = nil, maxBytes: Int? = nil, jpegQuality: Int? = nil) {
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.maxBytes = maxBytes
    self.jpegQuality = jpegQuality
  }
}

/// Image limits, matching pi's `ModelImageInputLimits`.
public struct ModelImageInputLimits: Codable, Equatable, Hashable, Sendable {
  /// Cache-safe resize profile applied before a new image enters conversation history.
  public var resize: ModelImageResizeOptions?
  /// Maximum images accepted in one provider message.
  public var maxPerMessage: Int?
  /// Maximum images accepted across one provider request.
  public var maxPerRequest: Int?

  /// Creates image limits. Nil fields are not enforced.
  public init(resize: ModelImageResizeOptions? = nil, maxPerMessage: Int? = nil, maxPerRequest: Int? = nil) {
    self.resize = resize
    self.maxPerMessage = maxPerMessage
    self.maxPerRequest = maxPerRequest
  }
}

/// Provider input limits, matching pi's `ModelInputLimits`.
public struct ModelInputLimits: Codable, Equatable, Hashable, Sendable {
  /// Maximum serialized provider request size in bytes.
  public var maxRequestBytes: Int?
  /// Image limits.
  public var images: ModelImageInputLimits?

  /// Creates input limits. Nil fields are not enforced.
  public init(maxRequestBytes: Int? = nil, images: ModelImageInputLimits? = nil) {
    self.maxRequestBytes = maxRequestBytes
    self.images = images
  }
}

/// One model served by an endpoint. Field names and types follow pi's `Model` (`ai/src/types.ts`), so the two can be compared directly.
/// IaPapo adds `zuid`, which pi does not have. `provider` holds the `zuid` of the endpoint that serves the model.
public struct LLMModel: Codable, Equatable, Hashable, Sendable {
  /// pi `id`: model name sent to the server, as returned by `/v1/models`. Unique within a provider.
  public var id: String
  /// pi `name`: display name. Empty means use `id` (see `displayName`).
  public var name: String
  /// pi `api`: wire protocol, such as `openai-completions`.
  public var api: String
  /// pi `baseUrl`: endpoint base URL.
  public var baseUrl: String
  /// pi `type`: `"chat"` or nil. Nil means chat.
  public var type: String?
  /// pi `reasoning`: whether the model supports reasoning.
  public var reasoning: Bool
  /// pi `thinkingLevelMap`: provider value per thinking level. A string is sent; nil (JSON null) hides the level.
  public var thinkingLevelMap: [String: String?]?
  /// pi `input`: modalities the model accepts.
  public var input: [ModelInputModality]
  /// pi `inputLimits`: provider request and image limits.
  public var inputLimits: ModelInputLimits?
  /// pi `cost`: prices in USD per million tokens.
  public var cost: ModelCost
  /// pi `promptCache`: prompt cache lifetimes per retention tier.
  public var promptCache: ModelPromptCache?
  /// pi `contextWindow`: total context size in tokens.
  public var contextWindow: Int
  /// pi `maxTokens`: hard cap on reply length, sent as `max_tokens`. Must be positive.
  public var maxTokens: Int
  /// pi `samplingParams`: default sampling parameters, merged into each request body.
  public var samplingParams: [String: JSONValue]?
  /// pi `samplingParamsByThinkingLevel`: sampling overrides keyed by thinking level.
  public var samplingParamsByThinkingLevel: [String: [String: JSONValue]]?
  /// pi `headers`: request headers.
  public var headers: [String: String]?
  /// pi `compat`: compatibility overrides for the wire protocol. Kept as JSON; pi's schema varies by `api`.
  public var compat: [String: JSONValue]?
  /// pi `provider`: provider id that serves this model. IaPapo uses the endpoint's `zuid` text.
  public var provider: String

  /// IaPapo: stable identity, generated once with `ZUID.create()`. Never changes. Pi has no equivalent.
  public let zuid: ZUID

  /// Largest `maxTokens` accepted. Catches typos such as 1G while allowing million-token models.
  public static let maxTokensLimit = 1_000_000

  /// Creates a model entry with pi's required fields.
  /// - Parameters:
  ///   - id: model name, as returned by `/v1/models`.
  ///   - name: display name. Empty falls back to `id`.
  ///   - api: wire protocol.
  ///   - baseUrl: endpoint base URL.
  ///   - type: `"chat"` or nil.
  ///   - reasoning: whether the model supports reasoning.
  ///   - thinkingLevelMap: provider value per thinking level.
  ///   - input: accepted modalities.
  ///   - inputLimits: provider request and image limits.
  ///   - cost: prices in USD per million tokens.
  ///   - promptCache: prompt cache lifetimes.
  ///   - contextWindow: total context size in tokens.
  ///   - maxTokens: reply length cap. Must be within `1 ... maxTokensLimit`.
  ///   - samplingParams: default sampling parameters.
  ///   - samplingParamsByThinkingLevel: sampling overrides per thinking level.
  ///   - headers: request headers.
  ///   - compat: compatibility overrides.
  ///   - provider: provider id that serves this model.
  ///   - zuid: identity. Defaults to a new `ZUID`; pass one only when restoring.
  public init(
    id: String,
    name: String = "",
    api: String,
    baseUrl: String,
    type: String? = nil,
    reasoning: Bool,
    thinkingLevelMap: [String: String?]? = nil,
    input: [ModelInputModality],
    inputLimits: ModelInputLimits? = nil,
    cost: ModelCost,
    promptCache: ModelPromptCache? = nil,
    contextWindow: Int,
    maxTokens: Int,
    samplingParams: [String: JSONValue]? = nil,
    samplingParamsByThinkingLevel: [String: [String: JSONValue]]? = nil,
    headers: [String: String]? = nil,
    compat: [String: JSONValue]? = nil,
    provider: String,
    zuid: ZUID = ZUID.create(),
  ) {
    self.id = id
    self.name = name
    self.api = api
    self.baseUrl = baseUrl
    self.type = type
    self.reasoning = reasoning
    self.thinkingLevelMap = thinkingLevelMap
    self.input = input
    self.inputLimits = inputLimits
    self.cost = cost
    self.promptCache = promptCache
    self.contextWindow = contextWindow
    self.maxTokens = maxTokens
    self.samplingParams = samplingParams
    self.samplingParamsByThinkingLevel = samplingParamsByThinkingLevel
    self.headers = headers
    self.compat = compat
    self.zuid = zuid
    self.provider = provider
  }

  /// The name to show: `name` when set, otherwise `id`.
  public var displayName: String {
    name.isEmpty ? id : name
  }

  /// Display label: the first six characters of `zuid` followed by the display name, as in doc slugs.
  /// Use for display only. The full `zuid` is the identity.
  public var label: String {
    "\(zuid.text.prefix(6))-\(displayName)"
  }

  /// Whether the entry can be used: `maxTokens` within `1 ... maxTokensLimit`, a non-empty `id`, and a positive `contextWindow`.
  public var isValid: Bool {
    (1 ... Self.maxTokensLimit).contains(maxTokens) && !id.isEmpty && contextWindow > 0
  }
}
