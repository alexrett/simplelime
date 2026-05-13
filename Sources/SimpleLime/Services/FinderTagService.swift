import Foundation
import Darwin

enum FinderTagService {
    private static let attributeName = "com.apple.metadata:_kMDItemUserTags"

    static func tags(for url: URL) -> [String] {
        if let data = extendedAttributeData(for: url),
           let rawTags = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
            return rawTags.compactMap { tag in
                tag.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        }

        return (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    static func setTags(_ tags: [String], for url: URL) throws {
        let tags = normalized(tags)
        if tags.isEmpty {
            try removeExtendedAttribute(from: url)
            return
        }

        let storedTags = tags.map { "\($0)\n0" }
        let data = try PropertyListSerialization.data(
            fromPropertyList: storedTags,
            format: .binary,
            options: 0
        )
        try writeExtendedAttribute(data, to: url)
    }

    static func addTag(_ tag: String, to url: URL) throws {
        let existing = tags(for: url)
        try setTags(existing + [tag], for: url)
    }

    private static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { rawTag in
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { return nil }
            let key = tag.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return tag
        }
    }

    private static func extendedAttributeData(for url: URL) -> Data? {
        let path = url.path
        let size = path.withCString { pathPointer in
            attributeName.withCString { attributePointer in
                getxattr(pathPointer, attributePointer, nil, 0, 0, 0)
            }
        }
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { buffer in
            path.withCString { pathPointer in
                attributeName.withCString { attributePointer in
                    getxattr(pathPointer, attributePointer, buffer.baseAddress, size, 0, 0)
                }
            }
        }

        guard read >= 0 else { return nil }
        return data
    }

    private static func writeExtendedAttribute(_ data: Data, to url: URL) throws {
        let path = url.path
        let result = data.withUnsafeBytes { buffer in
            path.withCString { pathPointer in
                attributeName.withCString { attributePointer in
                    setxattr(pathPointer, attributePointer, buffer.baseAddress, data.count, 0, 0)
                }
            }
        }

        if result != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func removeExtendedAttribute(from url: URL) throws {
        let path = url.path
        let result = path.withCString { pathPointer in
            attributeName.withCString { attributePointer in
                removexattr(pathPointer, attributePointer, 0)
            }
        }

        if result != 0, errno != ENOATTR {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
