import Foundation

/// `LLMClient` for the OpenAI Chat Completions protocol (`api = "openai-completions"`).
/// Posts the whole conversation to `{baseUrl}/chat/completions` and returns `choices[0].message.content`.
public struct OpenAICompletionsClient: LLMClient {
  /// Base URL including `/v1`, such as `http://localhost:8080/v1`.
  public let baseUrl: String
  /// Optional bearer key, sent as `Authorization: Bearer`.
  public let apiKey: String?
  /// Session used for requests. Tests pass one with a stub protocol.
  public let session: URLSession

  /// Creates a client for an OpenAI-compatible server.
  /// - Parameters:
  ///   - baseUrl: base URL of the server, including `/v1`.
  ///   - apiKey: optional bearer key.
  ///   - session: session for requests.
  public init(baseUrl: String, apiKey: String? = nil, session: URLSession = .shared) {
    self.baseUrl = baseUrl
    self.apiKey = apiKey
    self.session = session
  }

  /// Request body for `POST /chat/completions`.
  struct Request: Encodable {
    struct Message: Encodable {
      let role: String
      let content: String
    }
    let model: String
    let messages: [Message]
  }

  /// Response body from `POST /chat/completions`. Only the fields the app reads.
  struct Response: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable {
        let content: String?
      }
      let message: Message
    }
    let choices: [Choice]
  }

  /// Sends the conversation to the server and returns the reply text.
  /// - Parameters:
  ///   - messages: all prior turns plus the new user message, oldest first.
  ///   - model: model id from `GET {baseUrl}/models`.
  /// - Returns: the assistant's reply text.
  public func chat(_ messages: [LLMMessage], model: String) async throws -> String {
    guard let base = URL(string: baseUrl), base.scheme != nil else {
      throw LLMClientError.invalidBaseURL
    }
    var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let apiKey, !apiKey.isEmpty {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    let body = Request(
      model: model,
      messages: messages.map { Request.Message(role: $0.role.rawValue, content: $0.content) })
    let payload = try JSONEncoder().encode(body)
    request.httpBody = payload
    let target = request.url?.absoluteString ?? ""
    VALogger.log.info("POST \(target) body: \(String(decoding: payload, as: UTF8.self))")

    let (data, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
      throw LLMClientError.badStatus(http.statusCode)
    }
    guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
          let content = decoded.choices.first?.message.content
    else {
      throw LLMClientError.malformedResponse
    }
    VALogger.log.info("reply: \(content)")
    return content
  }
}
