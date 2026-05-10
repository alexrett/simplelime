import Foundation

struct SearchResult: Identifiable, Hashable {
    var id: String {
        "\(filePath ?? bufferID?.uuidString ?? bufferTitle)-\(range.location)-\(range.length)"
    }

    let bufferID: UUID?
    let filePath: String?
    let bufferTitle: String
    let lineNumber: Int
    let excerpt: String
    let range: TextRange

    init(
        bufferID: UUID? = nil,
        filePath: String? = nil,
        bufferTitle: String,
        lineNumber: Int,
        excerpt: String,
        range: TextRange
    ) {
        self.bufferID = bufferID
        self.filePath = filePath
        self.bufferTitle = bufferTitle
        self.lineNumber = lineNumber
        self.excerpt = excerpt
        self.range = range
    }
}
