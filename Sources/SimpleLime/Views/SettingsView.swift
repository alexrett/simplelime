import AppKit
import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @ObservedObject var workspace: WorkspaceStore
    @AppStorage("ai.copilot.executable") private var copilotExecutable = AIAgentProvider.copilot.defaultExecutable
    @AppStorage("ai.copilot.arguments") private var copilotArguments = AIAgentProvider.copilot.defaultArguments
    @AppStorage("ai.codex.executable") private var codexExecutable = AIAgentProvider.codex.defaultExecutable
    @AppStorage("ai.codex.arguments") private var codexArguments = AIAgentProvider.codex.defaultArguments
    @AppStorage("ai.http.provider") private var httpProviderRawValue = HTTPAIProvider.openAICompatible.rawValue
    @AppStorage("ai.http.baseURL") private var httpBaseURL = HTTPAIConfiguration.defaultBaseURLString
    @AppStorage("ai.http.apiKey") private var httpAPIKey = ""
    @AppStorage("ai.http.model") private var httpModel = HTTPAIConfiguration.defaultModel
    @AppStorage("ai.http.temperature") private var httpTemperature = HTTPAIConfiguration.defaultTemperature
    @AppStorage("ai.http.anthropic.baseURL") private var anthropicBaseURL = HTTPAIProvider.anthropic.defaultBaseURLString
    @AppStorage("ai.http.anthropic.apiKey") private var anthropicAPIKey = ""
    @AppStorage("ai.http.anthropic.model") private var anthropicModel = HTTPAIProvider.anthropic.defaultModel
    @AppStorage("ai.http.anthropic.temperature") private var anthropicTemperature = HTTPAIConfiguration.defaultTemperature
    @AppStorage("ai.http.gemini.baseURL") private var geminiBaseURL = HTTPAIProvider.gemini.defaultBaseURLString
    @AppStorage("ai.http.gemini.apiKey") private var geminiAPIKey = ""
    @AppStorage("ai.http.gemini.model") private var geminiModel = HTTPAIProvider.gemini.defaultModel
    @AppStorage("ai.http.gemini.temperature") private var geminiTemperature = HTTPAIConfiguration.defaultTemperature
    @AppStorage(CompanionSettings.includeSystemContextDefaultsKey) private var companionIncludesSystemContext = CompanionSettings.defaultIncludesSystemContext
    @AppStorage(CompanionSettings.includeAccessibilityContextDefaultsKey) private var companionIncludesAccessibilityContext = CompanionSettings.defaultIncludesAccessibilityContext
    @AppStorage(CompanionSettings.includeScreenTextContextDefaultsKey) private var companionIncludesScreenTextContext = CompanionSettings.defaultIncludesScreenTextContext
    @AppStorage(TerminalConfiguration.shellPathDefaultsKey) private var terminalShellPath = ""
    @AppStorage(TerminalConfiguration.terminalTypeDefaultsKey) private var terminalType = TerminalConfiguration.defaultTerminalType
    @AppStorage(TerminalConfiguration.localeDefaultsKey) private var terminalLocale = TerminalConfiguration.defaultLocale
    @AppStorage(DelimitedTablePreviewConfiguration.maximumRowsDefaultsKey) private var tablePreviewMaximumRows = DelimitedTablePreviewConfiguration.defaultMaximumRows
    @AppStorage(DelimitedTablePreviewConfiguration.maximumColumnsDefaultsKey) private var tablePreviewMaximumColumns = DelimitedTablePreviewConfiguration.defaultMaximumColumns
    @AppStorage(LargeFileConfiguration.generalThresholdDefaultsKey) private var largeFileGeneralThresholdBytes = LargeFileConfiguration.defaultGeneralThresholdBytes
    @AppStorage(LargeFileConfiguration.complexThresholdDefaultsKey) private var largeFileComplexThresholdBytes = LargeFileConfiguration.defaultComplexThresholdBytes
    @AppStorage(LargeFileConfiguration.generalPreviewByteLimitDefaultsKey) private var largeFileGeneralPreviewByteLimit = LargeFileConfiguration.defaultGeneralPreviewByteLimit
    @AppStorage(LargeFileConfiguration.complexPreviewByteLimitDefaultsKey) private var largeFileComplexPreviewByteLimit = LargeFileConfiguration.defaultComplexPreviewByteLimit
    @AppStorage(WhiteboardConfiguration.showsGridDefaultsKey) private var whiteboardShowsGrid = WhiteboardConfiguration.defaultShowsGrid
    @AppStorage(WhiteboardConfiguration.gridSpacingDefaultsKey) private var whiteboardGridSpacing = WhiteboardConfiguration.defaultGridSpacing
    @AppStorage(WhiteboardConfiguration.connectorArrowsDefaultsKey) private var whiteboardConnectorArrows = WhiteboardConfiguration.defaultConnectorArrows
    @AppStorage(WhiteboardConfiguration.connectorRoutingDefaultsKey) private var whiteboardConnectorRoutingRawValue = WhiteboardConfiguration.defaultConnectorRouting.rawValue
    @AppStorage(WhiteboardConfiguration.stickyFillDefaultsKey) private var whiteboardStickyFillRawValue = WhiteboardConfiguration.defaultStickyFill.rawValue
    @AppStorage(AppDataStorage.rootPathDefaultsKey) private var appDataRootPath = ""
    @State private var appDataStorageMessage = ""
    @State private var settingsSearchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsSearchField

                if visibleSettingsSections.isEmpty {
                    Text("No matching settings")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showsSettingsSection(.editor) {
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

                        settingRow("Column Guide") {
                            Stepper(value: columnGuideBinding, in: 0...200, step: 1) {
                                Text(columnGuideLabel)
                                    .monospacedDigit()
                                    .frame(width: 92, alignment: .trailing)
                            }
                            .fixedSize()
                        }

                        settingRow("Source Engine") {
                            Picker("", selection: sourceEditorEngineBinding) {
                                ForEach(SourceEditorEngine.allCases) { engine in
                                    Text(engine.title).tag(engine)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 260)
                            .help("Experimental. Native STTextView remains the default; the CodeMirror WebView path is an opt-in editor-core replacement prototype.")
                        }
                    }
                }

                settingsDivider(after: .editor)

                if showsSettingsSection(.performance) {
                    section("Performance") {
                        settingRow("Table Rows") {
                            Stepper(value: tablePreviewMaximumRowsBinding, in: 500...100_000, step: 500) {
                                Text("\(clampedTablePreviewMaximumRows) rows")
                                    .monospacedDigit()
                                    .frame(width: 112, alignment: .trailing)
                            }
                            .fixedSize()
                        }

                        settingRow("Table Columns") {
                            Stepper(value: tablePreviewMaximumColumnsBinding, in: 4...256, step: 4) {
                                Text("\(clampedTablePreviewMaximumColumns) cols")
                                    .monospacedDigit()
                                    .frame(width: 112, alignment: .trailing)
                            }
                            .fixedSize()
                        }

                        settingRow("Text Threshold") {
                            Stepper(
                                value: largeFileGeneralThresholdBinding,
                                in: LargeFileConfiguration.minimumThresholdBytes...LargeFileConfiguration.maximumThresholdBytes,
                                step: 256 * 1024
                            ) {
                                Text(byteCountLabel(clampedLargeFileGeneralThresholdBytes))
                                    .monospacedDigit()
                                    .frame(width: 112, alignment: .trailing)
                            }
                            .fixedSize()
                        }

                        settingRow("Code Threshold") {
                            Stepper(
                                value: largeFileComplexThresholdBinding,
                                in: LargeFileConfiguration.minimumThresholdBytes...LargeFileConfiguration.maximumThresholdBytes(for: .json),
                                step: 64 * 1024
                            ) {
                                Text(byteCountLabel(clampedLargeFileComplexThresholdBytes))
                                    .monospacedDigit()
                                    .frame(width: 112, alignment: .trailing)
                            }
                            .fixedSize()
                        }

                        settingRow("Text Chunk") {
                            Stepper(
                                value: largeFileGeneralPreviewBinding,
                                in: LargeFileConfiguration.minimumPreviewByteLimit...LargeFileConfiguration.maximumPreviewByteLimit,
                                step: 64 * 1024
                            ) {
                                Text(byteCountLabel(clampedLargeFileGeneralPreviewByteLimit))
                                    .monospacedDigit()
                                    .frame(width: 112, alignment: .trailing)
                            }
                            .fixedSize()
                        }

                        settingRow("Code Chunk") {
                            Stepper(
                                value: largeFileComplexPreviewBinding,
                                in: LargeFileConfiguration.minimumPreviewByteLimit...LargeFileConfiguration.maximumPreviewByteLimit,
                                step: 16 * 1024
                            ) {
                                Text(byteCountLabel(clampedLargeFileComplexPreviewByteLimit))
                                    .monospacedDigit()
                                    .frame(width: 112, alignment: .trailing)
                            }
                            .fixedSize()
                        }
                    }
                }

                settingsDivider(after: .performance)

                if showsSettingsSection(.whiteboard) {
                    section("Whiteboard") {
                        settingRow("Grid") {
                            Toggle("", isOn: $whiteboardShowsGrid)
                                .labelsHidden()
                        }

                        settingRow("Grid Size") {
                            Stepper(
                                value: whiteboardGridSpacingBinding,
                                in: WhiteboardConfiguration.minimumGridSpacing...WhiteboardConfiguration.maximumGridSpacing,
                                step: 4
                            ) {
                                Text("\(clampedWhiteboardGridSpacing) px")
                                    .monospacedDigit()
                                    .frame(width: 82, alignment: .trailing)
                            }
                            .fixedSize()
                        }

                        settingRow("Sticky Fill") {
                            Picker("", selection: whiteboardStickyFillBinding) {
                                ForEach(WhiteboardFill.allCases) { fill in
                                    Text(fill.rawValue.capitalized).tag(fill.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190, alignment: .leading)
                        }

                        settingRow("Connector Arrow") {
                            Toggle("", isOn: $whiteboardConnectorArrows)
                                .labelsHidden()
                        }

                        settingRow("Connector Route") {
                            Picker("", selection: whiteboardConnectorRoutingBinding) {
                                ForEach(WhiteboardConnectorRouting.allCases) { routing in
                                    Text(routing.displayName).tag(routing.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190, alignment: .leading)
                        }
                    }
                }

                settingsDivider(after: .whiteboard)

                if showsSettingsSection(.storage) {
                    section("Storage") {
                        settingRow("Data Root") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(currentAppDataRootPath)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(currentAppDataRootPath)

                                HStack(spacing: 8) {
                                    Button("Choose...") {
                                        chooseAppDataRoot()
                                    }

                                    Button("Use iCloud Drive") {
                                        useICloudDriveRoot()
                                    }

                                    Button("Default") {
                                        resetAppDataRoot()
                                    }
                                }

                                HStack(spacing: 8) {
                                    Text(workspace.appDataSyncStatus ?? "External app-data changes are checked periodically.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    Button("Check Now") {
                                        checkAppDataRootForChanges()
                                    }
                                }

                                if !appDataStorageMessage.isEmpty {
                                    Text(appDataStorageMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                settingsDivider(after: .storage)

                if showsSettingsSection(.aiAgents) {
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

                        Divider()

                        httpAISettings()

                        Divider()

                        settingRow("Auto Task Inference") {
                            Toggle("", isOn: taskAIAutoInferenceBinding)
                                .labelsHidden()
                        }

                        Divider()

                        settingRow("Companion Window Context") {
                            Toggle("", isOn: $companionIncludesSystemContext)
                                .labelsHidden()
                                .onChange(of: companionIncludesSystemContext) { _, _ in
                                    activeStore.refreshCompanionSystemContextMonitorForSettingsChange()
                                }
                        }

                        settingRow("Companion App Selection") {
                            HStack(spacing: 8) {
                                Toggle("", isOn: $companionIncludesAccessibilityContext)
                                    .labelsHidden()
                                    .onChange(of: companionIncludesAccessibilityContext) { _, _ in
                                        activeStore.refreshCompanionSystemContextMonitorForSettingsChange()
                                    }

                                Button("Request Access") {
                                    requestAccessibilityAccess()
                                }
                            }
                        }

                        settingRow("Companion Screen Text") {
                            HStack(spacing: 8) {
                                Toggle("", isOn: $companionIncludesScreenTextContext)
                                    .labelsHidden()
                                    .onChange(of: companionIncludesScreenTextContext) { _, _ in
                                        activeStore.refreshCompanionSystemContextMonitorForSettingsChange()
                                    }

                                Button("Request Access") {
                                    requestScreenCaptureAccess()
                                }
                            }
                        }
                    }
                }

                settingsDivider(after: .aiAgents)

                if showsSettingsSection(.terminal) {
                    section("Terminal") {
                        settingRow("Shell") {
                            HStack(spacing: 8) {
                                TextField(TerminalConfiguration.currentShellPath(), text: $terminalShellPath)
                                    .textFieldStyle(.roundedBorder)

                                Button("Default") {
                                    terminalShellPath = ""
                                }
                            }
                        }

                        settingRow("TERM") {
                            HStack(spacing: 8) {
                                Picker("", selection: terminalTypeBinding) {
                                    ForEach(TerminalConfiguration.supportedTerminalTypes, id: \.self) { value in
                                        Text(value).tag(value)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 190, alignment: .leading)

                                Button("Default") {
                                    terminalType = TerminalConfiguration.defaultTerminalType
                                }
                            }
                        }

                        settingRow("Locale") {
                            HStack(spacing: 8) {
                                TextField(TerminalConfiguration.defaultLocale, text: terminalLocaleBinding)
                                    .textFieldStyle(.roundedBorder)

                                Button("Default") {
                                    terminalLocale = TerminalConfiguration.defaultLocale
                                }
                            }
                        }
                    }
                }

                settingsDivider(after: .terminal)

                if showsSettingsSection(.automation) {
                    section("Automation") {
                        settingRow("Auto Meeting Scribe") {
                            Toggle("", isOn: voiceScribeAutoMeetingBinding)
                                .labelsHidden()
                        }

                        settingRow("Local Bridge") {
                            Text(workspace.localAutomationBridgeStatus ?? "Off")
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(.top, 54)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .frame(width: 620, height: 760, alignment: .topLeading)
    }

    private var activeStore: EditorStore {
        workspace.activeStore ?? workspace.store(for: workspace.primaryGroupID)!
    }

    private var settingsSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search settings", text: $settingsSearchText)
                .textFieldStyle(.plain)

            if !settingsSearchText.isEmpty {
                Button {
                    settingsSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleSettingsSections: [SettingsSearchSection] {
        SettingsSearchCatalog.visibleSections(matching: settingsSearchText)
    }

    private func showsSettingsSection(_ section: SettingsSearchSection) -> Bool {
        visibleSettingsSections.contains(section)
    }

    @ViewBuilder
    private func settingsDivider(after section: SettingsSearchSection) -> some View {
        if hasVisibleSettingsSection(after: section) {
            Divider()
        }
    }

    private func hasVisibleSettingsSection(after section: SettingsSearchSection) -> Bool {
        guard let index = SettingsSearchSection.allCases.firstIndex(of: section) else {
            return false
        }

        return SettingsSearchSection.allCases[(index + 1)...].contains { showsSettingsSection($0) }
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

    private var columnGuideBinding: Binding<Int> {
        Binding(
            get: { activeStore.columnGuide },
            set: { activeStore.columnGuide = $0 }
        )
    }

    private var sourceEditorEngineBinding: Binding<SourceEditorEngine> {
        Binding(
            get: { activeStore.sourceEditorEngine },
            set: { activeStore.sourceEditorEngine = $0 }
        )
    }

    private var taskAIAutoInferenceBinding: Binding<Bool> {
        Binding(
            get: { activeStore.isTaskAIAutoInferenceEnabled },
            set: { activeStore.isTaskAIAutoInferenceEnabled = $0 }
        )
    }

    private var voiceScribeAutoMeetingBinding: Binding<Bool> {
        Binding(
            get: { activeStore.isVoiceScribeAutoMeetingEnabled },
            set: { activeStore.isVoiceScribeAutoMeetingEnabled = $0 }
        )
    }

    private var columnGuideLabel: String {
        activeStore.columnGuide == 0 ? "Off" : "\(activeStore.columnGuide) cols"
    }

    private var clampedTablePreviewMaximumRows: Int {
        DelimitedTablePreviewConfiguration.clampedMaximumRows(tablePreviewMaximumRows)
    }

    private var clampedTablePreviewMaximumColumns: Int {
        DelimitedTablePreviewConfiguration.clampedMaximumColumns(tablePreviewMaximumColumns)
    }

    private var tablePreviewMaximumRowsBinding: Binding<Int> {
        Binding(
            get: {
                clampedTablePreviewMaximumRows
            },
            set: {
                tablePreviewMaximumRows = DelimitedTablePreviewConfiguration.clampedMaximumRows($0)
            }
        )
    }

    private var tablePreviewMaximumColumnsBinding: Binding<Int> {
        Binding(
            get: {
                clampedTablePreviewMaximumColumns
            },
            set: {
                tablePreviewMaximumColumns = DelimitedTablePreviewConfiguration.clampedMaximumColumns($0)
            }
        )
    }

    private var clampedLargeFileGeneralThresholdBytes: Int {
        LargeFileConfiguration.clampedThresholdBytes(largeFileGeneralThresholdBytes)
    }

    private var clampedLargeFileComplexThresholdBytes: Int {
        LargeFileConfiguration.clampedThresholdBytes(largeFileComplexThresholdBytes, for: .json)
    }

    private var clampedLargeFileGeneralPreviewByteLimit: Int {
        LargeFileConfiguration.clampedPreviewByteLimit(largeFileGeneralPreviewByteLimit)
    }

    private var clampedLargeFileComplexPreviewByteLimit: Int {
        LargeFileConfiguration.clampedPreviewByteLimit(largeFileComplexPreviewByteLimit)
    }

    private var largeFileGeneralThresholdBinding: Binding<Int> {
        Binding(
            get: { clampedLargeFileGeneralThresholdBytes },
            set: { largeFileGeneralThresholdBytes = LargeFileConfiguration.clampedThresholdBytes($0) }
        )
    }

    private var largeFileComplexThresholdBinding: Binding<Int> {
        Binding(
            get: { clampedLargeFileComplexThresholdBytes },
            set: { largeFileComplexThresholdBytes = LargeFileConfiguration.clampedThresholdBytes($0, for: .json) }
        )
    }

    private var largeFileGeneralPreviewBinding: Binding<Int> {
        Binding(
            get: { clampedLargeFileGeneralPreviewByteLimit },
            set: { largeFileGeneralPreviewByteLimit = LargeFileConfiguration.clampedPreviewByteLimit($0) }
        )
    }

    private var largeFileComplexPreviewBinding: Binding<Int> {
        Binding(
            get: { clampedLargeFileComplexPreviewByteLimit },
            set: { largeFileComplexPreviewByteLimit = LargeFileConfiguration.clampedPreviewByteLimit($0) }
        )
    }

    private var clampedWhiteboardGridSpacing: Int {
        WhiteboardConfiguration.clampedGridSpacing(whiteboardGridSpacing)
    }

    private var whiteboardGridSpacingBinding: Binding<Int> {
        Binding(
            get: { clampedWhiteboardGridSpacing },
            set: { whiteboardGridSpacing = WhiteboardConfiguration.clampedGridSpacing($0) }
        )
    }

    private var whiteboardConnectorRoutingBinding: Binding<String> {
        Binding(
            get: { WhiteboardConfiguration.connectorRouting(rawValue: whiteboardConnectorRoutingRawValue).rawValue },
            set: { whiteboardConnectorRoutingRawValue = WhiteboardConfiguration.connectorRouting(rawValue: $0).rawValue }
        )
    }

    private var whiteboardStickyFillBinding: Binding<String> {
        Binding(
            get: { WhiteboardConfiguration.stickyFill(rawValue: whiteboardStickyFillRawValue).rawValue },
            set: { whiteboardStickyFillRawValue = WhiteboardConfiguration.stickyFill(rawValue: $0).rawValue }
        )
    }

    private var terminalTypeBinding: Binding<String> {
        Binding(
            get: {
                TerminalConfiguration.sanitizedTerminalType(terminalType)
            },
            set: {
                terminalType = TerminalConfiguration.sanitizedTerminalType($0)
            }
        )
    }

    private var terminalLocaleBinding: Binding<String> {
        Binding(
            get: {
                terminalLocale
            },
            set: {
                terminalLocale = $0
            }
        )
    }

    private func byteCountLabel(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = bytes < 1024 * 1024 ? .useKB : [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private var currentAppDataRootURL: URL {
        AppDataStorage.currentRootURL()
    }

    private var currentAppDataRootPath: String {
        currentAppDataRootURL.path
    }

    private func chooseAppDataRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentAppDataRootURL
        panel.prompt = "Use"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyAppDataRoot(url)
    }

    private func useICloudDriveRoot() {
        guard let url = AppDataStorage.suggestedICloudDriveRootURL() else {
            appDataStorageMessage = "iCloud Drive folder is not available."
            return
        }

        applyAppDataRoot(url)
    }

    private func resetAppDataRoot() {
        let previousRoot = currentAppDataRootURL
        let defaultRoot = AppDataStorage.defaultRootURL()

        do {
            workspace.persistNow()
            try AppDataStorage.copyExistingData(from: previousRoot, to: defaultRoot)
            AppDataStorage.resetCustomRoot()
            appDataRootPath = ""
            workspace.reloadAppDataRoot()
            appDataStorageMessage = "Using default local storage. Existing data was merged."
        } catch {
            appDataStorageMessage = "Could not merge app data: \(error.localizedDescription)"
        }
    }

    private func checkAppDataRootForChanges() {
        if workspace.reloadAppDataRootIfChanged() {
            appDataStorageMessage = workspace.appDataSyncStatus ?? "App data reloaded from disk."
        } else if let status = workspace.appDataSyncStatus,
                  status.hasPrefix("App data changed on disk") {
            appDataStorageMessage = status
        } else {
            appDataStorageMessage = "Storage is current."
        }
    }

    private func applyAppDataRoot(_ url: URL) {
        let previousRoot = currentAppDataRootURL
        let targetRoot = url.standardizedFileURL

        do {
            workspace.persistNow()
            try AppDataStorage.copyExistingData(from: previousRoot, to: targetRoot)
            AppDataStorage.setCustomRootURL(targetRoot)
            appDataRootPath = targetRoot.path
            workspace.reloadAppDataRoot()
            appDataStorageMessage = "Using this storage root. Existing data was merged."
        } catch {
            appDataStorageMessage = "Could not merge app data: \(error.localizedDescription)"
        }
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

    private func httpAISettings() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HTTP LLM")
                .font(.subheadline.weight(.semibold))

            settingRow("Default") {
                Picker("", selection: $httpProviderRawValue) {
                    ForEach(HTTPAIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 210, alignment: .leading)
            }

            httpProviderSettings(
                title: "OpenAI-compatible",
                baseURL: $httpBaseURL,
                apiKey: $httpAPIKey,
                model: $httpModel,
                temperature: httpTemperatureBinding,
                temperatureValue: httpTemperature
            )

            Divider()

            httpProviderSettings(
                title: "Anthropic",
                baseURL: $anthropicBaseURL,
                apiKey: $anthropicAPIKey,
                model: $anthropicModel,
                temperature: anthropicTemperatureBinding,
                temperatureValue: anthropicTemperature
            )

            Divider()

            httpProviderSettings(
                title: "Gemini",
                baseURL: $geminiBaseURL,
                apiKey: $geminiAPIKey,
                model: $geminiModel,
                temperature: geminiTemperatureBinding,
                temperatureValue: geminiTemperature
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requestAccessibilityAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestScreenCaptureAccess() {
        _ = CGRequestScreenCaptureAccess()
    }

    private func httpProviderSettings(
        title: String,
        baseURL: Binding<String>,
        apiKey: Binding<String>,
        model: Binding<String>,
        temperature: Binding<Double>,
        temperatureValue: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            settingRow("Base URL") {
                TextField("", text: baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            settingRow("API Key") {
                SecureField("", text: apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            settingRow("Model") {
                TextField("", text: model)
                    .textFieldStyle(.roundedBorder)
            }

            settingRow("Temperature") {
                Stepper(value: temperature, in: 0...2, step: 0.1) {
                    Text(temperatureValue.formatted(.number.precision(.fractionLength(1))))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .fixedSize()
            }
        }
    }

    private var httpTemperatureBinding: Binding<Double> {
        Binding(
            get: { httpTemperature },
            set: { httpTemperature = min(max($0, 0), 2) }
        )
    }

    private var anthropicTemperatureBinding: Binding<Double> {
        Binding(
            get: { anthropicTemperature },
            set: { anthropicTemperature = min(max($0, 0), 2) }
        )
    }

    private var geminiTemperatureBinding: Binding<Double> {
        Binding(
            get: { geminiTemperature },
            set: { geminiTemperature = min(max($0, 0), 2) }
        )
    }
}
