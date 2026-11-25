import Foundation

/// Errors from `LLMModelDiscovery.fetchModelIDs`.
public enum LLMModelDiscoveryError: Error, Equatable {
  /// The base URL cannot be used to build the `/models` URL.
  case invalidBaseURL
  /// The server answered with a non-2xx status.
  case badStatus(Int)
  /// The body is not the OpenAI-style `{"data": [{"id": ...}]}` shape.
  case malformedResponse
}

/// A model listed by a provider's `/models` endpoint.
public struct DiscoveredModel: Equatable, Hashable, Sendable {
  /// Model id, as returned by `/v1/models`.
  public let id: String
  /// Context window in tokens, when the server reports it (oMLX `max_model_len`). Nil when absent.
  public let maxModelLen: Int?

  /// Creates a discovered model.
  /// - Parameters:
  ///   - id: model id.
  ///   - maxModelLen: context window in tokens, if reported.
  public init(id: String, maxModelLen: Int? = nil) {
    self.id = id
    self.maxModelLen = maxModelLen
  }
}

/// Lists models from a provider's `/models` endpoint, the OpenAI-compatible route under `baseUrl`.
public enum LLMModelDiscovery {
  /// Fetches the models a provider serves.
  /// - Parameters:
  ///   - baseUrl: provider base URL, such as `http://localhost:8080/v1`. `models` is appended to it.
  ///   - apiKey: optional bearer key, sent as `Authorization: Bearer`.
  ///   - session: session to use. Tests pass one with a stub protocol.
  /// - Returns: the models, in the order the server sent them.
  public static func fetchModels(
    baseUrl: String,
    apiKey: String? = nil,
    session: URLSession = .shared
  ) async throws -> [DiscoveredModel] {
    guard let base = URL(string: baseUrl), base.scheme != nil else {
      throw LLMModelDiscoveryError.invalidBaseURL
    }
    var request = URLRequest(url: base.appendingPathComponent("models"))
    request.httpMethod = "GET"
    if let apiKey, !apiKey.isEmpty {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
      throw LLMModelDiscoveryError.badStatus(http.statusCode)
    }
    return try parseModels(data)
  }

  /// Parses an OpenAI-style model list, reading `id` and the optional oMLX `max_model_len` of each entry.
  /// - Parameter data: the response body.
  /// - Returns: one `DiscoveredModel` per entry in `data`.
  static func parseModels(_ data: Data) throws -> [DiscoveredModel] {
    struct Listing: Decodable {
      struct Entry: Decodable {
        let id: String
        let maxModelLen: Int?
        enum CodingKeys: String, CodingKey { case id, maxModelLen = "max_model_len" }
      }
      let data: [Entry]
    }
    guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else {
      throw LLMModelDiscoveryError.malformedResponse
    }
    return listing.data.map { DiscoveredModel(id: $0.id, maxModelLen: $0.maxModelLen) }
  }
}
