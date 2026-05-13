import Foundation

struct LargeFileLineLocation: Equatable {
    let lineNumber: Int
    let byteOffset: Int64
}

struct LargeFileLineCheckpoint: Equatable {
    let lineNumber: Int
    let byteOffset: Int64
}

struct LargeFileLineIndex: Equatable {
    let fileSizeBytes: Int64
    let modificationDate: Date?
    let lineCount: Int
    let checkpointInterval: Int
    let checkpoints: [LargeFileLineCheckpoint]

    func isValid(fileSizeBytes: Int64?, modificationDate: Date?) -> Bool {
        self.fileSizeBytes == fileSizeBytes && self.modificationDate == modificationDate
    }

    func checkpoint(for lineNumber: Int) -> LargeFileLineCheckpoint {
        let targetLine = max(1, lineNumber)
        var lowerBound = 0
        var upperBound = checkpoints.count - 1
        var best = checkpoints[0]

        while lowerBound <= upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            let candidate = checkpoints[midpoint]
            if candidate.lineNumber <= targetLine {
                best = candidate
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint - 1
            }
        }

        return best
    }

    func checkpoint(containingOrBeforeByteOffset byteOffset: Int64) -> LargeFileLineCheckpoint {
        let targetOffset = max(0, byteOffset)
        var lowerBound = 0
        var upperBound = checkpoints.count - 1
        var best = checkpoints[0]

        while lowerBound <= upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            let candidate = checkpoints[midpoint]
            if candidate.byteOffset <= targetOffset {
                best = candidate
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint - 1
            }
        }

        return best
    }
}

enum LargeFileLineIndexer {
    static let defaultCheckpointInterval = 512
    private static let defaultChunkSize = 256 * 1024

    static func fileSignature(at url: URL) throws -> (fileSizeBytes: Int64, modificationDate: Date?) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
        return (fileSizeBytes, modificationDate)
    }

    static func buildIndex(
        at url: URL,
        checkpointInterval: Int = defaultCheckpointInterval,
        chunkSize: Int = defaultChunkSize
    ) throws -> LargeFileLineIndex {
        let initialSignature = try fileSignature(at: url)
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let interval = max(1, checkpointInterval)
        var checkpoints = [LargeFileLineCheckpoint(lineNumber: 1, byteOffset: 0)]
        var currentLine = 1
        var byteOffset: Int64 = 0

        while true {
            try Task.checkCancellation()
            let chunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }

            for byte in chunk {
                if byte == UInt8(ascii: "\n") {
                    currentLine += 1
                    let nextLineOffset = byteOffset + 1
                    if (currentLine - 1).isMultiple(of: interval) {
                        checkpoints.append(LargeFileLineCheckpoint(
                            lineNumber: currentLine,
                            byteOffset: nextLineOffset
                        ))
                    }
                }
                byteOffset += 1
            }
        }

        let finalSignature = try fileSignature(at: url)
        guard initialSignature.fileSizeBytes == finalSignature.fileSizeBytes,
              initialSignature.modificationDate == finalSignature.modificationDate else {
            throw CocoaError(.fileReadUnknown)
        }

        return LargeFileLineIndex(
            fileSizeBytes: finalSignature.fileSizeBytes,
            modificationDate: finalSignature.modificationDate,
            lineCount: currentLine,
            checkpointInterval: interval,
            checkpoints: checkpoints
        )
    }

    static func lineLocation(
        at url: URL,
        lineNumber: Int,
        cachedIndex: LargeFileLineIndex? = nil,
        checkpointInterval: Int = defaultCheckpointInterval,
        chunkSize: Int = defaultChunkSize
    ) throws -> (location: LargeFileLineLocation?, index: LargeFileLineIndex) {
        let signature = try fileSignature(at: url)
        let index: LargeFileLineIndex
        if let cachedIndex,
           cachedIndex.isValid(
               fileSizeBytes: signature.fileSizeBytes,
               modificationDate: signature.modificationDate
           ) {
            index = cachedIndex
        } else {
            index = try buildIndex(
                at: url,
                checkpointInterval: checkpointInterval,
                chunkSize: chunkSize
            )
        }

        let targetLine = max(1, lineNumber)
        guard targetLine <= index.lineCount else {
            return (nil, index)
        }

        let checkpoint = index.checkpoint(for: targetLine)
        let location = try scanLineLocation(
            at: url,
            targetLine: targetLine,
            startingAtLine: checkpoint.lineNumber,
            startingOffset: checkpoint.byteOffset,
            chunkSize: chunkSize
        )
        return (location, index)
    }

    private static func scanLineLocation(
        at url: URL,
        targetLine: Int,
        startingAtLine: Int,
        startingOffset: Int64,
        chunkSize: Int
    ) throws -> LargeFileLineLocation? {
        if targetLine == startingAtLine {
            return LargeFileLineLocation(lineNumber: targetLine, byteOffset: startingOffset)
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        try fileHandle.seek(toOffset: UInt64(max(0, startingOffset)))

        var currentLine = startingAtLine
        var byteOffset = max(0, startingOffset)

        while true {
            try Task.checkCancellation()
            let chunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                return nil
            }

            for byte in chunk {
                if byte == UInt8(ascii: "\n") {
                    currentLine += 1
                    if currentLine == targetLine {
                        return LargeFileLineLocation(
                            lineNumber: targetLine,
                            byteOffset: byteOffset + 1
                        )
                    }
                }
                byteOffset += 1
            }
        }
    }
}
