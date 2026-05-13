import XCTest
@testable import SimpleLime

private typealias SLTextRange = SimpleLime.TextRange

@MainActor
final class EditorStoreTextMacroTests: XCTestCase {
    func testBuiltInMacrosAreAvailable() {
        let store = makeStore(text: "")

        XCTAssertTrue(store.textMacros.contains { $0.id == "built-in:prd" })
        XCTAssertTrue(store.textMacros.contains { $0.id == "built-in:1x1" })
        XCTAssertTrue(store.textMacros.contains { $0.id == "built-in:meeting-notes" })
    }

    func testBuiltInTemplatesExposeVariableFields() throws {
        let prd = try XCTUnwrap(TextMacro.builtIns.first { $0.id == "built-in:prd" })

        XCTAssertEqual(prd.templateFields.map(\.name), ["Product", "Owner", "Date"])
        XCTAssertTrue(prd.hasTemplateFields)
    }

    func testApplyMacroInsertsAtCursor() {
        let store = makeStore(text: "Hello ", selection: SLTextRange(location: 6, length: 0))
        let macro = TextMacro.custom(title: "Name", body: "World", now: Date(timeIntervalSince1970: 1))

        store.applyTextMacro(macro)

        XCTAssertEqual(store.selectedBuffer?.text, "Hello World")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 6, length: 5)])
    }

    func testApplyMacroReplacesSelection() {
        let store = makeStore(text: "one PLACE two", selection: SLTextRange(location: 4, length: 5))
        let macro = TextMacro.custom(title: "X", body: "X", now: Date(timeIntervalSince1970: 1))

        store.applyTextMacro(macro)

        XCTAssertEqual(store.selectedBuffer?.text, "one X two")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 4, length: 1)])
    }

    func testApplyTemplateMacroPromptsFieldsThroughProvidedValues() {
        let store = makeStore(text: "", selection: .zero)
        let macro = TextMacro.custom(
            title: "Launch PRD",
            body: "# {{Product:Product}} Requirements\nOwner: {{Owner}}\nAgain: {{product}}",
            now: Date(timeIntervalSince1970: 1)
        )

        store.applyTextMacro(macro, templateValues: ["Product": "SimpleLime", "Owner": "Alex"])

        XCTAssertEqual(
            store.selectedBuffer?.text,
            "# SimpleLime Requirements\nOwner: Alex\nAgain: SimpleLime"
        )
    }

    func testTemplateMacroUsesDefaultsAndAutomaticDate() {
        let store = makeStore(text: "", selection: .zero)
        let macro = TextMacro.custom(
            title: "Daily",
            body: "# {{Title:Daily}}\nDate: {{Date}}\nMissing: {{Owner}}",
            now: Date(timeIntervalSince1970: 1)
        )
        let now = Date(timeIntervalSince1970: 1_706_097_600)

        store.applyTextMacro(macro, templateValues: [:], now: now)

        XCTAssertEqual(store.selectedBuffer?.text, "# Daily\nDate: 2024-01-24\nMissing: ")
    }

    func testCreateMacroFromSelectionUsesSelectedText() {
        let store = makeStore(
            text: "alpha\nbeta\ngamma",
            selections: [
                SLTextRange(location: 11, length: 5),
                SLTextRange(location: 0, length: 5)
            ]
        )

        let macro = store.createTextMacroFromSelection(title: "Pair")

        XCTAssertEqual(macro?.title, "Pair")
        XCTAssertEqual(macro?.body, "alpha\ngamma")
        XCTAssertEqual(store.customTextMacros.first, macro)
    }

    func testDeleteCustomMacroLeavesBuiltInsAlone() {
        let store = makeStore(text: "")
        let macro = store.addCustomTextMacro(title: "Draft", body: "Body")

        store.deleteCustomTextMacro(macro?.id ?? "")
        store.deleteCustomTextMacro("built-in:prd")

        XCTAssertTrue(store.customTextMacros.isEmpty)
        XCTAssertTrue(store.textMacros.contains { $0.id == "built-in:prd" })
    }

    func testCustomMacrosPersistThroughStorePersistence() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-editor-macro-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let persistence = TextMacroPersistence(macrosURL: temporaryDirectory.appendingPathComponent("macros.json"))
        let store = makeStore(text: "", textMacroPersistence: persistence)

        _ = store.addCustomTextMacro(title: "Checklist", body: "- [ ] ")

        XCTAssertEqual(persistence.load().map(\.title), ["Checklist"])
    }

    func testPinnedTextMacroButtonAppliesMacro() throws {
        let store = makeStore(text: "Hello ", selection: SLTextRange(location: 6, length: 0))
        let macro = try XCTUnwrap(store.addCustomTextMacro(title: "Name", body: "World"))

        store.toggleTextMacroPinned(macro.id)

        let button = try XCTUnwrap(store.pinnedMacroButtons.first)
        XCTAssertEqual(button.title, "Name")
        XCTAssertEqual(button.reference, .text(macro.id))

        store.applyPinnedMacro(button.reference)

        XCTAssertEqual(store.selectedBuffer?.text, "Hello World")
    }

    func testPinnedActionMacroButtonReplaysMacro() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-editor-pinned-action-macro-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let persistence = TextMacroPersistence(macrosURL: temporaryDirectory.appendingPathComponent("macros.json"))
        let store = makeStore(text: "", selection: .zero, textMacroPersistence: persistence)
        store.startActionMacroRecording(title: "Greeting")
        store.updateSelectedText("Hello")
        let macro = try XCTUnwrap(store.stopActionMacroRecording(title: "Greeting"))

        store.toggleActionMacroPinned(macro.id)

        let target = makeStore(
            text: "Say: ",
            selection: SLTextRange(location: 5, length: 0),
            textMacroPersistence: persistence
        )
        target.applyPinnedMacro(.action(macro.id))

        XCTAssertEqual(target.pinnedMacroButtons.map(\.title), ["Greeting"])
        XCTAssertEqual(target.selectedBuffer?.text, "Say: Hello")
    }

    func testPinnedMacrosPersistThroughStorePersistence() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-editor-pinned-macro-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let persistence = TextMacroPersistence(macrosURL: temporaryDirectory.appendingPathComponent("macros.json"))
        let store = makeStore(text: "", textMacroPersistence: persistence)
        let macro = try XCTUnwrap(store.addCustomTextMacro(title: "Checklist", body: "- [ ] "))

        store.toggleTextMacroPinned(macro.id)

        let restored = makeStore(text: "", textMacroPersistence: persistence)

        XCTAssertEqual(persistence.loadPinnedMacros(), [.text(macro.id)])
        XCTAssertEqual(restored.pinnedMacroButtons.map(\.title), ["Checklist"])
    }

    func testDeletingCustomMacroRemovesPinnedButton() throws {
        let store = makeStore(text: "")
        let macro = try XCTUnwrap(store.addCustomTextMacro(title: "Draft", body: "Body"))

        store.toggleTextMacroPinned(macro.id)
        store.deleteCustomTextMacro(macro.id)

        XCTAssertTrue(store.pinnedMacros.isEmpty)
        XCTAssertTrue(store.pinnedMacroButtons.isEmpty)
    }

    func testRecordsTypedTextAsFileAgnosticActionMacro() throws {
        let store = makeStore(text: "", selection: .zero)

        store.startActionMacroRecording(title: "Greeting")
        store.updateSelectedText("Hello")
        store.updateSelectedText("Hello world")
        let macro = store.stopActionMacroRecording(title: "Greeting")

        XCTAssertEqual(macro?.steps, [.replaceSelection("Hello world")])

        let target = makeStore(text: "Say: ", selection: SLTextRange(location: 5, length: 0))
        target.applyActionMacro(try XCTUnwrap(macro))

        XCTAssertEqual(target.selectedBuffer?.text, "Say: Hello world")
        XCTAssertEqual(target.selectedBuffer?.selectionRanges, [SLTextRange(location: 5, length: 11)])
    }

    func testRecordsRawMultiCursorTypingAsFileAgnosticActionMacro() throws {
        let selections = [
            SLTextRange(location: 5, length: 0),
            SLTextRange(location: 10, length: 0)
        ]
        let store = makeStore(text: "alpha beta gamma", selections: selections)
        let bufferID = try XCTUnwrap(store.selectedBuffer?.id)

        store.startActionMacroRecording(title: "Type at cursors")
        store.updateText("alpha! beta! gamma", in: bufferID)
        let macro = store.stopActionMacroRecording(title: "Type at cursors")

        XCTAssertEqual(macro?.steps, [.replaceSelection("!")])

        let target = makeStore(text: "first next final", selections: selections)
        target.applyActionMacro(try XCTUnwrap(macro))

        XCTAssertEqual(target.selectedBuffer?.text, "first! next! final")
        XCTAssertEqual(
            target.selectedBuffer?.selectionRanges,
            [
                SLTextRange(location: 5, length: 1),
                SLTextRange(location: 10, length: 1)
            ]
        )
    }

    func testRecordsRawMultiSelectionReplacementAsFileAgnosticActionMacro() throws {
        let selections = [
            SLTextRange(location: 4, length: 3),
            SLTextRange(location: 12, length: 3)
        ]
        let store = makeStore(text: "one old and old", selections: selections)
        let bufferID = try XCTUnwrap(store.selectedBuffer?.id)

        store.startActionMacroRecording(title: "Replace selections")
        store.updateText("one new and new", in: bufferID)
        let macro = store.stopActionMacroRecording(title: "Replace selections")

        XCTAssertEqual(macro?.steps, [.replaceSelection("new")])

        let target = makeStore(text: "red old and old", selections: selections)
        target.applyActionMacro(try XCTUnwrap(macro))

        XCTAssertEqual(target.selectedBuffer?.text, "red new and new")
        XCTAssertEqual(
            target.selectedBuffer?.selectionRanges,
            [
                SLTextRange(location: 4, length: 3),
                SLTextRange(location: 12, length: 3)
            ]
        )
    }

    func testRecordedSelectionDeletionReplaysInAnotherFile() throws {
        let store = makeStore(text: "delete keep", selection: SLTextRange(location: 0, length: 6))

        store.startActionMacroRecording(title: "Delete selected")
        store.updateSelectedText(" keep")
        let macro = store.stopActionMacroRecording(title: "Delete selected")

        XCTAssertEqual(macro?.steps, [.replaceSelection("")])

        let target = makeStore(text: "remove stay", selection: SLTextRange(location: 0, length: 6))
        target.applyActionMacro(try XCTUnwrap(macro))

        XCTAssertEqual(target.selectedBuffer?.text, " stay")
        XCTAssertEqual(target.selectedBuffer?.selectionRanges, [SLTextRange(location: 0, length: 0)])
    }

    func testRecordsTransformsAndReplaysOnCurrentSelection() throws {
        let store = makeStore(text: "one two", selection: SLTextRange(location: 4, length: 3))

        store.startActionMacroRecording(title: "Upper")
        store.performTextTransform(.uppercase)
        let macro = store.stopActionMacroRecording(title: "Upper")

        XCTAssertEqual(macro?.steps, [.transform(.uppercase)])
        XCTAssertEqual(store.selectedBuffer?.text, "one TWO")

        let target = makeStore(text: "alpha beta", selection: SLTextRange(location: 6, length: 4))
        target.applyActionMacro(try XCTUnwrap(macro))

        XCTAssertEqual(target.selectedBuffer?.text, "alpha BETA")
    }

    func testEditorCommandFallbackRecordsAndReplaysWithoutViewHandler() throws {
        let store = makeStore(text: "one\ntwo\nthree", selection: SLTextRange(location: 0, length: 3))

        store.startActionMacroRecording(title: "Move line")
        store.performEditorCommand(.moveLineDown)
        let macro = try XCTUnwrap(store.stopActionMacroRecording(title: "Move line"))

        XCTAssertEqual(macro.steps, [.editor(.moveLineDown)])
        XCTAssertEqual(store.selectedBuffer?.text, "two\none\nthree")

        let target = makeStore(text: "alpha\nbeta\ngamma", selection: SLTextRange(location: 0, length: 5))
        target.applyActionMacro(macro)

        XCTAssertEqual(target.selectedBuffer?.text, "beta\nalpha\ngamma")
        XCTAssertEqual(target.selectedBuffer?.selectionRanges, [SLTextRange(location: 5, length: 6)])
    }

    func testMarkdownCommandFallbackFormatsWithoutViewHandler() {
        let store = makeStore(text: "title", selection: SLTextRange(location: 0, length: 5))

        store.performMarkdownCommand(.heading2)

        XCTAssertEqual(store.selectedBuffer?.text, "## title")
        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 0, length: 8)])
    }

    func testToggleCommentFallbackUsesBufferLanguageWithoutViewHandler() {
        let store = makeStore(
            text: "let value = 1\nlet other = 2",
            selection: SLTextRange(location: 0, length: 13),
            language: .swift
        )

        store.performEditorCommand(.toggleComment)

        XCTAssertEqual(store.selectedBuffer?.text, "// let value = 1\nlet other = 2")

        store.performEditorCommand(.toggleComment)

        XCTAssertEqual(store.selectedBuffer?.text, "let value = 1\nlet other = 2")
    }

    func testRecordsSelectionMoveBeforeTransformAndReplaysInAnotherFile() throws {
        let store = makeStore(text: "one two three", selection: .zero)

        store.startActionMacroRecording(title: "Select and upper")
        store.updateSelectedSelection([SLTextRange(location: 4, length: 3)])
        store.performTextTransform(.uppercase)
        let macro = store.stopActionMacroRecording(title: "Select and upper")

        XCTAssertEqual(macro?.steps, [
            .select([SLTextRange(location: 4, length: 3)]),
            .transform(.uppercase)
        ])
        XCTAssertEqual(store.selectedBuffer?.text, "one TWO three")

        let target = makeStore(text: "abc def ghi", selection: .zero)
        target.applyActionMacro(try XCTUnwrap(macro))

        XCTAssertEqual(target.selectedBuffer?.text, "abc DEF ghi")
        XCTAssertEqual(target.selectedBuffer?.selectionRanges, [SLTextRange(location: 4, length: 3)])
    }

    func testConsecutiveRecordedSelectionMovesAreCoalesced() throws {
        let store = makeStore(text: "alpha beta", selection: .zero)

        store.startActionMacroRecording(title: "Move cursor")
        store.updateSelectedSelection([SLTextRange(location: 1, length: 0)])
        store.updateSelectedSelection([SLTextRange(location: 6, length: 4)])
        let macro = store.stopActionMacroRecording(title: "Move cursor")

        XCTAssertEqual(macro?.steps, [.select([SLTextRange(location: 6, length: 4)])])

        let target = makeStore(text: "hello test", selection: .zero)
        target.applyActionMacro(try XCTUnwrap(macro))

        XCTAssertEqual(target.selectedBuffer?.selectionRanges, [SLTextRange(location: 6, length: 4)])
    }

    func testActionMacrosPersistThroughStorePersistence() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-editor-action-macro-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let persistence = TextMacroPersistence(macrosURL: temporaryDirectory.appendingPathComponent("macros.json"))
        let store = makeStore(text: "", textMacroPersistence: persistence)

        store.startActionMacroRecording(title: "Template action")
        store.updateSelectedText("# Title")
        _ = store.stopActionMacroRecording(title: "Template action")

        XCTAssertEqual(persistence.loadActionMacros().map(\.title), ["Template action"])
        XCTAssertEqual(persistence.loadActionMacros().first?.steps, [.replaceSelection("# Title")])
    }

    private func makeStore(
        text: String,
        selection: SLTextRange? = nil,
        selections: [SLTextRange]? = nil,
        language: EditorLanguage = .markdown,
        textMacroPersistence: TextMacroPersistence? = nil
    ) -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.language = language
        buffer.selectionRanges = selections ?? [selection ?? .zero]

        return EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            textMacroPersistence: textMacroPersistence,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }
}
