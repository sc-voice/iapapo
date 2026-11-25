import Foundation

/// One turn of a conversation, sent to an `LLMClient`.
public struct LLMMessage: Sendable, Equatable {
  /// Who wrote the message.
  public enum Role: String, Sendable, Equatable {
    case system, user, assistant
  }

  /// Speaker of this message.
  public let role: Role
  /// Text of this message.
  public let content: String

  /// Creates a message.
  /// - Parameters:
  ///   - role: who wrote the message.
  ///   - content: text of the message.
  public init(role: Role, content: String) {
    self.role = role
    self.content = content
  }
}

/// Errors from `LLMClient` implementations.
public enum LLMClientError: Error, Equatable {
  /// The conversation does not end with a user message, so there is nothing to reply to.
  case lastMessageNotUser
  /// The server answered with a non-2xx status.
  case badStatus(Int)
  /// The response body does not have the expected shape.
  case malformedResponse
  /// The base URL cannot be used to build the endpoint URL.
  case invalidBaseURL
}

/// A chat backend, such as Apple's on-device model or an OpenAI-compatible server.
/// Each call sends the whole conversation, because implementations keep no state between calls.
public protocol LLMClient: Sendable {
  /// Sends the conversation and returns the assistant's next reply.
  /// - Parameters:
  ///   - messages: all prior turns plus the new user message, oldest first. A system message, if any, may come first.
  ///   - model: model id from the provider's `models`. Implementations with one fixed model may ignore it.
  /// - Returns: the assistant's reply text.
  func chat(_ messages: [LLMMessage], model: String) async throws -> String
}
