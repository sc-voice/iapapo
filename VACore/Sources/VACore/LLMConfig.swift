import Foundation

/// One connection to an LLM server: where it is, how to talk to it, and how much to ask for.
/// The API key is not encoded. It is stored in the Keychain, keyed by `zuid`.
public struct LLMConfig: Codable, Equatable, Hashable, Sendable, Identifiable {
  /// Stable identity, generated once at creation with `ZUID.create()`. Never changes.
  public let zuid: String
  /// Same as `zuid`, for SwiftUI.
  public var id: String { zuid }
  /// Display name for the list and picker. Empty means use `zuid` (see `displayName`).
  public var name: String
  /// Base URL of the server, for example `http://<host>:<port>/v1`. Scheme, host, and port are read from it.
  public var baseURL: URL
  /// Protocol name, matching `api` in `models.json`. For example `openai-completions`.
  public var api: String
  /// Bearer key for the server. Not encoded; the store fills it from the Keychain by `zuid`.
  public var apiKey: String?
  /// Model ID sent to the server, as returned by `/v1/models`.
  public var model: String
  /// Hard cap on reply length, sent as `max_tokens`. Must be positive.
  public var maxTokens: Int
  /// Seconds to wait for a reply before the request is treated as timed out.
  public var timeout: TimeInterval

  /// Creates a connection config.
  /// - Parameters:
  ///   - zuid: identity. Defaults to a new `ZUID`; pass one only when restoring.
  ///   - name: display name. Empty falls back to `zuid`.
  ///   - baseURL: base URL of the server.
  ///   - api: protocol name, such as `openai-completions`.
  ///   - apiKey: optional bearer key.
  ///   - model: model ID sent to the server.
  ///   - maxTokens: reply length cap. Must be positive.
  ///   - timeout: seconds before a request times out.
  public init(
    zuid: String = ZUID.create().description,
    name: String = "",
    baseURL: URL,
    api: String,
    apiKey: String? = nil,
    model: String,
    maxTokens: Int,
    timeout: TimeInterval = 60
  ) {
    self.zuid = zuid
    self.name = name
    self.baseURL = baseURL
    self.api = api
    self.apiKey = apiKey
    self.model = model
    self.maxTokens = maxTokens
    self.timeout = timeout
  }

  /// The name to show: `name` when set, otherwise `zuid`.
  public var displayName: String {
    name.isEmpty ? zuid : name
  }

  /// Keys written to storage. `apiKey` is deliberately absent.
  enum CodingKeys: String, CodingKey {
    case zuid, name, baseURL, api, model, maxTokens, timeout
  }

  /// Sanity ceiling for `maxTokens` on new configs. It catches typos such as 1G, and allows the million-token
  /// models. The server's own limit (262144 for current models) is a runtime check, not part of this.
  public static let maxTokensLimit = 1_000_000

  /// Whether the config can be used: `maxTokens` within 1 through `maxTokensLimit`, and an http or https base URL.
  public var isValid: Bool {
    (1 ... Self.maxTokensLimit).contains(maxTokens)
      && ["http", "https"].contains(baseURL.scheme?.lowercased() ?? "")
  }
}

/// The saved configs, keyed by `zuid`, and the `zuid` the user selected.
public struct LLMConfigCollection: Codable, Equatable, Sendable {
  /// Configs keyed by `zuid`. Keys never change, so renames and Keychain items stay valid.
  public var configs: [String: LLMConfig]
  /// The `zuid` the user picked in settings. May be nil or stale; `activeConfig` handles both.
  public var activeLLMZUID: String?

  /// Creates a collection.
  /// - Parameters:
  ///   - configs: configs keyed by `zuid`.
  ///   - activeLLMZUID: the `zuid` the user picked, if any.
  public init(configs: [String: LLMConfig] = [:], activeLLMZUID: String? = nil) {
    self.configs = configs
    self.activeLLMZUID = activeLLMZUID
  }

  /// The config that applies. It is the config keyed by `activeLLMZUID` when that key exists.
  /// Otherwise it is the config with the first `zuid` in sorted order, so the choice is deterministic.
  /// Nil when there are no configs.
  public var activeConfig: LLMConfig? {
    if let activeLLMZUID, let config = configs[activeLLMZUID] { return config }
    return configs.keys.sorted().first.flatMap { configs[$0] }
  }
}
