import SwiftUI

struct POModePanelView: View {
    @ObservedObject var store: EditorStore
    @State private var query = ""

    private var report: DocumentFolderAnalysis.Report? {
        store.poModeReport
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let report {
                search
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary(report)
                        aiInterpretation()
                        mindMap(report)
                        kanban(report)
                        gaps(report)
                        featureDocs(report)
                        searchIndex(report)
                    }
                    .padding(12)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 320, idealWidth: 460, maxWidth: 720)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
            Text("PO Mode")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                store.refreshPOModeAnalysisForDocumentCatalog()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Refresh analysis")

            Button {
                store.runPOModeAIInterpretationForDocumentCatalog()
            } label: {
                Image(systemName: store.isPOModeAIInterpretationRunning ? "sparkles" : "wand.and.stars")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(store.isPOModeAIInterpretationRunning)
            .help("Interpret with AI")

            Button {
                store.addPOModeGapsAsTasks()
            } label: {
                Image(systemName: "checklist")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled((report?.gapCount ?? 0) == 0)
            .help("Add PO gaps as tasks")

            Button {
                store.generatePOModeBriefForDocumentCatalog()
            } label: {
                Image(systemName: "doc.badge.plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Create Markdown brief")

            Button {
                store.hidePOModePanel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Hide PO mode")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search analysis", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No PO analysis")
                .font(.headline)
            Button("Analyze Folder") {
                store.refreshPOModeAnalysisForDocumentCatalog()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
    }

    private func summary(_ report: DocumentFolderAnalysis.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Summary", systemName: "chart.bar.doc.horizontal")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                metric("Docs", report.documentCount)
                metric("Headings", report.headingCount)
                metric("Tasks", report.taskCount)
                metric("Gaps", report.gapCount)
            }
        }
    }

    private func aiInterpretation() -> some View {
        Group {
            if store.isPOModeAIInterpretationRunning ||
                store.poModeAIInterpretation != nil ||
                store.poModeAIInterpretationStatus != nil {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("AI Interpretation", systemName: "sparkles")
                    if store.isPOModeAIInterpretationRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(store.poModeAIInterpretationStatus ?? "Interpreting...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    } else if let interpretation = store.poModeAIInterpretation {
                        Text(interpretation)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    } else if let status = store.poModeAIInterpretationStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func mindMap(_ report: DocumentFolderAnalysis.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Mind Map", systemName: "map")
            if filteredSummaries(report).isEmpty {
                emptyText("No matching documents")
            } else {
                ForEach(filteredSummaries(report), id: \.file.relativePath) { summary in
                    disclosure(summary)
                }
            }
        }
    }

    private func disclosure(_ summary: DocumentFolderAnalysis.FileSummary) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if summary.headings.isEmpty {
                    emptyText("No headings")
                } else {
                    ForEach(filteredReferences(summary.headings)) { reference in
                        referenceButton(reference, systemName: "number")
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(summary.file.relativePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(summary.headings.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func kanban(_ report: DocumentFolderAnalysis.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Kanban", systemName: "checklist")
            HStack(alignment: .top, spacing: 8) {
                ForEach(TaskBoardStatus.allCases) { status in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(status.title, systemImage: status.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        let tasks = filteredReferences(report.tasks(for: status))
                        if tasks.isEmpty {
                            emptyText("None")
                        } else {
                            ForEach(Array(tasks.prefix(12))) { reference in
                                referenceButton(reference, systemName: "arrow.turn.down.right")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(9)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func gaps(_ report: DocumentFolderAnalysis.Report) -> some View {
        let gaps = filteredReferences(report.gaps)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Gaps", systemName: "exclamationmark.triangle")
            if gaps.isEmpty {
                emptyText("No matching gaps")
            } else {
                ForEach(Array(gaps.prefix(30))) { reference in
                    referenceButton(reference, systemName: "quote.bubble")
                }
            }
        }
    }

    private func featureDocs(_ report: DocumentFolderAnalysis.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Feature Docs", systemName: "tablecells")
            ForEach(filteredSummaries(report), id: \.file.relativePath) { summary in
                Button {
                    store.openFile(at: summary.file.url)
                } label: {
                    HStack(spacing: 8) {
                        Text(summary.file.relativePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(summary.headings.count)H")
                        Text("\(summary.taskCount)T")
                        Text("\(summary.gaps.count)G")
                    }
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(summary.file.url.path)
            }
        }
    }

    private func searchIndex(_ report: DocumentFolderAnalysis.Report) -> some View {
        let terms = report.searchTerms.filter { matchesQuery($0.term) || trimmedQuery.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Search Index", systemName: "text.magnifyingglass")
            if terms.isEmpty {
                emptyText("No matching terms")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                    ForEach(terms) { term in
                        HStack(spacing: 4) {
                            Text(term.term)
                                .lineLimit(1)
                            Spacer()
                            Text("\(term.count)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, systemName: String) -> some View {
        Label(title, systemImage: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func referenceButton(_ reference: DocumentFolderAnalysis.LineReference, systemName: String) -> some View {
        Button {
            store.openPOModeReference(reference)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: systemName)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.title)
                        .lineLimit(2)
                    Text("\(reference.relativePath):\(reference.lineNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .padding(7)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(reference.excerpt)
    }

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
    }

    private func filteredSummaries(_ report: DocumentFolderAnalysis.Report) -> [DocumentFolderAnalysis.FileSummary] {
        guard !trimmedQuery.isEmpty else { return report.summaries }
        return report.summaries.filter { summary in
            matchesQuery(summary.file.relativePath) ||
                summary.headings.contains(where: matchesQuery) ||
                summary.gaps.contains(where: matchesQuery) ||
                TaskBoardStatus.allCases.contains { status in
                    (summary.tasks[status] ?? []).contains(where: matchesQuery)
                }
        }
    }

    private func filteredReferences(_ references: [DocumentFolderAnalysis.LineReference]) -> [DocumentFolderAnalysis.LineReference] {
        guard !trimmedQuery.isEmpty else { return references }
        return references.filter(matchesQuery)
    }

    private func matchesQuery(_ reference: DocumentFolderAnalysis.LineReference) -> Bool {
        matchesQuery(reference.title) ||
            matchesQuery(reference.relativePath) ||
            matchesQuery(reference.excerpt)
    }

    private func matchesQuery(_ value: String) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        return value.localizedCaseInsensitiveContains(trimmedQuery)
    }

}
