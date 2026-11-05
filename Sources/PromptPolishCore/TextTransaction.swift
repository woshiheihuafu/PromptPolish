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
        case .writeUnconfirmed: return "尚未确认写回结果，请检查原输入框。原文和优化结果仍保留，不会重复写入或自动回滚。"
        }
    }
}

public enum WriteConfirmationIssue: LocalizedError, Equatable {
    case setterFailed(String), readFailed(String), unchanged, differentValue(expectedBytes: Int, actualBytes: Int)
    public var errorDescription: String? {
        let detail: String
        switch self {
        case .setterFailed(let reason): detail = "系统写入调用未成功：\(reason)"
        case .readFailed(let reason): detail = "写入后无法读取原输入框：\(reason)"
        case .unchanged: detail = "写入后多次读取仍为原文，暂未确认输入框已更新。"
        case .differentValue(let expected, let actual): detail = "读回内容与优化结果不同（预期 \(expected) 字节，实际 \(actual) 字节），可能有新编辑或控件转换。"
        }
        return "\(detail) 请检查原输入框；原文与结果仍保留，不会重复写入或自动回滚。"
    }
}

@MainActor
public final class TextTransaction {
    public enum State: Equatable { case ready, replaced, undone, uncertain }
    public let original: String
    public let expiresAt: Date
    public private(set) var replacement: String?
    public private(set) var state: State = .ready
    public private(set) var confirmationIssue: WriteConfirmationIssue?
    private let access: any TextAccess

    public init(access: any TextAccess, original: String, createdAt: Date = Date()) {
        self.access = access
        self.original = original
        expiresAt = createdAt.addingTimeInterval(1_800)
    }

    public func replace(with text: String, now: Date = Date()) async throws {
        guard now < expiresAt else { throw TransactionError.expired }
        guard state == .ready else { throw TransactionError.invalidState }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TransactionError.emptyResult }
        guard sameText(try access.read(), original) else { throw TransactionError.contentChanged }
        replacement = text
        try await checkedWrite(text, previous: original, success: .replaced)
    }

    public func undo(now: Date = Date()) async throws {
        guard now < expiresAt else { throw TransactionError.expired }
        guard state == .replaced, let replacement else { throw TransactionError.invalidState }
        guard sameText(try access.read(), replacement) else { throw TransactionError.contentChanged }
        try await checkedWrite(original, previous: replacement, success: .undone)
    }

    private func checkedWrite(_ value: String, previous: String, success: State) async throws {
        // A setter may mutate before throwing. Never retry or silently roll back an uncertain write.
        state = .uncertain
        confirmationIssue = nil
        do { try access.write(value) }
        catch {
            confirmationIssue = .setterFailed(error.localizedDescription)
            throw TransactionError.writeUnconfirmed
        }
        // Cross-process accessibility caches may lag the actual editor. Retry reads only,
        // yielding to the run loop; never call the setter again or normalize the text.
        for attempt in 0...12 {
            do {
                let actual = try access.read()
                if sameText(actual, value) { state = success; confirmationIssue = nil; return }
                guard sameText(actual, previous) else {
                    confirmationIssue = .differentValue(expectedBytes: value.utf8.count, actualBytes: actual.utf8.count)
                    throw TransactionError.writeUnconfirmed
                }
                confirmationIssue = .unchanged
            } catch let error as TransactionError { throw error }
            catch { confirmationIssue = .readFailed(error.localizedDescription) }
            if attempt < 12 {
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { throw TransactionError.writeUnconfirmed }
            }
        }
        throw TransactionError.writeUnconfirmed
    }

    private func sameText(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
}
