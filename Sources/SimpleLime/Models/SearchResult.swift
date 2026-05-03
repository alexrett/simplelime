import Foundation

struct SearchResult: Identifiable, Hashable {
    var id: String {
        "\(bufferID.uuidString)-\(range.location)-\(range.length)"
    }

    let bufferID: UUID
    let bufferTitle: String
    let lineNumber: Int
    let excerpt: String
    let range: TextRange
}
