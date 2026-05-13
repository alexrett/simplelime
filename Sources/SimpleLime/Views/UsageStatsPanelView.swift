import SwiftUI

struct UsageStatsPanelView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.isUsageActivityWatchEnabled {
                        activityWatchBanner
                    }

                    ForEach(store.usageStatsSummaries, id: \.title) { summary in
                        UsageStatsSummaryCard(summary: summary)
                    }

                    if !store.todayUsageTimeline.isEmpty {
                        UsageTimelineSection(entries: store.todayUsageTimeline)
                    }

                    if store.usageStats.isEmpty {
                        emptyState
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 280, idealWidth: 330, maxWidth: 430)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.secondary)
            Text("Stats")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                store.toggleUsageActivityWatch()
            } label: {
                Image(systemName: store.isUsageActivityWatchEnabled ? "stop.circle.fill" : "record.circle")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.isUsageActivityWatchEnabled ? .red : .secondary)
            .help(store.isUsageActivityWatchEnabled ? "Stop activity watch" : "Start activity watch")

            Button {
                store.createTodayTimelogScratch()
            } label: {
                Image(systemName: "doc.badge.plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Create today's timelog scratch")

            Button {
                store.resetUsageStats()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reset stats")

            Button {
                store.toggleStatsPanel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Hide stats")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var activityWatchBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 3) {
                Text("Activity Watch is recording")
                    .font(.system(size: 12, weight: .semibold))
                Text("Frontmost app and window changes are written to the local timelog and stay out of Companion prompts unless Window Context is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No activity yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Edits, opens, saves, exports, unique documents, and active editing time are tracked locally.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct UsageStatsSummaryCard: View {
    let summary: UsageStatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(summary.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                metric("Edits", summary.editCount)
                metric("Added", summary.charactersAdded)
                metric("Removed", summary.charactersRemoved)
                metric("Docs", summary.uniqueDocumentCount)
                metric("Files", summary.uniqueFileCount)
                metric("Scratches", summary.uniqueScratchCount)
                metric("Opens", summary.openCount)
                metric("Saves", summary.saveCount)
                metric("Exports", summary.exportCount)
                metric("Macros", summary.macroCount)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var timeText: String {
        let minutes = summary.activeEditingSeconds / 60
        if minutes < 1 {
            return "\(summary.activeEditingSeconds)s"
        }
        return "\(minutes)m"
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageTimelineSection: View {
    let entries: [UsageTimelineEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today Log")
                .font(.system(size: 13, weight: .semibold))

            ForEach(entries.prefix(20)) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: iconName(for: entry.kind))
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(detailText(for: entry))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func iconName(for kind: UsageTimelineEntry.Kind) -> String {
        switch kind {
        case .edit:
            return "pencil"
        case .open:
            return "folder"
        case .save:
            return "square.and.arrow.down"
        case .export:
            return "square.and.arrow.up"
        case .macro:
            return "wand.and.stars"
        case .app:
            return "macwindow"
        }
    }

    private func detailText(for entry: UsageTimelineEntry) -> String {
        let label: String
        switch entry.kind {
        case .app:
            label = "App"
        default:
            label = entry.kind.rawValue.capitalized
        }

        guard entry.durationSeconds > 0 else {
            return label
        }

        if entry.durationSeconds < 60 {
            return "\(label) · \(entry.durationSeconds)s"
        }

        let minutes = entry.durationSeconds / 60
        return "\(label) · \(minutes)m"
    }
}
