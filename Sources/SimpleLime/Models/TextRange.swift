import Foundation

struct TextRange: Codable, Equatable, Hashable {
    var location: Int
    var length: Int

    static let zero = TextRange(location: 0, length: 0)

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }
}
