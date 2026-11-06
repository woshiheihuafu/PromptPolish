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

@MainActor
func expectAsyncThrows<T>(_ expression: @autoclosure () async throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) async {
    do { _ = try await expression(); fail("Expected error. \(message)", file: file, line: line) }
    catch { handler(error) }
}

@main
struct Checks {
    @MainActor static func main() async {
        let transaction = TextTransactionTests(), configuration = ConfigurationTests(), placement = FloatingPlacementTests(), previewPlacement = PreviewPlacementTests(), api = OptimizationClientTests(), model = AppModelTests(), ax = AXTextAccessTests(), panel = PreviewPanelTests()
        let scenes = SceneTests()
        let hover = FloatingHoverTests()
        let passive = PassiveProbeTests()
        let sync: [(String, () throws -> Void)] = [
            ("scene limit and required fields", scenes.testSceneLimitAndRequiredFields),
            ("scene settings persist and cancel", scenes.testSceneSettingsPersistAndCancelWithoutAPIChanges),
            ("deleted scene cannot start optimization", scenes.testDeletedSceneDoesNotCaptureOrStartRequest),
            ("expanded hover remains anchored outside input", hover.testExpansionKeepsOriginalHitAreaAndAvoidsInputAtEdges),
            ("empty scenes and no-space hover geometry", hover.testEmptyScenesHaveNoChooserAndNoRoomIsSafe),
            ("unconfigured hover has no popup", hover.testNoConfiguredScenesDoesNotShowPopup),
            ("native tracking starts hover synchronously", hover.testNativeTrackingDeliversEntrySynchronouslyForInactiveWindows),
            ("different input at same geometry closes old chooser", hover.testSameGeometryDifferentInputClosesOldChooser),
            ("legacy API configuration migration", configuration.testOldConfigurationMigratesWithoutLosingProviderSettings),
            ("custom prompt save and discard", model.testCustomPromptSaveAndDiscardUseExistingSettingsSemantics),
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
            ("AX focused window is optional", ax.testOptionalFocusedWindowIsNotRequiredWhenExactFieldIsKnown),
            ("AX rejects another focused field", ax.testOtherFocusedFieldIsNeverSubstituted),
            ("AX rejects another focused window", ax.testOtherWindowIsNeverAccepted),
            ("AX rejects changed window membership", ax.testPinnedFieldMovedToOtherWindowIsRejected),
            ("source foreground requires original focus", ax.testForegroundSourceStillRequiresItsOriginalFocus),
            ("AX rejects unrelated foreground app", ax.testUnrelatedForegroundApplicationBlocksWrite),
            ("AX rejects invalid and secure handles", ax.testInvalidOrSecurePinnedTargetsAreRejected),
            ("preview above bottom composer", previewPlacement.testBottomComposerGetsAdjacentPreviewAbove),
            ("preview below top composer", previewPlacement.testTopComposerGetsAdjacentPreviewBelow),
            ("preview shrinks before overlapping", previewPlacement.testShrinksToAvailableSpaceBeforeOverlappingComposer),
            ("preview uses available side", previewPlacement.testUsesSideWhenNeitherAboveNorBelowFits),
            ("preview stays on composer display", previewPlacement.testUsesTheComposerDisplayWithNegativeOrigin),
            ("compact fallback stays on screen", previewPlacement.testNoRoomStillKeepsCompactPopupOnScreen)
        ]
        var count = 0
        for (name, check) in sync {
            let before = CheckLog.shared.messages.count
            do { try check() } catch { fail("\(name): \(error)") }
            print("\(CheckLog.shared.messages.count == before ? "PASS" : "FAIL") \(name)")
            count += 1
        }
        let asyncChecks: [(String, () async throws -> Void)] = [
            ("scene prompt survives regeneration and resets for default", scenes.testSceneRequestRegenerationAndDefaultKeepCorrectPrompt),
            ("hover opens immediately and menu crossing retains it", hover.testHoverImmediatelyShowsConfiguredMenuAndCrossingKeepsItOpen),
            ("passive probe is nonblocking and coalesces newest target", passive.testPassiveProbeDoesNotBlockUIAndCoalescesNewestTarget),
            ("cancelled passive probe cannot overwrite capture", passive.testCancelledProbeCannotOverwriteFreshCapture),
            ("reenter during collapse keeps chooser expanded", hover.testReenterDuringCollapseAndPeriodicUpdateKeepMenuExpanded),
            ("latest-source scene persists and adding stops at five", scenes.testLatestSourceUsesSessionSceneAndAddStopsAtFive),
            ("replace/undo preserves Unicode and whitespace", transaction.testReplaceAndUndoPreserveOriginalExactly),
            ("changed original blocks write", transaction.testChangedOriginalRefusesToOverwrite),
            ("undo protects new edits", transaction.testUndoRefusesToOverwriteNewEdits),
            ("partial writes block retry", transaction.testPartialWriteBlocksAutomaticRetryAndUndo),
            ("mutating setter error is uncertain", transaction.testSetterThatMutatesThenThrowsIsUncertain),
            ("snapshot expires", transaction.testExpiredSnapshotCannotReplaceOrUndo),
            ("empty output/missing target never writes", transaction.testEmptyResultAndMissingTargetNeverWrite),
            ("normalization-only edit is protected", transaction.testUnicodeNormalizationChangeIsStillANewEdit),
            ("preview focus retains exact AX target", ax.testPreviewFocusDoesNotInvalidatePinnedField),
            ("preview blur still protects newer text", ax.testChangedTextStillBlocksWriteAfterPreviewFocus),
            ("delayed readback confirms replace and undo", transaction.testDelayedReadbackConfirmsReplaceAndUndoWithoutRepeatingWrite),
            ("delayed successful write closes popup", panel.testDelayedSuccessfulWriteClosesPopupAndRetainsUndo),
            ("stale readback has bounded confirmation", transaction.testUnchangedReadbackIsBoundedAndNeverRepeatsWrite),
            ("unreadable readback diagnosis", transaction.testUnreadableReadbackHasSpecificFailureAndNoRetryWrite),
            ("readback normalization remains unconfirmed", transaction.testReadbackNormalizationDoesNotBecomeConfirmedSuccess),
            ("write confirmation prevents interleaving and late popup", model.testWriteConfirmationBlocksInterleavingAndDoesNotReopenDismissedPreview),
            ("custom system prompt in both APIs", api.testCustomPromptIsUsedByBothProtocolsAndRegeneration),
            ("AX setter error retains code", ax.testSetterErrorCodeIsPreservedInConfirmationDiagnostic),
            ("AX readback error retains code", ax.testReadErrorCodeIsPreservedAfterSuccessfulSetter),
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
            ("fast mode requires first manual confirmation", model.testQuickModeRequiresSuccessfulManualReplacementFirst),
            ("comparison appears before response", model.testNewOptimizationShowsComparisonBeforeResponse),
            ("preview retains last matching source position", model.testPreviewRetainsLastMatchingAnchorWhenFocusChanges),
            ("successful replacement closes native popup and settings", panel.testSuccessfulReplaceHidesPopupAndSettingsButKeepsUndo),
            ("blocked replacement keeps popup", panel.testBlockedReplaceKeepsResultPopupOpen),
            ("closing loading popup cancels request", panel.testClosingLoadingPopupCancelsLateResult)
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
