import XCTest
@testable import SimpleLime

final class HexDumpTests: XCTestCase {
    func testFormatsOffsetsHexBytesAndASCIIColumns() {
        let data = Data([0x00, 0x41, 0x7E, 0x7F, 0x20, 0xFF])

        XCTAssertEqual(
            HexDump.format(data, bytesPerRow: 4),
            """
            00000000  00 41 7E 7F  |.A~.|
            00000004  20 FF        | .|
            """
        )
    }

    func testBinarySniffingKeepsPlainTextReadable() {
        XCTAssertFalse(HexDump.isLikelyBinary(Data("plain text\nwith tab\t".utf8)))
        XCTAssertTrue(HexDump.isLikelyBinary(Data([0x41, 0x00, 0x42])))
    }
}
