import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreLargeFileTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-large-file-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testLargeTextFileOpensAsBoundedSourceOnlyReadOnlyPreview() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.md")
        let largeText = "# Large File\n" + String(
            repeating: "This line is intentionally repetitive for large-file mode.\n",
            count: Int(EditorStore.largeFileModeThresholdBytes / 48) + 200
        )
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)

        let buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        XCTAssertTrue(buffer.text.hasPrefix("# Large File\n"))
        XCTAssertLessThan(buffer.text.count, largeText.count)
        XCTAssertLessThanOrEqual(buffer.text.utf8.count, EditorStore.largeFilePreviewByteLimit + 360)
        XCTAssertTrue(buffer.text.contains("SimpleLime large-file preview"))
        XCTAssertEqual(buffer.language, .markdown)
        XCTAssertEqual(buffer.savePolicy, .readOnly)
        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertEqual(buffer.largeFilePreviewStartOffsetBytes, 0)
        XCTAssertGreaterThan(buffer.largeFilePreviewByteCount ?? 0, 0)
        XCTAssertGreaterThanOrEqual(buffer.fileSizeBytes ?? 0, EditorStore.largeFileModeThresholdBytes)
        XCTAssertFalse(buffer.isDirty)
    }

    func testLargeFilePreviewCanPageThroughChunksWithoutLoadingWholeFile() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.log")
        var data = Data()
        let chunkCount = Int(EditorStore.largeFileModeThresholdBytes / Int64(EditorStore.largeFilePreviewByteLimit)) + 2
        for index in 0..<chunkCount {
            let byte = UInt8(ascii: "A") + UInt8(index % 26)
            data.append(Data(repeating: byte, count: EditorStore.largeFilePreviewByteLimit))
        }
        try data.write(to: url)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        XCTAssertTrue(buffer.text.hasPrefix("AAAA"))
        XCTAssertEqual(buffer.largeFilePreviewStartOffsetBytes, 0)
        XCTAssertEqual(buffer.largeFilePreviewByteCount, EditorStore.largeFilePreviewByteLimit)
        XCTAssertFalse(store.selectedLargeFileCanPageBackward)
        XCTAssertTrue(store.selectedLargeFileCanPageForward)

        store.showLargeFileNextChunk()
        buffer = try XCTUnwrap(store.selectedBuffer)
        XCTAssertTrue(buffer.text.hasPrefix("BBBB"))
        XCTAssertEqual(buffer.largeFilePreviewStartOffsetBytes, Int64(EditorStore.largeFilePreviewByteLimit))
        XCTAssertTrue(store.selectedLargeFileCanPageBackward)
        XCTAssertTrue(store.selectedLargeFileCanPageForward)

        store.showLargeFileLastChunk()
        buffer = try XCTUnwrap(store.selectedBuffer)
        let lastByte = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8((chunkCount - 1) % 26)))
        XCTAssertTrue(buffer.text.hasPrefix(String(lastByte)))
        XCTAssertEqual(buffer.largeFilePreviewStartOffsetBytes, Int64(EditorStore.largeFilePreviewByteLimit * (chunkCount - 1)))
        XCTAssertTrue(store.selectedLargeFileCanPageBackward)
        XCTAssertFalse(store.selectedLargeFileCanPageForward)

        store.showLargeFilePreviousChunk()
        buffer = try XCTUnwrap(store.selectedBuffer)
        let previousByte = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8((chunkCount - 2) % 26)))
        XCTAssertTrue(buffer.text.hasPrefix(String(previousByte)))
        XCTAssertEqual(buffer.largeFilePreviewStartOffsetBytes, Int64(EditorStore.largeFilePreviewByteLimit * (chunkCount - 2)))

        store.showLargeFileFirstChunk()
        buffer = try XCTUnwrap(store.selectedBuffer)
        XCTAssertTrue(buffer.text.hasPrefix("AAAA"))
        XCTAssertEqual(buffer.largeFilePreviewStartOffsetBytes, 0)
        XCTAssertFalse(buffer.isDirty)
        XCTAssertEqual(try Data(contentsOf: url).count, data.count)
    }

    func testLargeFileChunkCanOpenAsEditableScratchWithoutMarkerOrFullFileLoad() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.json")
        let chunkBody = #"{ "chunk": "first" }"#
        let largeText = chunkBody + "\n" + String(
            repeating: #"{ "chunk": "later" }"# + "\n",
            count: Int(EditorStore.complexTextLargeFileModeThresholdBytes / 22) + 2_000
        )
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let largeBuffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertTrue(largeBuffer.text.contains("SimpleLime large-file preview"))

        store.openSelectedLargeFileChunkAsScratch()
        let scratch = try XCTUnwrap(store.selectedBuffer)

        XCTAssertEqual(scratch.kind, .scratch)
        XCTAssertEqual(scratch.language, .json)
        XCTAssertEqual(scratch.savePolicy, .normal)
        XCTAssertFalse(scratch.isLargeFileMode)
        XCTAssertNil(scratch.filePath)
        XCTAssertTrue(scratch.isDirty)
        XCTAssertTrue(scratch.text.hasPrefix(chunkBody))
        XCTAssertFalse(scratch.text.contains("SimpleLime large-file preview"))
        XCTAssertLessThan(scratch.text.count, largeText.count)
        XCTAssertEqual(
            store.largeFileSearchStatus,
            "Opened current chunk as editable scratch. It can be saved back to the source file."
        )
    }

    func testLargeFilePreviewChunkCanBeEditedInPlaceAndSavedBack() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.json")
        let largeText = String(
            repeating: #"{ "chunk": "later" }"# + "\n",
            count: Int(EditorStore.complexTextLargeFileModeThresholdBytes / 22) + 2_000
        )
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        let sourceByteCount = try XCTUnwrap(buffer.largeFilePreviewByteCount)
        var capability = store.largeFileEditingCapability(for: buffer)
        XCTAssertEqual(capability.state, .readOnlyExactPreview)
        XCTAssertTrue(capability.canEnableInPlaceChunkEditing)
        XCTAssertFalse(capability.canEditLoadedText)
        XCTAssertFalse(capability.canSaveChunkBack)

        store.enableSelectedLargeFileChunkEditing()
        buffer = try XCTUnwrap(store.selectedBuffer)
        capability = store.largeFileEditingCapability(for: buffer)

        XCTAssertEqual(capability.state, .editablePreviewChunk)
        XCTAssertTrue(capability.canEditLoadedText)
        XCTAssertFalse(capability.canEnableInPlaceChunkEditing)
        XCTAssertFalse(capability.canSaveChunkBack)
        XCTAssertTrue(store.bufferCanEditLargeFileChunk(buffer))
        XCTAssertFalse(buffer.text.contains("SimpleLime large-file preview"))
        XCTAssertFalse(buffer.isDirty)
        XCTAssertFalse(store.selectedBufferCanSaveLargeFileChunkBack)
        XCTAssertEqual(
            store.largeFileSearchStatus,
            "Current chunk is editable. Cmd-S saves only this chunk back to the source file."
        )

        let replacement = #"{ "chunk": "edited in place" }"# + "\n" + buffer.text
        store.updateText(replacement, in: buffer.id)
        buffer = try XCTUnwrap(store.selectedBuffer)
        capability = store.largeFileEditingCapability(for: buffer)

        XCTAssertTrue(buffer.isDirty)
        XCTAssertEqual(capability.state, .editablePreviewChunk)
        XCTAssertTrue(capability.canSaveChunkBack)
        XCTAssertTrue(store.bufferCanEditLargeFileChunk(buffer))
        XCTAssertTrue(store.selectedBufferCanSaveLargeFileChunkBack)
        XCTAssertEqual(buffer.largeFileSourcePath, url.path)
        XCTAssertEqual(buffer.largeFileSourceStartOffsetBytes, 0)
        XCTAssertEqual(buffer.largeFileSourceByteCount, sourceByteCount)
        XCTAssertEqual(buffer.largeFileSourceFileSizeBytes, Int64(largeText.utf8.count))

        store.saveSelected()
        buffer = try XCTUnwrap(store.selectedBuffer)
        capability = store.largeFileEditingCapability(for: buffer)

        var expectedData = Data(largeText.utf8)
        expectedData.replaceSubrange(0..<sourceByteCount, with: Data(replacement.utf8))
        XCTAssertEqual(try Data(contentsOf: url), expectedData)
        XCTAssertFalse(buffer.isDirty)
        XCTAssertEqual(capability.state, .readOnlyExactPreview)
        XCTAssertTrue(capability.canEnableInPlaceChunkEditing)
        XCTAssertFalse(store.selectedBufferCanSaveLargeFileChunkBack)
        XCTAssertFalse(store.bufferCanEditLargeFileChunk(buffer))
        XCTAssertTrue(buffer.text.contains(#""chunk": "edited in place""#))
        XCTAssertTrue(buffer.text.contains("SimpleLime large-file preview"))
        XCTAssertEqual(buffer.fileSizeBytes, Int64(expectedData.count))
    }

    func testDirtyInPlaceLargeFileChunkBlocksPagingAndRequiresCloseConfirmation() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.json")
        let largeText = String(
            repeating: #"{ "chunk": "later" }"# + "\n",
            count: Int(EditorStore.complexTextLargeFileModeThresholdBytes / 22) + 2_000
        )
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.enableSelectedLargeFileChunkEditing()
        store.updateText("edited\n" + buffer.text, in: buffer.id)
        buffer = try XCTUnwrap(store.selectedBuffer)

        store.showLargeFileNextChunk()
        XCTAssertEqual(
            store.lastError,
            "Save or close the edited chunk before loading another large-file chunk."
        )
        XCTAssertTrue(store.selectedBuffer?.isDirty == true)

        store.closeBuffer(id: buffer.id)
        XCTAssertEqual(store.pendingCloseBuffer?.id, buffer.id)

        store.confirmPendingClose()
        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertFalse(store.buffers.contains { $0.id == buffer.id })
    }

    func testEditableLargeFileChunkCanBeSavedBackToSourceWithoutFullFileLoad() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.json")
        let largeText = String(
            repeating: #"{ "chunk": "later" }"# + "\n",
            count: Int(EditorStore.complexTextLargeFileModeThresholdBytes / 22) + 2_000
        )
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let loaded = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.openSelectedLargeFileChunkAsScratch()
        var scratch = try XCTUnwrap(store.selectedBuffer)
        let sourceByteCount = try XCTUnwrap(scratch.largeFileSourceByteCount)
        XCTAssertEqual(scratch.largeFileSourcePath, url.path)
        XCTAssertEqual(scratch.largeFileSourceStartOffsetBytes, 0)
        XCTAssertEqual(scratch.largeFileSourceFileSizeBytes, Int64(largeText.utf8.count))
        XCTAssertEqual(sourceByteCount, scratch.text.utf8.count)
        XCTAssertLessThan(scratch.text.count, largeText.count)

        let replacement = #"{ "chunk": "edited" }"# + "\n" + scratch.text
        store.updateText(replacement, in: scratch.id)

        XCTAssertTrue(store.saveSelectedLargeFileChunkBackToSource())

        scratch = try XCTUnwrap(store.selectedBuffer)
        XCTAssertFalse(scratch.isDirty)
        XCTAssertEqual(scratch.largeFileSourceByteCount, replacement.utf8.count)
        XCTAssertEqual(
            scratch.largeFileSourceFileSizeBytes,
            Int64(largeText.utf8.count - sourceByteCount + replacement.utf8.count)
        )
        XCTAssertEqual(store.largeFileSearchStatus, "Saved chunk back to \(url.lastPathComponent).")

        var expectedData = Data(largeText.utf8)
        expectedData.replaceSubrange(0..<sourceByteCount, with: Data(replacement.utf8))
        XCTAssertEqual(try Data(contentsOf: url), expectedData)

        let sourceBuffer = try XCTUnwrap(store.buffers.first { $0.id == loaded.id })
        XCTAssertTrue(sourceBuffer.isLargeFileMode)
        XCTAssertEqual(sourceBuffer.fileSizeBytes, Int64(expectedData.count))
        XCTAssertTrue(sourceBuffer.text.contains(#""chunk": "edited""#))
    }

    func testSavingEarlierEditableChunkShiftsLaterChunkScratchMetadata() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.log")
        let chunkSize = EditorStore.largeFilePreviewByteLimit
        let chunkCount = Int(EditorStore.largeFileModeThresholdBytes / Int64(chunkSize)) + 3
        var data = Data()
        for index in 0..<chunkCount {
            let byte = UInt8(ascii: "A") + UInt8(index % 26)
            data.append(Data(repeating: byte, count: chunkSize))
        }
        try data.write(to: url)

        let store = makeStore()
        store.openFile(at: url)
        let largeBuffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.openSelectedLargeFileChunkAsScratch()
        let firstScratch = try XCTUnwrap(store.selectedBuffer)
        let firstOriginalText = firstScratch.text
        XCTAssertEqual(firstOriginalText.utf8.count, chunkSize)

        store.selectedBufferID = largeBuffer.id
        store.showLargeFileNextChunk()
        XCTAssertEqual(store.selectedBuffer?.largeFilePreviewStartOffsetBytes, Int64(chunkSize))
        store.openSelectedLargeFileChunkAsScratch()
        let secondScratch = try XCTUnwrap(store.selectedBuffer)
        let secondOriginalText = secondScratch.text
        XCTAssertEqual(secondOriginalText.utf8.count, chunkSize)
        XCTAssertEqual(secondScratch.largeFileSourceStartOffsetBytes, Int64(chunkSize))

        let prefix = "FIRST\n"
        store.selectedBufferID = firstScratch.id
        store.updateText(prefix + firstOriginalText, in: firstScratch.id)
        XCTAssertTrue(store.saveSelectedLargeFileChunkBackToSource())

        var shiftedSecondScratch = try XCTUnwrap(store.buffers.first { $0.id == secondScratch.id })
        XCTAssertEqual(
            shiftedSecondScratch.largeFileSourceStartOffsetBytes,
            Int64(chunkSize + prefix.utf8.count)
        )
        XCTAssertEqual(
            shiftedSecondScratch.largeFileSourceFileSizeBytes,
            Int64(data.count + prefix.utf8.count)
        )

        let suffix = "\nSECOND"
        store.selectedBufferID = secondScratch.id
        store.updateText(secondOriginalText + suffix, in: secondScratch.id)
        XCTAssertTrue(store.saveSelectedLargeFileChunkBackToSource())
        shiftedSecondScratch = try XCTUnwrap(store.buffers.first { $0.id == secondScratch.id })
        XCTAssertEqual(
            shiftedSecondScratch.largeFileSourceFileSizeBytes,
            Int64(data.count + prefix.utf8.count + suffix.utf8.count)
        )

        var expectedData = data
        expectedData.replaceSubrange(0..<chunkSize, with: Data((prefix + firstOriginalText).utf8))
        let shiftedSecondStart = chunkSize + prefix.utf8.count
        expectedData.replaceSubrange(
            shiftedSecondStart..<(shiftedSecondStart + chunkSize),
            with: Data((secondOriginalText + suffix).utf8)
        )
        XCTAssertEqual(try Data(contentsOf: url), expectedData)
    }

    func testSavingEditableChunkInvalidatesOverlappingChunkScratchMetadata() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.json")
        let largeText = String(
            repeating: #"{ "chunk": "later" }"# + "\n",
            count: Int(EditorStore.complexTextLargeFileModeThresholdBytes / 22) + 2_000
        )
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let largeBuffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.openSelectedLargeFileChunkAsScratch()
        let firstScratch = try XCTUnwrap(store.selectedBuffer)
        store.selectedBufferID = largeBuffer.id
        store.openSelectedLargeFileChunkAsScratch()
        let overlappingScratch = try XCTUnwrap(store.selectedBuffer)
        XCTAssertNotEqual(firstScratch.id, overlappingScratch.id)
        XCTAssertEqual(overlappingScratch.largeFileSourceStartOffsetBytes, 0)

        store.selectedBufferID = firstScratch.id
        store.updateText(#"{ "chunk": "edited" }"# + "\n" + firstScratch.text, in: firstScratch.id)
        XCTAssertTrue(store.saveSelectedLargeFileChunkBackToSource())

        let invalidated = try XCTUnwrap(store.buffers.first { $0.id == overlappingScratch.id })
        XCTAssertNil(invalidated.largeFileSourcePath)
        XCTAssertNil(invalidated.largeFileSourceStartOffsetBytes)
        XCTAssertNil(invalidated.largeFileSourceByteCount)
        XCTAssertNil(invalidated.largeFileSourceFileSizeBytes)

        store.selectedBufferID = overlappingScratch.id
        XCTAssertFalse(store.selectedBufferCanSaveLargeFileChunkBack)
    }

    func testEditableLargeFileChunkRefusesSaveBackWhenSourceChangedOnDisk() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.json")
        let largeText = String(
            repeating: #"{ "chunk": "later" }"# + "\n",
            count: Int(EditorStore.complexTextLargeFileModeThresholdBytes / 22) + 2_000
        )
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        _ = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        store.openSelectedLargeFileChunkAsScratch()
        let scratch = try XCTUnwrap(store.selectedBuffer)

        try (largeText + "\nexternal change\n").write(to: url, atomically: true, encoding: .utf8)
        store.updateText("edited chunk", in: scratch.id)

        XCTAssertFalse(store.saveSelectedLargeFileChunkBackToSource())
        XCTAssertEqual(
            store.lastError,
            "Could not save chunk back because the source file changed on disk. Reopen the chunk before applying edits."
        )
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), largeText + "\nexternal change\n")
    }

    func testSessionPersistenceRoundTripsEditableLargeFileChunkSourceMetadata() throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("large.json")
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "large.json chunk 0 KB"
        buffer.text = #"{ "chunk": "edited" }"#
        buffer.language = .json
        buffer.isDirty = true
        buffer.largeFileSourcePath = sourceURL.path
        buffer.largeFileSourceStartOffsetBytes = 128
        buffer.largeFileSourceByteCount = 512
        buffer.largeFileSourceFileSizeBytes = 4096

        let persistence = SessionPersistence(rootURL: temporaryDirectory)
        try persistence.save(
            windowGroups: [
                EditorWindowGroupState(id: UUID(), selectedBufferID: buffer.id, buffers: [buffer])
            ],
            selectedGroupID: nil
        )

        let restored = try XCTUnwrap(persistence.loadWindowSession().groups.first?.buffers.first)
        XCTAssertEqual(restored.largeFileSourcePath, sourceURL.path)
        XCTAssertEqual(restored.largeFileSourceStartOffsetBytes, 128)
        XCTAssertEqual(restored.largeFileSourceByteCount, 512)
        XCTAssertEqual(restored.largeFileSourceFileSizeBytes, 4096)

        let legacyPersistence = SessionPersistence(
            rootURL: temporaryDirectory.appendingPathComponent("legacy-session", isDirectory: true)
        )
        try legacyPersistence.save(buffers: [buffer], selectedID: buffer.id)

        let legacyRestored = try XCTUnwrap(legacyPersistence.load().buffers.first)
        XCTAssertEqual(legacyRestored.largeFileSourcePath, sourceURL.path)
        XCTAssertEqual(legacyRestored.largeFileSourceStartOffsetBytes, 128)
        XCTAssertEqual(legacyRestored.largeFileSourceByteCount, 512)
        XCTAssertEqual(legacyRestored.largeFileSourceFileSizeBytes, 4096)
    }

    func testLargeFileSearchScansFullFileAndOpensMatchingChunk() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.log")
        let target = "TARGET-LARGE-FILE-SEARCH"
        let largeText = String(repeating: "A", count: Int(EditorStore.largeFileModeThresholdBytes) + 128)
            + "\n\(target)\n"
            + String(repeating: "B", count: EditorStore.largeFilePreviewByteLimit)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertFalse(buffer.text.contains(target))

        store.searchSelectedLargeFile(target)
        buffer = try await waitForLargeFileSearch(in: store, containing: target)

        XCTAssertTrue(buffer.text.contains(target))
        XCTAssertTrue(store.largeFileSearchStatus?.hasPrefix("Found at ") == true)
        XCTAssertEqual(buffer.selectionRanges.first?.length, target.utf16.count)
        XCTAssertTrue((buffer.largeFilePreviewStartOffsetBytes ?? 0) > 0)
        XCTAssertLessThan(buffer.text.count, largeText.count)
    }

    func testLargeFileSearchReportsNoMatchWithoutLoadingFullFile() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.log")
        let largeText = String(repeating: "large file line\n", count: Int(EditorStore.largeFileModeThresholdBytes / 16) + 100)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let loaded = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.searchSelectedLargeFile("missing-target")
        let status = try await waitForLargeFileSearchStatus(in: store, prefix: "No matches")

        XCTAssertEqual(status, #"No matches for "missing-target"."#)
        XCTAssertEqual(store.selectedBuffer?.id, loaded.id)
        XCTAssertLessThan(store.selectedBuffer?.text.count ?? 0, largeText.count)
    }

    func testLargeFileJumpToLineScansFullFileAndOpensTargetChunk() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-lines.json")
        let targetLine = 5_000
        let lines = (1...10_000).map { lineNumber in
            "line-\(lineNumber)-" + String(repeating: "x", count: 80)
        }
        let largeText = lines.joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertFalse(buffer.text.contains("line-\(targetLine)-"))

        store.jumpToLine(targetLine)
        buffer = try await waitForLargeFileLineJump(in: store, containing: "line-\(targetLine)-")

        XCTAssertTrue(buffer.text.hasPrefix("line-\(targetLine)-"))
        XCTAssertTrue(store.largeFileSearchStatus?.hasPrefix("Line \(targetLine) at ") == true)
        XCTAssertEqual(buffer.selectionRanges.first, TextRange(location: 0, length: 0))
        XCTAssertTrue((buffer.largeFilePreviewStartOffsetBytes ?? 0) > 0)
        XCTAssertLessThan(buffer.text.count, largeText.count)
    }

    func testLargeFileLineActivationOpensEditableChunkAtTargetLine() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-lines-edit.json")
        let targetLine = 5_000
        let lines = (1...10_000).map { lineNumber in
            "line-\(lineNumber)-" + String(repeating: "x", count: 80)
        }
        let largeText = lines.joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertFalse(buffer.text.contains("line-\(targetLine)-"))

        store.editSelectedLargeFileChunk(containingLine: targetLine)
        _ = try await waitForLargeFileSearchStatus(
            in: store,
            prefix: "Line \(targetLine) opened as editable chunk"
        )
        buffer = try XCTUnwrap(store.selectedBuffer)

        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertTrue(store.bufferCanEditLargeFileChunk(buffer))
        XCTAssertTrue(buffer.text.hasPrefix("line-\(targetLine)-"))
        XCTAssertFalse(buffer.text.contains("SimpleLime large-file preview"))
        XCTAssertEqual(buffer.selectionRanges.first, TextRange(location: 0, length: 0))
        XCTAssertTrue((buffer.largeFilePreviewStartOffsetBytes ?? 0) > 0)
        XCTAssertLessThan(buffer.text.count, largeText.count)
    }

    func testLargeFileVisibleRangeEditOpensChunkAtFirstVisibleLine() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-visible-edit.json")
        let targetLine = 7_200
        let lines = (1...10_000).map { lineNumber in
            "line-\(lineNumber)-" + String(repeating: "x", count: 80)
        }
        let largeText = lines.joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertFalse(buffer.text.contains("line-\(targetLine)-"))
        XCTAssertTrue(store.selectedLargeFileCanOpenVisibleChunkForEditing)

        store.editSelectedLargeFileChunk(containingVisibleLineRange: targetLine...(targetLine + 30))
        _ = try await waitForLargeFileSearchStatus(
            in: store,
            prefix: "Line \(targetLine) opened as editable chunk"
        )
        buffer = try XCTUnwrap(store.selectedBuffer)

        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertTrue(store.bufferCanEditLargeFileChunk(buffer))
        XCTAssertFalse(store.selectedLargeFileCanOpenVisibleChunkForEditing)
        XCTAssertTrue(buffer.text.hasPrefix("line-\(targetLine)-"))
        XCTAssertFalse(buffer.text.contains("SimpleLime large-file preview"))
        XCTAssertTrue((buffer.largeFilePreviewStartOffsetBytes ?? 0) > 0)
        XCTAssertLessThan(buffer.text.count, largeText.count)
    }

    func testLargeFileLineEditDefaultTracksVisibleVirtualRange() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-visible-line-default.json")
        let targetLine = 7_200
        let lines = (1...10_000).map { lineNumber in
            "line-\(lineNumber)-" + String(repeating: "x", count: 80)
        }
        let largeText = lines.joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.updateLargeFileVisibleLineRange(targetLine...(targetLine + 30), for: buffer.id)

        XCTAssertEqual(store.selectedLargeFileDefaultLineNumberForLineEdit, targetLine)
    }

    func testLargeFileVisibleRangeScratchOpensChunkAtFirstVisibleLine() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-visible-scratch.json")
        let targetLine = 7_200
        let lines = (1...10_000).map { lineNumber in
            "line-\(lineNumber)-" + String(repeating: "x", count: 80)
        }
        let largeText = lines.joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertFalse(buffer.text.contains("line-\(targetLine)-"))
        XCTAssertTrue(store.selectedLargeFileCanOpenVisibleChunkForEditing)

        store.openSelectedLargeFileChunkAsScratch(containingVisibleLineRange: targetLine...(targetLine + 30))
        _ = try await waitForLargeFileSearchStatus(
            in: store,
            prefix: "Opened line \(targetLine) as editable scratch"
        )
        let scratch = try XCTUnwrap(store.selectedBuffer)

        XCTAssertFalse(scratch.isLargeFileMode)
        XCTAssertTrue(scratch.text.hasPrefix("line-\(targetLine)-"))
        XCTAssertFalse(scratch.text.contains("SimpleLime large-file preview"))
        XCTAssertEqual(scratch.largeFileSourcePath, url.path)
        XCTAssertNotNil(scratch.largeFileSourceStartOffsetBytes)
        XCTAssertNotNil(scratch.largeFileSourceByteCount)
        XCTAssertEqual(scratch.largeFileSourceFileSizeBytes, Int64(largeText.utf8.count))
    }

    func testLargeFileVirtualLineReplacementUpdatesSourceAndVisibleChunk() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-line-replace.json")
        let targetLine = 6_400
        let lines = (1...10_000).map { lineNumber in
            "line-\(lineNumber)-" + String(repeating: "x", count: 80)
        }
        let largeText = lines.joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertFalse(buffer.text.contains("line-\(targetLine)-edited"))

        store.replaceSelectedLargeFileLine(targetLine, with: "line-\(targetLine)-edited")
        _ = try await waitForLargeFileSearchStatus(
            in: store,
            prefix: "Replaced line \(targetLine)"
        )
        buffer = try XCTUnwrap(store.selectedBuffer)
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertFalse(store.bufferCanEditLargeFileChunk(buffer))
        XCTAssertTrue(buffer.text.hasPrefix("line-\(targetLine)-edited"))
        XCTAssertTrue(buffer.text.contains("SimpleLime large-file preview"))
        XCTAssertTrue(source.contains("line-\(targetLine)-edited\nline-\(targetLine + 1)-"))
        XCTAssertFalse(source.contains("line-\(targetLine)-" + String(repeating: "x", count: 80)))
        XCTAssertEqual(store.largeFileLineIndexCacheCount, 1)
    }

    func testLargeFileVirtualRangeEditsUpdateSourceAndVisibleChunk() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-range-edits.json")
        let targetLine = 6_400
        let lines = (1...10_000).map { lineNumber in
            "line-\(lineNumber)-" + String(repeating: "x", count: 80)
        }
        let largeText = lines.joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        var buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertFalse(buffer.text.contains("range-edited-a"))

        store.replaceSelectedLargeFileLines(
            targetLine...(targetLine + 2),
            with: "range-edited-a\nrange-edited-b\n"
        )
        _ = try await waitForLargeFileSearchStatus(
            in: store,
            prefix: "Replaced lines \(targetLine)-\(targetLine + 2)"
        )
        buffer = try XCTUnwrap(store.selectedBuffer)
        var source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertFalse(store.bufferCanEditLargeFileChunk(buffer))
        XCTAssertTrue(buffer.text.hasPrefix("range-edited-a"))
        XCTAssertTrue(source.contains("line-\(targetLine - 1)-" + String(repeating: "x", count: 80) + "\nrange-edited-a\nrange-edited-b\nline-\(targetLine + 3)-"))

        store.insertSelectedLargeFileLines(targetLine, text: "range-inserted-a\nrange-inserted-b\n")
        _ = try await waitForLargeFileSearchStatus(
            in: store,
            prefix: "Inserted 2 lines before line \(targetLine)"
        )
        buffer = try XCTUnwrap(store.selectedBuffer)
        source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(buffer.text.hasPrefix("range-inserted-a"))
        XCTAssertTrue(source.contains("line-\(targetLine - 1)-" + String(repeating: "x", count: 80) + "\nrange-inserted-a\nrange-inserted-b\nrange-edited-a"))

        store.deleteSelectedLargeFileLines(targetLine...(targetLine + 1))
        _ = try await waitForLargeFileSearchStatus(
            in: store,
            prefix: "Deleted lines \(targetLine)-\(targetLine + 1)"
        )
        buffer = try XCTUnwrap(store.selectedBuffer)
        source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(buffer.text.hasPrefix("range-edited-a"))
        XCTAssertTrue(source.contains("line-\(targetLine - 1)-" + String(repeating: "x", count: 80) + "\nrange-edited-a\nrange-edited-b\nline-\(targetLine + 3)-"))
        XCTAssertFalse(source.contains("range-inserted-a"))
        XCTAssertEqual(store.largeFileLineIndexCacheCount, 1)
    }

    func testLargeFileLineIndexerUsesSparseCheckpointsForLocations() throws {
        let url = temporaryDirectory.appendingPathComponent("indexed-lines.txt")
        let lines = (1...30).map { "line-\($0)-" + String(repeating: "x", count: $0 % 7) }
        let text = lines.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)

        let index = try LargeFileLineIndexer.buildIndex(at: url, checkpointInterval: 5, chunkSize: 17)

        XCTAssertEqual(index.lineCount, 30)
        XCTAssertEqual(index.checkpoints.map(\.lineNumber), [1, 6, 11, 16, 21, 26])

        let result = try LargeFileLineIndexer.lineLocation(
            at: url,
            lineNumber: 18,
            cachedIndex: index,
            checkpointInterval: 5,
            chunkSize: 11
        )

        XCTAssertEqual(result.index, index)
        XCTAssertEqual(
            result.location,
            LargeFileLineLocation(lineNumber: 18, byteOffset: byteOffsetForLine(18, in: text))
        )
    }

    func testLargeFileLineJumpCachesIndexAndInvalidatesAfterChunkWriteBack() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-lines.json")
        let lines = (1...10_000).map { lineNumber in
            "line-\(lineNumber)-" + String(repeating: "x", count: 80)
        }
        let largeText = lines.joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let largeBuffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.jumpToLine(8_000)
        _ = try await waitForLargeFileLineJump(in: store, containing: "line-8000-")
        XCTAssertEqual(store.largeFileLineIndexCacheCount, 1)

        store.jumpToLine(2_000)
        _ = try await waitForLargeFileLineJump(in: store, containing: "line-2000-")
        XCTAssertEqual(store.largeFileLineIndexCacheCount, 1)

        store.selectedBufferID = largeBuffer.id
        store.showLargeFileFirstChunk()
        store.openSelectedLargeFileChunkAsScratch()
        let scratch = try XCTUnwrap(store.selectedBuffer)
        store.updateText("inserted-prefix\n" + scratch.text, in: scratch.id)

        XCTAssertTrue(store.saveSelectedLargeFileChunkBackToSource())
        XCTAssertEqual(store.largeFileLineIndexCacheCount, 0)
    }

    func testOpenLargeFileAtLineDefersStreamingLineJumpUntilPreviewLoads() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-lines.json")
        let targetLine = 7_250
        let lines = (1...8_000).map { lineNumber in
            #""line_\#(lineNumber)":{"value":"\#(String(repeating: "x", count: 80))"}"#
        }
        let largeText = "{\n" + lines.joined(separator: ",\n") + "\n}"
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url, lineNumber: targetLine)
        let buffer = try await waitForLargeFileLineJump(in: store, containing: #""line_\#(targetLine - 1)""#)

        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertEqual(buffer.savePolicy, .readOnly)
        XCTAssertTrue(store.largeFileSearchStatus?.hasPrefix("Line \(targetLine) at ") == true)
        XCTAssertLessThan(buffer.text.count, largeText.count)
    }

    func testLargeFileJumpToMissingLineDoesNotLoadWholeFile() async throws {
        let url = temporaryDirectory.appendingPathComponent("large-lines.json")
        let largeText = (1...7_000)
            .map { "line-\($0)-" + String(repeating: "x", count: 80) }
            .joined(separator: "\n")
        XCTAssertGreaterThan(Int64(largeText.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let loaded = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.jumpToLine(50_000)
        let status = try await waitForLargeFileSearchStatus(in: store, prefix: "Line 50000")

        XCTAssertEqual(status, "Line 50000 is past the end of the file.")
        XCTAssertEqual(store.selectedBuffer?.id, loaded.id)
        XCTAssertLessThan(store.selectedBuffer?.text.count ?? 0, largeText.count)
    }

    func testLargeDelimitedFileAllowsChunkTablePreviewButBlocksOtherExpensiveSurfaces() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.csv")
        let largeText = "a,b\n" + String(
            repeating: "1,2\n",
            count: Int(EditorStore.largeFileModeThresholdBytes / 4) + 100
        )
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.isPreviewVisible = false
        store.isWysiwygModeEnabled = false
        store.isMiniMapVisible = false
        store.isFocusModeEnabled = false
        store.openFile(at: url)
        _ = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.showDelimitedTablePreviewMode()
        XCTAssertTrue(store.isPreviewVisible)
        XCTAssertNil(store.lastError)

        store.showMarkdownWysiwygMode()
        XCTAssertFalse(store.isWysiwygModeEnabled)
        XCTAssertEqual(store.lastError, "Large-file mode keeps WYSIWYG disabled for performance.")

        store.toggleMiniMap()
        XCTAssertFalse(store.isMiniMapVisible)
        XCTAssertEqual(store.lastError, "Large-file mode keeps the minimap disabled for performance.")

        store.toggleFocusMode()
        XCTAssertFalse(store.isFocusModeEnabled)
        XCTAssertEqual(store.lastError, "Large-file mode keeps focus mode disabled for performance.")
    }

    func testCleanFileClosesWithoutUnsavedConfirmationEvenWhenTextIsLarge() {
        let text = String(repeating: #"{"openapi":"3.1.0"}"# + "\n", count: 40_000)
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = temporaryDirectory.appendingPathComponent("openapi.json").path
        buffer.text = text
        buffer.language = .json
        buffer.isDirty = false
        buffer.isLargeFileMode = true
        buffer.savePolicy = .readOnly

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.buffers.first?.kind, .scratch)
        XCTAssertEqual(store.buffers.first?.text, "")
    }

    func testStaleDirtyFileClosesWithoutConfirmationWhenItStillMatchesDisk() throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let text = String(repeating: #"{"openapi":"3.1.0"}"# + "\n", count: 1_000)
        try text.write(to: url, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = url.path
        buffer.text = text
        buffer.language = .json
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.buffers.first?.kind, .scratch)
    }

    func testDirtyFileStillRequiresCloseConfirmation() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "notes.md"
        buffer.filePath = temporaryDirectory.appendingPathComponent("notes.md").path
        buffer.text = "Edited"
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertEqual(store.pendingCloseBuffer?.id, buffer.id)
        XCTAssertEqual(store.buffers.first?.id, buffer.id)
    }

    func testStaleDirtyReadOnlyLargeJSONClosesWithoutConfirmation() throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = url.path
        buffer.text = String(json.prefix(4_096))
        buffer.language = .json
        buffer.isDirty = true
        buffer.savePolicy = .readOnly
        buffer.isLargeFileMode = false
        buffer.fileSizeBytes = Int64(json.utf8.count)

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.buffers.first?.kind, .scratch)
    }

    func testCorruptRestoredLargeJSONWithoutPathClosesWithoutConfirmation() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = nil
        buffer.text = ""
        buffer.language = .json
        buffer.isDirty = true
        buffer.savePolicy = .readOnly
        buffer.isLargeFileMode = true
        buffer.fileSizeBytes = EditorStore.complexTextLargeFileModeThresholdBytes + 1

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.buffers.first?.kind, .scratch)
    }

    func testReadOnlyLargeJSONWithoutPathClosesWithoutConfirmationWhenSizeIsKnown() throws {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = nil
        buffer.text = String(repeating: #"{"openapi":"3.1.0"}"# + "\n", count: 100)
        buffer.language = .json
        buffer.isDirty = true
        buffer.savePolicy = .readOnly
        buffer.isLargeFileMode = false
        buffer.fileSizeBytes = EditorStore.complexTextLargeFileModeThresholdBytes + 1

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.buffers.first?.kind, .scratch)
    }

    func testStaleDirtyLargeJSONClosesWithoutConfirmationEvenWhenOldSessionMarkedNormal() throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = url.path
        buffer.text = String(json.prefix(4_096))
        buffer.language = .json
        buffer.isDirty = true
        buffer.savePolicy = .normal
        buffer.isLargeFileMode = false
        buffer.fileSizeBytes = nil

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.buffers.first?.kind, .scratch)
    }

    func testLargeJSONCanBeClosedBeforePreviewLoadFinishes() async throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let openedID = try XCTUnwrap(store.selectedBufferID)

        store.closeBuffer(id: openedID)

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.buffers.first?.kind, .scratch)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(store.buffers.contains { $0.filePath == url.path })
        XCTAssertNil(store.lastError)
    }

    func testRestoredComplexJSONMigratesToLargePreviewBeforeRendering() async throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = url.path
        buffer.text = json
        buffer.language = .json
        buffer.isDirty = false
        buffer.savePolicy = .normal

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        var restored = try XCTUnwrap(store.selectedBuffer)

        XCTAssertEqual(restored.language, .json)
        XCTAssertTrue(restored.isLargeFileMode)
        XCTAssertEqual(restored.savePolicy, .readOnly)
        XCTAssertFalse(restored.isDirty)
        XCTAssertEqual(restored.text, "")

        restored = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertLessThan(restored.text.count, json.count)
        XCTAssertLessThanOrEqual(restored.text.utf8.count, EditorStore.complexTextLargeFilePreviewByteLimit + 360)
        XCTAssertEqual(restored.largeFilePreviewByteCount, EditorStore.complexTextLargeFilePreviewByteLimit)
        XCTAssertTrue(restored.text.contains("SimpleLime large-file preview"))
    }

    func testRestoredStaleDirtyComplexJSONMatchingDiskMigratesToLargePreviewAndClosesCleanly() throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = url.path
        buffer.text = json
        buffer.language = .json
        buffer.isDirty = true
        buffer.savePolicy = .normal

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        let restored = try XCTUnwrap(store.selectedBuffer)

        XCTAssertTrue(restored.isLargeFileMode)
        XCTAssertFalse(restored.isDirty)

        store.closeBuffer(id: restored.id)
        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.buffers.first?.kind, .scratch)
    }

    func testRestoredDirtyComplexJSONMismatchStillMigratesToLargePreview() async throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = url.path
        buffer.text = String(json.prefix(1_024)) + "\nlocal stale edit"
        buffer.language = .json
        buffer.isDirty = true
        buffer.savePolicy = .normal
        buffer.isLargeFileMode = false

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        var restored = try XCTUnwrap(store.selectedBuffer)

        XCTAssertTrue(restored.isLargeFileMode)
        XCTAssertEqual(restored.savePolicy, .readOnly)
        XCTAssertFalse(restored.isDirty)
        XCTAssertEqual(restored.text, "")

        restored = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)
        XCTAssertLessThan(restored.text.count, json.count)
        XCTAssertTrue(restored.text.contains("SimpleLime large-file preview"))
    }

    func testScratchWithTextStillRequiresCloseConfirmation() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Unsaved scratch"
        buffer.isDirty = false

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertEqual(store.pendingCloseBuffer?.id, buffer.id)
        XCTAssertEqual(store.buffers.first?.id, buffer.id)
    }

    func testForceCloseSelectedBypassesPendingCloseForStuckTab() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Unsaved scratch"
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeSelected()
        XCTAssertEqual(store.pendingCloseBuffer?.id, buffer.id)

        store.forceCloseSelected()

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertFalse(store.buffers.contains { $0.id == buffer.id })
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.selectedBuffer?.kind, .scratch)
    }

    func testPendingCloseSuspendsEditorRenderingForLargeScratch() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "openapi.json"
        buffer.text = String(
            repeating: #"{"openapi":"3.1.0","paths":{}}"# + "\n",
            count: Int(EditorStore.closeConfirmationRenderSuspensionThresholdBytes / 16) + 100
        )
        buffer.language = .json
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)
        let selected = try! XCTUnwrap(store.selectedBuffer)

        XCTAssertEqual(store.pendingCloseBuffer?.id, buffer.id)
        XCTAssertTrue(store.shouldSuspendEditorRenderingForPendingClose(selected))

        store.cancelPendingClose()
        XCTAssertFalse(store.shouldSuspendEditorRenderingForPendingClose(selected))
    }

    func testPendingCloseQuarantinesLargeScratchTextAndRestoresOnCancel() {
        let text = String(
            repeating: #"{"openapi":"3.1.0","paths":{}}"# + "\n",
            count: Int(EditorStore.closeConfirmationRenderSuspensionThresholdBytes / 16) + 100
        )
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "openapi.json"
        buffer.text = text
        buffer.language = .json
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)

        XCTAssertEqual(store.pendingCloseBuffer?.id, buffer.id)
        XCTAssertEqual(store.selectedBuffer?.text, "")
        XCTAssertFalse(store.buffersForPersistence.contains { $0.id == buffer.id })
        XCTAssertTrue(store.shouldSuspendEditorRenderingForPendingClose(store.selectedBuffer!))

        store.cancelPendingClose()

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertEqual(store.selectedBuffer?.text, text)
        XCTAssertTrue(store.selectedBuffer?.isDirty == true)
        XCTAssertTrue(store.buffersForPersistence.contains { $0.id == buffer.id })
    }

    func testPendingCloseQuarantinesLargeScratchTextAndClosesWithoutRestoring() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = "openapi.json"
        buffer.text = String(
            repeating: #"{"openapi":"3.1.0","paths":{}}"# + "\n",
            count: Int(EditorStore.closeConfirmationRenderSuspensionThresholdBytes / 16) + 100
        )
        buffer.language = .json
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)
        store.confirmPendingClose()

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertFalse(store.buffers.contains { $0.id == buffer.id })
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.selectedBuffer?.kind, .scratch)
        XCTAssertEqual(store.selectedBuffer?.text, "")
    }

    func testPendingCloseKeepsSmallScratchRendered() {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Unsaved scratch"
        buffer.isDirty = true

        let store = EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )

        store.closeBuffer(id: buffer.id)
        let selected = try! XCTUnwrap(store.selectedBuffer)

        XCTAssertEqual(store.pendingCloseBuffer?.id, buffer.id)
        XCTAssertFalse(store.shouldSuspendEditorRenderingForPendingClose(selected))
    }

    func testComplexJSONUsesLowerThresholdAndBoundedPreview() async throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        XCTAssertEqual(buffer.language, .json)
        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertEqual(buffer.savePolicy, .readOnly)
        XCTAssertLessThan(buffer.text.count, json.count)
        XCTAssertLessThanOrEqual(buffer.text.utf8.count, EditorStore.complexTextLargeFilePreviewByteLimit + 360)
        XCTAssertEqual(buffer.largeFilePreviewByteCount, EditorStore.complexTextLargeFilePreviewByteLimit)
        XCTAssertTrue(buffer.text.contains("SimpleLime large-file preview"))
    }

    func testDelimitedFilesUseGeneralLargeFileThresholdForTablePreview() async throws {
        let url = temporaryDirectory.appendingPathComponent("table.csv")
        let csv = "A,B,C\r\n" + String(
            repeating: "1,2,3\r\n",
            count: Int(EditorStore.complexTextLargeFileModeThresholdBytes / 7) + 100
        )
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let buffer = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        XCTAssertEqual(buffer.language, .csv)
        XCTAssertFalse(buffer.isLargeFileMode)
        XCTAssertEqual(buffer.savePolicy, .normal)
        XCTAssertEqual(DelimitedTextTable.parse(buffer.text, delimiter: ",").columnCount, 3)
    }

    func testOpenAPISizedJSONStartsInLargeFileModeBeforePreviewLoads() throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedOpenAPISizedJSON(lineCount: 21_878)
        try json.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertGreaterThan(Int64(json.utf8.count), EditorStore.complexTextLargeFileModeThresholdBytes)

        let store = makeStore()
        store.openFile(at: url)
        let buffer = try XCTUnwrap(store.selectedBuffer)

        XCTAssertEqual(buffer.filePath, url.path)
        XCTAssertEqual(buffer.language, .json)
        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertEqual(buffer.savePolicy, .readOnly)
        XCTAssertEqual(buffer.text, "")
        XCTAssertEqual(buffer.fileSizeBytes, Int64(json.utf8.count))
    }

    func testProvidedOpenAPIFileStartsInLargeFileModeAndClosesImmediately() async throws {
        let url = URL(fileURLWithPath: "/Users/malikov/Downloads/openapi.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("User-provided openapi.json fixture is not available.")
        }

        let store = makeStore()
        store.openFile(at: url)
        let buffer = try XCTUnwrap(store.selectedBuffer)

        XCTAssertEqual(buffer.filePath, url.path)
        XCTAssertEqual(buffer.language, .json)
        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertEqual(buffer.savePolicy, .readOnly)
        XCTAssertEqual(buffer.text, "")

        store.closeBuffer(id: buffer.id)
        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertFalse(store.buffers.contains { $0.filePath == url.path })

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(store.buffers.contains { $0.filePath == url.path })
        XCTAssertNil(store.lastError)
    }

    func testProvidedOpenAPIFileLoadsBoundedPreviewAndClosesAfterPreview() async throws {
        let url = URL(fileURLWithPath: "/Users/malikov/Downloads/openapi.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("User-provided openapi.json fixture is not available.")
        }

        let store = makeStore()
        store.openFile(at: url)
        let loaded = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        XCTAssertTrue(loaded.isLargeFileMode)
        XCTAssertEqual(loaded.savePolicy, .readOnly)
        XCTAssertLessThanOrEqual(loaded.text.utf8.count, EditorStore.complexTextLargeFilePreviewByteLimit + 360)
        XCTAssertTrue(loaded.text.contains("SimpleLime large-file preview"))

        store.closeBuffer(id: loaded.id)

        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertFalse(store.buffers.contains { $0.filePath == url.path })
    }

    func testExistingOpenAPILargeFileBufferIsPromotedWhenReopened() throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedOpenAPISizedJSON(lineCount: 21_878)
        try json.write(to: url, atomically: true, encoding: .utf8)

        let now = Date()
        let oldBuffer = EditorBuffer(
            id: UUID(),
            title: "openapi.json",
            kind: .file,
            filePath: url.path,
            text: json,
            language: .json,
            createdAt: now,
            updatedAt: now,
            isDirty: true,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil,
            savePolicy: .normal,
            isLargeFileMode: false,
            fileSizeBytes: nil
        )
        let store = makeStore()
        store.buffers = [oldBuffer]
        store.selectedBufferID = oldBuffer.id

        store.openFile(at: url)
        let buffer = try XCTUnwrap(store.selectedBuffer)

        XCTAssertEqual(buffer.id, oldBuffer.id)
        XCTAssertEqual(buffer.filePath, url.path)
        XCTAssertTrue(buffer.isLargeFileMode)
        XCTAssertEqual(buffer.savePolicy, .readOnly)
        XCTAssertFalse(buffer.isDirty)
        XCTAssertLessThan(buffer.text.utf8.count, json.utf8.count)
    }

    func testLargeFileModeCannotBePromotedToWritableBuffer() async throws {
        let url = temporaryDirectory.appendingPathComponent("large.txt")
        let largeText = String(
            repeating: "large file line\n",
            count: Int(EditorStore.largeFileModeThresholdBytes / 16) + 100
        )
        try largeText.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        _ = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.setSelectedSavePolicy(.normal)
        XCTAssertEqual(store.selectedBuffer?.savePolicy, .readOnly)
        XCTAssertEqual(store.lastError, "Large-file previews stay read-only to avoid overwriting the full file.")

        store.saveSelected()
        XCTAssertEqual(
            store.lastError,
            "This large-file chunk cannot be saved because the preview cuts through a text encoding boundary."
        )
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), largeText)
    }

    func testLargeFilePreviewIgnoresTextEditsAndClosesWithoutConfirmation() async throws {
        let url = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.openFile(at: url)
        let loaded = try await waitForLoadedSelectedBuffer(in: store, filePath: url.path)

        store.updateText("accidental edit", in: loaded.id)
        let buffer = try XCTUnwrap(store.selectedBuffer)
        XCTAssertEqual(buffer.text, loaded.text)
        XCTAssertFalse(buffer.isDirty)
        XCTAssertEqual(buffer.savePolicy, .readOnly)
        XCTAssertEqual(
            store.lastError,
            "Large-file previews are read-only. Enable chunk editing or open the current chunk as a scratch before saving."
        )

        store.closeBuffer(id: loaded.id)
        XCTAssertNil(store.pendingCloseBuffer)
        XCTAssertFalse(store.buffers.contains { $0.id == loaded.id })
    }

    func testSessionPersistenceDoesNotWriteLargeFilePreviewText() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = fileURL.path
        buffer.text = String(repeating: "preview line\n", count: 10_000)
        buffer.language = .json
        buffer.isDirty = false
        buffer.isLargeFileMode = true
        buffer.savePolicy = .readOnly
        buffer.fileSizeBytes = Int64(json.utf8.count)

        let persistence = SessionPersistence(rootURL: temporaryDirectory)
        try persistence.save(
            windowGroups: [
                EditorWindowGroupState(id: UUID(), selectedBufferID: buffer.id, buffers: [buffer])
            ],
            selectedGroupID: nil
        )

        let storedTextURL = temporaryDirectory
            .appendingPathComponent("Buffers", isDirectory: true)
            .appendingPathComponent("\(buffer.id.uuidString).txt", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: storedTextURL, encoding: .utf8), "")

        let restored = try XCTUnwrap(persistence.loadWindowSession().groups.first?.buffers.first)
        XCTAssertTrue(restored.isLargeFileMode)
        XCTAssertEqual(restored.savePolicy, .readOnly)
        XCTAssertEqual(restored.text, "")

        let store = EditorStore(
            initialBuffers: [restored],
            selectedID: restored.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        let selected = try XCTUnwrap(store.selectedBuffer)
        XCTAssertTrue(selected.isLargeFileMode)
        XCTAssertEqual(selected.text, "")

        let loaded = try await waitForLoadedSelectedBuffer(in: store, filePath: fileURL.path)
        XCTAssertTrue(loaded.isLargeFileMode)
        XCTAssertFalse(loaded.text.isEmpty)
        XCTAssertLessThan(loaded.text.count, json.count)
        XCTAssertTrue(loaded.text.contains("SimpleLime large-file preview"))
    }

    func testSessionPersistenceKeepsDirtyInPlaceLargeFileChunkEditsBounded() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let chunkText = #"{"chunk":"edited"}"#
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = fileURL.path
        buffer.text = chunkText
        buffer.language = .json
        buffer.isDirty = true
        buffer.isLargeFileMode = true
        buffer.savePolicy = .readOnly
        buffer.fileSizeBytes = Int64(json.utf8.count)
        buffer.largeFilePreviewStartOffsetBytes = 0
        buffer.largeFilePreviewByteCount = 16 * 1024
        buffer.largeFileSourcePath = fileURL.path
        buffer.largeFileSourceStartOffsetBytes = 0
        buffer.largeFileSourceByteCount = 16 * 1024
        buffer.largeFileSourceFileSizeBytes = Int64(json.utf8.count)

        let persistence = SessionPersistence(rootURL: temporaryDirectory)
        try persistence.save(
            windowGroups: [
                EditorWindowGroupState(id: UUID(), selectedBufferID: buffer.id, buffers: [buffer])
            ],
            selectedGroupID: nil
        )

        let storedTextURL = temporaryDirectory
            .appendingPathComponent("Buffers", isDirectory: true)
            .appendingPathComponent("\(buffer.id.uuidString).txt", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: storedTextURL, encoding: .utf8), chunkText)

        let restored = try XCTUnwrap(persistence.loadWindowSession().groups.first?.buffers.first)
        let store = EditorStore(
            initialBuffers: [restored],
            selectedID: restored.id,
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
        let selected = try XCTUnwrap(store.selectedBuffer)

        XCTAssertTrue(selected.isLargeFileMode)
        XCTAssertTrue(selected.isDirty)
        XCTAssertEqual(selected.text, chunkText)
        XCTAssertEqual(selected.largeFileSourcePath, fileURL.path)
        XCTAssertTrue(store.bufferCanEditLargeFileChunk(selected))
        XCTAssertTrue(store.selectedBufferCanSaveLargeFileChunkBack)
    }

    func testSessionPersistencePromotesLegacyDirtyLargeJSONWithoutPersistingFullText() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("openapi.json")
        let json = generatedComplexJSON()
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.kind = .file
        buffer.title = "openapi.json"
        buffer.filePath = fileURL.path
        buffer.text = json
        buffer.language = .json
        buffer.isDirty = true
        buffer.isLargeFileMode = false
        buffer.savePolicy = .normal
        buffer.fileSizeBytes = nil

        let persistence = SessionPersistence(rootURL: temporaryDirectory)
        try persistence.save(
            windowGroups: [
                EditorWindowGroupState(id: UUID(), selectedBufferID: buffer.id, buffers: [buffer])
            ],
            selectedGroupID: nil
        )

        let storedTextURL = temporaryDirectory
            .appendingPathComponent("Buffers", isDirectory: true)
            .appendingPathComponent("\(buffer.id.uuidString).txt", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: storedTextURL, encoding: .utf8), "")

        let restored = try XCTUnwrap(persistence.loadWindowSession().groups.first?.buffers.first)
        XCTAssertTrue(restored.isLargeFileMode)
        XCTAssertEqual(restored.savePolicy, .readOnly)
        XCTAssertFalse(restored.isDirty)
        XCTAssertEqual(restored.text, "")
        XCTAssertEqual(restored.fileSizeBytes, Int64(json.utf8.count))
    }

    private func makeStore() -> EditorStore {
        EditorStore(
            initialBuffers: [EditorBuffer.scratch(index: 1)],
            persistence: nil,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func generatedComplexJSON() -> String {
        var paths: [String] = []
        var pathPayloadBytes = 0
        while pathPayloadBytes <= EditorStore.complexTextLargeFileModeThresholdBytes {
            let entry = #"{"path":"/api/v1/products/\#(paths.count)","method":"get","description":"Generated OpenAPI path used to exercise bounded JSON loading."}"#
            pathPayloadBytes += entry.utf8.count + (paths.isEmpty ? 0 : 1)
            paths.append(entry)
        }
        return #"{"openapi":"3.1.0","paths":["# + paths.joined(separator: ",") + #"]}"#
    }

    private func generatedOpenAPISizedJSON(lineCount: Int) -> String {
        var lines = [
            #"{"openapi":"3.1.0","#,
            #""paths":{"#
        ]
        for index in 0..<max(1, lineCount - 3) {
            let comma = index == lineCount - 4 ? "" : ","
            lines.append(#""/api/v1/products/\#(index)":{"get":{"operationId":"product_\#(index)","description":"Generated OpenAPI path for large-file open regression."}}\#(comma)"#)
        }
        lines.append("}}")
        return lines.joined(separator: "\n")
    }

    private func byteOffsetForLine(_ lineNumber: Int, in text: String) -> Int64 {
        let targetLine = max(1, lineNumber)
        guard targetLine > 1 else { return 0 }

        var currentLine = 1
        var byteOffset: Int64 = 0
        for byte in text.utf8 {
            if byte == UInt8(ascii: "\n") {
                currentLine += 1
                if currentLine == targetLine {
                    return byteOffset + 1
                }
            }
            byteOffset += 1
        }
        return byteOffset
    }

    private func waitForLoadedSelectedBuffer(in store: EditorStore, filePath: String) async throws -> EditorBuffer {
        for _ in 0..<200 {
            if let buffer = store.selectedBuffer,
               buffer.filePath == filePath,
               !buffer.text.isEmpty {
                return buffer
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for large file to load")
        return try XCTUnwrap(store.selectedBuffer)
    }

    private func waitForLargeFileSearch(in store: EditorStore, containing text: String) async throws -> EditorBuffer {
        for _ in 0..<200 {
            if let buffer = store.selectedBuffer,
               buffer.text.contains(text),
               store.largeFileSearchStatus?.hasPrefix("Found at ") == true {
                return buffer
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for large file search")
        return try XCTUnwrap(store.selectedBuffer)
    }

    private func waitForLargeFileLineJump(in store: EditorStore, containing text: String) async throws -> EditorBuffer {
        for _ in 0..<200 {
            if let buffer = store.selectedBuffer,
               buffer.text.contains(text),
               store.largeFileSearchStatus?.hasPrefix("Line ") == true {
                return buffer
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for large file line jump")
        return try XCTUnwrap(store.selectedBuffer)
    }

    private func waitForLargeFileSearchStatus(in store: EditorStore, prefix: String) async throws -> String {
        for _ in 0..<200 {
            if let status = store.largeFileSearchStatus,
               status.hasPrefix(prefix) {
                return status
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for large file search status")
        return store.largeFileSearchStatus ?? ""
    }
}
