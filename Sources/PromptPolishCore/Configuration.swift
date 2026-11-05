import Foundation

public enum APIProtocol: String, Codable, CaseIterable, Sendable {
    case chatCompletions, responses
    public var title: String { self == .chatCompletions ? "Chat Completions" : "Responses" }
    var endpoint: String { self == .chatCompletions ? "chat/completions" : "responses" }
}

public struct APIConfiguration: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var apiProtocol: APIProtocol
    public var systemPrompt: String

    public init(baseURL: String = "https://api.openai.com/v1", model: String = "", apiProtocol: APIProtocol = .chatCompletions, systemPrompt: String = OptimizationPrompt.defaultSystemPrompt) {
        self.baseURL = baseURL
        self.model = model
        self.apiProtocol = apiProtocol
        self.systemPrompt = systemPrompt
    }

    private enum CodingKeys: String, CodingKey { case baseURL, model, apiProtocol, systemPrompt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        model = try values.decode(String.self, forKey: .model)
        apiProtocol = try values.decode(APIProtocol.self, forKey: .apiProtocol)
        systemPrompt = try values.decodeIfPresent(String.self, forKey: .systemPrompt) ?? OptimizationPrompt.defaultSystemPrompt
    }

    public func validatedURL() throws -> URL {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationError.missingModel }
        guard !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationError.emptySystemPrompt }
        let text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw ConfigurationError.invalidURL
        }
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        guard parts.scheme == "https" || (parts.scheme == "http" && local) else { throw ConfigurationError.insecureURL }
        let path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.hasSuffix("chat/completions"), !path.hasSuffix("responses") else { throw ConfigurationError.endpointIncluded }
        guard let root = parts.url else { throw ConfigurationError.invalidURL }
        return root.appendingPathComponent(apiProtocol.endpoint)
    }
}

public enum ConfigurationError: LocalizedError, Equatable {
    case missingModel, missingKey, invalidURL, insecureURL, endpointIncluded, emptySystemPrompt
    public var errorDescription: String? {
        switch self {
        case .missingModel: return "请输入服务商提供的完整模型 ID。"
        case .missingKey: return "请先配置 API Key。"
        case .emptySystemPrompt: return "优化提示词不能为空，请填写规则或恢复默认。"
        case .invalidURL: return "请输入有效的 Base URL，且不要包含用户名、密码、查询参数或片段。"
        case .insecureURL: return "远程 API 需使用 HTTPS；本机模型服务可使用 HTTP。"
        case .endpointIncluded: return "Base URL 不应包含 chat/completions 或 responses 接口路径。"
        }
    }
}
