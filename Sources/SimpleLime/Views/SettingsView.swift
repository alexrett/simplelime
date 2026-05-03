import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: EditorStore
    @AppStorage("ai.copilot.executable") private var copilotExecutable = AIAgentProvider.copilot.defaultExecutable
    @AppStorage("ai.copilot.arguments") private var copilotArguments = AIAgentProvider.copilot.defaultArguments
    @AppStorage("ai.codex.executable") private var codexExecutable = AIAgentProvider.codex.defaultExecutable
    @AppStorage("ai.codex.arguments") private var codexArguments = AIAgentProvider.codex.defaultArguments

    var body: some View {
        Form {
            Section("Editor") {
                HStack {
                    Text("Editor Font Size")
                    Spacer()
                    Stepper(value: $store.fontSize, in: 10...28, step: 1) {
                        Text("\(Int(store.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }

            Section("AI Agents") {
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
        .padding(20)
        .frame(width: 520)
    }

    private func agentSettings(title: String, executable: Binding<String>, arguments: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Command")
                        .foregroundStyle(.secondary)
                    TextField("", text: executable)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Arguments")
                        .foregroundStyle(.secondary)
                    TextField("", text: arguments)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}
