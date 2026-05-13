import Foundation

struct LargeFileVirtualLine: Equatable {
    var number: Int
    var text: String
    var byteOffset: Int64
    var byteCount: Int
    var isTruncated: Bool
}

struct LargeFileVirtualLineEditResult: Equatable {
    var lineNumber: Int
    var byteOffset: Int64
    var oldByteCount: Int
    var newByteCount: Int
    var fileSizeBytes: Int64
    var index: LargeFileLineIndex
}

enum LargeFileVirtualEditError: LocalizedError, Equatable {
    case lineNotFound(Int)
    case sourceChanged
    case invalidRange
    case replacementContainsLineBreak
    case couldNotCreateTemporaryFile
    case couldNotReplaceSource

    var errorDescription: String? {
        switch self {
        case .lineNotFound(let lineNumber):
            return "Line \(lineNumber) is past the end of the file."
        case .sourceChanged:
            return "The source file changed on disk. Reopen it before applying virtual edits."
        case .invalidRange:
            return "The virtual line range no longer matches the source file."
        case .replacementContainsLineBreak:
            return "Virtual line replacement accepts one replacement line."
        case .couldNotCreateTemporaryFile:
            return "Could not create a temporary file next to the source file."
        case .couldNotReplaceSource:
            return "Could not replace the source file with the virtual line edit."
        }
    }
}

struct LargeFileVirtualTextDocument: Equatable {
    static let defaultMaximumLineBytes = 128 * 1024

    var url: URL
    var fileSizeBytes: Int64
    var modificationDate: Date?
    var index: LargeFileLineIndex

    var lineCount: Int {
        index.lineCount
    }

    static func open(
        at url: URL,
        cachedIndex: LargeFileLineIndex? = nil,
        checkpointInterval: Int = LargeFileLineIndexer.defaultCheckpointInterval
    ) throws -> LargeFileVirtualTextDocument {
        let signature = try LargeFileLineIndexer.fileSignature(at: url)
        let index: LargeFileLineIndex
        if let cachedIndex,
           cachedIndex.isValid(
               fileSizeBytes: signature.fileSizeBytes,
               modificationDate: signature.modificationDate
           ) {
            index = cachedIndex
        } else {
            index = try LargeFileLineIndexer.buildIndex(
                at: url,
                checkpointInterval: checkpointInterval
            )
        }

        return LargeFileVirtualTextDocument(
            url: url,
            fileSizeBytes: signature.fileSizeBytes,
            modificationDate: signature.modificationDate,
            index: index
        )
    }

    func isStillValid() -> Bool {
        guard let signature = try? LargeFileLineIndexer.fileSignature(at: url) else {
            return false
        }

        return index.isValid(
            fileSizeBytes: signature.fileSizeBytes,
            modificationDate: signature.modificationDate
        )
    }

    func line(
        _ lineNumber: Int,
        maximumLineBytes: Int = defaultMaximumLineBytes
    ) throws -> LargeFileVirtualLine? {
        let lineNumber = max(1, lineNumber)
        guard lineNumber <= index.lineCount else {
            return nil
        }

        let startLocation = try LargeFileLineIndexer.lineLocation(
            at: url,
            lineNumber: lineNumber,
            cachedIndex: index
        ).location
        guard let startLocation else {
            return nil
        }

        let nextByteOffset: Int64
        if lineNumber < index.lineCount,
           let nextLocation = try LargeFileLineIndexer.lineLocation(
               at: url,
               lineNumber: lineNumber + 1,
               cachedIndex: index
           ).location {
            nextByteOffset = nextLocation.byteOffset
        } else {
            nextByteOffset = fileSizeBytes
        }

        let byteCount = max(0, nextByteOffset - startLocation.byteOffset)
        let cappedByteCount = min(byteCount, Int64(max(1, maximumLineBytes)))
        let data = try readBytes(
            at: startLocation.byteOffset,
            count: Int(cappedByteCount)
        )
        var text = Self.decode(data)
        text = text.trimmingCharacters(in: .newlines)

        let isTruncated = cappedByteCount < byteCount
        if isTruncated {
            text += " [SimpleLime: line truncated after \(ByteCountFormatter.string(fromByteCount: cappedByteCount, countStyle: .file))]"
        }

        return LargeFileVirtualLine(
            number: lineNumber,
            text: text,
            byteOffset: startLocation.byteOffset,
            byteCount: Int(byteCount),
            isTruncated: isTruncated
        )
    }

    func lines(
        in range: ClosedRange<Int>,
        maximumLineBytes: Int = defaultMaximumLineBytes,
        maximumBatchBytes: Int = 8 * 1024 * 1024
    ) throws -> [LargeFileVirtualLine] {
        let lower = max(1, range.lowerBound)
        let upper = min(index.lineCount, range.upperBound)
        guard lower <= upper else { return [] }

        guard let startLocation = try LargeFileLineIndexer.lineLocation(
            at: url,
            lineNumber: lower,
            cachedIndex: index
        ).location else {
            return []
        }

        let endOffset: Int64
        if upper < index.lineCount,
           let nextLocation = try LargeFileLineIndexer.lineLocation(
               at: url,
               lineNumber: upper + 1,
               cachedIndex: index
           ).location {
            endOffset = nextLocation.byteOffset
        } else {
            endOffset = fileSizeBytes
        }

        let byteCount = max(0, endOffset - startLocation.byteOffset)
        if byteCount > Int64(maximumBatchBytes) {
            return try (lower...upper).compactMap { lineNumber in
                try line(lineNumber, maximumLineBytes: maximumLineBytes)
            }
        }

        let data = try readBytes(at: startLocation.byteOffset, count: Int(byteCount))
        return Self.decodeLines(
            data,
            firstLineNumber: lower,
            firstByteOffset: startLocation.byteOffset,
            maximumLineBytes: maximumLineBytes
        )
    }

    private static func decodeLines(
        _ data: Data,
        firstLineNumber: Int,
        firstByteOffset: Int64,
        maximumLineBytes: Int
    ) -> [LargeFileVirtualLine] {
        guard !data.isEmpty else {
            return [
                LargeFileVirtualLine(
                    number: firstLineNumber,
                    text: "",
                    byteOffset: firstByteOffset,
                    byteCount: 0,
                    isTruncated: false
                )
            ]
        }

        var lines: [LargeFileVirtualLine] = []
        var lineStart = data.startIndex
        var lineNumber = firstLineNumber

        func appendLine(upTo lineEnd: Data.Index, nextStart: Data.Index) {
            let byteCount = data.distance(from: lineStart, to: nextStart)
            let contentByteCount = data.distance(from: lineStart, to: lineEnd)
            let cappedContentByteCount = min(contentByteCount, max(1, maximumLineBytes))
            let contentEnd = data.index(lineStart, offsetBy: cappedContentByteCount)
            let lineData = data[lineStart..<contentEnd]

            var text = Self.decode(Data(lineData))
            let isTruncated = cappedContentByteCount < contentByteCount
            if isTruncated {
                text += " [SimpleLime: line truncated after \(ByteCountFormatter.string(fromByteCount: Int64(cappedContentByteCount), countStyle: .file))]"
            }

            lines.append(
                LargeFileVirtualLine(
                    number: lineNumber,
                    text: text,
                    byteOffset: firstByteOffset + Int64(data.distance(from: data.startIndex, to: lineStart)),
                    byteCount: byteCount,
                    isTruncated: isTruncated
                )
            )

            lineNumber += 1
            lineStart = nextStart
        }

        var index = data.startIndex
        while index < data.endIndex {
            if data[index] == UInt8(ascii: "\n") {
                var lineEnd = index
                if lineEnd > lineStart {
                    let previous = data.index(before: lineEnd)
                    if data[previous] == UInt8(ascii: "\r") {
                        lineEnd = previous
                    }
                }
                appendLine(upTo: lineEnd, nextStart: data.index(after: index))
            }
            index = data.index(after: index)
        }

        if lineStart < data.endIndex {
            appendLine(upTo: data.endIndex, nextStart: data.endIndex)
        }

        return lines
    }

    func lineTexts(in range: ClosedRange<Int>) throws -> [Int: String] {
        var values: [Int: String] = [:]
        for line in try lines(in: range) {
            values[line.number] = line.text
        }
        return values
    }

    func replacingLines(
        _ lineRange: ClosedRange<Int>,
        with replacementText: String,
        fileManager: FileManager = .default
    ) throws -> LargeFileVirtualLineEditResult {
        guard isStillValid() else {
            throw LargeFileVirtualEditError.sourceChanged
        }

        let normalizedRange = max(1, lineRange.lowerBound)...max(1, lineRange.upperBound)
        guard normalizedRange.lowerBound <= index.lineCount else {
            throw LargeFileVirtualEditError.lineNotFound(normalizedRange.lowerBound)
        }
        guard normalizedRange.upperBound <= index.lineCount else {
            throw LargeFileVirtualEditError.lineNotFound(normalizedRange.upperBound)
        }

        let byteRange = try byteRangeForLines(normalizedRange)
        let trailingLineEnding = try lineEnding(
            at: byteRange.byteOffset,
            byteCount: byteRange.byteCount
        )
        let blockLineEnding = trailingLineEnding.isEmpty ? try preferredLineEnding() : trailingLineEnding
        let replacementBody = Self.normalizedBlockText(
            replacementText,
            lineEnding: blockLineEnding
        )
        let replacementData = Data((replacementBody + trailingLineEnding).utf8)
        let newFileSizeBytes = try Self.replaceFileBytes(
            at: url,
            startOffset: byteRange.byteOffset,
            byteCount: byteRange.byteCount,
            replacement: replacementData,
            fileManager: fileManager
        )
        let newIndex = try LargeFileLineIndexer.buildIndex(
            at: url,
            checkpointInterval: index.checkpointInterval
        )

        return LargeFileVirtualLineEditResult(
            lineNumber: normalizedRange.lowerBound,
            byteOffset: byteRange.byteOffset,
            oldByteCount: byteRange.byteCount,
            newByteCount: replacementData.count,
            fileSizeBytes: newFileSizeBytes,
            index: newIndex
        )
    }

    func insertingLines(
        _ lineNumber: Int,
        text insertionText: String,
        fileManager: FileManager = .default
    ) throws -> LargeFileVirtualLineEditResult {
        guard isStillValid() else {
            throw LargeFileVirtualEditError.sourceChanged
        }

        let requestedLineNumber = max(1, lineNumber)
        guard requestedLineNumber <= index.lineCount + 1 else {
            throw LargeFileVirtualEditError.lineNotFound(requestedLineNumber)
        }

        let lineEnding = try preferredLineEnding()
        let insertionBody = Self.normalizedBlockText(
            insertionText,
            lineEnding: lineEnding
        )
        let insertionOffset: Int64
        let insertedText: String

        if fileSizeBytes == 0 {
            insertionOffset = 0
            insertedText = insertionBody
        } else if requestedLineNumber <= index.lineCount,
                  let startLocation = try LargeFileLineIndexer.lineLocation(
                    at: url,
                    lineNumber: requestedLineNumber,
                    cachedIndex: index
                  ).location {
            insertionOffset = startLocation.byteOffset
            insertedText = insertionBody + lineEnding
        } else {
            insertionOffset = fileSizeBytes
            insertedText = (try hasTrailingLineEnding()) ? insertionBody + lineEnding : lineEnding + insertionBody
        }

        let insertionData = Data(insertedText.utf8)
        let newFileSizeBytes = try Self.replaceFileBytes(
            at: url,
            startOffset: insertionOffset,
            byteCount: 0,
            replacement: insertionData,
            fileManager: fileManager
        )
        let newIndex = try LargeFileLineIndexer.buildIndex(
            at: url,
            checkpointInterval: index.checkpointInterval
        )

        return LargeFileVirtualLineEditResult(
            lineNumber: min(requestedLineNumber, newIndex.lineCount),
            byteOffset: insertionOffset,
            oldByteCount: 0,
            newByteCount: insertionData.count,
            fileSizeBytes: newFileSizeBytes,
            index: newIndex
        )
    }

    func deletingLines(
        _ lineRange: ClosedRange<Int>,
        fileManager: FileManager = .default
    ) throws -> LargeFileVirtualLineEditResult {
        guard isStillValid() else {
            throw LargeFileVirtualEditError.sourceChanged
        }

        let normalizedRange = max(1, lineRange.lowerBound)...max(1, lineRange.upperBound)
        guard normalizedRange.lowerBound <= index.lineCount else {
            throw LargeFileVirtualEditError.lineNotFound(normalizedRange.lowerBound)
        }
        guard normalizedRange.upperBound <= index.lineCount else {
            throw LargeFileVirtualEditError.lineNotFound(normalizedRange.upperBound)
        }

        let byteRange = try byteRangeForLines(normalizedRange)
        var deletionStartOffset = byteRange.byteOffset
        var deletedByteCount = byteRange.byteCount

        if normalizedRange.upperBound == index.lineCount,
           deletedByteCount > 0,
           deletionStartOffset > 0,
           try !lineRangeHasTrailingLineEnding(offset: deletionStartOffset, byteCount: deletedByteCount) {
            let precedingLineEndingByteCount = try precedingLineEndingByteCount(before: deletionStartOffset)
            if precedingLineEndingByteCount > 0 {
                deletionStartOffset -= Int64(precedingLineEndingByteCount)
                deletedByteCount += precedingLineEndingByteCount
            }
        }

        let newFileSizeBytes = try Self.replaceFileBytes(
            at: url,
            startOffset: deletionStartOffset,
            byteCount: deletedByteCount,
            replacement: Data(),
            fileManager: fileManager
        )
        let newIndex = try LargeFileLineIndexer.buildIndex(
            at: url,
            checkpointInterval: index.checkpointInterval
        )

        return LargeFileVirtualLineEditResult(
            lineNumber: min(normalizedRange.lowerBound, newIndex.lineCount),
            byteOffset: deletionStartOffset,
            oldByteCount: deletedByteCount,
            newByteCount: 0,
            fileSizeBytes: newFileSizeBytes,
            index: newIndex
        )
    }

    func replacingLine(
        _ lineNumber: Int,
        with replacementText: String,
        fileManager: FileManager = .default
    ) throws -> LargeFileVirtualLineEditResult {
        guard isStillValid() else {
            throw LargeFileVirtualEditError.sourceChanged
        }

        let lineNumber = max(1, lineNumber)
        guard lineNumber <= index.lineCount else {
            throw LargeFileVirtualEditError.lineNotFound(lineNumber)
        }

        guard let startLocation = try LargeFileLineIndexer.lineLocation(
            at: url,
            lineNumber: lineNumber,
            cachedIndex: index
        ).location else {
            throw LargeFileVirtualEditError.lineNotFound(lineNumber)
        }

        let nextByteOffset: Int64
        if lineNumber < index.lineCount,
           let nextLocation = try LargeFileLineIndexer.lineLocation(
               at: url,
               lineNumber: lineNumber + 1,
               cachedIndex: index
           ).location {
            nextByteOffset = nextLocation.byteOffset
        } else {
            nextByteOffset = fileSizeBytes
        }

        let oldByteCount = Int(max(0, nextByteOffset - startLocation.byteOffset))
        let lineEnding = try lineEnding(
            at: startLocation.byteOffset,
            byteCount: oldByteCount
        )
        let replacementLine = Self.textWithoutTrailingLineEnding(replacementText)
        guard !replacementLine.contains(where: { $0 == "\n" || $0 == "\r" }) else {
            throw LargeFileVirtualEditError.replacementContainsLineBreak
        }

        let replacement = replacementLine + lineEnding
        let replacementData = Data(replacement.utf8)
        let newFileSizeBytes = try Self.replaceFileBytes(
            at: url,
            startOffset: startLocation.byteOffset,
            byteCount: oldByteCount,
            replacement: replacementData,
            fileManager: fileManager
        )
        let newIndex = try LargeFileLineIndexer.buildIndex(
            at: url,
            checkpointInterval: index.checkpointInterval
        )

        return LargeFileVirtualLineEditResult(
            lineNumber: lineNumber,
            byteOffset: startLocation.byteOffset,
            oldByteCount: oldByteCount,
            newByteCount: replacementData.count,
            fileSizeBytes: newFileSizeBytes,
            index: newIndex
        )
    }

    func insertingLine(
        _ lineNumber: Int,
        text insertionText: String,
        fileManager: FileManager = .default
    ) throws -> LargeFileVirtualLineEditResult {
        guard isStillValid() else {
            throw LargeFileVirtualEditError.sourceChanged
        }

        let requestedLineNumber = max(1, lineNumber)
        guard requestedLineNumber <= index.lineCount + 1 else {
            throw LargeFileVirtualEditError.lineNotFound(requestedLineNumber)
        }

        let insertedLine = Self.textWithoutTrailingLineEnding(insertionText)
        guard !insertedLine.contains(where: { $0 == "\n" || $0 == "\r" }) else {
            throw LargeFileVirtualEditError.replacementContainsLineBreak
        }

        let lineEnding = try preferredLineEnding()
        let insertionOffset: Int64
        let insertedText: String

        if fileSizeBytes == 0 {
            insertionOffset = 0
            insertedText = insertedLine
        } else if requestedLineNumber <= index.lineCount,
                  let startLocation = try LargeFileLineIndexer.lineLocation(
                    at: url,
                    lineNumber: requestedLineNumber,
                    cachedIndex: index
                  ).location {
            insertionOffset = startLocation.byteOffset
            insertedText = insertedLine + lineEnding
        } else {
            insertionOffset = fileSizeBytes
            insertedText = (try hasTrailingLineEnding()) ? insertedLine + lineEnding : lineEnding + insertedLine
        }

        let insertionData = Data(insertedText.utf8)
        let newFileSizeBytes = try Self.replaceFileBytes(
            at: url,
            startOffset: insertionOffset,
            byteCount: 0,
            replacement: insertionData,
            fileManager: fileManager
        )
        let newIndex = try LargeFileLineIndexer.buildIndex(
            at: url,
            checkpointInterval: index.checkpointInterval
        )

        return LargeFileVirtualLineEditResult(
            lineNumber: min(requestedLineNumber, newIndex.lineCount),
            byteOffset: insertionOffset,
            oldByteCount: 0,
            newByteCount: insertionData.count,
            fileSizeBytes: newFileSizeBytes,
            index: newIndex
        )
    }

    func deletingLine(
        _ lineNumber: Int,
        fileManager: FileManager = .default
    ) throws -> LargeFileVirtualLineEditResult {
        guard isStillValid() else {
            throw LargeFileVirtualEditError.sourceChanged
        }

        let lineNumber = max(1, lineNumber)
        guard lineNumber <= index.lineCount,
              let startLocation = try LargeFileLineIndexer.lineLocation(
                at: url,
                lineNumber: lineNumber,
                cachedIndex: index
              ).location else {
            throw LargeFileVirtualEditError.lineNotFound(lineNumber)
        }

        let nextByteOffset: Int64
        if lineNumber < index.lineCount,
           let nextLocation = try LargeFileLineIndexer.lineLocation(
            at: url,
            lineNumber: lineNumber + 1,
            cachedIndex: index
           ).location {
            nextByteOffset = nextLocation.byteOffset
        } else {
            nextByteOffset = fileSizeBytes
        }

        var deletionStartOffset = startLocation.byteOffset
        var deletedByteCount = Int(max(0, nextByteOffset - startLocation.byteOffset))

        if lineNumber == index.lineCount,
           deletedByteCount > 0,
           deletionStartOffset > 0,
           try !lineRangeHasTrailingLineEnding(offset: deletionStartOffset, byteCount: deletedByteCount) {
            let precedingLineEndingByteCount = try precedingLineEndingByteCount(before: deletionStartOffset)
            if precedingLineEndingByteCount > 0 {
                deletionStartOffset -= Int64(precedingLineEndingByteCount)
                deletedByteCount += precedingLineEndingByteCount
            }
        }

        let newFileSizeBytes = try Self.replaceFileBytes(
            at: url,
            startOffset: deletionStartOffset,
            byteCount: deletedByteCount,
            replacement: Data(),
            fileManager: fileManager
        )
        let newIndex = try LargeFileLineIndexer.buildIndex(
            at: url,
            checkpointInterval: index.checkpointInterval
        )

        return LargeFileVirtualLineEditResult(
            lineNumber: min(lineNumber, newIndex.lineCount),
            byteOffset: deletionStartOffset,
            oldByteCount: deletedByteCount,
            newByteCount: 0,
            fileSizeBytes: newFileSizeBytes,
            index: newIndex
        )
    }

    func lineNumber(containingByteOffset byteOffset: Int64) throws -> Int {
        let clampedOffset = min(max(0, byteOffset), max(0, fileSizeBytes))
        let checkpoint = index.checkpoint(containingOrBeforeByteOffset: clampedOffset)

        if checkpoint.byteOffset == clampedOffset {
            return checkpoint.lineNumber
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        try fileHandle.seek(toOffset: UInt64(checkpoint.byteOffset))

        var currentLine = checkpoint.lineNumber
        var currentOffset = checkpoint.byteOffset

        while currentOffset < clampedOffset {
            try Task.checkCancellation()
            let remaining = clampedOffset - currentOffset
            let readCount = min(256 * 1024, Int(remaining))
            let data = try fileHandle.read(upToCount: readCount) ?? Data()
            if data.isEmpty {
                break
            }

            for byte in data {
                if byte == UInt8(ascii: "\n") {
                    currentLine += 1
                }
                currentOffset += 1
                if currentOffset >= clampedOffset {
                    break
                }
            }
        }

        return min(max(1, currentLine), index.lineCount)
    }

    private func readBytes(at offset: Int64, count: Int) throws -> Data {
        guard count > 0 else { return Data() }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        try fileHandle.seek(toOffset: UInt64(max(0, offset)))
        return try fileHandle.read(upToCount: count) ?? Data()
    }

    private func byteRangeForLines(_ lineRange: ClosedRange<Int>) throws -> (byteOffset: Int64, byteCount: Int) {
        guard let startLocation = try LargeFileLineIndexer.lineLocation(
            at: url,
            lineNumber: lineRange.lowerBound,
            cachedIndex: index
        ).location else {
            throw LargeFileVirtualEditError.lineNotFound(lineRange.lowerBound)
        }

        let endOffset: Int64
        if lineRange.upperBound < index.lineCount,
           let nextLocation = try LargeFileLineIndexer.lineLocation(
            at: url,
            lineNumber: lineRange.upperBound + 1,
            cachedIndex: index
           ).location {
            endOffset = nextLocation.byteOffset
        } else {
            endOffset = fileSizeBytes
        }

        return (
            byteOffset: startLocation.byteOffset,
            byteCount: Int(max(0, endOffset - startLocation.byteOffset))
        )
    }

    private func lineEnding(at offset: Int64, byteCount: Int) throws -> String {
        guard byteCount > 0 else { return "" }

        let suffixCount = min(2, byteCount)
        let suffix = try readBytes(
            at: offset + Int64(byteCount - suffixCount),
            count: suffixCount
        )

        if suffix.count >= 2,
           suffix[suffix.index(before: suffix.endIndex)] == UInt8(ascii: "\n"),
           suffix[suffix.index(suffix.endIndex, offsetBy: -2)] == UInt8(ascii: "\r") {
            return "\r\n"
        }
        if suffix.last == UInt8(ascii: "\n") {
            return "\n"
        }
        return ""
    }

    private func preferredLineEnding() throws -> String {
        guard fileSizeBytes > 0 else { return "\n" }

        let data = try readBytes(at: 0, count: min(Int(fileSizeBytes), 1024 * 1024))
        var index = data.startIndex
        while index < data.endIndex {
            if data[index] == UInt8(ascii: "\n") {
                if index > data.startIndex {
                    let previous = data.index(before: index)
                    if data[previous] == UInt8(ascii: "\r") {
                        return "\r\n"
                    }
                }
                return "\n"
            }
            index = data.index(after: index)
        }

        return "\n"
    }

    private func hasTrailingLineEnding() throws -> Bool {
        guard fileSizeBytes > 0 else { return false }
        return try readBytes(at: fileSizeBytes - 1, count: 1).last == UInt8(ascii: "\n")
    }

    private func lineRangeHasTrailingLineEnding(offset: Int64, byteCount: Int) throws -> Bool {
        guard byteCount > 0 else { return false }
        return try readBytes(at: offset + Int64(byteCount - 1), count: 1).last == UInt8(ascii: "\n")
    }

    private func precedingLineEndingByteCount(before offset: Int64) throws -> Int {
        guard offset > 0 else { return 0 }

        let suffixCount = min(2, Int(offset))
        let suffix = try readBytes(at: offset - Int64(suffixCount), count: suffixCount)
        guard suffix.last == UInt8(ascii: "\n") else { return 0 }

        if suffix.count >= 2,
           suffix[suffix.index(suffix.endIndex, offsetBy: -2)] == UInt8(ascii: "\r") {
            return 2
        }

        return 1
    }

    private static func textWithoutTrailingLineEnding(_ text: String) -> String {
        if text.hasSuffix("\r\n") {
            return String(text.dropLast(2))
        }
        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            return String(text.dropLast())
        }
        return text
    }

    private static func normalizedBlockText(_ text: String, lineEnding: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasSuffix("\n") {
            normalized.removeLast()
        }
        return normalized.replacingOccurrences(of: "\n", with: lineEnding)
    }

    private static func replaceFileBytes(
        at url: URL,
        startOffset: Int64,
        byteCount: Int,
        replacement: Data,
        chunkSize: Int = 256 * 1024,
        fileManager: FileManager = .default
    ) throws -> Int64 {
        let currentSize = try LargeFileLineIndexer.fileSignature(at: url).fileSizeBytes
        guard startOffset >= 0,
              byteCount >= 0,
              startOffset + Int64(byteCount) <= currentSize else {
            throw LargeFileVirtualEditError.invalidRange
        }

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).simplelime-\(UUID().uuidString).tmp", isDirectory: false)
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw LargeFileVirtualEditError.couldNotCreateTemporaryFile
        }

        let input = try FileHandle(forReadingFrom: url)
        let output = try FileHandle(forWritingTo: temporaryURL)
        do {
            try copyFileHandleBytes(from: input, to: output, byteCount: startOffset, chunkSize: chunkSize)
            try output.write(contentsOf: replacement)
            try input.seek(toOffset: UInt64(startOffset + Int64(byteCount)))
            try copyFileHandleRemainder(from: input, to: output, chunkSize: chunkSize)
            try output.close()
            try input.close()
        } catch {
            try? output.close()
            try? input.close()
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }

        do {
            _ = try fileManager.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            try? fileManager.removeItem(at: url)
            do {
                try fileManager.moveItem(at: temporaryURL, to: url)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw LargeFileVirtualEditError.couldNotReplaceSource
            }
        }

        return currentSize - Int64(byteCount) + Int64(replacement.count)
    }

    private static func copyFileHandleBytes(
        from input: FileHandle,
        to output: FileHandle,
        byteCount: Int64,
        chunkSize: Int
    ) throws {
        var remaining = byteCount
        while remaining > 0 {
            try Task.checkCancellation()
            let readCount = min(chunkSize, Int(remaining))
            let data = try input.read(upToCount: readCount) ?? Data()
            guard !data.isEmpty else {
                throw LargeFileVirtualEditError.invalidRange
            }
            try output.write(contentsOf: data)
            remaining -= Int64(data.count)
        }
    }

    private static func copyFileHandleRemainder(
        from input: FileHandle,
        to output: FileHandle,
        chunkSize: Int
    ) throws {
        while true {
            try Task.checkCancellation()
            let data = try input.read(upToCount: chunkSize) ?? Data()
            guard !data.isEmpty else { return }
            try output.write(contentsOf: data)
        }
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
