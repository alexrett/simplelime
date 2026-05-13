import AppKit
import XCTest
@testable import SimpleLime

final class WhiteboardDocumentTests: XCTestCase {
    func testEmptyTextDecodesToEmptyDocument() {
        XCTAssertEqual(WhiteboardDocument.decode(from: ""), .empty)
        XCTAssertTrue(WhiteboardDocument.decode(from: "not json").isEmpty)
    }

    func testEncodesAndDecodesStrokes() {
        let stroke = WhiteboardStroke(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            ink: .red,
            lineWidth: 5,
            points: [
                WhiteboardPoint(x: 0.1, y: 0.2),
                WhiteboardPoint(x: 0.8, y: 0.9)
            ]
        )
        let document = WhiteboardDocument.empty.appending(stroke)

        let decoded = WhiteboardDocument.decode(from: document.encodedText())

        XCTAssertEqual(decoded, document)
    }

    func testNormalizesOutOfBoundsStrokeValues() {
        let stroke = WhiteboardStroke(
            lineWidth: 100,
            points: [WhiteboardPoint(x: -1, y: 2)]
        )

        let decoded = WhiteboardDocument.decode(from: WhiteboardDocument(strokes: [stroke]).encodedText())

        XCTAssertEqual(decoded.strokes.first?.lineWidth, 24)
        XCTAssertEqual(decoded.strokes.first?.points.first, WhiteboardPoint(x: 0, y: 1))
    }

    func testEncodesBoardItemsForMiroStyleBasics() {
        let stickyID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let decisionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: stickyID, kind: .sticky, rect: WhiteboardRect(x: 0.1, y: 0.1, width: 0.2, height: 0.14), text: "Idea", fill: .yellow, ink: .black, lineWidth: 1))
            .appending(WhiteboardItem(id: decisionID, kind: .shape, rect: WhiteboardRect(x: 0.45, y: 0.2, width: 0.16, height: 0.16), text: "Decision", fill: .white, ink: .blue, lineWidth: 3, shape: .diamond))
            .appending(.text(rect: WhiteboardRect(x: 0.2, y: 0.6, width: 0.25, height: 0.08), text: "Label"))
            .appending(.connector(
                from: WhiteboardPoint(x: 0.3, y: 0.2),
                to: WhiteboardPoint(x: 0.45, y: 0.28),
                endArrow: true,
                routing: .orthogonal,
                startConnection: WhiteboardConnectionEndpoint(itemID: stickyID),
                endConnection: WhiteboardConnectionEndpoint(itemID: decisionID)
            ))
            .groupingAllItems(title: "Flow")

        let decoded = WhiteboardDocument.decode(from: document.encodedText())

        XCTAssertEqual(decoded.renderItems.filter { $0.kind == .sticky }.count, 1)
        XCTAssertEqual(decoded.renderItems.filter { $0.kind == .shape }.first?.shape, .diamond)
        XCTAssertEqual(decoded.renderItems.filter { $0.kind == .text }.first?.text, "Label")
        XCTAssertEqual(decoded.renderItems.filter { $0.kind == .connector }.first?.endArrow, true)
        XCTAssertEqual(decoded.renderItems.filter { $0.kind == .connector }.first?.resolvedConnectorRouting, .orthogonal)
        XCTAssertEqual(decoded.renderItems.filter { $0.kind == .connector }.first?.startConnection?.itemID, stickyID)
        XCTAssertEqual(decoded.renderItems.filter { $0.kind == .group }.first?.text, "Flow")
    }

    func testSmartConnectorRoutesFromObjectEdges() throws {
        let sourceID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let targetID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let source = WhiteboardItem(
            id: sourceID,
            kind: .shape,
            rect: WhiteboardRect(x: 0.10, y: 0.10, width: 0.20, height: 0.20),
            fill: .white,
            ink: .blue,
            shape: .rectangle
        )
        let target = WhiteboardItem(
            id: targetID,
            kind: .shape,
            rect: WhiteboardRect(x: 0.62, y: 0.58, width: 0.18, height: 0.16),
            fill: .white,
            ink: .green,
            shape: .rectangle
        )
        let connector = WhiteboardItem.connector(
            from: WhiteboardPoint(x: 0.20, y: 0.20),
            to: WhiteboardPoint(x: 0.71, y: 0.66),
            routing: .orthogonal,
            startConnection: WhiteboardConnectionEndpoint(itemID: sourceID),
            endConnection: WhiteboardConnectionEndpoint(itemID: targetID)
        )
        let points = WhiteboardConnectorRouter.routedPoints(
            for: connector,
            in: [source, target, connector],
            size: CGSize(width: 1000, height: 1000)
        )

        XCTAssertGreaterThanOrEqual(points.count, 3)
        assertPoint(points[0], isOnEdgeOf: CGRect(x: 100, y: 100, width: 200, height: 200))
        assertPoint(try XCTUnwrap(points.last), isOnEdgeOf: CGRect(x: 620, y: 580, width: 180, height: 160))
    }

    func testSmartConnectorAvoidsIntermediateObjectWhenPossible() {
        let sourceID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let targetID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let source = WhiteboardItem(id: sourceID, kind: .shape, rect: WhiteboardRect(x: 0.10, y: 0.42, width: 0.14, height: 0.12), fill: .white, ink: .blue, shape: .rectangle)
        let blocker = WhiteboardItem(kind: .sticky, rect: WhiteboardRect(x: 0.42, y: 0.40, width: 0.15, height: 0.16), text: "Block")
        let target = WhiteboardItem(id: targetID, kind: .shape, rect: WhiteboardRect(x: 0.74, y: 0.42, width: 0.14, height: 0.12), fill: .white, ink: .green, shape: .rectangle)
        let connector = WhiteboardItem.connector(
            from: WhiteboardPoint(x: 0.24, y: 0.48),
            to: WhiteboardPoint(x: 0.74, y: 0.48),
            routing: .orthogonal,
            startConnection: WhiteboardConnectionEndpoint(itemID: sourceID),
            endConnection: WhiteboardConnectionEndpoint(itemID: targetID)
        )

        let points = WhiteboardConnectorRouter.routedPoints(
            for: connector,
            in: [source, blocker, target, connector],
            size: CGSize(width: 1000, height: 1000)
        )

        XCTAssertTrue(points.contains { $0.y < 390 || $0.y > 570 }, "\(points)")
    }

    func testMovesSelectedBoardItem() throws {
        let itemID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: itemID, kind: .sticky, rect: WhiteboardRect(x: 0.10, y: 0.20, width: 0.20, height: 0.10), text: "", fill: .yellow, ink: .black, lineWidth: 1))

        let moved = document.movingItem(id: itemID, by: WhiteboardPoint(x: 0.08, y: -0.05))
        let item = try XCTUnwrap(moved.renderItems.first(where: { $0.id == itemID }))

        assertRect(item.rect, equals: WhiteboardRect(x: 0.18, y: 0.15, width: 0.20, height: 0.10))
    }

    func testDuplicatesSelectedBoardItemWithNewIDAndOffset() throws {
        let itemID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: itemID, kind: .shape, rect: WhiteboardRect(x: 0.20, y: 0.20, width: 0.15, height: 0.10), fill: .white, ink: .blue, shape: .rectangle))

        let result = document.duplicatingItem(id: itemID, offset: WhiteboardPoint(x: 0.05, y: 0.04))
        let duplicatedID = try XCTUnwrap(result.duplicatedID)
        let duplicate = try XCTUnwrap(result.document.renderItems.first(where: { $0.id == duplicatedID }))

        XCTAssertNotEqual(duplicatedID, itemID)
        assertRect(duplicate.rect, equals: WhiteboardRect(x: 0.25, y: 0.24, width: 0.15, height: 0.10))
        XCTAssertEqual(result.document.renderItems.count, 2)
    }

    func testGroupsOnlySelectedWhiteboardItems() throws {
        let firstID = UUID(uuidString: "b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1")!
        let secondID = UUID(uuidString: "b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2")!
        let thirdID = UUID(uuidString: "b3b3b3b3-b3b3-b3b3-b3b3-b3b3b3b3b3b3")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: firstID, kind: .sticky, rect: WhiteboardRect(x: 0.10, y: 0.10, width: 0.10, height: 0.10), text: ""))
            .appending(WhiteboardItem(id: secondID, kind: .shape, rect: WhiteboardRect(x: 0.40, y: 0.20, width: 0.10, height: 0.10), fill: .white, ink: .blue, shape: .rectangle))
            .appending(WhiteboardItem(id: thirdID, kind: .text, rect: WhiteboardRect(x: 0.80, y: 0.80, width: 0.10, height: 0.06), text: "Out"))

        let grouped = document.groupingItems(ids: [firstID, secondID])
        let group = try XCTUnwrap(grouped.renderItems.first { $0.kind == .group })

        XCTAssertEqual(Set(group.memberIDs), [firstID, secondID])
        XCTAssertFalse(group.memberIDs.contains(thirdID))
        assertRect(group.rect, equals: WhiteboardRect(x: 0.075, y: 0.075, width: 0.45, height: 0.25))
    }

    func testMovesMultipleSelectedWhiteboardItemsTogether() throws {
        let firstID = UUID(uuidString: "b4b4b4b4-b4b4-b4b4-b4b4-b4b4b4b4b4b4")!
        let secondID = UUID(uuidString: "b5b5b5b5-b5b5-b5b5-b5b5-b5b5b5b5b5b5")!
        let thirdID = UUID(uuidString: "b6b6b6b6-b6b6-b6b6-b6b6-b6b6b6b6b6b6")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: firstID, kind: .sticky, rect: WhiteboardRect(x: 0.10, y: 0.10, width: 0.10, height: 0.10), text: ""))
            .appending(WhiteboardItem(id: secondID, kind: .shape, rect: WhiteboardRect(x: 0.40, y: 0.20, width: 0.10, height: 0.10), fill: .white, ink: .blue, shape: .rectangle))
            .appending(WhiteboardItem(id: thirdID, kind: .text, rect: WhiteboardRect(x: 0.80, y: 0.80, width: 0.10, height: 0.06), text: "Out"))

        let moved = document.movingItems(ids: [firstID, secondID], by: WhiteboardPoint(x: 0.05, y: 0.04))
        let first = try XCTUnwrap(moved.renderItems.first { $0.id == firstID })
        let second = try XCTUnwrap(moved.renderItems.first { $0.id == secondID })
        let third = try XCTUnwrap(moved.renderItems.first { $0.id == thirdID })

        assertRect(first.rect, equals: WhiteboardRect(x: 0.15, y: 0.14, width: 0.10, height: 0.10))
        assertRect(second.rect, equals: WhiteboardRect(x: 0.45, y: 0.24, width: 0.10, height: 0.10))
        assertRect(third.rect, equals: WhiteboardRect(x: 0.80, y: 0.80, width: 0.10, height: 0.06))
    }

    func testDuplicatesMultipleSelectedWhiteboardItemsAndInternalConnector() throws {
        let firstID = UUID(uuidString: "b7b7b7b7-b7b7-b7b7-b7b7-b7b7b7b7b7b7")!
        let secondID = UUID(uuidString: "b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8")!
        let connectorID = UUID(uuidString: "b9b9b9b9-b9b9-b9b9-b9b9-b9b9b9b9b9b9")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: firstID, kind: .sticky, rect: WhiteboardRect(x: 0.10, y: 0.10, width: 0.10, height: 0.10), text: ""))
            .appending(WhiteboardItem(id: secondID, kind: .shape, rect: WhiteboardRect(x: 0.40, y: 0.20, width: 0.10, height: 0.10), fill: .white, ink: .blue, shape: .rectangle))
            .appending(WhiteboardItem(
                id: connectorID,
                kind: .connector,
                ink: .blue,
                lineWidth: 3,
                points: [WhiteboardPoint(x: 0.20, y: 0.15), WhiteboardPoint(x: 0.40, y: 0.25)],
                endArrow: true,
                connectorRouting: .orthogonal,
                startConnection: WhiteboardConnectionEndpoint(itemID: firstID, anchor: .right),
                endConnection: WhiteboardConnectionEndpoint(itemID: secondID, anchor: .left)
            ))

        let result = document.duplicatingItems(ids: [firstID, secondID, connectorID], offset: WhiteboardPoint(x: 0.05, y: 0.04))
        let duplicatedFirstID = try XCTUnwrap(result.duplicatedIDs[firstID])
        let duplicatedSecondID = try XCTUnwrap(result.duplicatedIDs[secondID])
        let duplicatedConnectorID = try XCTUnwrap(result.duplicatedIDs[connectorID])
        let duplicatedConnector = try XCTUnwrap(result.document.renderItems.first { $0.id == duplicatedConnectorID })

        XCTAssertEqual(result.document.renderItems.count, 6)
        XCTAssertEqual(duplicatedConnector.startConnection?.itemID, duplicatedFirstID)
        XCTAssertEqual(duplicatedConnector.endConnection?.itemID, duplicatedSecondID)
        XCTAssertNotEqual(duplicatedFirstID, firstID)
        XCTAssertNotEqual(duplicatedSecondID, secondID)
    }

    func testMovingGroupedMemberReflowsGroupBounds() throws {
        let firstID = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let secondID = UUID(uuidString: "34343434-3434-3434-3434-343434343434")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: firstID, kind: .sticky, rect: WhiteboardRect(x: 0.20, y: 0.20, width: 0.10, height: 0.10), text: ""))
            .appending(WhiteboardItem(id: secondID, kind: .sticky, rect: WhiteboardRect(x: 0.50, y: 0.20, width: 0.10, height: 0.10), text: ""))
            .groupingAllItems(title: "Pair")

        let moved = document.movingItem(id: firstID, by: WhiteboardPoint(x: 0.25, y: 0.10))
        let group = try XCTUnwrap(moved.renderItems.first { $0.kind == .group })

        assertRect(group.rect, equals: WhiteboardRect(x: 0.425, y: 0.175, width: 0.20, height: 0.25))
    }

    func testMovingGroupKeepsBoundsAroundMovedMembers() throws {
        let firstID = UUID(uuidString: "56565656-5656-5656-5656-565656565656")!
        let secondID = UUID(uuidString: "78787878-7878-7878-7878-787878787878")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: firstID, kind: .sticky, rect: WhiteboardRect(x: 0.20, y: 0.20, width: 0.10, height: 0.10), text: ""))
            .appending(WhiteboardItem(id: secondID, kind: .sticky, rect: WhiteboardRect(x: 0.50, y: 0.20, width: 0.10, height: 0.10), text: ""))
            .groupingAllItems(title: "Pair")
        let groupID = try XCTUnwrap(document.renderItems.first { $0.kind == .group }?.id)

        let moved = document.movingItem(id: groupID, by: WhiteboardPoint(x: 0.10, y: 0.05))
        let group = try XCTUnwrap(moved.renderItems.first { $0.id == groupID })
        let first = try XCTUnwrap(moved.renderItems.first { $0.id == firstID })

        assertRect(first.rect, equals: WhiteboardRect(x: 0.30, y: 0.25, width: 0.10, height: 0.10))
        assertRect(group.rect, equals: WhiteboardRect(x: 0.275, y: 0.225, width: 0.45, height: 0.15))
    }

    func testUngroupsSelectedGroupWithoutRemovingMembers() throws {
        let firstID = UUID(uuidString: "90909090-9090-9090-9090-909090909090")!
        let secondID = UUID(uuidString: "91919191-9191-9191-9191-919191919191")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: firstID, kind: .sticky, rect: WhiteboardRect(x: 0.10, y: 0.10, width: 0.10, height: 0.10), text: ""))
            .appending(WhiteboardItem(id: secondID, kind: .shape, rect: WhiteboardRect(x: 0.40, y: 0.20, width: 0.14, height: 0.10), fill: .white, ink: .blue, shape: .rectangle))
            .groupingAllItems(title: "Pair")
        let groupID = try XCTUnwrap(document.renderItems.first { $0.kind == .group }?.id)

        let ungrouped = document.ungroupingItem(id: groupID)

        XCTAssertNil(ungrouped.renderItems.first { $0.id == groupID })
        XCTAssertNotNil(ungrouped.renderItems.first { $0.id == firstID })
        XCTAssertNotNil(ungrouped.renderItems.first { $0.id == secondID })
        XCTAssertEqual(ungrouped.renderItems.count, 2)
    }

    func testAlignsGroupedMembersToLeftEdgeAndReflowsBounds() throws {
        let firstID = UUID(uuidString: "92929292-9292-9292-9292-929292929292")!
        let secondID = UUID(uuidString: "93939393-9393-9393-9393-939393939393")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: firstID, kind: .sticky, rect: WhiteboardRect(x: 0.20, y: 0.20, width: 0.10, height: 0.10), text: ""))
            .appending(WhiteboardItem(id: secondID, kind: .shape, rect: WhiteboardRect(x: 0.50, y: 0.25, width: 0.14, height: 0.08), fill: .white, ink: .blue, shape: .rectangle))
            .groupingAllItems(title: "Pair")
        let groupID = try XCTUnwrap(document.renderItems.first { $0.kind == .group }?.id)

        let aligned = document.aligningGroupMembers(groupID: groupID, alignment: .left)
        let first = try XCTUnwrap(aligned.renderItems.first { $0.id == firstID })
        let second = try XCTUnwrap(aligned.renderItems.first { $0.id == secondID })
        let group = try XCTUnwrap(aligned.renderItems.first { $0.id == groupID })

        assertRect(first.rect, equals: WhiteboardRect(x: 0.20, y: 0.20, width: 0.10, height: 0.10))
        assertRect(second.rect, equals: WhiteboardRect(x: 0.20, y: 0.25, width: 0.14, height: 0.08))
        assertRect(group.rect, equals: WhiteboardRect(x: 0.175, y: 0.175, width: 0.19, height: 0.18))
    }

    func testAlignsGroupedMembersToVerticalCenter() throws {
        let firstID = UUID(uuidString: "94949494-9494-9494-9494-949494949494")!
        let secondID = UUID(uuidString: "95959595-9595-9595-9595-959595959595")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: firstID, kind: .sticky, rect: WhiteboardRect(x: 0.20, y: 0.10, width: 0.10, height: 0.10), text: ""))
            .appending(WhiteboardItem(id: secondID, kind: .shape, rect: WhiteboardRect(x: 0.50, y: 0.40, width: 0.10, height: 0.20), fill: .white, ink: .blue, shape: .rectangle))
            .groupingAllItems(title: "Pair")
        let groupID = try XCTUnwrap(document.renderItems.first { $0.kind == .group }?.id)

        let aligned = document.aligningGroupMembers(groupID: groupID, alignment: .verticalCenter)
        let first = try XCTUnwrap(aligned.renderItems.first { $0.id == firstID })
        let second = try XCTUnwrap(aligned.renderItems.first { $0.id == secondID })
        let group = try XCTUnwrap(aligned.renderItems.first { $0.id == groupID })

        assertRect(first.rect, equals: WhiteboardRect(x: 0.20, y: 0.30, width: 0.10, height: 0.10))
        assertRect(second.rect, equals: WhiteboardRect(x: 0.50, y: 0.25, width: 0.10, height: 0.20))
        assertRect(group.rect, equals: WhiteboardRect(x: 0.175, y: 0.225, width: 0.45, height: 0.25))
    }

    func testConnectorUsesExplicitFourSideAnchors() {
        let sourceID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let targetID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let source = WhiteboardItem(id: sourceID, kind: .shape, rect: WhiteboardRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20), fill: .white, ink: .blue, shape: .rectangle)
        let target = WhiteboardItem(id: targetID, kind: .shape, rect: WhiteboardRect(x: 0.70, y: 0.20, width: 0.20, height: 0.20), fill: .white, ink: .green, shape: .rectangle)
        let connector = WhiteboardItem.connector(
            from: WhiteboardPoint(x: 0.30, y: 0.30),
            to: WhiteboardPoint(x: 0.70, y: 0.30),
            routing: .orthogonal,
            startConnection: WhiteboardConnectionEndpoint(itemID: sourceID, anchor: .right),
            endConnection: WhiteboardConnectionEndpoint(itemID: targetID, anchor: .left)
        )

        let points = WhiteboardConnectorRouter.routedPoints(
            for: connector,
            in: [source, target, connector],
            size: CGSize(width: 1000, height: 1000)
        )

        XCTAssertEqual(points.first, CGPoint(x: 300, y: 300))
        XCTAssertEqual(points.last, CGPoint(x: 700, y: 300))
    }

    func testConnectorApproachesEndpointAnchorFromAnchorSide() throws {
        let sourceID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        let targetID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
        let source = WhiteboardItem(id: sourceID, kind: .sticky, rect: WhiteboardRect(x: 0.08, y: 0.10, width: 0.18, height: 0.12), text: "")
        let target = WhiteboardItem(id: targetID, kind: .sticky, rect: WhiteboardRect(x: 0.72, y: 0.66, width: 0.18, height: 0.12), text: "")
        let connector = WhiteboardItem.connector(
            from: WhiteboardPoint(x: 0.26, y: 0.16),
            to: WhiteboardPoint(x: 0.72, y: 0.72),
            routing: .orthogonal,
            startConnection: WhiteboardConnectionEndpoint(itemID: sourceID, anchor: .right),
            endConnection: WhiteboardConnectionEndpoint(itemID: targetID, anchor: .left)
        )

        let points = WhiteboardConnectorRouter.routedPoints(
            for: connector,
            in: [source, target, connector],
            size: CGSize(width: 1000, height: 1000)
        )
        let tail = try XCTUnwrap(points.dropLast().last)
        let tip = try XCTUnwrap(points.last)

        XCTAssertEqual(tip, CGPoint(x: 720, y: 720))
        XCTAssertEqual(tail.y, tip.y, accuracy: 0.001)
        XCTAssertLessThan(tail.x, tip.x)
    }

    func testMiroStyleLoopConnectorTerminatesAtVisibleAnchors() throws {
        let sourceID = UUID(uuidString: "abababab-abab-abab-abab-abababababab")!
        let targetID = UUID(uuidString: "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd")!
        let source = WhiteboardItem(id: sourceID, kind: .sticky, rect: WhiteboardRect(x: 0.78, y: 0.58, width: 0.14, height: 0.12), text: "")
        let target = WhiteboardItem(id: targetID, kind: .sticky, rect: WhiteboardRect(x: 0.18, y: 0.16, width: 0.14, height: 0.14), text: "")
        let connector = WhiteboardItem.connector(
            from: WhiteboardPoint(x: 0.85, y: 0.70),
            to: WhiteboardPoint(x: 0.18, y: 0.23),
            endArrow: true,
            routing: .orthogonal,
            startConnection: WhiteboardConnectionEndpoint(itemID: sourceID, anchor: .bottom),
            endConnection: WhiteboardConnectionEndpoint(itemID: targetID, anchor: .left)
        )

        let points = WhiteboardConnectorRouter.routedPoints(
            for: connector,
            in: [source, target, connector],
            size: CGSize(width: 1000, height: 1000)
        )
        let first = try XCTUnwrap(points.first)
        let firstTail = try XCTUnwrap(points.dropFirst().first)
        let lastTail = try XCTUnwrap(points.dropLast().last)
        let last = try XCTUnwrap(points.last)

        XCTAssertEqual(first, CGPoint(x: 850, y: 700))
        XCTAssertGreaterThan(firstTail.y, first.y)
        XCTAssertEqual(last, CGPoint(x: 180, y: 230))
        XCTAssertEqual(lastTail.y, last.y, accuracy: 0.001)
        XCTAssertLessThan(lastTail.x, last.x)
    }

    func testConnectorPathCommandsRoundElbowsAndKeepEndpointLine() {
        let commands = WhiteboardConnectorRouter.pathCommands(
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 100)
            ],
            bridges: [],
            bridgeRadius: 10,
            cornerRadius: 12
        )

        XCTAssertEqual(commands, [
            .move(to: CGPoint(x: 0, y: 0)),
            .line(to: CGPoint(x: 88, y: 0)),
            .quadCurve(to: CGPoint(x: 100, y: 12), control: CGPoint(x: 100, y: 0)),
            .line(to: CGPoint(x: 100, y: 100))
        ])
    }

    func testLaterConnectorCreatesBridgeOverEarlierConnector() {
        let first = WhiteboardItem.connector(
            from: WhiteboardPoint(x: 0.10, y: 0.50),
            to: WhiteboardPoint(x: 0.90, y: 0.50),
            routing: .horizontalFirst
        )
        let second = WhiteboardItem.connector(
            from: WhiteboardPoint(x: 0.50, y: 0.10),
            to: WhiteboardPoint(x: 0.50, y: 0.90),
            routing: .verticalFirst
        )
        let items = [first, second]
        let points = WhiteboardConnectorRouter.routedPoints(for: second, in: items, size: CGSize(width: 1000, height: 1000))
        let bridges = WhiteboardConnectorRouter.bridges(for: second, routedPoints: points, in: items, size: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(bridges.count, 1)
        XCTAssertEqual(bridges.first?.point, CGPoint(x: 500, y: 500))
    }

    func testExportsWhiteboardAsSVGAndPNG() throws {
        let stickyID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let shapeID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let document = WhiteboardDocument.empty
            .appending(WhiteboardItem(id: stickyID, kind: .sticky, rect: WhiteboardRect(x: 0.1, y: 0.1, width: 0.2, height: 0.14), text: "", fill: .yellow, ink: .black, lineWidth: 1))
            .appending(WhiteboardItem(id: shapeID, kind: .shape, rect: WhiteboardRect(x: 0.6, y: 0.42, width: 0.2, height: 0.14), fill: .white, ink: .blue, shape: .rectangle))
            .appending(.connector(
                from: WhiteboardPoint(x: 0.3, y: 0.17),
                to: WhiteboardPoint(x: 0.6, y: 0.49),
                endArrow: true,
                routing: .orthogonal,
                startConnection: WhiteboardConnectionEndpoint(itemID: stickyID),
                endConnection: WhiteboardConnectionEndpoint(itemID: shapeID)
            ))

        let svg = WhiteboardExportService.svgDocument(title: "Board", document: document, size: CGSize(width: 400, height: 250))
        let png = try XCTUnwrap(WhiteboardExportService.pngData(document: document, size: CGSize(width: 400, height: 250)))

        XCTAssertTrue(svg.contains("<svg"), svg)
        XCTAssertTrue(svg.contains("data-kind=\"grid\""), svg)
        XCTAssertTrue(svg.contains("data-kind=\"connector\""), svg)
        XCTAssertTrue(svg.contains("data-routing=\"orthogonal\""), svg)
        XCTAssertTrue(svg.contains("marker-end"), svg)
        XCTAssertFalse(svg.contains(">Sticky<"), svg)
        XCTAssertTrue(png.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
    }

    func testWritesWhiteboardPNGToPasteboard() throws {
        let document = WhiteboardDocument.empty
            .appending(.sticky(rect: WhiteboardRect(x: 0.1, y: 0.1, width: 0.2, height: 0.14), text: "Copy"))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("simplelime-whiteboard-copy-\(UUID().uuidString)"))

        XCTAssertTrue(WhiteboardExportService.writePNGToPasteboard(
            document: document,
            size: CGSize(width: 400, height: 250),
            pasteboard: pasteboard
        ))

        let data = try XCTUnwrap(pasteboard.data(forType: .png))
        XCTAssertTrue(data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
    }

    private func assertRect(_ actual: WhiteboardRect?, equals expected: WhiteboardRect, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("Expected rect \(expected), got nil", file: file, line: line)
            return
        }

        XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.000_001, file: file, line: line)
    }

    private func assertPoint(_ point: CGPoint, isOnEdgeOf rect: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let onVerticalEdge = abs(point.x - rect.minX) < 0.001 || abs(point.x - rect.maxX) < 0.001
        let onHorizontalEdge = abs(point.y - rect.minY) < 0.001 || abs(point.y - rect.maxY) < 0.001
        let withinX = point.x >= rect.minX - 0.001 && point.x <= rect.maxX + 0.001
        let withinY = point.y >= rect.minY - 0.001 && point.y <= rect.maxY + 0.001

        XCTAssertTrue((onVerticalEdge && withinY) || (onHorizontalEdge && withinX), "\(point) is not on \(rect)", file: file, line: line)
    }
}
