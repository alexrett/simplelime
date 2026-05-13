import Foundation

struct DelimitedVirtualTableRow: Equatable {
    var number: Int
    var cells: [String]
    var byteOffset: Int64
    var byteCount: Int
    var isTruncated: Bool

    func cell(_ column: Int) -> String {
        guard cells.indices.contains(column) else { return "" }
        return cells[column]
    }
}

struct DelimitedVirtualTableIndex: Equatable {
    var fileSizeBytes: Int64
    var modificationDate: Date?
    var delimiter: Character
    var recordOffsets: [Int64]
    var columnCount: Int

    var rowCount: Int {
        recordOffsets.count
    }

    func isValid(fileSizeBytes: Int64?, modificationDate: Date?, delimiter: Character) -> Bool {
        self.fileSizeBytes == fileSizeBytes &&
            self.modificationDate == modificationDate &&
            self.delimiter == delimiter
    }
}

struct DelimitedVirtualTableDocument: Equatable {
    static let defaultMaximumRecordBytes = 2 * 1024 * 1024

    var url: URL
    var fileSizeBytes: Int64
    var modificationDate: Date?
    var delimiter: Character
    var index: DelimitedVirtualTableIndex

    var rowCount: Int {
        index.rowCount
    }

    var columnCount: Int {
        index.columnCount
    }

    static func open(
        at url: URL,
        delimiter: Character,
        cachedIndex: DelimitedVirtualTableIndex? = nil
    ) throws -> DelimitedVirtualTableDocument {
        let signature = try LargeFileLineIndexer.fileSignature(at: url)
        let index: DelimitedVirtualTableIndex
        if let cachedIndex,
           cachedIndex.isValid(
               fileSizeBytes: signature.fileSizeBytes,
               modificationDate: signature.modificationDate,
               delimiter: delimiter
           ) {
            index = cachedIndex
        } else {
            index = try buildIndex(at: url, delimiter: delimiter)
        }

        return DelimitedVirtualTableDocument(
            url: url,
            fileSizeBytes: signature.fileSizeBytes,
            modificationDate: signature.modificationDate,
            delimiter: delimiter,
            index: index
        )
    }

    func row(
        _ rowNumber: Int,
        maximumColumns: Int,
        maximumRecordBytes: Int = defaultMaximumRecordBytes
    ) throws -> DelimitedVirtualTableRow? {
        let rowNumber = max(1, rowNumber)
        guard index.recordOffsets.indices.contains(rowNumber - 1) else {
            return nil
        }

        let startOffset = index.recordOffsets[rowNumber - 1]
        let endOffset: Int64
        if index.recordOffsets.indices.contains(rowNumber) {
            endOffset = index.recordOffsets[rowNumber]
        } else {
            endOffset = fileSizeBytes
        }

        let byteCount = max(0, endOffset - startOffset)
        let cappedByteCount = min(byteCount, Int64(max(1, maximumRecordBytes)))
        let data = try readBytes(at: startOffset, count: Int(cappedByteCount))
        let text = Self.decode(data)
        var cells = DelimitedTextTable
            .parseVisiblePreview(
                text,
                delimiter: delimiter,
                maximumStoredRows: 1,
                maximumStoredColumns: max(0, maximumColumns)
            )
            .rows
            .first ?? []

        let isTruncated = cappedByteCount < byteCount
        if isTruncated {
            if cells.isEmpty {
                cells = ["[SimpleLime: row truncated after \(ByteCountFormatter.string(fromByteCount: cappedByteCount, countStyle: .file))]"]
            } else {
                cells[cells.count - 1] += " [SimpleLime: row truncated after \(ByteCountFormatter.string(fromByteCount: cappedByteCount, countStyle: .file))]"
            }
        }

        return DelimitedVirtualTableRow(
            number: rowNumber,
            cells: cells,
            byteOffset: startOffset,
            byteCount: Int(byteCount),
            isTruncated: isTruncated
        )
    }

    func rows(in range: ClosedRange<Int>, maximumColumns: Int) throws -> [DelimitedVirtualTableRow] {
        let lower = max(1, range.lowerBound)
        let upper = min(rowCount, range.upperBound)
        guard lower <= upper else { return [] }

        return try (lower...upper).compactMap { rowNumber in
            try row(rowNumber, maximumColumns: maximumColumns)
        }
    }

    private func readBytes(at offset: Int64, count: Int) throws -> Data {
        guard count > 0 else { return Data() }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        try fileHandle.seek(toOffset: UInt64(max(0, offset)))
        return try fileHandle.read(upToCount: count) ?? Data()
    }

    private static func buildIndex(
        at url: URL,
        delimiter: Character,
        chunkSize: Int = 256 * 1024
    ) throws -> DelimitedVirtualTableIndex {
        guard let delimiterByte = asciiByte(for: delimiter) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let initialSignature = try LargeFileLineIndexer.fileSignature(at: url)
        guard initialSignature.fileSizeBytes > 0 else {
            return DelimitedVirtualTableIndex(
                fileSizeBytes: initialSignature.fileSizeBytes,
                modificationDate: initialSignature.modificationDate,
                delimiter: delimiter,
                recordOffsets: [],
                columnCount: 0
            )
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let quote = UInt8(ascii: "\"")
        let lineFeed = UInt8(ascii: "\n")
        let carriageReturn = UInt8(ascii: "\r")

        var recordOffsets: [Int64] = [0]
        var maxColumnCount = 0
        var fieldCount = 0
        var fieldStarted = false
        var isInsideQuotedField = false
        var pendingQuoteInQuotedField = false
        var pendingCarriageReturnRow = false
        var byteOffset: Int64 = 0
        var endedWithRecordTerminator = false

        func finishField() {
            fieldStarted = false
            fieldCount += 1
        }

        func finishRow(nextOffset: Int64) {
            finishField()
            maxColumnCount = max(maxColumnCount, fieldCount)
            fieldCount = 0
            recordOffsets.append(nextOffset)
            endedWithRecordTerminator = true
        }

        func processOutsideQuotedField(_ byte: UInt8, nextOffset: Int64) {
            if pendingCarriageReturnRow {
                pendingCarriageReturnRow = false
                if byte == lineFeed {
                    recordOffsets[recordOffsets.count - 1] = nextOffset
                    endedWithRecordTerminator = true
                    return
                }
            }

            if byte == quote && !fieldStarted {
                isInsideQuotedField = true
                fieldStarted = true
                endedWithRecordTerminator = false
            } else if byte == delimiterByte {
                finishField()
                endedWithRecordTerminator = false
            } else if byte == lineFeed {
                finishRow(nextOffset: nextOffset)
            } else if byte == carriageReturn {
                finishRow(nextOffset: nextOffset)
                pendingCarriageReturnRow = true
            } else {
                fieldStarted = true
                endedWithRecordTerminator = false
            }
        }

        while true {
            try Task.checkCancellation()
            let chunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }

            for byte in chunk {
                let nextOffset = byteOffset + 1

                if pendingQuoteInQuotedField {
                    pendingQuoteInQuotedField = false
                    if byte == quote {
                        byteOffset = nextOffset
                        endedWithRecordTerminator = false
                        continue
                    }

                    isInsideQuotedField = false
                    processOutsideQuotedField(byte, nextOffset: nextOffset)
                    byteOffset = nextOffset
                    continue
                }

                if isInsideQuotedField {
                    if byte == quote {
                        pendingQuoteInQuotedField = true
                    } else {
                        endedWithRecordTerminator = false
                    }
                    byteOffset = nextOffset
                    continue
                }

                processOutsideQuotedField(byte, nextOffset: nextOffset)
                byteOffset = nextOffset
            }
        }

        if pendingQuoteInQuotedField {
            isInsideQuotedField = false
            pendingQuoteInQuotedField = false
        }

        if !endedWithRecordTerminator {
            finishField()
            maxColumnCount = max(maxColumnCount, fieldCount)
        } else if recordOffsets.last == byteOffset, recordOffsets.count > 1 {
            recordOffsets.removeLast()
        }

        let finalSignature = try LargeFileLineIndexer.fileSignature(at: url)
        guard initialSignature.fileSizeBytes == finalSignature.fileSizeBytes,
              initialSignature.modificationDate == finalSignature.modificationDate else {
            throw CocoaError(.fileReadUnknown)
        }

        return DelimitedVirtualTableIndex(
            fileSizeBytes: finalSignature.fileSizeBytes,
            modificationDate: finalSignature.modificationDate,
            delimiter: delimiter,
            recordOffsets: recordOffsets,
            columnCount: maxColumnCount
        )
    }

    private static func asciiByte(for delimiter: Character) -> UInt8? {
        let bytes = Array(String(delimiter).utf8)
        guard bytes.count == 1 else { return nil }
        return bytes[0]
    }

    private static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        if let text = String(data: data, encoding: .windowsCP1251) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }
}
