import Foundation

public struct OptimizationScene: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var systemPrompt: String
    public init(id: UUID = UUID(), name: String = "", systemPrompt: String = "") {
        self.id = id; self.name = name; self.systemPrompt = systemPrompt
    }
}

public struct SceneConfiguration: Codable, Equatable, Sendable {
    public static let maximumCount = 5
    public var scenes: [OptimizationScene]
    public init(scenes: [OptimizationScene] = []) { self.scenes = scenes }
    public func validated() throws -> Self {
        guard scenes.count <= Self.maximumCount else { throw SceneError.tooMany }
        guard Set(scenes.map(\.id)).count == scenes.count else { throw SceneError.duplicateIdentity }
        var result = self
        for index in result.scenes.indices {
            result.scenes[index].name = result.scenes[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.scenes[index].name.isEmpty else { throw SceneError.missingName }
            guard !result.scenes[index].systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SceneError.missingPrompt }
        }
        return result
    }
}

public enum SceneError: LocalizedError, Equatable {
    case tooMany, missingName, missingPrompt, duplicateIdentity, unavailable
    public var errorDescription: String? {
        switch self {
        case .tooMany: return "最多可配置 5 个优化场景。"
        case .missingName: return "请为每个场景填写名称。"
        case .missingPrompt: return "请为每个场景填写独立的优化提示词。"
        case .duplicateIdentity: return "场景配置存在重复标识，请重新添加重复的场景。"
        case .unavailable: return "该场景已被删除或配置已变化，请重新选择。"
        }
    }
}
