import Foundation
@testable import PromptPolishCore

final class ConfigurationTests {
    func testBuildsEndpointWithoutDuplicatingSlashes() throws {
        let config = APIConfiguration(baseURL: " https://example.com/v1/ ", model: " model ")
        expectEqual(try config.validatedURL().absoluteString, "https://example.com/v1/chat/completions")
    }
    func testResponsesEndpoint() throws {
        var config = APIConfiguration(baseURL: "https://example.com/v1", model: "model")
        config.apiProtocol = .responses
        expectEqual(try config.validatedURL().path, "/v1/responses")
    }
    func testRejectsInsecureRemoteURLAndEmbeddedCredentials() {
        for url in ["http://example.com/v1", "https://user:key@example.com", "https://example.com?key=secret", "https://example.com/#fragment", "file:///tmp/api", "https://example.com/v1/chat/completions"] {
            expectThrows(try APIConfiguration(baseURL: url, model: "model").validatedURL(), url)
        }
    }
    func testAllowsLocalModelServerButRequiresModel() throws {
        expectEqual(try APIConfiguration(baseURL: "http://localhost:1234/v1", model: "local").validatedURL().host, "localhost")
        expectThrows(try APIConfiguration(baseURL: "https://example.com", model: " \n").validatedURL())
    }
}
