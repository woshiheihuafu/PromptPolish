import Foundation

final class CheckLog {
    static let shared = CheckLog()
    private let lock = NSLock()
    private var failures = [String]()
    func record(_ message: String) { lock.lock(); defer { lock.unlock() }; failures.append(message) }
    var messages: [String] { lock.lock(); defer { lock.unlock() }; return failures }
}
func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    CheckLog.shared.record("\(file):\(line): \(message)")
}
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if lhs != rhs { fail("Expected \(rhs), got \(lhs). \(message)", file: file, line: line) }
}
func expectTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !value { fail("Expected true. \(message)", file: file, line: line) }
}
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    expectTrue(!value, file: file, line: line)
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { fail("Expected nil", file: file, line: line) }
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    do { _ = try expression(); fail("Expected error. \(message)", file: file, line: line) }
    catch { handler(error) }
}

@main
struct Checks {
    @MainActor static func main() async {
        let transaction = TextTransactionTests(), configuration = ConfigurationTests(), placement = FloatingPlacementTests(), api = OptimizationClientTests(), model = AppModelTests(), ax = AXTextAccessTests()
        let sync: [(String, () throws -> Void)] = [
            ("replace/undo preserves Unicode and whitespace", transaction.testReplaceAndUndoPreserveOriginalExactly),
            ("changed original blocks write", transaction.testChangedOriginalRefusesToOverwrite),
            ("undo protects new edits", transaction.testUndoRefusesToOverwriteNewEdits),
            ("partial writes block retry", transaction.testPartialWriteBlocksAutomaticRetryAndUndo),
            ("mutating setter error is uncertain", transaction.testSetterThatMutatesThenThrowsIsUncertain),
            ("snapshot expires", transaction.testExpiredSnapshotCannotReplaceOrUndo),
            ("empty output/missing target never writes", transaction.testEmptyResultAndMissingTargetNeverWrite),
            ("normalization-only edit is protected", transaction.testUnicodeNormalizationChangeIsStillANewEdit),
            ("base URL normalization", configuration.testBuildsEndpointWithoutDuplicatingSlashes),
            ("Responses endpoint", configuration.testResponsesEndpoint),
            ("reject insecure URLs/credentials", configuration.testRejectsInsecureRemoteURLAndEmbeddedCredentials),
            ("local server and required model", configuration.testAllowsLocalModelServerButRequiresModel),
            ("right button placement", placement.testPrefersRightOutsideField),
            ("left button placement", placement.testRightEdgeUsesLeftAndDoesNotOverlap),
            ("above button placement", placement.testSpansScreenWidthUsesAbove),
            ("no room/offscreen hides button", placement.testNoRoomOrOffscreenHidesButton),
            ("secondary display", placement.testNegativeOriginSecondaryDisplay),
            ("original focused AX target reads", ax.testOriginalFocusedTargetCanBeRead),
            ("preview focus retains exact AX target", ax.testPreviewFocusDoesNotInvalidatePinnedField),
            ("AX focused window is optional", ax.testOptionalFocusedWindowIsNotRequiredWhenExactFieldIsKnown),
            ("preview blur still protects newer text", ax.testChangedTextStillBlocksWriteAfterPreviewFocus),
            ("AX rejects another focused field", ax.testOtherFocusedFieldIsNeverSubstituted),
            ("AX rejects another focused window", ax.testOtherWindowIsNeverAccepted),
            ("AX rejects changed window membership", ax.testPinnedFieldMovedToOtherWindowIsRejected),
            ("source foreground requires original focus", ax.testForegroundSourceStillRequiresItsOriginalFocus),
            ("AX rejects unrelated foreground app", ax.testUnrelatedForegroundApplicationBlocksWrite),
            ("AX rejects invalid and secure handles", ax.testInvalidOrSecurePinnedTargetsAreRejected)
        ]
        var count = 0
        for (name, check) in sync {
            let before = CheckLog.shared.messages.count
            do { try check() } catch { fail("\(name): \(error)") }
            print("\(CheckLog.shared.messages.count == before ? "PASS" : "FAIL") \(name)")
            count += 1
        }
        let asyncChecks: [(String, () async throws -> Void)] = [
            ("Chat Completions real serialization", api.testChatRequestPreservesOriginalAndParsesResult),
            ("Responses parsing", api.testResponsesParsesTextBlocksInOrder),
            ("safe HTTP error", api.testUnauthorizedIsSafeErrorWithoutServiceBody),
            ("reject empty/malformed output", api.testEmptyAndMalformedResultsNeverBecomeReplacement),
            ("reject incomplete provider output", api.testExplicitlyIncompleteResponsesAreRejected),
            ("settings pause blocks late quick replacement", model.testSettingsPauseCancelsAndRejectsLateQuickReplacement),
            ("dismiss cancels late preview", model.testDismissedRequestCannotReopenPreview),
            ("obsolete request cannot replace newer result", model.testOlderRequestCannotReplaceNewerResult),
            ("in-flight edits block quick replacement", model.testInFlightEditPreventsQuickReplacement),
            ("native model preview/replace/undo", model.testPreviewReplaceAndUndoThroughNativeModel),
            ("deleting result retains native editor", model.testDeletingResultKeepsNativeTextEditorMounted),
            ("fast mode requires first manual confirmation", model.testQuickModeRequiresSuccessfulManualReplacementFirst)
        ]
        for (name, check) in asyncChecks {
            let before = CheckLog.shared.messages.count
            do { try await check() } catch { fail("\(name): \(error)") }
            api.tearDown()
            print("\(CheckLog.shared.messages.count == before ? "PASS" : "FAIL") \(name)")
            count += 1
        }
        let failures = CheckLog.shared.messages
        for message in failures { print(message) }
        print("\(count) checks, \(failures.count) failure(s)")
        if !failures.isEmpty { exit(1) }
    }
}
