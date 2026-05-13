import SwiftUI

struct TaskBoardPanelView: View {
    @ObservedObject var store: EditorStore
    @State private var draft = ""
    @State private var draftScope: ManualTaskScope = .workspace

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            composer
            Divider()
            board
        }
        .frame(minWidth: 320, idealWidth: 520, maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
            Text("Tasks")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                store.runAITaskInference(scope: draftScope)
            } label: {
                Image(systemName: store.isTaskAIInferenceRunning ? "sparkles" : "wand.and.stars")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Infer tasks with AI")
            .disabled(store.isTaskAIInferenceRunning)

            Button {
                store.toggleTasksPanel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Hide tasks")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("New task", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addTask)

                Button {
                    addTask()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Add task")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Picker("Task scope", selection: $draftScope) {
                ForEach(ManualTaskScope.allCases) { scope in
                    Label(scope.title, systemImage: scope.systemImage)
                        .tag(scope)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .help("Choose whether the task appears only in this workspace or globally on this Mac")

            if let status = store.taskAIInferenceStatus {
                HStack(spacing: 6) {
                    if store.isTaskAIInferenceRunning {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                            .frame(width: 12, height: 12)
                    }
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
    }

    private var board: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(TaskBoardStatus.allCases) { status in
                        TaskBoardColumnView(
                            status: status,
                            cards: store.taskCards(for: status),
                            onManualStatus: { task, newStatus in
                                store.updateManualTask(task.id, status: newStatus)
                            },
                            onDeleteManual: { task in
                                store.deleteManualTask(task.id)
                            },
                            onDetectedStatus: { task, newStatus in
                                store.updateDetectedTask(task, status: newStatus)
                            },
                            onOpenDetected: { task in
                                store.openDetectedTask(task)
                            }
                        )
                        .frame(width: 168)
                    }
                }
                .padding(12)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .defaultScrollAnchor(.topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func addTask() {
        let text = draft
        draft = ""
        store.addManualTask(title: text, scope: draftScope)
    }
}

private struct TaskBoardColumnView: View {
    let status: TaskBoardStatus
    let cards: [TaskBoardCard]
    let onManualStatus: (ManualTask, TaskBoardStatus) -> Void
    let onDeleteManual: (ManualTask) -> Void
    let onDetectedStatus: (DetectedTask, TaskBoardStatus) -> Void
    let onOpenDetected: (DetectedTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(.secondary)
                Text(status.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(cards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if cards.isEmpty {
                emptyState
            } else {
                ForEach(cards) { card in
                    TaskBoardCardView(
                        card: card,
                        onManualStatus: onManualStatus,
                        onDeleteManual: onDeleteManual,
                        onDetectedStatus: onDetectedStatus,
                        onOpenDetected: onOpenDetected
                    )
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        Text("No tasks")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
    }
}

private struct TaskBoardCardView: View {
    let card: TaskBoardCard
    let onManualStatus: (ManualTask, TaskBoardStatus) -> Void
    let onDeleteManual: (ManualTask) -> Void
    let onDetectedStatus: (DetectedTask, TaskBoardStatus) -> Void
    let onOpenDetected: (DetectedTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.system(size: 12))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            switch card {
            case .manual(let task):
                manualFooter(task)
            case .detected(let task):
                detectedFooter(task)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func manualFooter(_ task: ManualTask) -> some View {
        HStack(spacing: 6) {
            Label(task.scope.title, systemImage: task.scope.systemImage)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .help("\(task.scope.title) manual task")

            Spacer()
            statusMenu { status in
                onManualStatus(task, status)
            }

            Button {
                onDeleteManual(task)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete task")
        }
        .font(.caption)
    }

    private func detectedFooter(_ task: DetectedTask) -> some View {
        HStack(spacing: 6) {
            Button {
                onOpenDetected(task)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(task.sourceLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(task.filePath ?? task.sourceLabel)

            Spacer()
            statusMenu { status in
                onDetectedStatus(task, status)
            }
        }
        .font(.caption)
    }

    private func statusMenu(_ action: @escaping (TaskBoardStatus) -> Void) -> some View {
        Menu {
            ForEach(TaskBoardStatus.allCases) { status in
                Button(status.title) {
                    action(status)
                }
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Move task")
    }
}
