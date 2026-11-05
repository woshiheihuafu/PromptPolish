import Foundation

@MainActor
public protocol TextAccess: AnyObject {
    func read() throws -> String
    func write(_ text: String) throws
}

public enum TransactionError: LocalizedError, Equatable {
    case contentChanged, expired, invalidState, emptyResult, writeUnconfirmed
    public var errorDescription: String? {
        switch self {
        case .contentChanged: return "原文已更新，已暂停操作。当前输入保持不变，请使用最新内容重新优化。"
        case .expired: return "原文快照已过期，请回到输入框重新触发优化。"
        case .invalidState: return "当前操作无法执行。请先查看输入框和已保存的文本快照。"
        case .emptyResult: return "优化结果为空，无法替换原文。"
        case .writeUnconfirmed: return "未能确认写回结果，内容可能只写入了一部分。请检查原输入框；为保护新内容，不会自动重试或回滚。"
        }
    }
}

@MainActor
public final class TextTransaction {
    public enum State: Equatable { case ready, replaced, undone, uncertain }
    public let original: String
    public let expiresAt: Date
    public private(set) var replacement: String?
    public private(set) var state: State = .ready
    private let access: any TextAccess

    public init(access: any TextAccess, original: String, createdAt: Date = Date()) {
        self.access = access
        self.original = original
        expiresAt = createdAt.addingTimeInterval(1_800)
    }

    public func replace(with text: String, now: Date = Date()) throws {
        guard now < expiresAt else { throw TransactionError.expired }
        guard state == .ready else { throw TransactionError.invalidState }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TransactionError.emptyResult }
        guard sameText(try access.read(), original) else { throw TransactionError.contentChanged }
        replacement = text
        try checkedWrite(text, success: .replaced)
    }

    public func undo(now: Date = Date()) throws {
        guard now < expiresAt else { throw TransactionError.expired }
        guard state == .replaced, let replacement else { throw TransactionError.invalidState }
        guard sameText(try access.read(), replacement) else { throw TransactionError.contentChanged }
        try checkedWrite(original, success: .undone)
    }

    private func checkedWrite(_ value: String, success: State) throws {
        // A setter may mutate before throwing. Never retry or silently roll back an uncertain write.
        state = .uncertain
        do {
            try access.write(value)
            guard sameText(try access.read(), value) else { throw TransactionError.writeUnconfirmed }
            state = success
        } catch { throw TransactionError.writeUnconfirmed }
    }

    private func sameText(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
}
