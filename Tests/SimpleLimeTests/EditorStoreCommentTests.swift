import XCTest
@testable import SimpleLime

private typealias SLTextRange = SimpleLime.TextRange

@MainActor
final class EditorStoreCommentTests: XCTestCase {
    func testAddCommentUsesSelectedRangeAndShowsPanel() throws {
        let store = makeStore(text: "alpha beta gamma", selection: SLTextRange(location: 6, length: 4))

        let comment = try XCTUnwrap(store.addCommentToSelection(body: "Check this"))

        XCTAssertEqual(comment.quote, "beta")
        XCTAssertEqual(comment.range, SLTextRange(location: 6, length: 4))
        XCTAssertEqual(comment.body, "Check this")
        XCTAssertTrue(store.isCommentsPanelVisible)
        XCTAssertEqual(store.selectedCommentID, comment.id)
        XCTAssertEqual(store.selectedBufferComments.map { $0.id }, [comment.id])
    }

    func testCommentReanchorsByQuoteAfterTextChanges() throws {
        let store = makeStore(text: "alpha beta gamma", selection: SLTextRange(location: 6, length: 4))
        let comment = try XCTUnwrap(store.addCommentToSelection())
        let bufferID = try XCTUnwrap(store.selectedBuffer?.id)

        store.updateText("alpha x beta gamma", in: bufferID)

        let updated = try XCTUnwrap(store.documentComments.first { $0.id == comment.id })
        XCTAssertEqual(updated.range, SLTextRange(location: 8, length: 4))
        XCTAssertEqual(updated.quote, "beta")
    }

    func testJumpToCommentSelectsRange() throws {
        let store = makeStore(text: "alpha beta gamma", selection: SLTextRange(location: 6, length: 4))
        let comment = try XCTUnwrap(store.addCommentToSelection())
        store.updateSelection([SLTextRange.zero], in: try XCTUnwrap(store.selectedBuffer?.id))

        store.jumpToComment(comment.id)

        XCTAssertEqual(store.selectedBuffer?.selectionRanges, [SLTextRange(location: 6, length: 4)])
        XCTAssertEqual(store.selectedCommentID, comment.id)
        XCTAssertTrue(store.isCommentsPanelVisible)
    }

    func testReminderSchedulingAndCancel() throws {
        let scheduler = ReminderRecorder()
        let store = makeStore(
            text: "alpha beta gamma",
            selection: SLTextRange(location: 6, length: 4),
            scheduler: scheduler
        )
        let comment = try XCTUnwrap(store.addCommentToSelection())

        store.scheduleCommentReminder(comment.id, after: 60)

        XCTAssertEqual(scheduler.scheduled.map(\.id), [comment.id])
        XCTAssertNotNil(store.documentComments.first { $0.id == comment.id }?.reminderAt)

        store.clearCommentReminder(comment.id)

        XCTAssertEqual(scheduler.cancelled, [comment.id])
        XCTAssertNil(store.documentComments.first { $0.id == comment.id }?.reminderAt)
    }

    func testDocumentCommentPersistenceRoundTrips() throws {
        let rootURL = try makeTemporaryDirectory()
        let fileURL = rootURL.appendingPathComponent("comments.json")
        let persistence = DocumentCommentPersistence(fileURL: fileURL)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let comment = DocumentComment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            documentKey: "file:/tmp/example.md",
            range: SLTextRange(location: 3, length: 5),
            quote: "quote",
            body: "body",
            createdAt: date,
            updatedAt: date,
            reminderAt: date.addingTimeInterval(60)
        )

        try persistence.save([comment])

        XCTAssertEqual(persistence.load(), [comment])
    }

    private func makeStore(
        text: String,
        selection: SLTextRange,
        scheduler: CommentReminderScheduling? = nil
    ) -> EditorStore {
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = text
        buffer.selectionRanges = [selection]
        return EditorStore(
            initialBuffers: [buffer],
            persistence: nil,
            commentPersistence: nil,
            commentReminderScheduler: scheduler,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class ReminderRecorder: CommentReminderScheduling {
    var scheduled: [DocumentComment] = []
    var cancelled: [UUID] = []

    func scheduleReminder(for comment: DocumentComment) {
        scheduled.append(comment)
    }

    func cancelReminder(commentID: UUID) {
        cancelled.append(commentID)
    }
}
