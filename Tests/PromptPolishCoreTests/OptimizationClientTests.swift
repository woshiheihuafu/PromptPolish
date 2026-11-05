import Foundation
@testable import PromptPolishCore

final class OptimizationClientTests {
    final class ProtocolStub: URLProtocol {
        static var handler: ((URLRequest) throws -> (Int, Data))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            do {
                let (status, data) = try Self.handler!(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        override func stopLoading() {}
    }

    func client() -> OptimizationClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProtocolStub.self]
        return OptimizationClient(session: URLSession(configuration: config))
    }
    func tearDown() { ProtocolStub.handler = nil }

    func testChatRequestPreservesOriginalAndParsesResult() async throws {
        let original = "  原文\n请保持 Unicode 🧑‍💻"
        ProtocolStub.handler = { request in
            expectEqual(request.url?.path, "/v1/chat/completions")
            expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
            let stream = request.httpBodyStream!
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let messages = json["messages"] as! [[String: String]]
            expectEqual(messages.last?["content"], original)
            expectEqual(json["model"] as? String, "test-model")
            expectTrue(messages[0]["content"]!.contains("Do not invent"))
            return (200, Data(#"{"choices":[{"message":{"content":"优化后的内容"}}]}"#.utf8))
        }
        let value = try await client().optimize(prompt: original, configuration: APIConfiguration(baseURL: "https://example.com/v1", model: "test-model"), apiKey: "unit-test-key", instruction: nil)
        expectEqual(value, "优化后的内容")
    }

    func testResponsesParsesTextBlocksInOrder() async throws {
        ProtocolStub.handler = { request in
            expectEqual(request.url?.path, "/v1/responses")
            return (200, Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"第一段"},{"type":"output_text","text":"第二段"}]}]}"#.utf8))
        }
        var configuration = APIConfiguration(baseURL: "https://example.com/v1", model: "model")
        configuration.apiProtocol = .responses
        let value = try await client().optimize(prompt: "original", configuration: configuration, apiKey: "test-key", instruction: "更简短")
        expectEqual(value, "第一段\n第二段")
    }

    func testUnauthorizedIsSafeErrorWithoutServiceBody() async {
        ProtocolStub.handler = { _ in (401, Data("secret diagnostic material".utf8)) }
        do {
            _ = try await client().optimize(prompt: "original", configuration: APIConfiguration(baseURL: "https://example.com/v1", model: "model"), apiKey: "test-key", instruction: nil)
            fail("Should reject 401")
        } catch { expectEqual(error as? OptimizationError, .httpStatus(401)) }
    }

    func testEmptyAndMalformedResultsNeverBecomeReplacement() async {
        for json in [#"{"choices":[{"message":{"content":"  "}}]}"#, #"{"choices":[]}"#, "not JSON"] {
            ProtocolStub.handler = { _ in (200, Data(json.utf8)) }
            do {
                _ = try await client().optimize(prompt: "original", configuration: APIConfiguration(baseURL: "https://example.com/v1", model: "model"), apiKey: "test-key", instruction: nil)
                fail("Should reject unusable response")
            } catch { expectTrue(error is OptimizationError) }
        }
    }

    func testExplicitlyIncompleteResponsesAreRejected() async {
        for json in [#"{"choices":[{"finish_reason":"length","message":{"content":"partial prompt"}}]}"#, #"{"choices":[{"finish_reason":"content_filter","message":{"content":"partial prompt"}}]}"#] {
            ProtocolStub.handler = { _ in (200, Data(json.utf8)) }
            do {
                _ = try await client().optimize(prompt: "original", configuration: APIConfiguration(baseURL: "https://example.com/v1", model: "model"), apiKey: "test-key", instruction: nil)
                fail("Explicitly truncated output must not be used")
            } catch { expectTrue(error is OptimizationError) }
        }
        for status in ["incomplete", "failed", "cancelled", "in_progress"] {
            let body: [String: Any] = ["status": status, "output": [["content": [["type": "output_text", "text": "partial prompt"]]]]]
            ProtocolStub.handler = { _ in (200, try JSONSerialization.data(withJSONObject: body)) }
            do {
                _ = try await client().optimize(prompt: "original", configuration: APIConfiguration(baseURL: "https://example.com/v1", model: "model", apiProtocol: .responses), apiKey: "test-key", instruction: nil)
                fail("Non-completed Responses status must not be used: \(status)")
            } catch { expectTrue(error is OptimizationError) }
        }
    }
}
