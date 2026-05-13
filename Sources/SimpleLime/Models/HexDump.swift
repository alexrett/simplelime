import Foundation

struct HexDumpPreview: Equatable {
    var data: Data
    var fileSizeBytes: Int64?
    var isTruncated: Bool

    var byteCount: Int {
        data.count
    }
}

enum HexDump {
    static let previewByteLimit = 64 * 1024
    private static let binarySampleByteLimit = 4 * 1024

    static func readPreview(at url: URL, limit: Int = previewByteLimit) throws -> HexDumpPreview {
        let fileSizeBytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: max(1, limit)) ?? Data()
        let isTruncated = fileSizeBytes.map { Int64(data.count) < $0 } ?? false
        return HexDumpPreview(data: data, fileSizeBytes: fileSizeBytes, isTruncated: isTruncated)
    }

    static func isLikelyBinaryFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: binarySampleByteLimit)) ?? Data()
        return isLikelyBinary(data)
    }

    static func isLikelyBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }

        if hasUnicodeTextBOM(data) {
            return false
        }

        if data.contains(0) {
            return true
        }

        let controlBytes = data.reduce(0) { count, byte in
            count + (isUnexpectedControlByte(byte) ? 1 : 0)
        }

        return Double(controlBytes) / Double(data.count) > 0.05
    }

    static func format(_ data: Data, baseOffset: Int64 = 0, bytesPerRow: Int = 16) -> String {
        guard !data.isEmpty else { return "" }

        let rowWidth = max(1, bytesPerRow)
        var lines: [String] = []
        lines.reserveCapacity(Int(ceil(Double(data.count) / Double(rowWidth))))

        var rowStart = 0
        while rowStart < data.count {
            let rowEnd = min(rowStart + rowWidth, data.count)
            let row = data[rowStart..<rowEnd]
            let offset = String(format: "%08llX", baseOffset + Int64(rowStart))
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let paddedHex = hex.padding(toLength: rowWidth * 3 - 1, withPad: " ", startingAt: 0)
            let ascii = row.map { byte -> Character in
                if 0x20...0x7E ~= byte {
                    return Character(UnicodeScalar(byte))
                }
                return "."
            }

            lines.append("\(offset)  \(paddedHex)  |\(String(ascii))|")
            rowStart += rowWidth
        }

        return lines.joined(separator: "\n")
    }

    private static func hasUnicodeTextBOM(_ data: Data) -> Bool {
        data.starts(with: [0xEF, 0xBB, 0xBF])
            || data.starts(with: [0xFF, 0xFE])
            || data.starts(with: [0xFE, 0xFF])
    }

    private static func isUnexpectedControlByte(_ byte: UInt8) -> Bool {
        guard byte < 0x20 else { return false }
        switch byte {
        case 0x08, 0x09, 0x0A, 0x0C, 0x0D:
            return false
        default:
            return true
        }
    }
}
