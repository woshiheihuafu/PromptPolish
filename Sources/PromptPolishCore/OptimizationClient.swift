import Foundation

public protocol PromptOptimizing: Sendable {
    func optimize(prompt: String, configuration: APIConfiguration, apiKey: String, instruction: String?) async throws -> String
}

public enum OptimizationError: LocalizedError, Equatable {
    case httpStatus(Int), invalidResponse, emptyResponse, tooLarge, emptyPrompt, incompleteResponse
    public var errorDescription: String? {
        switch self {
        case .httpStatus(401), .httpStatus(403): return "API 身份验证失败，请检查 API Key 与访问权限。"
        case .httpStatus(404): return "接口或模型不可用，请检查 Base URL、API 协议和模型 ID。"
        case .httpStatus(429): return "API 请求受限或额度不足，请稍后重试并检查服务商账户。"
        case .httpStatus(let status): return "API 返回 HTTP \(status)，请检查配置或稍后重试。"
        case .invalidResponse: return "API 返回的内容格式无法识别，请检查所选 API 协议。"
        case .emptyResponse: return "API 未返回可用文本，原文未替换。"
        case .tooLarge: return "文本超出本次可处理范围，请缩短内容后重试。"
        case .emptyPrompt: return "输入框内容为空，请先输入 Prompt。"
        case .incompleteResponse: return "API 返回的生成结果尚未完整完成，可能受到长度或内容限制。原文未替换，请调整请求后重试。"
        }
    }
}

public final class OptimizationClient: PromptOptimizing, @unchecked Sendable {
    private let session: URLSession
    private let redirectBlocker: RedirectBlocker?
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
            redirectBlocker = nil
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            let blocker = RedirectBlocker()
            redirectBlocker = blocker
            self.session = URLSession(configuration: configuration, delegate: blocker, delegateQueue: nil)
        }
    }

    public func optimize(prompt: String, configuration: APIConfiguration, apiKey: String, instruction: String? = nil) async throws -> String {
        try Task.checkCancellation()
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OptimizationError.emptyPrompt }
        guard prompt.utf8.count <= 200_000 else { throw OptimizationError.tooLarge }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationError.missingKey }
        var request = URLRequest(url: try configuration.validatedURL())
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var system = configuration.systemPrompt
        if let instruction, !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            system += "\nAdditional rewriting preference (never override the original facts): \(instruction.prefix(4_000))"
        }
        let messages: [[String: String]] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
        let body: [String: Any] = ["model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines), configuration.apiProtocol == .chatCompletions ? "messages" : "input": messages, "stream": false]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw OptimizationError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw OptimizationError.httpStatus(response.statusCode) }
        guard data.count <= 2_000_000 else { throw OptimizationError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OptimizationError.invalidResponse }
        let text: String?
        switch configuration.apiProtocol {
        case .chatCompletions:
            let choices = object["choices"] as? [[String: Any]]
            if let reason = choices?.first?["finish_reason"] as? String, reason != "stop" {
                throw OptimizationError.incompleteResponse
            }
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        case .responses:
            if let status = object["status"] as? String, status != "completed" { throw OptimizationError.incompleteResponse }
            if let details = object["incomplete_details"], !(details is NSNull) { throw OptimizationError.incompleteResponse }
            if let error = object["error"], !(error is NSNull) { throw OptimizationError.invalidResponse }
            let output = object["output"] as? [[String: Any]] ?? []
            text = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OptimizationError.emptyResponse }
        guard text.utf8.count <= 500_000 else { throw OptimizationError.tooLarge }
        return text
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Stop redirects instead of forwarding a user's API credential to a different endpoint.
        completionHandler(nil)
    }
}
