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
        func read() throws -> String {
            guard isAvailable else { throw CocoaError(.fileNoSuchFile) }
            return text
        }
        func write(_ value: String) throws {
            writes.append(value)
            text = transform?(value) ?? value
            if failWrite { throw CocoaError(.fileWriteUnknown) }
        }
    }
    let now = Date(timeIntervalSince1970: 1_000)

    func testReplaceAndUndoPreserveOriginalExactly() throws {
        let field = Field(), original = field.text
        let transaction = TextTransaction(access: field, original: original, createdAt: now)
        try transaction.replace(with: "清晰的需求", now: now)
        expectEqual(field.text, "清晰的需求")
        expectEqual(transaction.state, .replaced)
        try transaction.undo(now: now.addingTimeInterval(5))
        expectEqual(field.text, original)
        expectEqual(transaction.state, .undone)
        expectEqual(field.writes, ["清晰的需求", original])
    }

    func testChangedOriginalRefusesToOverwrite() {
        let field = Field(), transaction = TextTransaction(access: Field(), original: "old", createdAt: now)
        field.text = "new edit"
        let current = TextTransaction(access: field, original: "old", createdAt: now)
        expectThrows(try current.replace(with: "AI result", now: now)) {
            expectEqual($0 as? TransactionError, .contentChanged)
        }
        expectTrue(field.writes.isEmpty)
        expectEqual(transaction.state, .ready)
    }

    func testUndoRefusesToOverwriteNewEdits() throws {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        try transaction.replace(with: "optimized", now: now)
        field.text = "optimized plus my edit"
        expectThrows(try transaction.undo(now: now)) {
            expectEqual($0 as? TransactionError, .contentChanged)
        }
        expectEqual(field.text, "optimized plus my edit")
        expectEqual(field.writes.count, 1)
    }

    func testPartialWriteBlocksAutomaticRetryAndUndo() {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        field.transform = { String($0.prefix(2)) }
        expectThrows(try transaction.replace(with: "complete result", now: now))
        expectEqual(transaction.state, .uncertain)
        expectThrows(try transaction.replace(with: "retry", now: now))
        expectThrows(try transaction.undo(now: now))
        expectEqual(field.writes.count, 1)
    }

    func testSetterThatMutatesThenThrowsIsUncertain() {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        field.failWrite = true
        expectThrows(try transaction.replace(with: "result", now: now))
        expectEqual(transaction.state, .uncertain)
        expectEqual(transaction.replacement, "result")
    }

    func testExpiredSnapshotCannotReplaceOrUndo() throws {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        let expired = now.addingTimeInterval(1_800)
        expectThrows(try transaction.replace(with: "result", now: expired)) {
            expectEqual($0 as? TransactionError, .expired)
        }
        try transaction.replace(with: "result", now: now)
        expectThrows(try transaction.undo(now: expired))
        expectEqual(field.writes.count, 1)
    }

    func testEmptyResultAndMissingTargetNeverWrite() {
        let field = Field(), transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        expectThrows(try transaction.replace(with: " \n", now: now))
        field.isAvailable = false
        expectThrows(try transaction.replace(with: "result", now: now))
        expectTrue(field.writes.isEmpty)
    }

    func testUnicodeNormalizationChangeIsStillANewEdit() {
        let field = Field()
        field.text = "caf\u{00E9}"
        let transaction = TextTransaction(access: field, original: field.text, createdAt: now)
        field.text = "cafe\u{0301}"
        expectThrows(try transaction.replace(with: "replacement", now: now)) {
            expectEqual($0 as? TransactionError, .contentChanged)
        }
        expectTrue(field.writes.isEmpty)
    }
}
