import Foundation
@testable import PromptPolishCore

@MainActor
final class TextTransactionTests {
    final class Field: TextAccess {
        var text = "  原始 Prompt 👩🏽‍💻\n"
        var writes = [String]()
        var transform: ((String) -> String)?
        var failWrite = false
        var isAvailable = true
        var staleReadsAfterWrite = 0
        var failReadsAfterWrite = false
        private var remainingStaleReads = 0
        private var cached = ""
        func read() throws -> String {
            guard isAvailable else { throw CocoaError(.fileNoSuchFile) }
            if failReadsAfterWrite && !writes.isEmpty { throw CocoaError(.fileReadUnknown) }
            if remainingStaleReads > 0 { remainingStaleReads -= 1; return cached }
            return text
        }
        func write(_ value: String) throws {
            cached = text
            remainingStaleReads = staleReadsAfterWrite
            writes.append(value)
            text = transform?(value) ?? value
            if failWrite { throw CocoaError(.fileWriteUnknown) }
        }
    }
    let now = Date(timeIntervalSince1970: 1_000)

    func testDelayedReadbackConfirmsReplaceAndUndoWithoutRepeatingWrite() async throws {
        let field = Field(), original = field.text
        field.staleReadsAfterWrite = 2
        let transaction = TextTransaction(access: field, original: original)
        try await transaction.replace(with: "优化后的完整内容")
        expectEqual(transaction.state, .replaced)
        expectEqual(field.writes, ["优化后的完整内容"])
        try await transaction.undo()
        expectEqual(transaction.state, .undone)
        expectEqual(field.text, original)
        expectEqual(field.writes, ["优化后的完整内容", original])
    }

    func testUnchangedReadbackIsBoundedAndNeverRepeatsWrite() async {
        let field = Field()
        field.staleReadsAfterWrite = 100
        let transaction = TextTransaction(access: field, original: field.text)
        await expectAsyncThrows(try await transaction.replace(with: "complete"))
        expectEqual(transaction.state, .uncertain)
        expectEqual(transaction.confirmationIssue, .unchanged)
        expectEqual(field.writes, ["complete"])
    }

    func testUnreadableReadbackHasSpecificFailureAndNoRetryWrite() async {
        let field = Field()
        field.failReadsAfterWrite = true
        let transaction = TextTransaction(access: field, original: field.text)
        await expectAsyncThrows(try await transaction.replace(with: "complete"))
        if case .readFailed = transaction.confirmationIssue {} else { fail("Expected a readback failure, not a partial-write diagnosis") }
        expectEqual(transaction.state, .uncertain)
        expectEqual(field.writes, ["complete"])
    }

    func testReadbackNormalizationDoesNotBecomeConfirmedSuccess() async {
        let field = Field()
        field.transform = { _ in "cafe\u{0301}" }
        let transaction = TextTransaction(access: field, original: field.text)
        await expectAsyncThrows(try await transaction.replace(with: "caf\u{00E9}"))
        expectEqual(transaction.confirmationIssue, .differentValue(expectedBytes: 5, actualBytes: 6))
        expectEqual(transaction.state, .uncertain)
        expectEqual(field.writes.count, 1)
    }

    func testReplaceAndUndoPreserveOriginalExactly() async throws {
        let field = Field(), original = field.text
        let transaction = TextTransaction(access: field, original: original, createdAt: now)
        try await transaction.replace(with: "清晰的需求", now: now)
        expectEqual(field.text, "清晰的需求")
        expectEqual(transaction.state, .replaced)
        try await transaction.undo(now: now.addingTimeInterval(5))
        expectEqual(field.text, original)
        expectEqual(transaction.state, .undone)
        expectEqual(field.writes, ["清晰的需求", original])
    }

    func testChangedOriginalRefusesToOverwrite() async {
        let field = Field(), transaction = TextTransaction(access: Field(), original: "old", createdAt: now)
        field.text = "new edit"
        let current = TextTransaction(access: field, original: "old", createdAt: now)
        await expectAsyncThrows(try await current.replace(with: "AI result", now: now)) {
            expectEqual($0 as? TransactionError, .contentChanged)
        }
        expectTrue(field.writes.isEmpty)
        expectEqual(transaction.state, .ready)
    }

    func testUndoRefusesToOverwriteNewEdits() async throws {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        try await transaction.replace(with: "optimized", now: now)
        field.text = "optimized plus my edit"
        await expectAsyncThrows(try await transaction.undo(now: now)) {
            expectEqual($0 as? TransactionError, .contentChanged)
        }
        expectEqual(field.text, "optimized plus my edit")
        expectEqual(field.writes.count, 1)
    }

    func testPartialWriteBlocksAutomaticRetryAndUndo() async {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        field.transform = { String($0.prefix(2)) }
        await expectAsyncThrows(try await transaction.replace(with: "complete result", now: now))
        expectEqual(transaction.state, .uncertain)
        await expectAsyncThrows(try await transaction.replace(with: "retry", now: now))
        await expectAsyncThrows(try await transaction.undo(now: now))
        expectEqual(field.writes.count, 1)
    }

    func testSetterThatMutatesThenThrowsIsUncertain() async {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        field.failWrite = true
        await expectAsyncThrows(try await transaction.replace(with: "result", now: now))
        expectEqual(transaction.state, .uncertain)
        expectEqual(transaction.replacement, "result")
    }

    func testExpiredSnapshotCannotReplaceOrUndo() async throws {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        let expired = now.addingTimeInterval(1_800)
        await expectAsyncThrows(try await transaction.replace(with: "result", now: expired)) {
            expectEqual($0 as? TransactionError, .expired)
        }
        try await transaction.replace(with: "result", now: now)
        await expectAsyncThrows(try await transaction.undo(now: expired))
        expectEqual(field.writes.count, 1)
    }

    func testEmptyResultAndMissingTargetNeverWrite() async {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        await expectAsyncThrows(try await transaction.replace(with: " \n", now: now))
        field.isAvailable = false
        await expectAsyncThrows(try await transaction.replace(with: "result", now: now))
        expectTrue(field.writes.isEmpty)
    }

    func testUnicodeNormalizationChangeIsStillANewEdit() async {
        let field = Field()
        field.text = "caf\u{00E9}"
        let transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        field.text = "cafe\u{0301}"
        await expectAsyncThrows(try await transaction.replace(with: "replacement", now: now)) {
            expectEqual($0 as? TransactionError, .contentChanged)
        }
        expectTrue(field.writes.isEmpty)
    }
}
