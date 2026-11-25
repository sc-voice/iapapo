import Foundation
import Testing

@testable import VACore

/// Answers requests with a canned response, so discovery tests never touch the network.
private final class StubProtocol: URLProtocol {
  nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = StubProtocol.handler else { return }
    let (status, body) = handler(request)
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func stubbedSession() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [StubProtocol.self]
  return URLSession(configuration: config)
}

@Suite(.serialized)
struct LLMModelDiscoveryTests {
  @Test func parsesModelIDsFromOpenAIListing() throws {
    let body = Data(#"{"object":"list","data":[{"id":"gemma-a"},{"id":"qwen-b"}]}"#.utf8)
    #expect(try LLMModelDiscovery.parseModels(body) == [DiscoveredModel(id: "gemma-a"), DiscoveredModel(id: "qwen-b")])
  }

  @Test func parsesOMLXMaxModelLen() throws {
    let body = Data(#"{"data":[{"id":"m","max_model_len":131072}]}"#.utf8)
    #expect(try LLMModelDiscovery.parseModels(body) == [DiscoveredModel(id: "m", maxModelLen: 131_072)])
  }

  @Test func rejectsMalformedListing() {
    #expect(throws: LLMModelDiscoveryError.malformedResponse) {
      try LLMModelDiscovery.parseModels(Data(#"{"models":[]}"#.utf8))
    }
  }

  @Test func fetchesModelsUnderBaseURLWithBearerKey() async throws {
    var seen: URLRequest?
    StubProtocol.handler = { request in
      seen = request
      return (200, Data(#"{"data":[{"id":"m1"}]}"#.utf8))
    }
    let models = try await LLMModelDiscovery.fetchModels(
      baseUrl: "http://localhost:8080/v1", apiKey: "k", session: stubbedSession())
    #expect(models == [DiscoveredModel(id: "m1")])
    #expect(seen?.url?.absoluteString == "http://localhost:8080/v1/models")
    #expect(seen?.value(forHTTPHeaderField: "Authorization") == "Bearer k")
  }

  @Test func reportsNonSuccessStatus() async {
    StubProtocol.handler = { _ in (401, Data()) }
    await #expect(throws: LLMModelDiscoveryError.badStatus(401)) {
      try await LLMModelDiscovery.fetchModels(baseUrl: "http://localhost:8080/v1", session: stubbedSession())
    }
  }
}
