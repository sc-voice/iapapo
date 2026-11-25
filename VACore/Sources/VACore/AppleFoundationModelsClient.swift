import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// `LLMClient` for Apple's on-device model, through the Foundation Models framework. Serves `LLMProvider.appleFoundationModels`.
/// The framework has no URL or key. The system message becomes session instructions, earlier turns become
/// transcript entries, and the last user message is the prompt. Requires iOS 27.0 or later.
public struct AppleFoundationModelsClient: LLMClient {
  /// Creates a client for the default on-device model.
  public init() {}

  /// Maximum context size in tokens, as reported by `SystemLanguageModel.default.contextSize`.
  public static var contextSize: Int {
    SystemLanguageModel.default.contextSize
  }

  /// Whether the on-device model can be used now.
  public static var isAvailable: Bool {
    SystemLanguageModel.default.isAvailable
  }

  /// Builds a session from the conversation and returns the reply to its last user message.
  /// - Parameters:
  ///   - messages: all prior turns plus the new user message, oldest first.
  ///   - model: ignored. The framework has one fixed model, `system`.
  /// - Returns: the model's reply text.
  public func chat(_ messages: [LLMMessage], model: String) async throws -> String {
    VALogger.log.info("chat model=\(model) messages=\(messages.count)")
    for message in messages {
      VALogger.log.info("\(message.role.rawValue): \(message.content)")
    }
    var entries: [Transcript.Entry] = []

    if let system = messages.first(where: { $0.role == .system }) {
      VALogger.log.info("entry instructions: \(system.content)")
      entries.append(.instructions(Transcript.Instructions(
        segments: [.text(Transcript.TextSegment(content: system.content))],
        toolDefinitions: [])))
    }

    let turns = messages.filter { $0.role != .system }
    guard let last = turns.last, last.role == .user else {
      throw LLMClientError.lastMessageNotUser
    }

    for turn in turns.dropLast() {
      let segment = Transcript.Segment.text(Transcript.TextSegment(content: turn.content))
      switch turn.role {
      case .user:
        VALogger.log.info("entry prompt: \(turn.content)")
        entries.append(.prompt(Transcript.Prompt(segments: [segment])))
      case .assistant:
        VALogger.log.info("entry response: \(turn.content)")
        entries.append(.response(Transcript.Response(segments: [segment])))
      case .system:
        break
      }
    }

    let session = LanguageModelSession(model: .default, transcript: Transcript(entries: entries))
    VALogger.log.info("respond transcriptEntries=\(entries.count)")
    VALogger.log.info("respond prompt: \(last.content)")
    let reply = try await session.respond(to: last.content).content
    VALogger.log.info("respond reply: \(reply)")
    return reply
  }
}
#endif
