import SwiftUI

struct SearchPanelView: View {
    @ObservedObject var store: EditorStore
    @FocusState private var isFindFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                TextField(placeholder, text: $store.findQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFindFocused)
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 420)
                    .onSubmit {
                        if store.findPanelMode == .global {
                            if let first = store.globalSearchResults.first {
                                store.selectSearchResult(first)
                            }
                        } else {
                            store.findNext()
                        }
                    }

                Toggle(isOn: $store.findUsesRegex) {
                    Text(".*")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .toggleStyle(.button)
                .help("Use regular expression")

                if store.findPanelMode != .global {
                    Button {
                        store.findPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .help("Find previous")

                    Button {
                        store.findNext()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .help("Find next")

                    Button {
                        store.selectAllMatches()
                    } label: {
                        Text("Select All")
                    }
                    .help("Select all matches")
                }

                if store.findPanelMode == .replace {
                    Divider()

                    TextField("Replace", text: $store.replaceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, idealWidth: 260, maxWidth: 360)

                    Button("Replace") {
                        store.replaceCurrent()
                    }

                    Button("All") {
                        store.replaceAll()
                    }
                }

                Spacer()

                if store.findPanelMode == .global {
                    Text("\(store.globalSearchResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button {
                    store.hideFindPanel()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Close search")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(height: 42)

            if store.findPanelMode == .global, !store.findQuery.isEmpty {
                GlobalSearchResultsView(store: store)
                    .frame(height: globalResultsHeight)
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onAppear {
            isFindFocused = true
        }
        .onChange(of: store.findPanelMode) { _ in
            isFindFocused = true
        }
    }

    private var iconName: String {
        store.findPanelMode == .global ? "doc.text.magnifyingglass" : "magnifyingglass"
    }

    private var placeholder: String {
        switch store.findPanelMode {
        case .hidden, .find:
            return "Find"
        case .replace:
            return "Find"
        case .global:
            return "Find in all tabs"
        }
    }

    private var globalResultsHeight: CGFloat {
        let rowCount = max(store.globalSearchResults.count, 1)
        return min(180, CGFloat(rowCount * 28))
    }
}

private struct GlobalSearchResultsView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if store.globalSearchResults.isEmpty {
                    Text("No results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }

                ForEach(store.globalSearchResults) { result in
                    Button {
                        store.selectSearchResult(result)
                    } label: {
                        HStack(spacing: 10) {
                            Text(result.bufferTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 140, alignment: .leading)
                                .lineLimit(1)

                            Text("\(result.lineNumber)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)

                            Text(result.excerpt)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 188)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
    }
}
