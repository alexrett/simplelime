import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreUsageStatsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-editor-usage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testTextUpdatesRecordDailyEditingStats() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "a"
        let store = makeStore(buffer: buffer)

        store.updateText("abc", in: buffer.id)
        store.updateText("ab", in: buffer.id)

        let today = UsageStatsClock.dayIdentifier(for: Date())
        let stats = store.usageStats.first { $0.day == today }
        XCTAssertEqual(stats?.editCount, 2)
        XCTAssertEqual(stats?.charactersAdded, 2)
        XCTAssertEqual(stats?.charactersRemoved, 1)
        XCTAssertEqual(stats?.uniqueDocumentKeys.count, 1)

        let summary = store.usageStatsSummary(title: "Today", dayCount: 1)
        XCTAssertEqual(summary.editCount, 2)
        XCTAssertEqual(summary.uniqueDocumentCount, 1)
        XCTAssertEqual(summary.uniqueFileCount, 0)
        XCTAssertEqual(summary.uniqueScratchCount, 1)
    }

    func testSaveRecordsSaveCount() throws {
        let url = temporaryDirectory.appendingPathComponent("note.txt")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        let now = Date()
        let buffer = EditorBuffer(
            id: UUID(),
            title: "note.txt",
            kind: .file,
            filePath: url.path,
            text: "new",
            language: .plain,
            createdAt: now,
            updatedAt: now,
            isDirty: true,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil,
            savePolicy: .normal
        )
        let store = makeStore(buffer: buffer)

        store.saveSelected()

        XCTAssertEqual(store.usageStatsSummary(title: "Today", dayCount: 1).saveCount, 1)
    }

    func testUsageSummarySeparatesUniqueFilesAndScratches() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("file-note.txt")
        try "old".write(to: fileURL, atomically: true, encoding: .utf8)
        let now = Date()
        let fileBuffer = EditorBuffer(
            id: UUID(),
            title: "file-note.txt",
            kind: .file,
            filePath: fileURL.path,
            text: "old",
            language: .plain,
            createdAt: now,
            updatedAt: now,
            isDirty: false,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil,
            savePolicy: .normal
        )
        var scratch = EditorBuffer.scratch(index: 1)
        scratch.text = "scratch"
        let store = EditorStore(
            initialBuffers: [fileBuffer, scratch],
            selectedID: fileBuffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.updateText("new", in: fileBuffer.id)
        store.updateText("scratch note", in: scratch.id)

        let summary = store.usageStatsSummary(title: "Today", dayCount: 1)
        XCTAssertEqual(summary.uniqueDocumentCount, 2)
        XCTAssertEqual(summary.uniqueFileCount, 1)
        XCTAssertEqual(summary.uniqueScratchCount, 1)
    }

    func testResetUsageStatsClearsAggregates() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "a"
        let store = makeStore(buffer: buffer)
        store.updateText("abc", in: buffer.id)

        store.resetUsageStats()

        XCTAssertTrue(store.usageStats.isEmpty)
        XCTAssertEqual(store.usageStatsSummary(title: "Today", dayCount: 1).editCount, 0)
    }

    func testTimelogRecordsEditAndMacroEvents() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "alpha"
        let store = makeStore(buffer: buffer)

        store.updateText("alpha beta", in: buffer.id)
        store.applyTextMacro(TextMacro.custom(title: "Greeting", body: "Hello"))

        let timeline = store.todayUsageTimeline
        XCTAssertTrue(timeline.contains { $0.kind == .edit && $0.title == "Edited Scratch 1" })
        XCTAssertTrue(timeline.contains { $0.kind == .macro && $0.title == "Inserted macro Greeting" })
        XCTAssertEqual(store.usageStatsSummary(title: "Today", dayCount: 1).macroCount, 1)
    }

    func testTimelogRecordsPlayedActionMacroDuration() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = ""
        let store = makeStore(buffer: buffer)

        store.startActionMacroRecording(title: "Type Hello")
        store.updateText("Hello", in: buffer.id)
        let macro = try XCTUnwrap(store.stopActionMacroRecording(title: "Type Hello"))
        store.updateText("", in: buffer.id)

        store.applyActionMacro(macro)

        let timeline = store.todayUsageTimeline
        XCTAssertTrue(timeline.contains { $0.kind == .macro && $0.title == "Recorded macro Type Hello" })
        XCTAssertTrue(timeline.contains { $0.kind == .macro && $0.title == "Played macro Type Hello" })
        XCTAssertTrue(timeline.contains { $0.kind == .macro && $0.durationSeconds >= 1 })
    }

    func testActivityWatchRecordsFrontmostAppWithoutLiveCompanion() async throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Launch note"
        var systemContext = CompanionSystemContext(
            frontmostApplicationName: "Pages",
            frontmostBundleIdentifier: "com.apple.iWork.Pages",
            frontmostWindowTitle: "Launch plan"
        )
        let store = makeStore(
            buffer: buffer,
            companionSystemContextProvider: { systemContext },
            companionSystemContextPollIntervalNanoseconds: 1_000_000
        )

        XCTAssertFalse(store.isCompanionAutoScanEnabled)

        store.toggleUsageActivityWatch()
        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app && entry.title == "Active in Pages: Launch plan"
        }

        XCTAssertFalse(store.isCompanionAutoScanEnabled)
        XCTAssertNil(store.companionStatus)
        XCTAssertTrue(store.companionSuggestions(for: buffer.id).isEmpty)

        try await Task.sleep(nanoseconds: 20_000_000)
        systemContext.frontmostWindowTitle = "Budget plan"
        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app &&
                entry.title == "Active in Pages: Launch plan" &&
                entry.durationSeconds > 0
        }
        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app && entry.title == "Active in Pages: Budget plan"
        }

        store.toggleUsageActivityWatch()
        XCTAssertFalse(store.isUsageActivityWatchEnabled)

        store.createTodayTimelogScratch()
        let timelog = try XCTUnwrap(store.selectedBuffer)
        XCTAssertTrue(timelog.text.contains("Active in Pages: Launch plan"))
        XCTAssertTrue(timelog.text.contains("Active in Pages: Budget plan"))
    }

    func testActivityWatchRecordsFrontmostAppWhenCompanionWindowContextIsDisabled() async throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Launch note"
        let store = makeStore(
            buffer: buffer,
            companionSystemContextProvider: {
                CompanionSystemContext(
                    frontmostApplicationName: "Safari",
                    frontmostBundleIdentifier: "com.apple.Safari",
                    frontmostWindowTitle: "Release checklist"
                )
            },
            companionIncludesSystemContextProvider: { false },
            companionSystemContextPollIntervalNanoseconds: 1_000_000
        )

        store.toggleUsageActivityWatch()

        await waitForTodayTimelineEntry(in: store) { entry in
            entry.kind == .app && entry.title == "Active in Safari: Release checklist"
        }

        XCTAssertFalse(store.isCompanionAutoScanEnabled)
        XCTAssertNil(store.companionStatus)
        XCTAssertTrue(store.companionSuggestions(for: buffer.id).isEmpty)
    }

    func testCreateTodayTimelogScratchCreatesMarkdownSummary() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "alpha"
        let store = makeStore(buffer: buffer)

        store.updateText("alpha beta", in: buffer.id)
        store.applyTextMacro(TextMacro.custom(title: "Greeting", body: "Hello"))
        store.createTodayTimelogScratch()

        let timelog = try XCTUnwrap(store.selectedBuffer)
        XCTAssertEqual(timelog.kind, .scratch)
        XCTAssertEqual(timelog.language, .markdown)
        XCTAssertTrue(timelog.isDirty)
        XCTAssertTrue(timelog.title.hasPrefix("Timelog "))
        XCTAssertTrue(timelog.text.contains("# Timelog"))
        XCTAssertTrue(timelog.text.contains("## Summary"))
        XCTAssertTrue(timelog.text.contains("- Edits:"))
        XCTAssertTrue(timelog.text.contains("- Macros: 1"))
        XCTAssertTrue(timelog.text.contains("## Activity"))
        XCTAssertTrue(timelog.text.contains("Edited Scratch 1"))
        XCTAssertTrue(timelog.text.contains("Inserted macro Greeting"))
    }

    func testCreateTodayTimelogScratchHandlesEmptyDay() throws {
        let buffer = EditorBuffer.scratch(index: 1)
        let store = makeStore(buffer: buffer)

        store.createTodayTimelogScratch()

        let timelog = try XCTUnwrap(store.selectedBuffer)
        XCTAssertEqual(timelog.language, .markdown)
        XCTAssertTrue(timelog.title.hasPrefix("Timelog "))
        XCTAssertTrue(timelog.text.contains("- No activity recorded today."))
    }

    private func makeStore(
        buffer: EditorBuffer,
        companionSystemContextProvider: (@MainActor () async -> CompanionSystemContext?)? = nil,
        companionIncludesSystemContextProvider: @escaping () -> Bool = { true },
        companionSystemContextPollIntervalNanoseconds: UInt64 = 2_000_000_000
    ) -> EditorStore {
        EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            companionSystemContextProvider: companionSystemContextProvider,
            companionIncludesSystemContextProvider: companionIncludesSystemContextProvider,
            companionSystemContextPollIntervalNanoseconds: companionSystemContextPollIntervalNanoseconds,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
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
