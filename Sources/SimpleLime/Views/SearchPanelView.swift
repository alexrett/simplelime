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

                Toggle(isOn: $store.findMatchesCase) {
                    Text("Aa")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .toggleStyle(.button)
                .help("Match case")

                Toggle(isOn: $store.findWholeWord) {
                    Text("ab")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .toggleStyle(.button)
                .help("Whole word")

                if !store.findStatusText.isEmpty {
                    Text(store.findStatusText)
                        .font(.caption)
                        .foregroundStyle(store.findValidationError == nil ? Color.secondary : Color.red)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(minWidth: 74, alignment: .leading)
                }

                if store.findPanelMode != .global {
                    Divider()

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
                        Image(systemName: "selection.pin.in.out")
                    }
                    .help("Select all matches")
                }

                if store.findPanelMode == .replace || store.findPanelMode == .global {
                    Divider()

                    TextField("Replace", text: $store.replaceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, idealWidth: 260, maxWidth: 360)

                    if store.findPanelMode == .global {
                        Button {
                            store.replaceAllGlobalMatches()
                        } label: {
                            Label("Replace All", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .help("Replace all matches in open tabs and the opened folder")
                        .disabled(store.findQuery.isEmpty || store.findValidationError != nil)
                    } else {
                        Button {
                            store.replaceCurrent()
                        } label: {
                            Label("Replace", systemImage: "arrow.turn.down.right")
                        }
                        .disabled(store.findQuery.isEmpty || store.findValidationError != nil)

                        Button {
                            store.replaceAll()
                        } label: {
                            Label("All", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(store.findQuery.isEmpty || store.findValidationError != nil)
                    }
                }

                Spacer()

                if store.findPanelMode == .global {
                    Text(store.globalReplaceStatusText.isEmpty ? "\(store.globalSearchResults.count)" : store.globalReplaceStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(maxWidth: 260, alignment: .trailing)
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
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onAppear {
            isFindFocused = true
        }
        .onChange(of: store.findPanelMode) {
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
            return store.documentCatalogRootPath == nil ? "Find in tabs" : "Find in tabs and folder"
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
        .background(Color(nsColor: .textBackgroundColor))
    }
}
