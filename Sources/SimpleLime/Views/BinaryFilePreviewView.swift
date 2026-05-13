import PDFKit
import SwiftUI

struct BinaryFilePreviewView: View {
    let fileURL: URL
    let language: EditorLanguage

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var preview: some View {
        switch language {
        case .image:
            ImageFilePreview(fileURL: fileURL)
        case .pdf:
            PDFFilePreview(fileURL: fileURL)
        case .hex:
            HexFilePreview(fileURL: fileURL)
        default:
            unavailablePreview
        }
    }

    private var unavailablePreview: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(fileURL.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: footerSystemImage)
                .foregroundStyle(.secondary)
            Text(fileURL.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(language.displayName)
                .foregroundStyle(.secondary)
            if let size = fileSizeText {
                Text(size)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var fileSizeText: String? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private var footerSystemImage: String {
        switch language {
        case .pdf:
            return "doc.richtext"
        case .hex:
            return "number"
        default:
            return "photo"
        }
    }
}

private struct ImageFilePreview: View {
    let fileURL: URL
    @State private var zoom: CGFloat = 1
    @State private var fitToWindow = true

    private var inspection: ImageFileInspection? {
        ImageFileInspection.inspect(url: fileURL)
    }

    var body: some View {
        if let image = NSImage(contentsOf: fileURL) {
            VStack(spacing: 0) {
                inspectorBar
                Divider()
                imageCanvas(image)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            previewError
        }
    }

    private var inspectorBar: some View {
        HStack(spacing: 10) {
            Label(inspection?.pixelSizeText ?? "Image", systemImage: "ruler")
                .lineLimit(1)

            if let fileSize = inspection?.fileSizeText {
                Label(fileSize, systemImage: "internaldrive")
                    .lineLimit(1)
            }

            if let inspection {
                Label(inspection.colorSummaryText, systemImage: inspection.hasAlpha == true ? "square.on.checkerboard" : "paintpalette")
                    .lineLimit(1)
            }

            if let dpi = inspection?.dpiText {
                Label(dpi, systemImage: "dot.scope")
                    .lineLimit(1)
            }

            Spacer()

            if ExternalFileEditorService.simpleShotApplicationURL() != nil {
                Button {
                    ExternalFileEditorService.openInSimpleShot(fileURL)
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Open in SimpleShot")
            }

            Button {
                ExternalFileEditorService.openInDefaultApplication(fileURL)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Open in default app")

            Button {
                ExternalFileEditorService.revealInFinder(fileURL)
            } label: {
                Image(systemName: "folder")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            Button {
                fitToWindow = false
                zoom = max(0.1, zoom / 1.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Zoom out")

            Button {
                fitToWindow = true
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(fitToWindow ? Color.accentColor : Color.secondary)
            .help("Fit image to window")

            Button {
                fitToWindow = false
                zoom = 1
            } label: {
                Text("1:1")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 30, height: 22)
            }
            .buttonStyle(.plain)
            .help("Actual pixel size")

            Button {
                fitToWindow = false
                zoom = min(8, zoom * 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Zoom in")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func imageCanvas(_ image: NSImage) -> some View {
        if fitToWindow {
            ZStack {
                CheckerboardBackground(squareSize: 12)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    CheckerboardBackground(squareSize: max(4, 12 * zoom))
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(zoom >= 2 ? .none : .high)
                        .frame(width: displayWidth(for: image), height: displayHeight(for: image))
                        .padding(18)
                }
                .frame(minWidth: displayWidth(for: image) + 36, minHeight: displayHeight(for: image) + 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func displayWidth(for image: NSImage) -> CGFloat {
        CGFloat(max(inspection?.pixelWidth ?? Int(image.size.width), 1)) * zoom
    }

    private func displayHeight(for image: NSImage) -> CGFloat {
        CGFloat(max(inspection?.pixelHeight ?? Int(image.size.height), 1)) * zoom
    }

    private var previewError: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Could not preview image")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CheckerboardBackground: View {
    let squareSize: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .textBackgroundColor)))
            let light = Color(nsColor: .windowBackgroundColor).opacity(0.9)
            let dark = Color(nsColor: .separatorColor).opacity(0.45)
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var column = 0
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color((row + column).isMultiple(of: 2) ? light : dark))
                    x += squareSize
                    column += 1
                }
                y += squareSize
                row += 1
            }
        }
    }
}

private struct PDFFilePreview: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .textBackgroundColor
        view.document = PDFDocument(url: fileURL)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != fileURL {
            view.document = PDFDocument(url: fileURL)
        }
        view.autoScales = true
    }
}

private struct HexFilePreview: View {
    let fileURL: URL

    private var preview: Result<HexDumpPreview, Error> {
        Result { try HexDump.readPreview(at: fileURL) }
    }

    var body: some View {
        switch preview {
        case .success(let preview):
            VStack(spacing: 0) {
                header(for: preview)
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    Text(HexDump.format(preview.data))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .failure(let error):
            VStack(spacing: 10) {
                Image(systemName: "number")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Could not preview binary file")
                    .font(.headline)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for preview: HexDumpPreview) -> some View {
        HStack(spacing: 10) {
            Label("\(preview.byteCount) bytes shown", systemImage: "number")
                .lineLimit(1)

            if let fileSizeBytes = preview.fileSizeBytes {
                Label(ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file), systemImage: "internaldrive")
                    .lineLimit(1)
            }

            if preview.isTruncated {
                Label("Preview limited", systemImage: "scissors")
                    .lineLimit(1)
            }

            Spacer()

            Text("Read-only")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
