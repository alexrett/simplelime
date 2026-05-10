import AppKit
import Foundation

enum CollaborationMessageKind: String, Codable {
    case invite
    case accept
    case patch
    case selection
    case leave
}

struct CollaborationTextPatch: Codable, Equatable {
    var range: TextRange
    var removedText: String
    var replacement: String
    var prefixContext: String
    var suffixContext: String

    static func make(oldText: String, newText: String, contextLength: Int = 40) -> CollaborationTextPatch? {
        guard oldText != newText else { return nil }

        let old = oldText as NSString
        let new = newText as NSString
        let oldLength = old.length
        let newLength = new.length

        var prefixLength = 0
        while prefixLength < oldLength,
              prefixLength < newLength,
              old.character(at: prefixLength) == new.character(at: prefixLength) {
            prefixLength += 1
        }

        var suffixLength = 0
        while suffixLength < oldLength - prefixLength,
              suffixLength < newLength - prefixLength,
              old.character(at: oldLength - suffixLength - 1) == new.character(at: newLength - suffixLength - 1) {
            suffixLength += 1
        }

        let removedRange = NSRange(location: prefixLength, length: oldLength - prefixLength - suffixLength)
        let replacementRange = NSRange(location: prefixLength, length: newLength - prefixLength - suffixLength)
        let contextStart = max(0, removedRange.location - contextLength)
        let contextEnd = min(oldLength, removedRange.location + removedRange.length + contextLength)

        return CollaborationTextPatch(
            range: TextRange(removedRange),
            removedText: old.substring(with: removedRange),
            replacement: new.substring(with: replacementRange),
            prefixContext: old.substring(with: NSRange(location: contextStart, length: removedRange.location - contextStart)),
            suffixContext: old.substring(
                with: NSRange(
                    location: removedRange.location + removedRange.length,
                    length: contextEnd - (removedRange.location + removedRange.length)
                )
            )
        )
    }

    func apply(to text: String) -> String {
        let nsText = text as NSString
        let targetRange = relocatedRange(in: nsText)
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: targetRange, with: replacement)
        return mutable as String
    }

    private func relocatedRange(in text: NSString) -> NSRange {
        let directRange = clamped(range.nsRange, in: text.length)
        let removedLength = (removedText as NSString).length
        if removedLength > 0, text.substring(with: directRange) == removedText {
            return directRange
        }
        if removedLength == 0, directInsertionContextMatches(in: text, at: directRange.location) {
            return directRange
        }

        let prefixLength = (prefixContext as NSString).length
        let fullContext = "\(prefixContext)\(removedText)\(suffixContext)"

        if !fullContext.isEmpty {
            let fullRange = text.range(of: fullContext)
            if fullRange.location != NSNotFound {
                return NSRange(location: fullRange.location + prefixLength, length: removedLength)
            }
        }

        if removedLength > 0 {
            let first = text.range(of: removedText)
            if first.location != NSNotFound {
                let restStart = first.location + first.length
                let restRange = NSRange(location: restStart, length: max(0, text.length - restStart))
                if text.range(of: removedText, options: [], range: restRange).location == NSNotFound {
                    return first
                }
            }
        }

        if removedLength == 0, !prefixContext.isEmpty || !suffixContext.isEmpty {
            let context = "\(prefixContext)\(suffixContext)"
            let contextRange = text.range(of: context)
            if contextRange.location != NSNotFound {
                return NSRange(location: contextRange.location + prefixLength, length: 0)
            }
            if !prefixContext.isEmpty {
                let prefixRange = text.range(of: prefixContext)
                if prefixRange.location != NSNotFound {
                    return NSRange(location: prefixRange.location + prefixRange.length, length: 0)
                }
            }
        }

        return directRange
    }

    private func directInsertionContextMatches(in text: NSString, at location: Int) -> Bool {
        let prefixLength = (prefixContext as NSString).length
        let suffixLength = (suffixContext as NSString).length

        if prefixLength > 0 {
            guard location >= prefixLength else { return false }
            let prefixRange = NSRange(location: location - prefixLength, length: prefixLength)
            guard text.substring(with: prefixRange) == prefixContext else { return false }
        }

        if suffixLength > 0 {
            guard location + suffixLength <= text.length else { return false }
            let suffixRange = NSRange(location: location, length: suffixLength)
            guard text.substring(with: suffixRange) == suffixContext else { return false }
        }

        return prefixLength > 0 || suffixLength > 0
    }

    private func clamped(_ range: NSRange, in length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
}

struct RemoteCollaborator: Identifiable, Codable, Equatable {
    var id: String { deviceID }

    var deviceID: String
    var name: String
    var selectionRanges: [TextRange]
    var colorIndex: Int
    var lastSeenAt: Date
}

struct CollaborationSessionState: Equatable {
    var id: UUID
    var bufferID: UUID
    var title: String
    var localRevision: Int
    var isHost: Bool
    var startedAt: Date
    var collaborators: [RemoteCollaborator]

    var statusText: String {
        if collaborators.isEmpty {
            return "Collaboration active"
        }
        let names = collaborators.map(\.name).joined(separator: ", ")
        return "Editing with \(names)"
    }
}

struct CollaborationPayload: Codable, Equatable {
    var type = "collaboration"
    var kind: CollaborationMessageKind
    var sessionID: UUID
    var title: String
    var text: String?
    var language: EditorLanguage?
    var patch: CollaborationTextPatch?
    var selectionRanges: [TextRange]
    var revision: Int
    var sentAt: Date
    var sourceDeviceID: String
    var sourceDeviceName: String
    var sourceToken: String?
    var actorDeviceID: String? = nil
    var actorDeviceName: String? = nil
}

extension CollaborationPayload {
    var collaboratorDeviceID: String {
        actorDeviceID ?? sourceDeviceID
    }

    var collaboratorName: String {
        actorDeviceName ?? sourceDeviceName
    }
}

extension RemoteCollaborator {
    var nsColor: NSColor {
        let colors: [NSColor] = [
            .systemBlue,
            .systemGreen,
            .systemOrange,
            .systemPink,
            .systemPurple,
            .systemTeal
        ]
        return colors[abs(colorIndex) % colors.count]
    }

    var cssColor: String {
        let color = nsColor.usingColorSpace(.deviceRGB) ?? .systemBlue
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return "rgb(\(red), \(green), \(blue))"
    }
}
