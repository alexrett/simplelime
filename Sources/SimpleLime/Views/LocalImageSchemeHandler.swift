import Foundation
import WebKit

final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "simplelime-image"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let path = Self.filePath(from: url) else {
            fail(urlSchemeTask, code: NSURLErrorBadURL)
            return
        }

        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        do {
            let data = try Data(contentsOf: fileURL)
            let response = URLResponse(
                url: url,
                mimeType: Self.mimeType(for: fileURL.pathExtension),
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            fail(urlSchemeTask, code: NSURLErrorFileDoesNotExist)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static func filePath(from url: URL) -> String? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else {
            return nil
        }

        return path
    }

    private func fail(_ task: WKURLSchemeTask, code: Int) {
        task.didFailWithError(NSError(domain: NSURLErrorDomain, code: code))
    }

    private static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "apng": return "image/apng"
        case "avif": return "image/avif"
        case "gif": return "image/gif"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}
