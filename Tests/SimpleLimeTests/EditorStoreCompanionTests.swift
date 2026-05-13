import XCTest
@testable import SimpleLime

private typealias SLTextRange = SimpleLime.TextRange

@MainActor
final class EditorStoreCompanionTests: XCTestCase {
    func testApplyCompanionSuggestionReplacesAnchoredText() {
        let store = makeStore(text: "The draft is very very fast.")
        let bufferID = store.selectedBufferID!
        let suggestion = CompanionSuggestion(
            title: "Tighten copy",
            comment: "Shorter wording reads better.",
            findText: "very very fast",
            replacementText: "fast"
        )
        store.replaceCompanionSuggestions([suggestion], for: bufferID)

        store.applyCompanionSuggestion(suggestion.id, in: bufferID)

        XCTAssertEqual(store.selectedBuffer?.text, "The draft is fast.")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 13, length: 4)])
        XCTAssertEqual(store.companionSuggestions(for: bufferID).first?.isApplied, true)
    }

    func testApplyCompanionSuggestionUsesUniqueFuzzyAnchor() {
        let store = makeStore(text: "The draft is very fast.")
        let bufferID = store.selectedBufferID!
        let suggestion = CompanionSuggestion(
            title: "Tighten copy",
            comment: "Shorter wording reads better.",
            findText: "very very fast",
            replacementText: "fast"
        )
        store.replaceCompanionSuggestions([suggestion], for: bufferID)

        store.applyCompanionSuggestion(suggestion.id, in: bufferID)

        XCTAssertEqual(store.selectedBuffer?.text, "The draft is fast.")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 13, length: 4)])
        XCTAssertEqual(store.companionSuggestions(for: bufferID).first?.isApplied, true)
    }

    func testApplyCompanionSuggestionRejectsAmbiguousFuzzyAnchor() {
        let store = makeStore(text: "The draft is very fast. The fallback is very fast.")
        let bufferID = store.selectedBufferID!
        let suggestion = CompanionSuggestion(
            title: "Tighten copy",
            comment: "Shorter wording reads better.",
            findText: "very very fast",
            replacementText: "fast"
        )
        store.replaceCompanionSuggestions([suggestion], for: bufferID)

        store.applyCompanionSuggestion(suggestion.id, in: bufferID)

        XCTAssertEqual(store.selectedBuffer?.text, "The draft is very fast. The fallback is very fast.")
        XCTAssertEqual(store.lastError, "Could not apply companion suggestion because the original text was not found.")
        XCTAssertEqual(store.companionSuggestions(for: bufferID).first?.isApplied, false)
    }

    func testAddCompanionSuggestionAsCommentAnchorsComment() {
        let store = makeStore(text: "Ship this TBD after review.")
        let bufferID = store.selectedBufferID!
        let suggestion = CompanionSuggestion(
            title: "Resolve TBD",
            comment: "This placeholder needs a decision.",
            findText: "TBD",
            replacementText: "TBD"
        )
        store.replaceCompanionSuggestions([suggestion], for: bufferID)

        let comment = store.addCompanionSuggestionAsComment(suggestion.id, in: bufferID)

        XCTAssertEqual(comment?.body, "This placeholder needs a decision.")
        XCTAssertEqual(comment?.quote, "TBD")
        XCTAssertEqual(store.selectedBufferComments.map(\.id), [comment?.id].compactMap { $0 })
    }

    func testAddCompanionSuggestionAsCommentUsesFuzzyAnchor() {
        let store = makeStore(text: "Ship this TBD item after review.")
        let bufferID = store.selectedBufferID!
        let suggestion = CompanionSuggestion(
            title: "Resolve TBD",
            comment: "This placeholder needs a decision.",
            findText: "Ship this TBD after review",
            replacementText: "Ship this TBD after review"
        )
        store.replaceCompanionSuggestions([suggestion], for: bufferID)

        let comment = store.addCompanionSuggestionAsComment(suggestion.id, in: bufferID)

        XCTAssertEqual(comment?.body, "This placeholder needs a decision.")
        XCTAssertEqual(comment?.quote, "Ship this TBD item after review")
    }

    func testApplyCompanionSuggestionReportsMissingAnchor() {
        let store = makeStore(text: "Changed text")
        let bufferID = store.selectedBufferID!
        let suggestion = CompanionSuggestion(
            title: "Replace",
            comment: "Anchor is gone.",
            findText: "Original text",
            replacementText: "Replacement"
        )
        store.replaceCompanionSuggestions([suggestion], for: bufferID)

        store.applyCompanionSuggestion(suggestion.id, in: bufferID)

        XCTAssertEqual(store.selectedBuffer?.text, "Changed text")
        XCTAssertEqual(store.lastError, "Could not apply companion suggestion because the original text was not found.")
    }

    func testApplyCompanionPatchSuggestionAppliesUnifiedDiff() {
        let store = makeStore(
            text: """
            Title: Alpha
            Status: draft
            Owner: TBD
            """
        )
        let bufferID = store.selectedBufferID!
        let suggestion = CompanionSuggestion(
            title: "Patch status",
            comment: "Applies a multi-line edit.",
            findText: "",
            replacementText: "",
            patchText: """
            @@
             Title: Alpha
            -Status: draft
            +Status: ready
             Owner: TBD
            @@
            -Owner: TBD
            +Owner: Malik
            """
        )
        store.replaceCompanionSuggestions([suggestion], for: bufferID)

        store.applyCompanionSuggestion(suggestion.id, in: bufferID)

        XCTAssertEqual(
            store.selectedBuffer?.text,
            """
            Title: Alpha
            Status: ready
            Owner: Malik
            """
        )
        XCTAssertEqual(store.selectedBuffer?.selectionRanges.first?.location, 0)
        XCTAssertEqual(store.companionSuggestions(for: bufferID).first?.isApplied, true)
    }

    func testApplyCompanionPatchSuggestionRejectsStaleContext() {
        let store = makeStore(text: "Status: already ready\n")
        let bufferID = store.selectedBufferID!
        let suggestion = CompanionSuggestion(
            title: "Patch status",
            comment: "Context is stale.",
            findText: "",
            replacementText: "",
            patchText: """
            @@
            -Status: draft
            +Status: ready
            """
        )
        store.replaceCompanionSuggestions([suggestion], for: bufferID)

        store.applyCompanionSuggestion(suggestion.id, in: bufferID)

        XCTAssertEqual(store.selectedBuffer?.text, "Status: already ready\n")
        XCTAssertEqual(store.lastError, "Could not apply companion patch because its context no longer matches this document.")
        XCTAssertEqual(store.companionSuggestions(for: bufferID).first?.isApplied, false)
    }

    func testLiveCompanionAutoScanRunsAfterTextEdit() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Resolve placeholder","comment":"TBD needs a decision.","findText":"TBD","replacementText":"decision"}]}
            """
        )
        let store = try makeStore(
            text: "Ship TBD.",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000
        )

        store.toggleCompanionAutoScan()
        store.updateSelectedText("Ship TBD today.")
        await waitForCompanionSuggestions(in: store)

        let suggestions = store.companionSuggestions(for: store.selectedBufferID!)
        XCTAssertEqual(suggestions.first?.title, "Resolve placeholder")
        XCTAssertEqual(store.companionStatus, "1 suggestion ready.")
        XCTAssertTrue(store.isCompanionPanelVisible)
        XCTAssertTrue(client.receivedPrompt?.contains("Ship TBD today.") == true)
    }

    func testLiveCompanionAutoScanRunsAfterSelectionChange() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Review selected text","comment":"The selected text needs attention.","findText":"Beta placeholder","replacementText":"Beta decision"}]}
            """
        )
        let store = try makeStore(
            text: "Alpha\nBeta placeholder\nGamma",
            client: client,
            companionAutoScanDelayNanoseconds: 10_000_000
        )

        store.toggleCompanionAutoScan()
        store.updateSelectedSelection([SLTextRange(location: 6, length: 16)])
        await waitForCompanionSuggestions(in: store)

        XCTAssertEqual(store.companionSuggestions(for: store.selectedBufferID!).first?.title, "Review selected text")
        XCTAssertTrue(client.receivedPrompt?.contains("selection line 2: Beta placeholder") == true)
    }

    func testLiveCompanionAutoScanRunsAfterTaskContextChange() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Follow task","comment":"Task context changed.","findText":"Launch note","replacementText":"Launch note"}]}
            """
        )
        let store = try makeStore(
            text: "Launch note",
            client: client,
            companionAutoScanDelayNanoseconds: 10_000_000
        )

        store.toggleCompanionAutoScan()
        store.addManualTask(title: "Review release blockers", status: .inProgress, scope: .global)
        await waitForCompanionSuggestions(in: store)

        let prompt = try XCTUnwrap(client.receivedPrompt)
        XCTAssertTrue(prompt.contains("Tasks:"))
        XCTAssertTrue(prompt.contains("Global In Progress: Review release blockers"))
    }

    func testLiveCompanionAutoScanRunsAfterSystemContextChange() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Review external selection","comment":"Use active-app selection.","findText":"Launch note","replacementText":"Launch note"}]}
            """
        )
        var systemContext = CompanionSystemContext(
            frontmostApplicationName: "Pages",
            frontmostBundleIdentifier: "com.apple.iWork.Pages",
            frontmostWindowTitle: "Launch plan",
            focusedElementRole: "AXTextArea",
            selectedText: "Initial external selection"
        )
        let store = try makeStore(
            text: "Launch note",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: { systemContext },
            companionSystemContextPollIntervalNanoseconds: 1_000_000
        )

        store.toggleCompanionAutoScan()
        await waitForCompanionPrompt(in: client, containing: "Initial external selection")

        systemContext.selectedText = "Updated external selection"
        await waitForCompanionPrompt(in: client, containing: "Updated external selection")

        XCTAssertTrue(client.receivedPrompts.contains { $0.contains("Updated external selection") })
    }

    func testLiveCompanionSystemContextChangesRecordTodayAppActivity() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Review window context","comment":"Use active window.","findText":"Launch note","replacementText":"Launch note"}]}
            """
        )
        var systemContext = CompanionSystemContext(
            frontmostApplicationName: "Pages",
            frontmostBundleIdentifier: "com.apple.iWork.Pages",
            frontmostWindowTitle: "Launch plan"
        )
        let store = try makeStore(
            text: "Launch note",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: { systemContext },
            companionSystemContextPollIntervalNanoseconds: 1_000_000
        )

        store.toggleCompanionAutoScan()
        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app && entry.title == "Active in Pages: Launch plan"
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        systemContext.frontmostWindowTitle = "Budget plan"
        await waitForCompanionPrompt(in: client, containing: "Budget plan")
        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app &&
                entry.title == "Active in Pages: Launch plan" &&
                entry.durationSeconds > 0
        }

        let appEntries = store.todayUsageTimeline.filter { $0.kind == .app }
        XCTAssertTrue(appEntries.contains { $0.title == "Active in Pages: Budget plan" })
        XCTAssertEqual(store.usageStatsSummary(title: "Today", dayCount: 1).uniqueDocumentCount, 0)

        store.createTodayTimelogScratch()
        let timelog = try XCTUnwrap(store.selectedBuffer)
        XCTAssertTrue(timelog.text.contains("Active in Pages: Launch plan"))
    }

    func testLiveCompanionSystemContextMonitorStopsWhenContextSettingIsDisabled() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Review external selection","comment":"Use active-app selection.","findText":"Launch note","replacementText":"Launch note"}]}
            """
        )
        var systemContext = CompanionSystemContext(
            frontmostApplicationName: "Pages",
            frontmostBundleIdentifier: "com.apple.iWork.Pages",
            frontmostWindowTitle: "Launch plan",
            selectedText: "Initial external selection"
        )
        let store = try makeStore(
            text: "Launch note",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: { systemContext },
            companionIncludesSystemContextProvider: { false },
            companionSystemContextPollIntervalNanoseconds: 1_000_000
        )

        store.toggleCompanionAutoScan()
        await waitForCompanionPromptCount(in: client, count: 1)
        systemContext.selectedText = "Should not trigger scan"
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(client.receivedPrompts.count, 1)
        XCTAssertFalse(client.receivedPrompts.contains { $0.contains("Should not trigger scan") })
    }

    func testLiveCompanionFlushesCurrentAppActivityDurationWhenAutoScanStops() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Review window context","comment":"Use active window.","findText":"Launch note","replacementText":"Launch note"}]}
            """
        )
        let systemContext = CompanionSystemContext(
            frontmostApplicationName: "Pages",
            frontmostBundleIdentifier: "com.apple.iWork.Pages",
            frontmostWindowTitle: "Launch plan"
        )
        let store = try makeStore(
            text: "Launch note",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: { systemContext },
            companionSystemContextPollIntervalNanoseconds: 1_000_000
        )

        store.toggleCompanionAutoScan()
        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app && entry.title == "Active in Pages: Launch plan"
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        store.toggleCompanionAutoScan()

        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app &&
                entry.title == "Active in Pages: Launch plan" &&
                entry.durationSeconds > 0
        }
    }

    func testCompanionScanIncludesWorkspaceContextFromTabsTasksCommentsAndActivity() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Resolve placeholder","comment":"TBD needs a decision.","findText":"TBD","replacementText":"decision"}]}
            """
        )

        var current = EditorBuffer.scratch(index: 1)
        current.title = "Launch note"
        current.text = "Ship TBD today."
        current.selectionRanges = [.zero]

        var roadmap = EditorBuffer.scratch(index: 2)
        roadmap.title = "Roadmap"
        roadmap.text = "Next milestone"
        roadmap.selectionRanges = [.zero]

        let store = try makeStore(
            buffers: [current, roadmap],
            selectedID: current.id,
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000
        )
        store.addManualTask(title: "Prepare launch checklist", status: .inProgress)
        _ = store.addComment(
            to: SLTextRange(location: 5, length: 3),
            in: current.id,
            body: "Resolve before publish"
        )
        store.updateSelectedText("Ship TBD today after review.")

        store.runCompanionScan()
        await waitForCompanionSuggestions(in: store)

        let prompt = try XCTUnwrap(client.receivedPrompt)
        XCTAssertTrue(prompt.contains("Workspace context:"))
        XCTAssertTrue(prompt.contains("Current buffer state: scratch, modified, Normal"))
        XCTAssertTrue(prompt.contains("Open tabs:"))
        XCTAssertTrue(prompt.contains("Launch note (Markdown, current, modified, scratch)"))
        XCTAssertTrue(prompt.contains("Roadmap (Markdown, saved, scratch)"))
        XCTAssertTrue(prompt.contains("Open comments on current tab:"))
        XCTAssertTrue(prompt.contains("Resolve before publish"))
        XCTAssertTrue(prompt.contains("Tasks:"))
        XCTAssertTrue(prompt.contains("In Progress: Prepare launch checklist"))
        XCTAssertTrue(prompt.contains("Recent activity today:"))
        XCTAssertTrue(prompt.contains("Edited Launch note"))
    }

    func testCompanionScanIncludesFrontmostApplicationContext() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Resolve placeholder","comment":"TBD needs a decision.","findText":"TBD","replacementText":"decision"}]}
            """
        )
        let store = try makeStore(
            text: "Ship TBD.",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: {
                CompanionSystemContext(
                    frontmostApplicationName: "Safari",
                    frontmostBundleIdentifier: "com.apple.Safari",
                    frontmostWindowTitle: "Checkout recovery PRD"
                )
            }
        )

        store.runCompanionScan()
        await waitForCompanionSuggestions(in: store)

        let prompt = try XCTUnwrap(client.receivedPrompt)
        XCTAssertTrue(prompt.contains("System context:"))
        XCTAssertTrue(prompt.contains("frontmost app: Safari"))
        XCTAssertTrue(prompt.contains("bundle: com.apple.Safari"))
        XCTAssertTrue(prompt.contains("window: Checkout recovery PRD"))
    }

    func testCompanionScanIncludesAccessibilitySelectionContextWhenProvided() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Resolve placeholder","comment":"TBD needs a decision.","findText":"TBD","replacementText":"decision"}]}
            """
        )
        let store = try makeStore(
            text: "Ship TBD.",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: {
                CompanionSystemContext(
                    frontmostApplicationName: "Pages",
                    frontmostBundleIdentifier: "com.apple.iWork.Pages",
                    frontmostWindowTitle: "Launch plan",
                    focusedElementRole: "AXTextArea",
                    focusedElementTitle: "Body",
                    selectedText: "Need launch risk review",
                    focusedValue: "Ignored when selected text exists"
                )
            }
        )

        store.runCompanionScan()
        await waitForCompanionSuggestions(in: store)

        let prompt = try XCTUnwrap(client.receivedPrompt)
        XCTAssertTrue(prompt.contains("focused role: AXTextArea"))
        XCTAssertTrue(prompt.contains("focused title: Body"))
        XCTAssertTrue(prompt.contains("selected text: Need launch risk review"))
        XCTAssertFalse(prompt.contains("Ignored when selected text exists"))
    }

    func testCompanionScanIncludesScreenTextContextWhenProvided() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Resolve placeholder","comment":"TBD needs a decision.","findText":"TBD","replacementText":"decision"}]}
            """
        )
        let store = try makeStore(
            text: "Ship TBD.",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: {
                CompanionSystemContext(
                    frontmostApplicationName: "Safari",
                    frontmostBundleIdentifier: "com.apple.Safari",
                    frontmostWindowTitle: "Checkout recovery",
                    screenText: "Payment failed banner Retry checkout"
                )
            }
        )

        store.runCompanionScan()
        await waitForCompanionSuggestions(in: store)

        let prompt = try XCTUnwrap(client.receivedPrompt)
        XCTAssertTrue(prompt.contains("screen text: Payment failed banner Retry checkout"))
    }

    func testCompanionScanCanOmitFrontmostApplicationContextFromSettings() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Resolve placeholder","comment":"TBD needs a decision.","findText":"TBD","replacementText":"decision"}]}
            """
        )
        let store = try makeStore(
            text: "Ship TBD.",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: {
                CompanionSystemContext(
                    frontmostApplicationName: "Safari",
                    frontmostBundleIdentifier: "com.apple.Safari",
                    frontmostWindowTitle: "Private tab",
                    focusedElementRole: "AXTextArea",
                    focusedElementTitle: "Private form",
                    selectedText: "Secret selected text",
                    screenText: "Secret screen text"
                )
            },
            companionIncludesSystemContextProvider: { false }
        )

        store.runCompanionScan()
        await waitForCompanionSuggestions(in: store)

        let prompt = try XCTUnwrap(client.receivedPrompt)
        XCTAssertFalse(prompt.contains("System context:"))
        XCTAssertFalse(prompt.contains("frontmost app: Safari"))
        XCTAssertFalse(prompt.contains("window: Private tab"))
        XCTAssertFalse(prompt.contains("Secret selected text"))
        XCTAssertFalse(prompt.contains("Secret screen text"))
    }

    func testActivityWatchAppTimelineStaysOutOfCompanionPromptWhenWindowContextIsDisabled() async throws {
        let client = CompanionFakeHTTPAICompleting(
            response: """
            {"suggestions":[{"title":"Resolve placeholder","comment":"TBD needs a decision.","findText":"TBD","replacementText":"decision"}]}
            """
        )
        let store = try makeStore(
            text: "Ship TBD.",
            client: client,
            companionAutoScanDelayNanoseconds: 1_000_000,
            companionSystemContextProvider: {
                CompanionSystemContext(
                    frontmostApplicationName: "Safari",
                    frontmostBundleIdentifier: "com.apple.Safari",
                    frontmostWindowTitle: "Private release tab"
                )
            },
            companionIncludesSystemContextProvider: { false },
            companionSystemContextPollIntervalNanoseconds: 1_000_000
        )

        store.toggleUsageActivityWatch()
        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app && entry.title == "Active in Safari: Private release tab"
        }

        store.runCompanionScan()
        await waitForCompanionSuggestions(in: store)

        let prompt = try XCTUnwrap(client.receivedPrompt)
        XCTAssertFalse(prompt.contains("System context:"))
        XCTAssertFalse(prompt.contains("Recent activity today:"))
        XCTAssertFalse(prompt.contains("Safari"))
        XCTAssertFalse(prompt.contains("Private release tab"))
    }

    private func makeStore(text: String) -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.selectionRanges = [.zero]
        return EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeStore(
        text: String,
        client: CompanionFakeHTTPAICompleting,
        companionAutoScanDelayNanoseconds: UInt64,
        companionSystemContextProvider: @escaping @MainActor () async -> CompanionSystemContext? = { nil },
        companionIncludesSystemContextProvider: @escaping () -> Bool = { true },
        companionSystemContextPollIntervalNanoseconds: UInt64 = 2_000_000_000
    ) throws -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.selectionRanges = [.zero]
        let configuration = try HTTPAIConfiguration(baseURLString: "https://example.com/v1", model: "test-model")
        return EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            httpAIClientFactory: { _ in client },
            httpAIConfigurationProvider: { configuration },
            companionSystemContextProvider: companionSystemContextProvider,
            companionIncludesSystemContextProvider: companionIncludesSystemContextProvider,
            companionAutoScanDelayNanoseconds: companionAutoScanDelayNanoseconds,
            companionSystemContextPollIntervalNanoseconds: companionSystemContextPollIntervalNanoseconds,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeStore(
        buffers: [EditorBuffer],
        selectedID: UUID,
        client: CompanionFakeHTTPAICompleting,
        companionAutoScanDelayNanoseconds: UInt64,
        companionSystemContextProvider: @escaping @MainActor () async -> CompanionSystemContext? = { nil },
        companionIncludesSystemContextProvider: @escaping () -> Bool = { true },
        companionSystemContextPollIntervalNanoseconds: UInt64 = 2_000_000_000
    ) throws -> EditorStore {
        let configuration = try HTTPAIConfiguration(baseURLString: "https://example.com/v1", model: "test-model")
        return EditorStore(
            initialBuffers: buffers,
            selectedID: selectedID,
            persistence: nil,
            httpAIClientFactory: { _ in client },
            httpAIConfigurationProvider: { configuration },
            companionSystemContextProvider: companionSystemContextProvider,
            companionIncludesSystemContextProvider: companionIncludesSystemContextProvider,
            companionAutoScanDelayNanoseconds: companionAutoScanDelayNanoseconds,
            companionSystemContextPollIntervalNanoseconds: companionSystemContextPollIntervalNanoseconds,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func waitForCompanionSuggestions(in store: EditorStore) async {
        for _ in 0..<200 where store.companionSuggestions(for: store.selectedBufferID!).isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForCompanionPrompt(in client: CompanionFakeHTTPAICompleting, containing text: String) async {
        for _ in 0..<200 where !client.receivedPrompts.contains(where: { $0.contains(text) }) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForCompanionPromptCount(in client: CompanionFakeHTTPAICompleting, count: Int) async {
        for _ in 0..<200 where client.receivedPrompts.count < count {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForTodayTimelineEntry(
        in store: EditorStore,
        matching predicate: (UsageTimelineEntry) -> Bool
    ) async {
        for _ in 0..<200 where !store.todayUsageTimeline.contains(where: predicate) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class CompanionFakeHTTPAICompleting: HTTPAICompleting, @unchecked Sendable {
    private let response: String
    private let lock = NSLock()
    private var prompt: String?
    private var prompts: [String] = []

    init(response: String) {
        self.response = response
    }

    var receivedPrompt: String? {
        lock.withLock { prompt }
    }

    var receivedPrompts: [String] {
        lock.withLock { prompts }
    }

    func complete(messages: [HTTPAIChatMessage], systemPrompt: String) async throws -> String {
        lock.withLock {
            let currentPrompt = messages.first?.content
            prompt = currentPrompt
            if let currentPrompt {
                prompts.append(currentPrompt)
            }
        }
        return response
    }
}
