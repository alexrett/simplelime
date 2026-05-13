import SwiftUI

struct DocumentCatalogView: View {
    @ObservedObject var store: EditorStore

    private var rootName: String {
        guard let path = store.documentCatalogRootPath else { return "Documents" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var visibleNodes: [DocumentCatalogNode] {
        let query = store.documentCatalogQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.documentCatalogNodes }
        return store.documentCatalogNodes.compactMap { filteredNode($0, query: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.documentCatalogRootPath != nil {
                TextField("Filter files", text: $store.documentCatalogQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            Divider()

            if store.documentCatalogRootPath == nil {
                emptyState
            } else if visibleNodes.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No documents")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleNodes) { node in
                            DocumentCatalogNodeRow(
                                node: node,
                                selectedPath: store.selectedBuffer?.filePath,
                                onOpenFile: { store.openFile(at: $0) }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            Text(rootName)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                store.openFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Open folder")

            if store.documentCatalogRootPath != nil {
                Button {
                    store.refreshPOModeAnalysisForDocumentCatalog()
                } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.borderless)
                .help("Open PO mode panel")

                Button {
                    store.refreshDocumentCatalog()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh folder")

                Button {
                    store.closeFolder()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close folder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Open a folder")
                .font(.headline)

            Button("Open Folder...") {
                store.openFolder()
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func filteredNode(_ node: DocumentCatalogNode, query: String) -> DocumentCatalogNode? {
        if node.name.localizedCaseInsensitiveContains(query) {
            return node
        }

        let children = node.children.compactMap { filteredNode($0, query: query) }
        guard !children.isEmpty else { return nil }
        return DocumentCatalogNode(url: node.url, isDirectory: node.isDirectory, children: children)
    }
}

private struct DocumentCatalogNodeRow: View {
    let node: DocumentCatalogNode
    let selectedPath: String?
    let onOpenFile: (URL) -> Void

    @State private var isExpanded = true

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { child in
                    DocumentCatalogNodeRow(
                        node: child,
                        selectedPath: selectedPath,
                        onOpenFile: onOpenFile
                    )
                    .padding(.leading, 12)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(node.name)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13))
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .disclosureGroupStyle(.automatic)
            .padding(.horizontal, 8)
        } else {
            Button {
                onOpenFile(node.url)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: iconName)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(node.name)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
    }

    private var isSelected: Bool {
        selectedPath == node.url.path
    }

    private var iconName: String {
        let language = EditorLanguage.detect(fileName: node.name)
        if language.isMarkdown {
            return "doc.richtext"
        }
        if language.isDelimitedTable {
            return "tablecells"
        }
        if language == .image {
            return "photo"
        }
        if language == .pdf {
            return "doc.richtext"
        }
        return "doc.text"
    }
}
