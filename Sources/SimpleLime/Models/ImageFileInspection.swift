import Foundation
import ImageIO

struct ImageFileInspection: Equatable {
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSizeBytes: Int64?
    let typeDescription: String?
    let colorModel: String?
    let hasAlpha: Bool?
    let dpiWidth: Double?
    let dpiHeight: Double?

    var pixelSizeText: String {
        "\(pixelWidth) x \(pixelHeight) px"
    }

    var fileSizeText: String? {
        fileSizeBytes.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
    }

    var colorSummaryText: String {
        let model = colorModel?.isEmpty == false ? colorModel! : "Color"
        guard let hasAlpha else { return model }
        return hasAlpha ? "\(model), alpha" : model
    }

    var dpiText: String? {
        guard let dpiWidth, let dpiHeight, dpiWidth > 0, dpiHeight > 0 else {
            return nil
        }

        if abs(dpiWidth - dpiHeight) < 0.5 {
            return "\(Int(dpiWidth.rounded())) dpi"
        }

        return "\(Int(dpiWidth.rounded())) x \(Int(dpiHeight.rounded())) dpi"
    }

    static func inspect(url: URL) -> ImageFileInspection? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let type = CGImageSourceGetType(source).map { String($0) }
        return ImageFileInspection(
            pixelWidth: integerValue(properties[kCGImagePropertyPixelWidth]) ?? 0,
            pixelHeight: integerValue(properties[kCGImagePropertyPixelHeight]) ?? 0,
            fileSizeBytes: fileSize,
            typeDescription: type,
            colorModel: properties[kCGImagePropertyColorModel] as? String,
            hasAlpha: boolValue(properties[kCGImagePropertyHasAlpha]),
            dpiWidth: doubleValue(properties[kCGImagePropertyDPIWidth]),
            dpiHeight: doubleValue(properties[kCGImagePropertyDPIHeight])
        )
    }

    private static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["true", "yes", "1"].contains(value.lowercased())
        default:
            return nil
        }
    }
}
