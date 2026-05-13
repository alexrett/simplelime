import Foundation

enum JSONTextFormatter {
    enum FormattingError: Error {
        case invalidUTF8
    }

    static func format(_ text: String, prettyPrinted: Bool) throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw FormattingError.invalidUTF8
        }

        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let options: JSONSerialization.WritingOptions = prettyPrinted
            ? [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]
            : [.withoutEscapingSlashes, .fragmentsAllowed]
        let output = try JSONSerialization.data(withJSONObject: object, options: options)

        guard let formatted = String(data: output, encoding: .utf8) else {
            throw FormattingError.invalidUTF8
        }

        return prettyPrinted ? "\(formatted)\n" : formatted
    }
}
