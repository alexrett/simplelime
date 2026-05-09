import SwiftUI

struct SettingsView: View {
    @ObservedObject var workspace: WorkspaceStore
    @AppStorage("ai.copilot.executable") private var copilotExecutable = AIAgentProvider.copilot.defaultExecutable
    @AppStorage("ai.copilot.arguments") private var copilotArguments = AIAgentProvider.copilot.defaultArguments
    @AppStorage("ai.codex.executable") private var codexExecutable = AIAgentProvider.codex.defaultExecutable
    @AppStorage("ai.codex.arguments") private var codexArguments = AIAgentProvider.codex.defaultArguments

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Editor") {
                settingRow("Font Size") {
                    Stepper(value: fontSizeBinding, in: 10...28, step: 1) {
                        Text("\(Int(activeStore.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 54, alignment: .trailing)
                    }
                    .fixedSize()
                }

                settingRow("Word Wrap") {
                    Toggle("", isOn: wrapLinesBinding)
                        .labelsHidden()
                }
            }

            Divider()

            section("AI Agents") {
                agentSettings(
                    title: "Copilot",
                    executable: $copilotExecutable,
                    arguments: $copilotArguments
                )

                Divider()

                agentSettings(
                    title: "Codex",
                    executable: $codexExecutable,
                    arguments: $codexArguments
                )
            }
        }
        .padding(.top, 54)
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
        .frame(width: 560, height: 440, alignment: .topLeading)
    }

    private var activeStore: EditorStore {
        workspace.activeStore ?? workspace.store(for: workspace.primaryGroupID)!
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { activeStore.fontSize },
            set: { activeStore.fontSize = $0 }
        )
    }

    private var wrapLinesBinding: Binding<Bool> {
        Binding(
            get: { activeStore.wrapsLines },
            set: { activeStore.wrapsLines = $0 }
        )
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func agentSettings(
        title: String,
        executable: Binding<String>,
        arguments: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            settingRow("Command") {
                TextField("", text: executable)
                    .textFieldStyle(.roundedBorder)
            }

            settingRow("Arguments") {
                TextField("", text: arguments)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
