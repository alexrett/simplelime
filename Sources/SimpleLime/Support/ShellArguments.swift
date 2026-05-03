import Foundation

enum ShellArguments {
    static func split(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in text {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if isEscaping {
            current.append("\\")
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}
