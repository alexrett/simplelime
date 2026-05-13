import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

private struct OpenedTextFile {
    let text: String
    let language: EditorLanguage
    let isLargeFileMode: Bool
    let fileSizeBytes: Int64?
    let largeFilePreviewStartOffsetBytes: Int64?
    let largeFilePreviewByteCount: Int?
}

private struct LargeFilePreview {
    let text: String
    let startOffsetBytes: Int64
    let byteCount: Int
}

struct LargeFileEditingCapability: Equatable {
    enum State: String, Equatable {
        case normalBuffer
        case extractedChunk
        case readOnlyExactPreview
        case editablePreviewChunk
        case unsafePreviewBoundary
        case unavailable
    }

    let state: State
    let status: String
    let detail: String
    let canEnableInPlaceChunkEditing: Bool
    let canSaveChunkBack: Bool
    let canEditLoadedText: Bool

    var saveUnavailableMessage: String {
        switch state {
        case .normalBuffer:
            return "This buffer is not linked to an editable large-file chunk."
        case .extractedChunk, .editablePreviewChunk:
            return "This chunk is not linked to a source range that can be saved back."
        case .readOnlyExactPreview:
            return "Large-file previews are read-only. Enable chunk editing or open the current chunk as a scratch before saving."
        case .unsafePreviewBoundary:
            return "This large-file chunk cannot be saved because the preview cuts through a text encoding boundary."
        case .unavailable:
            return "Open a large-file preview before saving a chunk."
        }
    }

    var editUnavailableMessage: String {
        switch state {
        case .normalBuffer:
            return "Open a large-file preview before editing a chunk."
        case .extractedChunk:
            return "This extracted chunk is already editable."
        case .readOnlyExactPreview:
            return "The current large-file preview chunk can be made editable."
        case .editablePreviewChunk:
            return "Current chunk is already editable. Cmd-S saves only this chunk back to the source file."
        case .unsafePreviewBoundary:
            return "Chunk editing is disabled because this preview cuts through a text encoding boundary."
        case .unavailable:
            return "Open a large-file preview before editing a chunk."
        }
    }
}

private struct LargeFileSearchResult {
    let byteOffset: Int64
}

private enum DiffInputError: LocalizedError {
    case largePreviewMissingSource
    case sourceReadFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .largePreviewMissingSource:
            return "Large-file previews without a source file path cannot be diffed."
        case .sourceReadFailed(let title, let message):
            return "Could not read \(title) for diff: \(message)"
        }
    }
}

private enum LargeFileChunkWriteError: LocalizedError {
    case invalidRange
    case couldNotCreateTemporaryFile
    case couldNotReplaceSource

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "The saved chunk range no longer matches the source file."
        case .couldNotCreateTemporaryFile:
            return "Could not create a temporary file next to the source file."
        case .couldNotReplaceSource:
            return "Could not replace the source file with the edited chunk."
        }
    }
}

private struct VoiceScribeAudioSourceResolution {
    let audioSource: VoiceScribeAudioSource
    let detectedMeetingApp: VoiceScribeMeetingAppDetection?
    let status: String
}

typealias TerminalOutputObserver = @MainActor ([UInt8]) -> Void

struct PendingCloseBuffer: Equatable {
    let id: UUID
    let displayTitle: String

    init(id: UUID, displayTitle: String) {
        self.id = id
        self.displayTitle = displayTitle
    }
}

struct CompanionSystemContext: Equatable {
    var frontmostApplicationName: String
    var frontmostBundleIdentifier: String?
    var frontmostWindowTitle: String? = nil
    var focusedElementRole: String? = nil
    var focusedElementTitle: String? = nil
    var selectedText: String? = nil
    var focusedValue: String? = nil
    var screenText: String? = nil
}

@MainActor
final class EditorStore: ObservableObject {
    private static let maxPinnedMacroButtons = 6

    @Published var buffers: [EditorBuffer]
    @Published var selectedBufferID: UUID? {
        didSet {
            guard selectedBufferID != oldValue else { return }
            scheduleCompanionAutoScanIfNeeded(for: selectedBufferID)
            scheduleTaskAIAutoInferenceIfNeeded(for: selectedBufferID)
        }
    }
    @Published var findQuery = "" {
        didSet {
            if findQuery != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var replaceText = "" {
        didSet {
            if replaceText != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var findUsesRegex = false {
        didSet {
            if findUsesRegex != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var findMatchesCase = false {
        didSet {
            if findMatchesCase != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var findWholeWord = false {
        didSet {
            if findWholeWord != oldValue {
                globalReplaceStatusText = ""
            }
        }
    }
    @Published var globalReplaceStatusText = ""
    @Published var findPanelMode: FindPanelMode = .hidden
    @Published var isPreviewVisible = false
    @Published var isOutlineVisible: Bool {
        didSet {
            UserDefaults.standard.set(isOutlineVisible, forKey: Self.outlineDefaultsKey)
        }
    }
    @Published var isFocusModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isFocusModeEnabled, forKey: Self.focusModeDefaultsKey)
        }
    }
    @Published var isTypewriterModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTypewriterModeEnabled, forKey: Self.typewriterModeDefaultsKey)
        }
    }
    @Published var isMiniMapVisible: Bool {
        didSet {
            UserDefaults.standard.set(isMiniMapVisible, forKey: Self.miniMapDefaultsKey)
        }
    }
    @Published var isWysiwygModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWysiwygModeEnabled, forKey: Self.wysiwygModeDefaultsKey)
        }
    }
    @Published var isDocumentCatalogVisible: Bool {
        didSet {
            UserDefaults.standard.set(isDocumentCatalogVisible, forKey: Self.documentCatalogVisibleDefaultsKey)
        }
    }
    @Published var documentCatalogRootPath: String? {
        didSet {
            if let documentCatalogRootPath {
                UserDefaults.standard.set(documentCatalogRootPath, forKey: Self.documentCatalogRootDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.documentCatalogRootDefaultsKey)
            }
        }
    }
    @Published var documentCatalogNodes: [DocumentCatalogNode] = []
    @Published var documentCatalogQuery = ""
    @Published var isCommandPaletteVisible = false
    @Published var fontSize: Double = 14
    @Published var wrapsLines: Bool {
        didSet {
            UserDefaults.standard.set(wrapsLines, forKey: Self.wrapsLinesDefaultsKey)
        }
    }
    @Published var columnGuide: Int {
        didSet {
            columnGuide = min(max(0, columnGuide), 200)
            UserDefaults.standard.set(columnGuide, forKey: Self.columnGuideDefaultsKey)
        }
    }
    @Published var sourceEditorEngine: SourceEditorEngine {
        didSet {
            UserDefaults.standard.set(sourceEditorEngine.rawValue, forKey: Self.sourceEditorEngineDefaultsKey)
        }
    }
    @Published var lastError: String?
    @Published var pendingCloseBuffer: PendingCloseBuffer?
    @Published var isAIPanelVisible = false
    @Published var isNetworkPanelVisible = false
    @Published var isTasksPanelVisible = false
    @Published var isStatsPanelVisible = false
    @Published var isMacrosPanelVisible = false
    @Published var isCommentsPanelVisible = false
    @Published var isCompanionPanelVisible = false
    @Published var isPOModePanelVisible = false
    @Published var isScribePanelVisible = false
    @Published var isTerminalPanelVisible = false
    @Published var voiceScribeTitle = "Voice Transcript"
    @Published var voiceScribeSpeaker = ""
    @Published var voiceScribeAudioSource: VoiceScribeAudioSource = .microphone
    @Published var isVoiceScribeCommandCaptureEnabled = true
    @Published var isVoiceScribeAutoMeetingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVoiceScribeAutoMeetingEnabled, forKey: Self.voiceScribeAutoMeetingDefaultsKey)
            if isVoiceScribeAutoMeetingEnabled {
                showScribePanel()
                startVoiceScribeAutoMeetingMonitor()
                checkVoiceScribeAutoMeetingNow()
            } else {
                stopVoiceScribeAutoMeetingMonitor(clearStatus: true)
            }
        }
    }
    @Published private(set) var voiceScribeDetectedMeetingApp: VoiceScribeMeetingAppDetection?
    @Published var isCompanionAutoScanEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCompanionAutoScanEnabled, forKey: Self.companionAutoScanDefaultsKey)
            if isCompanionAutoScanEnabled {
                showCompanionPanel()
                startCompanionSystemContextMonitoring()
                scheduleCompanionAutoScanIfNeeded(for: selectedBufferID)
            } else {
                companionAutoScanTask?.cancel()
                companionAutoScanTask = nil
                lastCompanionSystemContextSignature = nil
                if isUsageActivityWatchEnabled {
                    startCompanionSystemContextMonitoring()
                } else {
                    stopCompanionSystemContextMonitoring()
                }
                if companionStatus == "Companion scan queued..." {
                    companionStatus = nil
                }
            }
        }
    }
    @Published var isUsageActivityWatchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isUsageActivityWatchEnabled, forKey: Self.usageActivityWatchDefaultsKey)
            if isUsageActivityWatchEnabled {
                startCompanionSystemContextMonitoring()
            } else if !isCompanionAutoScanEnabled {
                stopCompanionSystemContextMonitoring()
            }
        }
    }
    @Published var isTaskAIAutoInferenceEnabled = AITaskInference.defaultAutoInferenceEnabled {
        didSet {
            UserDefaults.standard.set(isTaskAIAutoInferenceEnabled, forKey: AITaskInference.autoInferenceDefaultsKey)
            if isTaskAIAutoInferenceEnabled {
                scheduleTaskAIAutoInferenceIfNeeded(for: selectedBufferID)
            } else {
                cancelTaskAIAutoInference(clearQueuedStatus: true)
                lastTaskAIAutoInferenceContext = nil
            }
        }
    }
    @Published private(set) var documentComments: [DocumentComment] = []
    @Published private(set) var manualTasks: [ManualTask] = []
    @Published private(set) var globalManualTasks: [ManualTask] = []
    @Published private(set) var documentCatalogTasks: [DetectedTask] = []
    @Published private(set) var customTextMacros: [TextMacro] = []
    @Published private(set) var customActionMacros: [ActionMacro] = []
    @Published private(set) var pinnedMacros: [PinnedMacroReference] = []
    @Published private(set) var actionMacroRecording: ActionMacroRecording?
    @Published private(set) var usageStats: [DailyUsageStats] = []
    @Published private(set) var terminalSessions: [TerminalSession] = []
    @Published var selectedTerminalSessionID: UUID?
    @Published var selectedCommentID: UUID?
    @Published var collaborationSession: CollaborationSessionState?
    @Published var aiRunningSessions = Set<UUID>()
    @Published var aiSessionStatuses: [UUID: String] = [:]
    @Published private(set) var companionSuggestionsByBufferID: [UUID: [CompanionSuggestion]] = [:]
    @Published private(set) var isCompanionRunning = false
    @Published private(set) var companionStatus: String?
    @Published private(set) var isTaskAIInferenceRunning = false
    @Published private(set) var taskAIInferenceStatus: String?
    @Published private(set) var largeFileSearchStatus: String?
    @Published private(set) var isTranslationRunning = false
    @Published private(set) var translationStatus: String?
    @Published private(set) var poModeReport: DocumentFolderAnalysis.Report?
    @Published private(set) var poModeAIInterpretation: String?
    @Published private(set) var isPOModeAIInterpretationRunning = false
    @Published private(set) var poModeAIInterpretationStatus: String?
    @Published private(set) var isVoiceScribeRunning = false
    @Published private(set) var voiceScribeStatus: String?
    @Published private(set) var voiceScribeAutoMeetingStatus: String?
    @Published private(set) var voiceScribePartialTranscript = ""
    @Published private(set) var collaborationRelayState: CollaborationRelayState?
    @Published private(set) var collaborationRelayStatus: String?
    @Published private(set) var foldedRangesByBufferID: [UUID: [StructuredFoldRange]] = [:]

    let windowGroupID: UUID
    let networkShare: NetworkShareService
    let terminalProcessFactory: TerminalProcessFactory
    let voiceScribeRecognizerFactory: () -> VoiceScribeRecognizing?
    let systemAudioScribeRecognizerFactory: () -> VoiceScribeRecognizing?
    let voiceScribeMeetingAppDetector: () -> VoiceScribeMeetingAppDetection?
    var onPersistRequested: (() -> Void)?
    var onMoveTabBetweenGroups: ((_ sourceGroupID: UUID, _ targetGroupID: UUID, _ bufferID: UUID) -> Void)?
    var onDocumentCatalogRootChanged: ((String?) -> Void)?
    var onGlobalManualTasksChanged: (([ManualTask]) -> Void)?

    private let persistence: SessionPersistence?
    private let commentPersistence: DocumentCommentPersistence?
    private let taskPersistence: TaskBoardPersistence?
    private let globalTaskPersistence: TaskBoardPersistence?
    private let textMacroPersistence: TextMacroPersistence?
    private let usageStatsPersistence: UsageStatsPersistence?
    private let commentReminderScheduler: CommentReminderScheduling?
    private let httpAIConfigurationProvider: () throws -> HTTPAIConfiguration
    private let httpAIClientFactory: (HTTPAIConfiguration) -> any HTTPAICompleting
    private let companionSystemContextProvider: @MainActor () async -> CompanionSystemContext?
    private let companionIncludesSystemContextProvider: () -> Bool
    private let companionAutoScanDelayNanoseconds: UInt64
    private let companionSystemContextPollIntervalNanoseconds: UInt64
    private let taskAIAutoInferenceDelayNanoseconds: UInt64
    private let voiceScribeAutoMeetingPollIntervalNanoseconds: UInt64
    private let aiFileBridge = AIBufferFileBridge()
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingCommentSaveTask: Task<Void, Never>?
    private var pendingTextMacroSaveTask: Task<Void, Never>?
    private var pendingUsageStatsSaveTask: Task<Void, Never>?
    private var documentCatalogTaskScanTask: Task<Void, Never>?
    private var editorCommandHandler: ((EditorCommand) -> Bool)?
    private var aiClients: [UUID: ACPAgentClient] = [:]
    private var aiHTTPTasks: [UUID: Task<Void, Never>] = [:]
    private var companionTask: Task<Void, Never>?
    private var companionAutoScanTask: Task<Void, Never>?
    private var companionSystemContextMonitorTask: Task<Void, Never>?
    private var lastCompanionSystemContextSignature: String?
    private var lastCompanionUsageActivitySignature: String?
    private var lastCompanionUsageActivityTitle: String?
    private var lastCompanionUsageActivityDocumentKey: String?
    private var lastCompanionUsageActivityAt: Date?
    private var taskAIInferenceTask: Task<Void, Never>?
    private var taskAIAutoInferenceTask: Task<Void, Never>?
    private var taskAIAutoInferenceGeneration = 0
    private var lastTaskAIAutoInferenceContext: String?
    private var largeFileSearchTask: Task<Void, Never>?
    private var largeFileLineJumpTask: Task<Void, Never>?
    private var largeFileLineEditTask: Task<Void, Never>?
    private var largeFileLineIndexes: [String: LargeFileLineIndex] = [:]
    private var largeFileVisibleLineRangesByBufferID: [UUID: ClosedRange<Int>] = [:]
    private var editableLargeFilePreviewIDs = Set<UUID>()
    private var poModeAIInterpretationTask: Task<Void, Never>?
    private var voiceScribeRecognizer: VoiceScribeRecognizing?
    private var voiceScribeAutoMeetingTask: Task<Void, Never>?
    private var isVoiceScribeStartedByAutoMeetingWatcher = false
    private var collaborationRelayServer: CollaborationRelayServer?
    private var collaborationRelayClient: CollaborationRelayClient?
    private var terminalProcesses: [UUID: TerminalProcessRunning] = [:]
    private var terminalProcessGenerations: [UUID: Int] = [:]
    private var terminalOutputDecoders: [UUID: TerminalOutputDecoder] = [:]
    private var terminalOutputObservers: [UUID: [UUID: TerminalOutputObserver]] = [:]
    private var pendingFileLineJumps: [UUID: Int] = [:]
    private var pendingCloseSuspendedBuffer: EditorBuffer?
    private var encryptionPasswordsByPath: [String: String] = [:]
    private var aiChatIDsByAgentSession: [String: UUID] = [:]
    private var aiStreamingMessageIDs: [UUID: UUID] = [:]
    private var pendingFileLoadIDs = Set<UUID>()
    private var pendingFileLoadTasks: [UUID: Task<Void, Never>] = [:]
    private var openCommentObserver: NSObjectProtocol?
    private var isApplyingCollaborationUpdate = false
    private var lastEditingActivityAt: Date?
    private var actionMacroPlaybackDepth = 0
    private var actionMacroCommandDepth = 0

    var largeFileLineIndexCacheCount: Int {
        largeFileLineIndexes.count
    }

    private static let wrapsLinesDefaultsKey = "editor.wrapsLines"
    private static let columnGuideDefaultsKey = "editor.columnGuide"
    private static let sourceEditorEngineDefaultsKey = "editor.sourceEngine"
    private static let outlineDefaultsKey = "editor.markdownOutline"
    private static let focusModeDefaultsKey = "editor.focusMode"
    private static let typewriterModeDefaultsKey = "editor.typewriterMode"
    private static let miniMapDefaultsKey = "editor.miniMap"
    private static let wysiwygModeDefaultsKey = "editor.markdownWysiwyg"
    private static let documentCatalogVisibleDefaultsKey = "editor.documentCatalogVisible"
    private static let documentCatalogRootDefaultsKey = "editor.documentCatalogRoot"
    private static let translationTargetDefaultsKey = "ai.translation.targetLanguage"
    private static let companionAutoScanDefaultsKey = "ai.companion.autoScan"
    private static let usageActivityWatchDefaultsKey = "usage.activityWatch"
    private static let voiceScribeAutoMeetingDefaultsKey = "scribe.autoMeeting.enabled"
    private static let taskAIAutoInferenceQueuedStatus = "AI task inference queued..."
    nonisolated static let largeFileModeThresholdBytes = Int64(LargeFileConfiguration.defaultGeneralThresholdBytes)
    nonisolated static let complexTextLargeFileModeThresholdBytes = Int64(LargeFileConfiguration.defaultComplexThresholdBytes)
    nonisolated static let largeFilePreviewByteLimit = LargeFileConfiguration.defaultGeneralPreviewByteLimit
    nonisolated static let complexTextLargeFilePreviewByteLimit = LargeFileConfiguration.defaultComplexPreviewByteLimit
    nonisolated static let closeConfirmationRenderSuspensionThresholdBytes = LargeFileConfiguration.defaultComplexThresholdBytes
    private static let terminalOutputLimit = 200_000
    private static let terminalReplayResetBytes = Data([0x1B, 0x63])
    private static let editorDiagnosticsComplexHighlightCharacterLimit = 250_000
    private static let maxDiffInputBytes = 1 * 1024 * 1024
    private static let maxDiffInputLines = 2_000
    private static let diffInputLimitDescription = "1 MB and 2,000 lines per side"
    private static let maxUsageTimelineEntriesPerDay = 500
    private static let usageTimelineMergeWindow: TimeInterval = 300
    private nonisolated static let maxDocumentCatalogDetectedTasks = 500
    private nonisolated static let maxDocumentCatalogTaskScanFileSizeBytes: Int64 = 1 * 1024 * 1024
    private static let collaborationColors: [NSColor] = [
        .systemBlue,
        .systemGreen,
        .systemOrange,
        .systemPink,
        .systemPurple,
        .systemTeal
    ]

    private static func defaultCommentReminderScheduler() -> CommentReminderScheduling? {
        if isRunningTests {
            return nil
        }

        return CommentReminderService.shared
    }

    private static func defaultCommentPersistence() -> DocumentCommentPersistence? {
        if isRunningTests {
            return nil
        }

        return DocumentCommentPersistence()
    }

    private static func defaultTaskPersistence() -> TaskBoardPersistence? {
        if isRunningTests {
            return nil
        }

        return TaskBoardPersistence()
    }

    private static func defaultUsageStatsPersistence() -> UsageStatsPersistence? {
        if isRunningTests {
            return nil
        }

        return UsageStatsPersistence()
    }

    private static func defaultTextMacroPersistence() -> TextMacroPersistence? {
        if isRunningTests {
            return nil
        }

        return TextMacroPersistence()
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil ||
            NSClassFromString("XCTest.XCTestCase") != nil
    }

    private static func tasks(_ tasks: [ManualTask], normalizedTo scope: ManualTaskScope) -> [ManualTask] {
        tasks.map { task in
            var normalized = task
            normalized.scope = scope
            return normalized
        }
    }

    init(
        windowGroupID: UUID = UUID(),
        initialBuffers: [EditorBuffer]? = nil,
        selectedID: UUID? = nil,
        persistence: SessionPersistence? = SessionPersistence(),
        commentPersistence: DocumentCommentPersistence? = nil,
        taskPersistence: TaskBoardPersistence? = nil,
        globalTaskPersistence: TaskBoardPersistence? = nil,
        textMacroPersistence: TextMacroPersistence? = nil,
        usageStatsPersistence: UsageStatsPersistence? = nil,
        commentReminderScheduler: CommentReminderScheduling? = nil,
        networkShare: NetworkShareService = NetworkShareService(),
        terminalProcessFactory: @escaping TerminalProcessFactory = { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                onOutput: onOutput,
                onExit: onExit
            )
        },
        voiceScribeRecognizerFactory: @escaping () -> VoiceScribeRecognizing? = {
            SystemVoiceScribeRecognizer()
        },
        systemAudioScribeRecognizerFactory: @escaping () -> VoiceScribeRecognizing? = {
            SystemAudioVoiceScribeRecognizer()
        },
        voiceScribeMeetingAppDetector: @escaping () -> VoiceScribeMeetingAppDetection? = {
            VoiceScribeMeetingAppDetector.detectRunningApplication()
        },
        httpAIClientFactory: @escaping (HTTPAIConfiguration) -> any HTTPAICompleting = { configuration in
            HTTPAIClient(configuration: configuration)
        },
        httpAIConfigurationProvider: @escaping () throws -> HTTPAIConfiguration = {
            try HTTPAIConfiguration.current()
        },
        companionSystemContextProvider: (@MainActor () async -> CompanionSystemContext?)? = nil,
        companionIncludesSystemContextProvider: @escaping () -> Bool = {
            CompanionSettings.includesSystemContext()
        },
        companionAutoScanDelayNanoseconds: UInt64 = 1_500_000_000,
        companionSystemContextPollIntervalNanoseconds: UInt64 = 2_000_000_000,
        taskAIAutoInferenceEnabled: Bool? = nil,
        taskAIAutoInferenceDelayNanoseconds: UInt64 = 5_000_000_000,
        voiceScribeAutoMeetingEnabled: Bool? = nil,
        voiceScribeAutoMeetingPollIntervalNanoseconds: UInt64 = 3_000_000_000,
        autoPersistOnInit: Bool = true,
        registerNetworkReceiver: Bool = true
    ) {
        self.windowGroupID = windowGroupID
        self.persistence = persistence
        self.commentPersistence = commentPersistence ?? Self.defaultCommentPersistence()
        self.taskPersistence = taskPersistence ?? Self.defaultTaskPersistence()
        self.globalTaskPersistence = globalTaskPersistence
        self.textMacroPersistence = textMacroPersistence ?? Self.defaultTextMacroPersistence()
        self.usageStatsPersistence = usageStatsPersistence ?? Self.defaultUsageStatsPersistence()
        self.commentReminderScheduler = commentReminderScheduler ?? Self.defaultCommentReminderScheduler()
        self.networkShare = networkShare
        self.terminalProcessFactory = terminalProcessFactory
        self.voiceScribeRecognizerFactory = voiceScribeRecognizerFactory
        self.systemAudioScribeRecognizerFactory = systemAudioScribeRecognizerFactory
        self.voiceScribeMeetingAppDetector = voiceScribeMeetingAppDetector
        self.httpAIConfigurationProvider = httpAIConfigurationProvider
        self.httpAIClientFactory = httpAIClientFactory
        self.companionSystemContextProvider = companionSystemContextProvider ?? {
            await EditorStore.currentCompanionSystemContext()
        }
        self.companionIncludesSystemContextProvider = companionIncludesSystemContextProvider
        self.companionAutoScanDelayNanoseconds = companionAutoScanDelayNanoseconds
        self.companionSystemContextPollIntervalNanoseconds = companionSystemContextPollIntervalNanoseconds
        self.taskAIAutoInferenceDelayNanoseconds = taskAIAutoInferenceDelayNanoseconds
        self.voiceScribeAutoMeetingPollIntervalNanoseconds = voiceScribeAutoMeetingPollIntervalNanoseconds
        self.wrapsLines = UserDefaults.standard.object(forKey: Self.wrapsLinesDefaultsKey) as? Bool ?? true
        self.columnGuide = UserDefaults.standard.object(forKey: Self.columnGuideDefaultsKey) as? Int ?? 0
        let sourceEngineRawValue = UserDefaults.standard.string(forKey: Self.sourceEditorEngineDefaultsKey)
        self.sourceEditorEngine = sourceEngineRawValue.flatMap(SourceEditorEngine.init(rawValue:)) ?? .nativeSTTextView
        self.isOutlineVisible = UserDefaults.standard.object(forKey: Self.outlineDefaultsKey) as? Bool ?? false
        self.isFocusModeEnabled = UserDefaults.standard.object(forKey: Self.focusModeDefaultsKey) as? Bool ?? false
        self.isTypewriterModeEnabled = UserDefaults.standard.object(forKey: Self.typewriterModeDefaultsKey) as? Bool ?? false
        self.isMiniMapVisible = UserDefaults.standard.object(forKey: Self.miniMapDefaultsKey) as? Bool ?? true
        self.isWysiwygModeEnabled = UserDefaults.standard.object(forKey: Self.wysiwygModeDefaultsKey) as? Bool ?? false
        self.isDocumentCatalogVisible = UserDefaults.standard.object(forKey: Self.documentCatalogVisibleDefaultsKey) as? Bool ?? false
        self.isCompanionAutoScanEnabled = Self.isRunningTests
            ? false
            : (UserDefaults.standard.object(forKey: Self.companionAutoScanDefaultsKey) as? Bool ?? false)
        self.isUsageActivityWatchEnabled = Self.isRunningTests
            ? false
            : (UserDefaults.standard.object(forKey: Self.usageActivityWatchDefaultsKey) as? Bool ?? false)
        self.isTaskAIAutoInferenceEnabled = taskAIAutoInferenceEnabled ??
            (Self.isRunningTests
                ? AITaskInference.defaultAutoInferenceEnabled
                : (UserDefaults.standard.object(forKey: AITaskInference.autoInferenceDefaultsKey) as? Bool ?? AITaskInference.defaultAutoInferenceEnabled))
        self.isVoiceScribeAutoMeetingEnabled = voiceScribeAutoMeetingEnabled ??
            (Self.isRunningTests
                ? false
                : (UserDefaults.standard.object(forKey: Self.voiceScribeAutoMeetingDefaultsKey) as? Bool ?? false))
        self.documentCatalogRootPath = UserDefaults.standard.string(forKey: Self.documentCatalogRootDefaultsKey)
        let loaded: (buffers: [EditorBuffer], selectedID: UUID?)

        if let initialBuffers {
            loaded = (initialBuffers, selectedID)
        } else {
            loaded = persistence?.load() ?? ([], nil)
        }

        let restoredBuffers = Self.migratedRestoredBuffers(loaded.buffers)

        if restoredBuffers.isEmpty {
            let initial = EditorBuffer.scratch(index: 1)
            buffers = [initial]
            selectedBufferID = initial.id
        } else {
            buffers = restoredBuffers
            selectedBufferID = loaded.selectedID.flatMap { selectedID in
                restoredBuffers.contains(where: { $0.id == selectedID }) ? selectedID : nil
            } ?? restoredBuffers.first?.id
        }
        documentComments = commentPersistence?.load() ?? []
        manualTasks = Self.tasks(self.taskPersistence?.load() ?? [], normalizedTo: .workspace)
        globalManualTasks = Self.tasks(self.globalTaskPersistence?.load() ?? [], normalizedTo: .global)
        customTextMacros = self.textMacroPersistence?.load() ?? []
        customActionMacros = self.textMacroPersistence?.loadActionMacros() ?? []
        pinnedMacros = self.textMacroPersistence?.loadPinnedMacros() ?? []
        usageStats = self.usageStatsPersistence?.load() ?? []

        normalizeLoadedEditorModeState()
        installOpenCommentObserver()

        if registerNetworkReceiver {
            networkShare.onReceivedNote = { [weak self] note in
                self?.importSharedNote(note)
            }
            networkShare.onReceivedCollaboration = { [weak self] payload in
                self?.handleCollaborationPayload(payload)
            }
        }

        if autoPersistOnInit {
            persistSoon()
        }
        loadRestoredLargeFilePreviews()

        if documentCatalogRootPath != nil {
            refreshDocumentCatalog()
        }
        if isVoiceScribeAutoMeetingEnabled {
            startVoiceScribeAutoMeetingMonitor()
            checkVoiceScribeAutoMeetingNow()
        }
    }

    deinit {
        pendingSaveTask?.cancel()
        pendingCommentSaveTask?.cancel()
        pendingTextMacroSaveTask?.cancel()
        pendingUsageStatsSaveTask?.cancel()
        documentCatalogTaskScanTask?.cancel()
        aiHTTPTasks.values.forEach { $0.cancel() }
        companionTask?.cancel()
        taskAIInferenceTask?.cancel()
        taskAIAutoInferenceTask?.cancel()
        largeFileSearchTask?.cancel()
        largeFileLineJumpTask?.cancel()
        largeFileLineEditTask?.cancel()
        companionSystemContextMonitorTask?.cancel()
        poModeAIInterpretationTask?.cancel()
        voiceScribeAutoMeetingTask?.cancel()
        aiClients.values.forEach { $0.stop() }
        voiceScribeRecognizer?.stop()
        collaborationRelayClient?.stop()
        collaborationRelayServer?.stop()
        terminalProcesses.values.forEach { $0.stop() }
        pendingFileLoadTasks.values.forEach { $0.cancel() }
        if let openCommentObserver {
            NotificationCenter.default.removeObserver(openCommentObserver)
        }
    }

    var selectedBuffer: EditorBuffer? {
        guard let selectedBufferID else { return nil }
        return buffers.first { $0.id == selectedBufferID }
    }

    var buffersForPersistence: [EditorBuffer] {
        guard let suspendedBuffer = pendingCloseSuspendedBuffer,
              pendingCloseBuffer?.id == suspendedBuffer.id,
              let index = buffers.firstIndex(where: { $0.id == suspendedBuffer.id }) else {
            return buffers
        }

        var persistedBuffers = buffers
        persistedBuffers.remove(at: index)
        return persistedBuffers
    }

    var selectedIndex: Int? {
        guard let selectedBufferID else { return nil }
        return buffers.firstIndex { $0.id == selectedBufferID }
    }

    var globalSearchResults: [SearchResult] {
        searchAllSources(query: findQuery)
    }

    var findStatusText: String {
        if let error = findValidationError {
            return error
        }

        guard !findQuery.isEmpty, let selectedBuffer else {
            return ""
        }

        let matches = allMatches(in: selectedBuffer.text)
        guard !matches.isEmpty else {
            return "No matches"
        }

        let selected = normalizedRanges(selectedBuffer.selectionRanges, in: selectedBuffer.text).first
        let currentIndex = selected.flatMap { selection in
            matches.firstIndex { NSEqualRanges($0.range, selection.nsRange) }
        } ?? 0

        return "\(currentIndex + 1) of \(matches.count)"
    }

    var findValidationError: String? {
        guard findUsesRegex, !findQuery.isEmpty else { return nil }
        do {
            _ = try makeFindRegex()
            return nil
        } catch {
            return "Invalid regex"
        }
    }

    var selectedBufferLanguage: EditorLanguage {
        selectedBuffer?.language ?? .plain
    }

    var selectedSavePolicy: BufferSavePolicy {
        selectedBuffer?.savePolicy ?? .normal
    }

    var selectedBufferIsLargeFileMode: Bool {
        selectedBuffer?.isLargeFileMode == true
    }

    func shouldSuspendEditorRenderingForPendingClose(_ buffer: EditorBuffer) -> Bool {
        guard pendingCloseBuffer?.id == buffer.id else { return false }

        if pendingCloseSuspendedBuffer != nil {
            return true
        }

        if buffer.isLargeFileMode || isLargeReadOnlyFilePreview(buffer) {
            return true
        }

        if let fileSizeBytes = buffer.fileSizeBytes,
           fileSizeBytes >= Self.closeConfirmationRenderSuspensionThresholdBytes {
            return true
        }

        return buffer.text.utf8.count >= Self.closeConfirmationRenderSuspensionThresholdBytes
    }

    var selectedLargeFileCanPageBackward: Bool {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode else {
            return false
        }

        return (buffer.largeFilePreviewStartOffsetBytes ?? 0) > 0
    }

    var selectedLargeFileCanPageForward: Bool {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              let fileSizeBytes = buffer.fileSizeBytes else {
            return false
        }

        let start = buffer.largeFilePreviewStartOffsetBytes ?? 0
        let count = Int64(buffer.largeFilePreviewByteCount ?? Self.largeFilePreviewByteLimit(for: buffer.language))
        return start + count < fileSizeBytes
    }

    var selectedBufferCanSaveLargeFileChunkBack: Bool {
        guard let buffer = selectedBuffer else { return false }
        return largeFileEditingCapability(for: buffer).canSaveChunkBack
    }

    var selectedBufferCanSave: Bool {
        guard selectedBuffer?.isLargeFileMode != true else { return false }
        return !selectedSavePolicy.blocksSaving
    }

    var selectedLargeFileCanEnableChunkEditing: Bool {
        guard let buffer = selectedBuffer else { return false }
        return largeFileEditingCapability(for: buffer).canEnableInPlaceChunkEditing
    }

    var selectedLargeFileCanOpenVisibleChunkForEditing: Bool {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              buffer.filePath != nil else {
            return false
        }

        return !largeFileEditingCapability(for: buffer).canEditLoadedText
    }

    var selectedLargeFileCanReplaceLine: Bool {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              buffer.filePath != nil else {
            return false
        }

        return true
    }

    var selectedLargeFileDefaultLineNumberForLineEdit: Int? {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode else {
            return nil
        }

        if let visibleLineRange = largeFileVisibleLineRangesByBufferID[buffer.id] {
            return max(1, visibleLineRange.lowerBound)
        }

        return selectedLargeFileLineNumberForPreviewStartOffset()
    }

    func bufferCanEditLargeFileChunk(_ buffer: EditorBuffer) -> Bool {
        guard buffer.isLargeFileMode else { return false }
        return largeFileEditingCapability(for: buffer).canEditLoadedText
    }

    func largeFileEditingCapability(for buffer: EditorBuffer) -> LargeFileEditingCapability {
        let sourceIsLinked = selectedLargeFileChunkSourceIsLinked(buffer)

        guard buffer.isLargeFileMode else {
            if sourceIsLinked {
                return LargeFileEditingCapability(
                    state: .extractedChunk,
                    status: "Editable extracted chunk",
                    detail: "This buffer is a normal editor buffer linked to a byte range in a large source file. Saving back rewrites only that source range.",
                    canEnableInPlaceChunkEditing: false,
                    canSaveChunkBack: true,
                    canEditLoadedText: true
                )
            }

            return LargeFileEditingCapability(
                state: .normalBuffer,
                status: "Normal editable buffer",
                detail: "The loaded text is edited directly; no large-file chunk workflow is active.",
                canEnableInPlaceChunkEditing: false,
                canSaveChunkBack: false,
                canEditLoadedText: true
            )
        }

        if editableLargeFilePreviewIDs.contains(buffer.id) || sourceIsLinked {
            return LargeFileEditingCapability(
                state: .editablePreviewChunk,
                status: "Editable preview chunk",
                detail: sourceIsLinked
                    ? "Only the currently loaded large-file chunk is editable and linked for save-back."
                    : "Only the currently loaded large-file chunk is editable; the source range is linked when the chunk first changes.",
                canEnableInPlaceChunkEditing: false,
                canSaveChunkBack: sourceIsLinked,
                canEditLoadedText: true
            )
        }

        if largeFileChunkHasExactByteRange(buffer) {
            return LargeFileEditingCapability(
                state: .readOnlyExactPreview,
                status: "Read-only virtual preview",
                detail: "The full file is browsed through virtual chunks. The current exact chunk can be enabled for bounded editing.",
                canEnableInPlaceChunkEditing: true,
                canSaveChunkBack: false,
                canEditLoadedText: false
            )
        }

        return LargeFileEditingCapability(
            state: .unsafePreviewBoundary,
            status: "Read-only boundary preview",
            detail: "The current preview does not map to an exact UTF-8 byte range, so it can be inspected but not edited in place.",
            canEnableInPlaceChunkEditing: false,
            canSaveChunkBack: false,
            canEditLoadedText: false
        )
    }

    var selectedBufferSupportsStructuredFolding: Bool {
        guard let selectedBuffer else { return false }
        return supportsStructuredFolding(selectedBuffer.language) && !selectedBuffer.isLargeFileMode
    }

    var selectedGitRepository: GitRepositoryService.Repository? {
        guard let filePath = selectedBuffer?.filePath else { return nil }
        return GitRepositoryService.repository(containingFileAt: URL(fileURLWithPath: filePath))
    }

    var selectedFinderTags: [String] {
        guard let selectedBuffer,
              !selectedBuffer.isLargeFileMode,
              let filePath = selectedBuffer.filePath else { return [] }
        return FinderTagService.tags(for: URL(fileURLWithPath: filePath))
    }

    var selectedTerminalSession: TerminalSession? {
        guard let selectedTerminalSessionID else { return nil }
        return terminalSessions.first { $0.id == selectedTerminalSessionID }
    }

    var selectedAIChatSession: AIChatSession? {
        guard let selectedBuffer else { return nil }
        return selectedAIChatSession(in: selectedBuffer.id)
    }

    func select(_ id: UUID?) {
        selectedBufferID = id
        persistSoon()
    }

    func toggleAIPanel() {
        if isAIPanelVisible {
            isAIPanelVisible = false
        } else {
            showAIPanel()
        }
    }

    func showAIPanel() {
        hideRightPanels()
        isAIPanelVisible = true
    }

    func toggleCompanionPanel() {
        if isCompanionPanelVisible {
            isCompanionPanelVisible = false
        } else {
            showCompanionPanel()
        }
    }

    func showCompanionPanel() {
        hideRightPanels()
        isCompanionPanelVisible = true
    }

    func toggleCompanionAutoScan() {
        isCompanionAutoScanEnabled.toggle()
    }

    func toggleUsageActivityWatch() {
        isUsageActivityWatchEnabled.toggle()
    }

    func refreshCompanionSystemContextMonitorForSettingsChange() {
        guard shouldMonitorCompanionSystemContext else {
            stopCompanionSystemContextMonitoring()
            return
        }
        if !companionIncludesSystemContextProvider() {
            lastCompanionSystemContextSignature = nil
        }
        startCompanionSystemContextMonitoring()
    }

    func toggleNetworkPanel() {
        if isNetworkPanelVisible {
            isNetworkPanelVisible = false
        } else {
            showNetworkPanel()
        }
    }

    func showNetworkPanel() {
        hideRightPanels()
        isNetworkPanelVisible = true
    }

    func toggleTasksPanel() {
        if isTasksPanelVisible {
            isTasksPanelVisible = false
        } else {
            showTasksPanel()
        }
    }

    func showTasksPanel() {
        hideRightPanels()
        isTasksPanelVisible = true
    }

    func hideTasksPanel() {
        isTasksPanelVisible = false
    }

    func toggleStatsPanel() {
        if isStatsPanelVisible {
            isStatsPanelVisible = false
        } else {
            showStatsPanel()
        }
    }

    func showStatsPanel() {
        hideRightPanels()
        isStatsPanelVisible = true
    }

    func hideStatsPanel() {
        isStatsPanelVisible = false
    }

    func toggleMacrosPanel() {
        if isMacrosPanelVisible {
            isMacrosPanelVisible = false
        } else {
            showMacrosPanel()
        }
    }

    func showMacrosPanel() {
        hideRightPanels()
        isMacrosPanelVisible = true
    }

    func hideMacrosPanel() {
        isMacrosPanelVisible = false
    }

    func togglePOModePanel() {
        if isPOModePanelVisible {
            isPOModePanelVisible = false
        } else {
            showPOModePanel()
        }
    }

    func showPOModePanel() {
        if poModeReport == nil,
           refreshPOModeAnalysisForDocumentCatalog(showPanel: false) == nil {
            return
        }
        hideRightPanels()
        isPOModePanelVisible = true
    }

    func hidePOModePanel() {
        isPOModePanelVisible = false
    }

    func toggleScribePanel() {
        if isScribePanelVisible {
            isScribePanelVisible = false
        } else {
            showScribePanel()
        }
    }

    func showScribePanel() {
        hideRightPanels()
        isScribePanelVisible = true
    }

    func hideScribePanel() {
        isScribePanelVisible = false
    }

    func toggleCommentsPanel() {
        if isCommentsPanelVisible {
            isCommentsPanelVisible = false
        } else {
            showCommentsPanel()
        }
    }

    func showCommentsPanel() {
        hideRightPanels()
        isCommentsPanelVisible = true
    }

    func foldedRanges(for buffer: EditorBuffer) -> [StructuredFoldRange] {
        foldedRangesByBufferID[buffer.id] ?? []
    }

    func foldableStructuredRanges(for buffer: EditorBuffer) -> [StructuredFoldRange] {
        guard supportsStructuredFolding(buffer.language), !buffer.isLargeFileMode else {
            return []
        }

        return StructuredTextFolder.foldableRanges(in: buffer.text, language: buffer.language)
    }

    func hasStructuredFolds(for buffer: EditorBuffer) -> Bool {
        !(foldedRangesByBufferID[buffer.id] ?? []).isEmpty
    }

    func toggleStructuredFoldAtSelection() {
        guard let buffer = selectedBuffer else { return }
        let selection = normalizedRanges(buffer.selectionRanges, in: buffer.text).first ?? .zero
        let lineNumber = StructuredTextFolder.lineNumber(at: selection.location, in: buffer.text)
        toggleStructuredFold(containingLine: lineNumber, in: buffer.id)
    }

    func toggleStructuredFold(containingLine lineNumber: Int, in bufferID: UUID) {
        guard let buffer = buffers.first(where: { $0.id == bufferID }) else { return }
        guard supportsStructuredFolding(buffer.language), !buffer.isLargeFileMode else {
            lastError = "Structured folding is available for Markdown, JSON, and YAML source buffers."
            return
        }

        guard let range = StructuredTextFolder.bestRange(containing: max(1, lineNumber), in: buffer.text, language: buffer.language) else {
            lastError = "No foldable block at the current line."
            return
        }

        var folds = foldedRangesByBufferID[buffer.id] ?? []
        if let index = folds.firstIndex(where: { $0.id == range.id }) {
            folds.remove(at: index)
        } else {
            folds.removeAll { existing in
                existing.contains(line: range.startLine) ||
                    range.contains(line: existing.startLine)
            }
            folds.append(range)
        }

        foldedRangesByBufferID[buffer.id] = folds.sorted { $0.startLine < $1.startLine }
        if buffer.id == selectedBufferID {
            showSourceMode()
        }
    }

    func unfoldAllStructuredBlocks() {
        guard let selectedBufferID else { return }
        foldedRangesByBufferID[selectedBufferID] = nil
    }

    private func supportsStructuredFolding(_ language: EditorLanguage) -> Bool {
        language.supportsStructuredFoldGutter
    }

    func hideCommentsPanel() {
        isCommentsPanelVisible = false
    }

    func toggleTerminalPanel() {
        if isTerminalPanelVisible {
            isTerminalPanelVisible = false
        } else {
            showTerminalPanel()
        }
    }

    func showTerminalPanel() {
        if terminalSessions.isEmpty {
            createTerminalSession()
        }
        isTerminalPanelVisible = true
    }

    func hideTerminalPanel() {
        isTerminalPanelVisible = false
    }

    func createTerminalSession() {
        let workingDirectory = terminalWorkingDirectoryForSelectedBuffer()
        let session = TerminalSession.new(
            index: terminalSessions.count + 1,
            workingDirectory: workingDirectory
        )
        terminalSessions.append(session)
        selectedTerminalSessionID = session.id
        isTerminalPanelVisible = true
        terminalOutputDecoders[session.id] = TerminalOutputDecoder()
        startTerminalProcess(for: session.id, workingDirectory: workingDirectory)
    }

    func selectTerminalSession(_ id: UUID) {
        guard terminalSessions.contains(where: { $0.id == id }) else { return }
        selectedTerminalSessionID = id
    }

    func closeTerminalSession(_ id: UUID) {
        terminalProcesses.removeValue(forKey: id)?.stop()
        terminalProcessGenerations.removeValue(forKey: id)
        terminalOutputDecoders.removeValue(forKey: id)
        guard let index = terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        terminalSessions.remove(at: index)

        if selectedTerminalSessionID == id {
            selectedTerminalSessionID = terminalSessions.indices.contains(index)
                ? terminalSessions[index].id
                : terminalSessions.last?.id
        }

        if terminalSessions.isEmpty {
            isTerminalPanelVisible = false
        }
    }

    func sendInputToTerminal(_ id: UUID, input: String) {
        sendInputToTerminal(id, data: Array(input.utf8)[...])
    }

    func sendInputToTerminal(_ id: UUID, data: ArraySlice<UInt8>) {
        terminalProcesses[id]?.send(data)
    }

    func runSelectedTerminalDiagnostics() {
        showTerminalPanel()
        guard let selectedTerminalSessionID else { return }
        runTerminalDiagnostics(selectedTerminalSessionID)
    }

    func runTerminalDiagnostics(_ id: UUID) {
        guard terminalProcesses[id] != nil else { return }
        sendTerminalDiagnosticScript(id)
    }

    private func sendTerminalDiagnosticScript(_ id: UUID) {
        let bytes = Array(Self.terminalDiagnosticScript.utf8)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + Self.terminalDiagnosticInputChunkSize, bytes.count)
            terminalProcesses[id]?.send(bytes[offset..<end])
            offset = end
            if offset < bytes.count {
                Thread.sleep(forTimeInterval: Self.terminalDiagnosticInputChunkDelay)
            }
        }
    }

    func interruptTerminalSession(_ id: UUID) {
        sendInputToTerminal(id, data: [0x03][...])
    }

    func resetTerminalSession(_ id: UUID) {
        interruptTerminalSession(id)
        clearTerminalOutput(id)
        sendInputToTerminal(id, input: "stty sane 2>/dev/null; reset\r")
    }

    func restartTerminalSession(_ id: UUID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        let workingDirectory = terminalWorkingDirectory(for: terminalSessions[index])

        terminalProcesses.removeValue(forKey: id)?.stop()
        terminalOutputDecoders[id] = TerminalOutputDecoder()
        terminalSessions[index].output = ""
        terminalSessions[index].rawOutputData.removeAll(keepingCapacity: true)
        terminalSessions[index].clearGeneration += 1
        terminalSessions[index].isRunning = true
        terminalSessions[index].lastExitStatus = nil
        terminalSessions[index].workingDirectoryPath = workingDirectory.path

        startTerminalProcess(for: id, workingDirectory: workingDirectory)
    }

    func clearTerminalOutput(_ id: UUID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        terminalSessions[index].output = ""
        terminalSessions[index].rawOutputData.removeAll(keepingCapacity: true)
        terminalSessions[index].clearGeneration += 1
        terminalOutputDecoders[id]?.reset()
    }

    func markTerminalSessionTerminated(_ id: UUID, exitStatus: Int32?) {
        finishTerminalSession(id, exitStatus: exitStatus ?? -1, appendStatusMessage: false)
    }

    func resizeTerminalSession(_ id: UUID, columns: Int, rows: Int) {
        terminalProcesses[id]?.resize(columns: columns, rows: rows)
    }

    func updateTerminalSessionTitle(_ id: UUID, title: String) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        let sanitizedTitle = sanitizedTerminalTitle(title)
        guard !sanitizedTitle.isEmpty else { return }
        terminalSessions[index].title = sanitizedTitle
    }

    func updateTerminalSessionWorkingDirectory(_ id: UUID, directory: String?) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == id }),
              let url = terminalDirectoryURL(from: directory) else {
            return
        }
        terminalSessions[index].workingDirectoryPath = url.standardizedFileURL.path
    }

    func registerTerminalOutputObserver(
        for sessionID: UUID,
        replayExistingOutput: Bool = true,
        handler: @escaping TerminalOutputObserver
    ) -> UUID {
        let observerID = UUID()
        terminalOutputObservers[sessionID, default: [:]][observerID] = handler
        if replayExistingOutput,
           let session = terminalSessions.first(where: { $0.id == sessionID }),
           !session.rawOutputData.isEmpty {
            handler(Array(session.rawOutputData))
        }
        return observerID
    }

    func unregisterTerminalOutputObserver(_ observerID: UUID, for sessionID: UUID) {
        terminalOutputObservers[sessionID]?[observerID] = nil
        if terminalOutputObservers[sessionID]?.isEmpty == true {
            terminalOutputObservers[sessionID] = nil
        }
    }

    func terminalWorkingDirectoryForSelectedBuffer() -> URL {
        if let filePath = selectedBuffer?.filePath {
            return URL(fileURLWithPath: filePath, isDirectory: false)
                .deletingLastPathComponent()
                .standardizedFileURL
        }

        if let documentCatalogRootPath {
            return URL(fileURLWithPath: documentCatalogRootPath, isDirectory: true)
                .standardizedFileURL
        }

        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    private func terminalWorkingDirectory(for session: TerminalSession) -> URL {
        let url = URL(fileURLWithPath: session.workingDirectoryPath, isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url
        }

        return terminalWorkingDirectoryForSelectedBuffer()
    }

    private func startTerminalProcess(for sessionID: UUID, workingDirectory: URL) {
        let generation = (terminalProcessGenerations[sessionID] ?? 0) + 1
        terminalProcessGenerations[sessionID] = generation

        do {
            let process = try terminalProcessFactory(
                workingDirectory,
                { [weak self] output in
                    Task { @MainActor in
                        self?.appendTerminalOutput(output, to: sessionID)
                    }
                },
                { [weak self] status in
                    Task { @MainActor in
                        self?.finishTerminalSession(
                            sessionID,
                            exitStatus: status,
                            processGeneration: generation
                        )
                    }
                }
            )
            terminalProcesses[sessionID] = process
        } catch {
            appendTerminalOutput(Array("Terminal error: \(error.localizedDescription)\n".utf8), to: sessionID)
            finishTerminalSession(sessionID, exitStatus: -1, processGeneration: generation)
        }
    }

    private func appendTerminalOutput(_ output: [UInt8], to sessionID: UUID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        terminalSessions[index].rawOutputData.append(contentsOf: output)
        terminalSessions[index].rawOutputData = Self.boundedTerminalReplayData(terminalSessions[index].rawOutputData)
        terminalOutputObservers[sessionID]?.values.forEach { $0(output) }

        let decoder = terminalOutputDecoders[sessionID] ?? TerminalOutputDecoder()
        terminalOutputDecoders[sessionID] = decoder
        decoder.append(output, to: &terminalSessions[index].output)
        if terminalSessions[index].output.count > Self.terminalOutputLimit {
            terminalSessions[index].output = String(terminalSessions[index].output.suffix(Self.terminalOutputLimit))
        }
    }

    private static func boundedTerminalReplayData(_ data: Data) -> Data {
        guard data.count > terminalOutputLimit else { return data }

        let suffixLimit = max(0, terminalOutputLimit - terminalReplayResetBytes.count)
        let suffix = trimmingLeadingUTF8ContinuationBytes(Data(data.suffix(suffixLimit)))
        return terminalReplayResetBytes + suffix
    }

    private static let terminalDiagnosticInputChunkSize = 256
    private static let terminalDiagnosticInputChunkDelay = 0.008

    private static let terminalDiagnosticScript = #"""
__simplelime_diag="${TMPDIR:-/tmp}/simplelime-terminal-diag-$$.sh"
cat > "$__simplelime_diag" <<'SIMPLELIME_TERMINAL_DIAG'
printf '\n[SimpleLime terminal diagnostics]\n'
printf 'shell=%s\n' "${SHELL:-unknown}"
printf 'term=%s colorterm=%s\n' "${TERM:-unknown}" "${COLORTERM:-}"
printf 'locale=%s\n' "${LC_ALL:-${LC_CTYPE:-${LANG:-unknown}}}"
printf 'size='
stty size < /dev/tty 2>/dev/null || printf 'unknown\n'
printf '\033]0;SimpleLime Terminal Diagnostics\007'
printf 'ansi: \033[31mred\033[0m \033[32mgreen\033[0m \033[34mblue\033[0m\n'
printf 'utf8: Кириллица — ✓\n'
printf '\033[?25l\033[?1049h\033[2J\033[H'
printf 'SimpleLime alternate screen diagnostic\n'
printf '\033[4;12Hcursor addressing OK'
sleep 0.2
printf '\033[?1049l\033[?25h'
if command -v python3 >/dev/null 2>&1; then
    __simplelime_py="${TMPDIR:-/tmp}/simplelime-terminal-curses-$$.py"
    cat > "$__simplelime_py" <<'SIMPLELIME_TERMINAL_PY'
import curses
import time

def main(stdscr):
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    stdscr.clear()
    max_y, max_x = stdscr.getmaxyx()
    stdscr.addstr(0, 0, "SimpleLime curses diagnostic")
    text = "curses cursor OK"
    row = min(3, max(0, max_y - 1))
    col = min(12, max(0, max_x - len(text) - 1))
    try:
        stdscr.addstr(row, col, text)
    except curses.error:
        pass
    stdscr.refresh()
    time.sleep(0.2)

curses.wrapper(main)
print("[SimpleLime curses diagnostic complete]")
SIMPLELIME_TERMINAL_PY
    python3 "$__simplelime_py" < /dev/tty || printf '[SimpleLime curses diagnostic failed]\n'
    rm -f "$__simplelime_py"
else
    printf '[SimpleLime curses diagnostic skipped: python3 not found]\n'
fi
printf '[SimpleLime terminal diagnostics complete]\n'
SIMPLELIME_TERMINAL_DIAG
/bin/sh "$__simplelime_diag"
__simplelime_status=$?
rm -f "$__simplelime_diag"
unset __simplelime_diag __simplelime_status
"""#

    private func sanitizedTerminalTitle(_ title: String) -> String {
        let cleaned = String(
            title.unicodeScalars.filter { scalar in
                !CharacterSet.controlCharacters.contains(scalar) &&
                    !CharacterSet.newlines.contains(scalar)
            }
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        return String(cleaned.prefix(80))
    }

    private func terminalDirectoryURL(from directory: String?) -> URL? {
        guard let rawDirectory = directory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawDirectory.isEmpty else {
            return nil
        }

        let url: URL
        if let parsed = URL(string: rawDirectory),
           parsed.isFileURL {
            url = parsed
        } else {
            url = URL(fileURLWithPath: rawDirectory, isDirectory: true)
        }

        guard url.path.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }

    private func finishTerminalSession(
        _ sessionID: UUID,
        exitStatus: Int32,
        appendStatusMessage: Bool = true,
        processGeneration: Int? = nil
    ) {
        if let processGeneration,
           terminalProcessGenerations[sessionID] != processGeneration {
            return
        }

        terminalProcesses.removeValue(forKey: sessionID)
        terminalProcessGenerations.removeValue(forKey: sessionID)
        terminalOutputDecoders.removeValue(forKey: sessionID)
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        terminalSessions[index].isRunning = false
        terminalSessions[index].lastExitStatus = exitStatus
        if appendStatusMessage {
            appendTerminalOutput(Array("\n[Process exited with status \(exitStatus)]\n".utf8), to: sessionID)
        }
    }

    private func hideRightPanels() {
        isAIPanelVisible = false
        isNetworkPanelVisible = false
        isTasksPanelVisible = false
        isStatsPanelVisible = false
        isMacrosPanelVisible = false
        isCommentsPanelVisible = false
        isCompanionPanelVisible = false
        isPOModePanelVisible = false
        isScribePanelVisible = false
    }

    func comments(for buffer: EditorBuffer) -> [DocumentComment] {
        let key = documentKey(for: buffer)
        return documentComments
            .filter { $0.documentKey == key && !$0.isResolved }
            .sorted {
                if $0.range.location == $1.range.location {
                    return $0.createdAt < $1.createdAt
                }
                return $0.range.location < $1.range.location
            }
    }

    var selectedBufferComments: [DocumentComment] {
        guard let selectedBuffer else { return [] }
        return comments(for: selectedBuffer)
    }

    var selectedComment: DocumentComment? {
        guard let selectedCommentID else { return nil }
        return documentComments.first { $0.id == selectedCommentID }
    }

    @discardableResult
    func addCommentToSelection(body: String = "") -> DocumentComment? {
        guard let selectedIndex else { return nil }
        let buffer = buffers[selectedIndex]
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        guard let range = ranges.first else {
            showCommentsPanel()
            lastError = "Select text before adding a comment."
            return nil
        }

        return addComment(to: range, in: buffer.id, body: body)
    }

    @discardableResult
    func addComment(to rawRange: TextRange, in bufferID: UUID, body: String = "") -> DocumentComment? {
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }) else { return nil }
        let buffer = buffers[index]
        guard let range = normalizedNonEmptyRanges([rawRange], in: buffer.text).first else { return nil }

        let quote = (buffer.text as NSString).substring(with: range.nsRange)
        let now = Date()
        let comment = DocumentComment(
            documentKey: documentKey(for: buffer),
            range: range,
            quote: quote,
            body: body,
            createdAt: now,
            updatedAt: now
        )

        documentComments.append(comment)
        selectedCommentID = comment.id
        buffers[index].selectionRanges = [range]
        showCommentsPanel()
        persistCommentsSoon()
        scheduleCompanionAutoScanIfNeeded(for: bufferID)
        persistSoon()
        return comment
    }

    func selectComment(_ commentID: UUID) {
        selectedCommentID = commentID
        guard let comment = documentComments.first(where: { $0.id == commentID }),
              let buffer = buffers.first(where: { documentKey(for: $0) == comment.documentKey }) else {
            return
        }
        scheduleCompanionAutoScanIfNeeded(for: buffer.id)
    }

    func jumpToComment(_ commentID: UUID) {
        guard let comment = documentComments.first(where: { $0.id == commentID }) else { return }

        selectedCommentID = commentID
        showCommentsPanel()

        if let index = buffers.firstIndex(where: { documentKey(for: $0) == comment.documentKey }) {
            selectedBufferID = buffers[index].id
            buffers[index].selectionRanges = [normalizedRange(comment.range, in: buffers[index].text)]
            scheduleCompanionAutoScanIfNeeded(for: buffers[index].id)
            persistSoon()
            return
        }

        guard let filePath = filePath(fromDocumentKey: comment.documentKey) else { return }

        do {
            let url = URL(fileURLWithPath: filePath)
            var encoding = String.Encoding.utf8
            let text = try String(contentsOf: url, usedEncoding: &encoding)
            let now = Date()
            let buffer = EditorBuffer(
                id: UUID(),
                title: url.lastPathComponent,
                kind: .file,
                filePath: filePath,
                text: text,
                language: EditorLanguage.detect(fileName: url.lastPathComponent, text: text),
                createdAt: now,
                updatedAt: now,
                isDirty: false,
                selectionRanges: [normalizedRange(comment.range, in: text)]
            )
            buffers.append(buffer)
            selectedBufferID = buffer.id
            scheduleCompanionAutoScanIfNeeded(for: buffer.id)
            persistSoon()
        } catch {
            lastError = "Could not open commented document: \(error.localizedDescription)"
        }
    }

    func updateCommentBody(_ commentID: UUID, body: String) {
        guard let index = documentComments.firstIndex(where: { $0.id == commentID }),
              documentComments[index].body != body else {
            return
        }

        documentComments[index].body = body
        documentComments[index].updatedAt = Date()
        persistCommentsSoon()
        if let buffer = buffers.first(where: { documentKey(for: $0) == documentComments[index].documentKey }) {
            scheduleCompanionAutoScanIfNeeded(for: buffer.id)
        }
    }

    func resolveComment(_ commentID: UUID) {
        guard let index = documentComments.firstIndex(where: { $0.id == commentID }) else { return }

        let commentDocumentKey = documentComments[index].documentKey
        documentComments[index].resolvedAt = Date()
        documentComments[index].updatedAt = Date()
        documentComments[index].reminderAt = nil
        if selectedCommentID == commentID {
            selectedCommentID = nil
        }
        commentReminderScheduler?.cancelReminder(commentID: commentID)
        persistCommentsSoon()
        if let buffer = buffers.first(where: { documentKey(for: $0) == commentDocumentKey }) {
            scheduleCompanionAutoScanIfNeeded(for: buffer.id)
        }
    }

    func deleteComment(_ commentID: UUID) {
        guard let index = documentComments.firstIndex(where: { $0.id == commentID }) else { return }

        let commentDocumentKey = documentComments[index].documentKey
        documentComments.remove(at: index)
        if selectedCommentID == commentID {
            selectedCommentID = nil
        }
        commentReminderScheduler?.cancelReminder(commentID: commentID)
        persistCommentsSoon()
        if let buffer = buffers.first(where: { documentKey(for: $0) == commentDocumentKey }) {
            scheduleCompanionAutoScanIfNeeded(for: buffer.id)
        }
    }

    func scheduleCommentReminder(_ commentID: UUID, after interval: TimeInterval) {
        guard let index = documentComments.firstIndex(where: { $0.id == commentID }) else { return }

        documentComments[index].reminderAt = Date().addingTimeInterval(interval)
        documentComments[index].updatedAt = Date()
        commentReminderScheduler?.scheduleReminder(for: documentComments[index])
        persistCommentsSoon()
    }

    func clearCommentReminder(_ commentID: UUID) {
        guard let index = documentComments.firstIndex(where: { $0.id == commentID }) else { return }

        documentComments[index].reminderAt = nil
        documentComments[index].updatedAt = Date()
        commentReminderScheduler?.cancelReminder(commentID: commentID)
        persistCommentsSoon()
    }

    var detectedTasks: [DetectedTask] {
        let openFilePaths = Set(buffers.compactMap(\.filePath))
        let openBufferTasks = buffers.flatMap { buffer -> [DetectedTask] in
            guard buffer.language.supportsTaskScanning else { return [] }
            return MarkdownTaskScanner.scan(buffer.text).map { match in
                DetectedTask(
                    bufferID: buffer.id,
                    bufferTitle: buffer.displayTitle,
                    filePath: buffer.filePath,
                    title: match.title,
                    status: match.status,
                    lineNumber: match.lineNumber,
                    lineRange: match.lineRange,
                    markerRange: match.markerRange,
                    updateMode: match.updateMode
                )
            }
        }
        let catalogTasks = documentCatalogTasks.filter { task in
            guard let filePath = task.filePath else { return true }
            return !openFilePaths.contains(filePath)
        }
        return openBufferTasks + catalogTasks
    }

    func taskCards(for status: TaskBoardStatus) -> [TaskBoardCard] {
        let manualCards = (globalManualTasks + manualTasks)
            .filter { $0.status == status }
            .map(TaskBoardCard.manual)
        let detectedCards = detectedTasks
            .filter { $0.status == status }
            .map(TaskBoardCard.detected)
        return manualCards + detectedCards
    }

    func addManualTaskWithPrompt() {
        let alert = NSAlert()
        alert.messageText = "New Task"
        alert.informativeText = "Add a global SimpleLime task."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Task title"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        addManualTask(title: field.stringValue, scope: .global)
    }

    func addManualTask(
        title: String,
        status: TaskBoardStatus = .todo,
        scope: ManualTaskScope = .workspace
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch scope {
        case .workspace:
            manualTasks.insert(.new(title: trimmed, status: status, scope: .workspace), at: 0)
            persistManualTasks()
        case .global:
            globalManualTasks.insert(.new(title: trimmed, status: status, scope: .global), at: 0)
            persistGlobalManualTasks()
            onGlobalManualTasksChanged?(globalManualTasks)
        }
        scheduleCompanionAutoScanIfNeeded(for: selectedBufferID)
    }

    func runAITaskInference(scope: ManualTaskScope = .workspace) {
        cancelTaskAIAutoInference(clearQueuedStatus: true)
        runAITaskInference(scope: scope, showsPanel: true, isAutomatic: false)
    }

    private func scheduleTaskAIAutoInferenceIfNeeded(for bufferID: UUID?) {
        guard isTaskAIAutoInferenceEnabled else { return }
        cancelTaskAIAutoInference(clearQueuedStatus: false)

        guard let bufferID,
              let buffer = buffers.first(where: { $0.id == bufferID }),
              buffer.language.supportsTaskScanning,
              !buffer.isLargeFileMode,
              !buffer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if taskAIInferenceStatus == Self.taskAIAutoInferenceQueuedStatus {
                taskAIInferenceStatus = nil
            }
            return
        }

        taskAIAutoInferenceGeneration += 1
        let generation = taskAIAutoInferenceGeneration
        let delay = taskAIAutoInferenceDelayNanoseconds
        taskAIInferenceStatus = Self.taskAIAutoInferenceQueuedStatus

        taskAIAutoInferenceTask = Task { [weak self, bufferID, generation, delay] in
            do {
                try await Task.sleep(nanoseconds: delay)
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          self.taskAIAutoInferenceGeneration == generation,
                          self.selectedBufferID == bufferID else {
                        return
                    }
                    self.taskAIAutoInferenceTask = nil
                    self.runAITaskInference(scope: .workspace, showsPanel: false, isAutomatic: true)
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.taskAIAutoInferenceGeneration == generation else {
                        return
                    }
                    self.taskAIAutoInferenceTask = nil
                    if self.taskAIInferenceStatus == Self.taskAIAutoInferenceQueuedStatus {
                        self.taskAIInferenceStatus = nil
                    }
                }
            }
        }
    }

    private func cancelTaskAIAutoInference(clearQueuedStatus: Bool) {
        taskAIAutoInferenceTask?.cancel()
        taskAIAutoInferenceTask = nil
        taskAIAutoInferenceGeneration += 1
        if clearQueuedStatus,
           taskAIInferenceStatus == Self.taskAIAutoInferenceQueuedStatus {
            taskAIInferenceStatus = nil
        }
    }

    private func runAITaskInference(
        scope: ManualTaskScope,
        showsPanel: Bool,
        isAutomatic: Bool
    ) {
        let context = aiTaskInferenceContext()
        guard !context.isEmpty else {
            if showsPanel {
                lastError = "Open a text document before asking AI to infer tasks."
                showTasksPanel()
            } else if taskAIInferenceStatus == Self.taskAIAutoInferenceQueuedStatus {
                taskAIInferenceStatus = nil
            }
            return
        }

        if isAutomatic,
           context == lastTaskAIAutoInferenceContext {
            if taskAIInferenceStatus == Self.taskAIAutoInferenceQueuedStatus {
                taskAIInferenceStatus = nil
            }
            return
        }

        let client: any HTTPAICompleting
        do {
            client = httpAIClientFactory(try httpAIConfigurationProvider())
        } catch {
            if showsPanel {
                lastError = "AI task inference requires HTTP LLM settings: \(error.localizedDescription)"
                showTasksPanel()
            } else {
                taskAIInferenceStatus = "AI task auto-inference paused: \(error.localizedDescription)"
            }
            return
        }

        taskAIInferenceTask?.cancel()
        if showsPanel {
            showTasksPanel()
        }
        isTaskAIInferenceRunning = true
        taskAIInferenceStatus = "Inferring tasks..."

        let prompt = AITaskInference.userPrompt(context: context)
        taskAIInferenceTask = Task { [weak self, context, isAutomatic] in
            do {
                let response = try await client.complete(
                    messages: [
                        HTTPAIChatMessage(role: "user", content: prompt)
                    ],
                    systemPrompt: AITaskInference.systemPrompt
                )
                let inferredTasks = AITaskInference.parse(response)

                try Task.checkCancellation()
                await MainActor.run {
                    guard let self else { return }
                    let addedCount = self.addInferredManualTasks(inferredTasks, scope: scope)
                    if isAutomatic {
                        self.lastTaskAIAutoInferenceContext = context
                        self.taskAIInferenceStatus = addedCount == 0
                            ? "AI auto-inference found no new tasks."
                            : "Auto-added \(addedCount) AI task\(addedCount == 1 ? "" : "s")."
                    } else {
                        self.taskAIInferenceStatus = addedCount == 0
                            ? "No new AI tasks found."
                            : "Added \(addedCount) AI task\(addedCount == 1 ? "" : "s")."
                    }
                    self.isTaskAIInferenceRunning = false
                    self.taskAIInferenceTask = nil
                }
            } catch {
                await MainActor.run {
                    if Task.isCancelled {
                        self?.taskAIInferenceStatus = isAutomatic ? nil : "Cancelled."
                    } else {
                        self?.taskAIInferenceStatus = "AI task inference error: \(error.localizedDescription)"
                    }
                    self?.isTaskAIInferenceRunning = false
                    self?.taskAIInferenceTask = nil
                }
            }
        }
    }

    private func addInferredManualTasks(
        _ inferredTasks: [AITaskInferenceResult],
        scope: ManualTaskScope
    ) -> Int {
        var existingTitles = Set(
            (manualTasks + globalManualTasks).map { normalizedTaskTitle($0.title) } +
            detectedTasks.map { normalizedTaskTitle($0.title) }
        )
        var addedCount = 0

        for task in inferredTasks {
            let key = normalizedTaskTitle(task.title)
            guard !key.isEmpty,
                  existingTitles.insert(key).inserted else {
                continue
            }

            addManualTask(title: task.title, status: task.status, scope: scope)
            addedCount += 1
        }

        return addedCount
    }

    private func normalizedTaskTitle(_ title: String) -> String {
        title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private func aiTaskInferenceContext() -> String {
        let orderedBuffers = buffers.sorted { left, right in
            if left.id == selectedBufferID { return true }
            if right.id == selectedBufferID { return false }
            return left.updatedAt > right.updatedAt
        }

        var sections: [String] = []
        var remainingCharacters = 20_000

        for buffer in orderedBuffers.prefix(8) {
            guard buffer.language.supportsTaskScanning,
                  !buffer.isLargeFileMode,
                  !buffer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  remainingCharacters > 0 else {
                continue
            }

            let path = buffer.filePath.map { "\nPath: \($0)" } ?? ""
            let text = String(buffer.text.prefix(remainingCharacters))
            remainingCharacters -= text.count
            sections.append(
                """
                Document: \(buffer.displayTitle)
                Language: \(buffer.language.displayName)\(path)
                Text:
                \(text)
                """
            )
        }

        if remainingCharacters <= 0 {
            sections.append("[SimpleLime truncated task inference context.]")
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    func updateManualTask(_ taskID: UUID, status: TaskBoardStatus) {
        if let index = manualTasks.firstIndex(where: { $0.id == taskID }) {
            manualTasks[index].status = status
            manualTasks[index].updatedAt = Date()
            persistManualTasks()
            scheduleCompanionAutoScanIfNeeded(for: selectedBufferID)
            return
        }

        guard let index = globalManualTasks.firstIndex(where: { $0.id == taskID }) else { return }
        globalManualTasks[index].status = status
        globalManualTasks[index].updatedAt = Date()
        persistGlobalManualTasks()
        onGlobalManualTasksChanged?(globalManualTasks)
        scheduleCompanionAutoScanIfNeeded(for: selectedBufferID)
    }

    func deleteManualTask(_ taskID: UUID) {
        var didChange = false
        let workspaceCount = manualTasks.count
        manualTasks.removeAll { $0.id == taskID }
        if manualTasks.count != workspaceCount {
            persistManualTasks()
            didChange = true
        }

        let globalCount = globalManualTasks.count
        globalManualTasks.removeAll { $0.id == taskID }
        if globalManualTasks.count != globalCount {
            persistGlobalManualTasks()
            onGlobalManualTasksChanged?(globalManualTasks)
            didChange = true
        }
        if didChange {
            scheduleCompanionAutoScanIfNeeded(for: selectedBufferID)
        }
    }

    func replaceGlobalManualTasks(_ tasks: [ManualTask]) {
        globalManualTasks = Self.tasks(tasks, normalizedTo: .global)
        scheduleCompanionAutoScanIfNeeded(for: selectedBufferID)
    }

    func openDetectedTask(_ task: DetectedTask) {
        if let bufferID = task.bufferID {
            selectedBufferID = bufferID
            jumpToLine(task.lineNumber)
            return
        }

        guard let filePath = task.filePath else { return }
        openFile(at: URL(fileURLWithPath: filePath), lineNumber: task.lineNumber)
    }

    func updateDetectedTask(_ task: DetectedTask, status: TaskBoardStatus) {
        if let bufferID = task.bufferID {
            updateOpenDetectedTask(task, status: status, bufferID: bufferID)
            return
        }

        updateDocumentCatalogDetectedTask(task, status: status)
    }

    private func updateOpenDetectedTask(_ task: DetectedTask, status: TaskBoardStatus, bufferID: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }) else { return }

        let nsText = buffers[index].text as NSString
        let mutable = NSMutableString(string: buffers[index].text)

        switch task.updateMode {
        case .markdownMarker:
            let markerRange = task.markerRange.nsRange
            guard markerRange.location != NSNotFound,
                  markerRange.location + markerRange.length <= nsText.length else {
                return
            }

            mutable.replaceCharacters(in: markerRange, with: status.markdownTaskMarker)
        case .lineToMarkdownChecklist:
            let lineRange = task.lineRange.nsRange
            guard lineRange.location != NSNotFound,
                  lineRange.location + lineRange.length <= nsText.length else {
                return
            }

            mutable.replaceCharacters(
                in: lineRange,
                with: markdownChecklistLine(from: nsText.substring(with: lineRange), task: task, status: status)
            )
        }

        updateText(mutable as String, in: bufferID)
    }

    private func updateDocumentCatalogDetectedTask(_ task: DetectedTask, status: TaskBoardStatus) {
        guard let filePath = task.filePath else { return }

        let url = URL(fileURLWithPath: filePath)
        do {
            var encoding = String.Encoding.utf8
            let text = try String(contentsOf: url, usedEncoding: &encoding)
            let nsText = text as NSString
            let mutable = NSMutableString(string: text)
            switch task.updateMode {
            case .markdownMarker:
                let markerRange = task.markerRange.nsRange
                guard markerRange.location != NSNotFound,
                      markerRange.location + markerRange.length <= nsText.length else {
                    return
                }

                mutable.replaceCharacters(in: markerRange, with: status.markdownTaskMarker)
            case .lineToMarkdownChecklist:
                let lineRange = task.lineRange.nsRange
                guard lineRange.location != NSNotFound,
                      lineRange.location + lineRange.length <= nsText.length else {
                    return
                }

                mutable.replaceCharacters(
                    in: lineRange,
                    with: markdownChecklistLine(from: nsText.substring(with: lineRange), task: task, status: status)
                )
            }
            try (mutable as String).write(to: url, atomically: true, encoding: encoding)
            refreshDocumentCatalogTasks()
        } catch {
            lastError = "Could not update \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func markdownChecklistLine(
        from originalLine: String,
        task: DetectedTask,
        status: TaskBoardStatus
    ) -> String {
        let newline: String
        let body: String
        if originalLine.hasSuffix("\r\n") {
            newline = "\r\n"
            body = String(originalLine.dropLast(2))
        } else if originalLine.hasSuffix("\n") || originalLine.hasSuffix("\r") {
            newline = String(originalLine.suffix(1))
            body = String(originalLine.dropLast())
        } else {
            newline = ""
            body = originalLine
        }

        let indent = String(body.prefix { $0 == " " || $0 == "\t" })
        return "\(indent)- [\(status.markdownTaskMarker)] \(task.title)\(newline)"
    }

    var usageStatsSummaries: [UsageStatsSummary] {
        [
            usageStatsSummary(title: "Today", dayCount: 1),
            usageStatsSummary(title: "7 Days", dayCount: 7),
            usageStatsSummary(title: "30 Days", dayCount: 30),
            usageStatsSummary(title: "365 Days", dayCount: 365)
        ]
    }

    func usageStatsSummary(title: String, dayCount: Int, now: Date = Date()) -> UsageStatsSummary {
        let ids = UsageStatsClock.recentDayIdentifiers(count: dayCount, from: now)
        return UsageStatsSummary.make(title: title, days: usageStats.filter { ids.contains($0.day) })
    }

    var todayUsageTimeline: [UsageTimelineEntry] {
        usageStatsSummary(title: "Today", dayCount: 1).timelineEntries
    }

    func createTodayTimelogScratch(now: Date = Date()) {
        let dayID = UsageStatsClock.dayIdentifier(for: now)
        let nextIndex = buffers.filter { $0.title.hasPrefix("Timelog ") }.count + 1
        var buffer = EditorBuffer.scratch(index: buffers.filter { $0.kind == .scratch }.count + 1)
        buffer.title = nextIndex == 1 ? "Timelog \(dayID)" : "Timelog \(dayID) \(nextIndex)"
        buffer.text = todayTimelogMarkdown(now: now)
        buffer.language = .markdown
        buffer.isDirty = true
        buffer.updatedAt = now
        buffers.append(buffer)
        selectedBufferID = buffer.id
        persistSoon()
    }

    func createEditorDiagnosticsScratch(now: Date = Date()) {
        guard let sourceBuffer = selectedBuffer else {
            lastError = "No buffer selected for editor diagnostics."
            return
        }

        let dayID = UsageStatsClock.dayIdentifier(for: now)
        let nextIndex = buffers.filter { $0.title.hasPrefix("Editor Diagnostics ") }.count + 1
        var buffer = EditorBuffer.scratch(index: buffers.filter { $0.kind == .scratch }.count + 1)
        buffer.title = nextIndex == 1
            ? "Editor Diagnostics \(dayID)"
            : "Editor Diagnostics \(dayID) \(nextIndex)"
        buffer.text = editorDiagnosticsMarkdown(for: sourceBuffer, now: now)
        buffer.language = .markdown
        buffer.isDirty = true
        buffer.updatedAt = now
        buffers.append(buffer)
        selectedBufferID = buffer.id
        persistSoon()
    }

    func resetUsageStats() {
        usageStats = []
        lastEditingActivityAt = nil
        resetCompanionUsageActivityTracking()
        persistUsageStats()
    }

    private func todayTimelogMarkdown(now: Date = Date()) -> String {
        let dayID = UsageStatsClock.dayIdentifier(for: now)
        let summary = usageStatsSummary(title: "Today", dayCount: 1, now: now)
        let entries = usageStats
            .first { $0.day == dayID }?
            .timelineEntries
            .sorted { $0.timestamp < $1.timestamp } ?? []

        var lines: [String] = [
            "# Timelog \(dayID)",
            "",
            "## Summary",
            "- Edits: \(summary.editCount)",
            "- Added: \(summary.charactersAdded)",
            "- Removed: \(summary.charactersRemoved)",
            "- Opens: \(summary.openCount)",
            "- Saves: \(summary.saveCount)",
            "- Exports: \(summary.exportCount)",
            "- Macros: \(summary.macroCount)",
            "- Active editing: \(Self.timelogDurationText(summary.activeEditingSeconds))",
            "- Documents: \(summary.uniqueDocumentCount) (files: \(summary.uniqueFileCount), scratches: \(summary.uniqueScratchCount))",
            "",
            "## Activity"
        ]

        if entries.isEmpty {
            lines.append("- No activity recorded today.")
        } else {
            lines.append(contentsOf: entries.map(Self.timelogActivityLine))
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func editorDiagnosticsMarkdown(for buffer: EditorBuffer, now: Date) -> String {
        let dayID = UsageStatsClock.dayIdentifier(for: now)
        let characterCount = buffer.text.count
        let byteCount = buffer.text.utf8.count
        let lineCount = Self.editorDiagnosticsLineCount(in: buffer.text)
        let selectionLength = buffer.selectionRanges.reduce(0) { $0 + max(0, $1.length) }
        let largeFileThreshold = LargeFileConfiguration.thresholdBytes(for: buffer.language)
        let previewLimit = LargeFileConfiguration.previewByteLimit(for: buffer.language)
        let fileSize = buffer.fileSizeBytes ?? Int64(byteCount)
        let wouldUseLargeFileMode = Self.shouldUseLargeFileMode(
            fileSizeBytes: fileSize,
            language: buffer.language
        )
        let largeFileEditingCapability = largeFileEditingCapability(for: buffer)

        var lines: [String] = [
            "# Editor Diagnostics \(dayID)",
            "",
            "## Buffer",
            "- Title: \(Self.editorDiagnosticsValue(buffer.displayTitle))",
            "- Kind: \(buffer.kind.rawValue)",
            "- Path: \(Self.editorDiagnosticsValue(buffer.filePath))",
            "- Language: \(buffer.language.displayName)",
            "- Save policy: \(buffer.savePolicy.displayName)",
            "- Dirty: \(Self.yesNo(buffer.isDirty))",
            "- Encrypted: \(Self.yesNo(buffer.isEncrypted))",
            "",
            "## Size",
            "- Characters loaded: \(characterCount)",
            "- UTF-8 bytes loaded: \(Self.editorDiagnosticsByteText(Int64(byteCount)))",
            "- Lines loaded: \(lineCount)",
            "- Selection ranges: \(buffer.selectionRanges.count)",
            "- Selected characters: \(selectionLength)",
            "",
            "## Rendering",
            "- Active editor path: \(editorDiagnosticsRenderPath(for: buffer))",
            "- Syntax highlighting: \(buffer.language.needsDebouncedSyntaxHighlighting ? "Debounced" : "Off")",
            "- Complex syntax limit: \(Self.editorDiagnosticsComplexHighlightCharacterLimit) characters",
            "- Structured fold gutter: \(Self.yesNo(buffer.language.supportsStructuredFoldGutter && !buffer.isLargeFileMode))",
            "- Markdown preview: \(Self.yesNo(isPreviewVisible))",
            "- Markdown WYSIWYG: \(Self.yesNo(isWysiwygModeEnabled))",
            "- Minimap: \(Self.yesNo(isMiniMapVisible))",
            "- Focus mode: \(Self.yesNo(isFocusModeEnabled))",
            "- Typewriter mode: \(Self.yesNo(isTypewriterModeEnabled))",
            "- Word wrap: \(Self.yesNo(wrapsLines))",
            "- Font size: \(Int(fontSize.rounded()))",
            "- Column guide: \(columnGuide == 0 ? "Off" : "\(columnGuide)")",
            "",
            "## Large-File Policy",
            "- Large-file mode: \(Self.yesNo(buffer.isLargeFileMode))",
            "- Mode threshold: \(Self.editorDiagnosticsByteText(largeFileThreshold))",
            "- Preview chunk size: \(Self.editorDiagnosticsByteText(Int64(previewLimit)))",
            "- File size: \(Self.editorDiagnosticsByteText(fileSize))",
            "- Would use large-file mode from current metadata: \(Self.yesNo(wouldUseLargeFileMode))"
        ]

        if buffer.isLargeFileMode {
            lines.append(contentsOf: [
                "- Preview start: \(Self.editorDiagnosticsByteText(buffer.largeFilePreviewStartOffsetBytes ?? 0))",
                "- Preview loaded: \(Self.editorDiagnosticsByteText(Int64(buffer.largeFilePreviewByteCount ?? byteCount)))",
                "- Source path: \(Self.editorDiagnosticsValue(buffer.largeFileSourcePath ?? buffer.filePath))",
                "- Chunk can be saved back: \(Self.yesNo(Self.editorDiagnosticsCanSaveChunkBack(buffer)))"
            ])
        }

        lines.append(contentsOf: [
            "",
            "## Large-File Editing Capability",
            "- Status: \(largeFileEditingCapability.status)",
            "- Detail: \(largeFileEditingCapability.detail)",
            "- Can edit loaded text: \(Self.yesNo(largeFileEditingCapability.canEditLoadedText))",
            "- Can enable in-place chunk editing: \(Self.yesNo(largeFileEditingCapability.canEnableInPlaceChunkEditing))",
            "- Can save chunk back: \(Self.yesNo(largeFileEditingCapability.canSaveChunkBack))",
            "",
            "## Editor Core Compatibility"
        ])
        lines.append(contentsOf: editorDiagnosticsCompatibilityLines(for: buffer))
        lines.append(contentsOf: [
            "",
            "## Editor Core Acceptance Gates"
        ])
        lines.append(contentsOf: editorDiagnosticsAcceptanceGateLines(
            for: buffer,
            byteCount: byteCount,
            lineCount: lineCount,
            fileSize: fileSize,
            wouldUseLargeFileMode: wouldUseLargeFileMode
        ))
        lines.append(contentsOf: [
            "",
            "## Risk Flags"
        ])
        lines.append(contentsOf: editorDiagnosticsRiskLines(
            for: buffer,
            characterCount: characterCount,
            byteCount: byteCount,
            lineCount: lineCount,
            wouldUseLargeFileMode: wouldUseLargeFileMode
        ))
        lines.append(contentsOf: [
            "",
            "## Notes",
            "- This report uses cheap buffer metadata. It does not measure keystroke latency or AppKit selection latency.",
            "- For real input-lag work, profile the source editor with Instruments while typing, selecting, scrolling, and switching syntax modes.",
            ""
        ])

        return lines.joined(separator: "\n")
    }

    private func editorDiagnosticsRenderPath(for buffer: EditorBuffer) -> String {
        if buffer.language.isBinaryPreview {
            return "Binary preview"
        }
        if buffer.language.isWhiteboard {
            return "Whiteboard canvas"
        }
        if buffer.isLargeFileMode, bufferCanEditLargeFileChunk(buffer) {
            return "Large-file editable chunk"
        }
        if buffer.isLargeFileMode, buffer.language.isDelimitedTable {
            return "Large-file virtual table/source preview"
        }
        if buffer.isLargeFileMode {
            return "Large-file virtual source preview"
        }
        if isWysiwygModeEnabled, buffer.language.isMarkdown {
            return "Markdown WYSIWYG editor"
        }
        if isPreviewVisible, buffer.language.supportsRenderedPreview {
            return "Split source and rendered preview"
        }
        if sourceEditorEngine == .nativeSTTextView {
            return "STTextView source editor"
        }
        return "\(sourceEditorEngine.title) source editor"
    }

    private func editorDiagnosticsCompatibilityLines(for buffer: EditorBuffer) -> [String] {
        var lines = [
            "| Feature | Status | Notes |",
            "| --- | --- | --- |"
        ]

        for feature in SourceEditorFeature.allCases {
            let result = editorDiagnosticsCompatibilityResult(for: feature, buffer: buffer)
            lines.append(
                "| \(feature.title) | \(result.status) | \(Self.editorDiagnosticsTableValue(result.note)) |"
            )
        }

        return lines
    }

    private func editorDiagnosticsCompatibilityResult(
        for feature: SourceEditorFeature,
        buffer: EditorBuffer
    ) -> (status: String, note: String) {
        if buffer.language.isBinaryPreview {
            return feature == .diagnostics
                ? ("Yes", "Binary preview metadata is reported.")
                : ("N/A", "Binary previews do not use the source editor core.")
        }

        if buffer.language.isWhiteboard {
            return feature == .diagnostics
                ? ("Yes", "Whiteboard metadata is reported.")
                : ("N/A", "Whiteboards use the canvas renderer, not the source editor core.")
        }

        if buffer.isLargeFileMode {
            return editorDiagnosticsLargeFileCompatibilityResult(for: feature, buffer: buffer)
        }

        let engine = sourceEditorEngine
        switch feature {
        case .multipleSelections:
            return engine.supports(feature)
                ? ("Yes", "Multiple source selections are routed through the active source engine.")
                : ("No", "The active source engine does not expose this feature.")
        case .columnSelection:
            return engine.supports(feature)
                ? ("Yes", "Column selections are routed through the active source engine.")
                : ("No", "The active source engine does not expose this feature.")
        case .syntaxHighlighting:
            return engine.supports(feature)
                ? ("Yes", buffer.language.needsDebouncedSyntaxHighlighting ? "Debounced for source languages." : "Language does not need source syntax highlighting.")
                : ("No", "The active source engine does not expose this feature.")
        case .structuredFolding:
            return engine.supports(feature) && buffer.language.supportsStructuredFoldGutter
                ? ("Yes", "Available for structured source languages.")
                : ("N/A", "Current language does not expose structured fold regions.")
        case .minimapSource:
            return engine.supports(feature)
                ? ("Yes", "Available in normal source mode.")
                : ("No", "The active source engine does not expose this feature.")
        case .macrosTemplates:
            return engine.supports(feature)
                ? ("Yes", "Macros and templates apply through source text commands.")
                : ("No", "The active source engine does not expose this feature.")
        case .formattingCommands:
            return engine.supports(feature)
                ? ("Yes", "Formatting commands apply to the normal loaded source text.")
                : ("No", "The active source engine does not expose this feature.")
        case .largeFileSearchJump:
            return ("N/A", "Normal buffers use regular find and direct line navigation.")
        case .readOnlyTemporaryMode:
            return engine.supports(feature)
                ? ("Yes", buffer.savePolicy == .normal ? "Save policy is normal for this buffer." : "Current save policy blocks normal save writes.")
                : ("No", "The active source engine does not expose this feature.")
        case .largeFileChunkEditing:
            return ("N/A", "Normal buffers edit the loaded text directly.")
        case .largeFileFullEditing:
            return engine.supports(feature)
                ? ("Yes", "The active source engine advertises full-file virtual editing.")
                : ("No", "The active source engine does not expose full-file virtual editing; large files use read-only virtual browsing plus chunks.")
        default:
            return engine.supports(feature)
                ? ("Yes", "Provided by \(engine.title).")
                : ("No", "The active source engine does not expose this feature.")
        }
    }

    private func editorDiagnosticsLargeFileCompatibilityResult(
        for feature: SourceEditorFeature,
        buffer: EditorBuffer
    ) -> (status: String, note: String) {
        switch feature {
        case .textEditing:
            return ("Chunk-only", "The virtual full-file preview is read-only; edit exact chunks or extract a scratch.")
        case .multipleSelections:
            return ("Chunk-only", "Use an editable chunk for multiple selections.")
        case .columnSelection:
            return ("Chunk-only", "Use an editable chunk for column selections.")
        case .selectionReporting:
            return ("No", "The virtual preview avoids editable text selection to keep large-file rendering cheap.")
        case .commandRouting:
            return ("Limited", "Paging, full-file search, line jumps, chunk extraction, and chunk save-back are routed.")
        case .visibleRangeReporting:
            return ("Yes", "Visible rows are virtualized and prefetched off the main thread.")
        case .syntaxHighlighting:
            return buffer.language.needsDebouncedSyntaxHighlighting
                ? ("Visible rows", "Highlighting is bounded to visible virtual source rows.")
                : ("N/A", "Current language does not need source syntax highlighting.")
        case .structuredFolding:
            return ("No", "Folding is disabled in the virtual large-file preview.")
        case .comments:
            return ("No", "Comments are not anchored into the virtual full-file preview.")
        case .collaborationSelections:
            return ("No", "Collaboration selections are not anchored into the virtual full-file preview.")
        case .findReplaceBridge:
            return ("Line replace", "Full-file exact search, line jumps, and single-line virtual replacement are available; broad replace still requires editable chunks.")
        case .minimapSource:
            return ("No", "Minimap is disabled for large-file virtual previews.")
        case .macrosTemplates:
            return ("Chunk-only", "Macros and templates apply after enabling or extracting an editable chunk.")
        case .formattingCommands:
            return ("Chunk-only", "Formatters apply after enabling or extracting an editable chunk.")
        case .largeFileSearchJump:
            return ("Yes", "Full-file exact search and line jumps load matching virtual chunks.")
        case .readOnlyTemporaryMode:
            return ("Yes", "The virtual full-file preview is read-only by policy.")
        case .diagnostics:
            return ("Yes", "Large-file policy and risk metadata are reported.")
        case .largeFileChunkEditing:
            return Self.editorDiagnosticsCanSaveChunkBack(buffer)
                ? ("Yes", "Exact-boundary chunks can be edited and saved back when source size still matches.")
                : ("Scratch-only", "Chunk extraction is available, but this buffer lacks save-back metadata.")
        case .largeFileFullEditing:
            return ("No", "Requires a replacement editor core with a true virtual editable document model.")
        }
    }

    private func editorDiagnosticsAcceptanceGateLines(
        for buffer: EditorBuffer,
        byteCount: Int,
        lineCount: Int,
        fileSize: Int64,
        wouldUseLargeFileMode: Bool
    ) -> [String] {
        let context = SourceEditorAcceptanceGateContext(
            language: buffer.language,
            isLargeFileMode: buffer.isLargeFileMode,
            fileSizeBytes: fileSize,
            loadedByteCount: byteCount,
            lineCount: lineCount,
            wouldUseLargeFileMode: wouldUseLargeFileMode,
            isMiniMapVisible: isMiniMapVisible,
            canSaveLargeFileChunkBack: Self.editorDiagnosticsCanSaveChunkBack(buffer),
            hasLargeFileSourcePath: buffer.largeFileSourcePath != nil || buffer.filePath != nil
        )
        var lines = [
            "| Gate | Status | Evidence | Next action |",
            "| --- | --- | --- | --- |"
        ]
        lines.append(contentsOf: SourceEditorAcceptanceGate.evaluate(context).map { check in
            "| \(check.title) | \(check.status.title) | \(Self.editorDiagnosticsTableValue(check.evidence)) | \(Self.editorDiagnosticsTableValue(check.nextAction)) |"
        })
        return lines
    }

    private func editorDiagnosticsRiskLines(
        for buffer: EditorBuffer,
        characterCount: Int,
        byteCount: Int,
        lineCount: Int,
        wouldUseLargeFileMode: Bool
    ) -> [String] {
        var lines: [String] = []

        if buffer.isLargeFileMode {
            lines.append("- Full-file editable model: Not available. The current path shows virtual previews, bounded editable chunks, and single-line virtual replacement.")
            if buffer.language.isDelimitedTable {
                lines.append("- Table rendering is virtualized; full CSV editing still happens through source/chunk text.")
            }
        } else if wouldUseLargeFileMode {
            lines.append("- This buffer exceeds the large-file threshold but is loaded through the normal source editor.")
        }

        if buffer.language.needsDebouncedSyntaxHighlighting,
           characterCount > Self.editorDiagnosticsComplexHighlightCharacterLimit {
            lines.append("- Complex syntax highlighting is skipped above \(Self.editorDiagnosticsComplexHighlightCharacterLimit) characters, but base text attributes still touch the loaded text.")
        }

        if lineCount >= 20_000, !buffer.isLargeFileMode {
            lines.append("- More than 20,000 lines are loaded into the normal source editor. Cursor, selection, minimap, fold gutter, and focus mode need manual latency QA here.")
        }

        if byteCount >= LargeFileConfiguration.defaultComplexThresholdBytes, !buffer.isLargeFileMode {
            lines.append("- Loaded text is at or above the default complex-file threshold. Prefer virtual source/table rendering until the editable text engine is replaced.")
        }

        if isMiniMapVisible, lineCount >= 10_000, !buffer.isLargeFileMode {
            lines.append("- Minimap is enabled on a large normal buffer; this can amplify scrolling and selection work.")
        }

        if lines.isEmpty {
            lines.append("- No large-file/editor risk flags were detected by metadata checks.")
        }

        return lines
    }

    private static func editorDiagnosticsCanSaveChunkBack(_ buffer: EditorBuffer) -> Bool {
        buffer.largeFileSourcePath != nil &&
            buffer.largeFileSourceStartOffsetBytes != nil &&
            buffer.largeFileSourceByteCount != nil &&
            buffer.largeFileSourceFileSizeBytes != nil
    }

    private static func editorDiagnosticsLineCount(in text: String) -> Int {
        guard !text.isEmpty else { return 1 }
        return text.unicodeScalars.reduce(1) { count, scalar in
            scalar == "\n" ? count + 1 : count
        }
    }

    private static func editorDiagnosticsValue(_ value: String?) -> String {
        guard let value,
              !value.isEmpty else {
            return "None"
        }

        return value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func editorDiagnosticsTableValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func editorDiagnosticsByteText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: bytes)) (\(bytes) bytes)"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private static func timelogActivityLine(for entry: UsageTimelineEntry) -> String {
        var detail = "- \(timelogTimeText(for: entry.timestamp)) - \(timelogTitleText(entry.title)) (\(entry.kind.rawValue))"
        if entry.durationSeconds > 0 {
            detail += ", \(timelogDurationText(entry.durationSeconds))"
        }
        return detail
    }

    private static func timelogTitleText(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timelogTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func timelogDurationText(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        return remainderMinutes > 0 ? "\(hours)h \(remainderMinutes)m" : "\(hours)h"
    }

    var textMacros: [TextMacro] {
        TextMacro.builtIns + customTextMacros
    }

    var pinnedMacroButtons: [PinnedMacroButton] {
        pinnedMacros.compactMap { reference in
            switch reference.kind {
            case .text:
                guard let macro = textMacros.first(where: { $0.id == reference.macroID }) else {
                    return nil
                }
                return PinnedMacroButton(
                    reference: reference,
                    title: macro.title,
                    systemName: macro.isBuiltIn ? "doc.text" : "text.insert",
                    help: "Insert macro \(macro.title)"
                )
            case .action:
                guard let macro = customActionMacros.first(where: { $0.id == reference.macroID }) else {
                    return nil
                }
                return PinnedMacroButton(
                    reference: reference,
                    title: macro.title,
                    systemName: "play.fill",
                    help: "Play macro \(macro.title)"
                )
            }
        }
    }

    func applyTextMacro(
        _ macro: TextMacro,
        templateValues: [String: String]? = nil,
        now: Date = Date()
    ) {
        guard let body = resolvedTextMacroBody(for: macro, templateValues: templateValues, now: now) else {
            return
        }

        performActionMacroStep(.replaceSelection(body), recordsWhenCapturing: true) {
            insertTextAtSelections(body)
        }
        if let selectedBuffer {
            recordMacroUsage(
                title: "Inserted macro \(macro.title)",
                documentKey: documentKey(for: selectedBuffer)
            )
        }
    }

    private func resolvedTextMacroBody(
        for macro: TextMacro,
        templateValues: [String: String]?,
        now: Date
    ) -> String? {
        if let templateValues {
            return macro.expandedBody(values: templateValues, now: now)
        }

        guard macro.hasTemplateFields else {
            return macro.body
        }

        guard let values = promptForTextMacroTemplateValues(macro, now: now) else {
            return nil
        }

        return macro.expandedBody(values: values, now: now)
    }

    private func promptForTextMacroTemplateValues(_ macro: TextMacro, now: Date) -> [String: String]? {
        let fields = macro.templateFields
        guard !fields.isEmpty else { return [:] }

        let alert = NSAlert()
        alert.messageText = "Fill Template Fields"
        alert.informativeText = "Insert \(macro.title) after filling the template fields."
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 360).isActive = true

        var inputs: [(TextMacroTemplateField, NSTextField)] = []
        for field in fields {
            let label = NSTextField(labelWithString: field.name)
            label.font = .systemFont(ofSize: 11, weight: .semibold)

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
            input.stringValue = field.prefilledValue(now: now)
            input.placeholderString = field.defaultValue ?? field.name
            input.widthAnchor.constraint(equalToConstant: 360).isActive = true

            let row = NSStackView(views: [label, input])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 3
            stack.addArrangedSubview(row)
            inputs.append((field, input))
        }

        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return Dictionary(uniqueKeysWithValues: inputs.map { field, input in
            (field.name, input.stringValue)
        })
    }

    func isTextMacroPinned(_ id: String) -> Bool {
        pinnedMacros.contains(.text(id))
    }

    func isActionMacroPinned(_ id: String) -> Bool {
        pinnedMacros.contains(.action(id))
    }

    func toggleTextMacroPinned(_ id: String) {
        guard textMacros.contains(where: { $0.id == id }) else {
            lastError = "That text macro is no longer available."
            return
        }

        togglePinnedMacro(.text(id))
    }

    func toggleActionMacroPinned(_ id: String) {
        guard customActionMacros.contains(where: { $0.id == id }) else {
            lastError = "That recorded macro is no longer available."
            return
        }

        togglePinnedMacro(.action(id))
    }

    func applyPinnedMacro(_ reference: PinnedMacroReference) {
        switch reference.kind {
        case .text:
            guard let macro = textMacros.first(where: { $0.id == reference.macroID }) else {
                removePinnedMacro(reference)
                lastError = "That text macro is no longer available."
                return
            }
            applyTextMacro(macro)
        case .action:
            guard let macro = customActionMacros.first(where: { $0.id == reference.macroID }) else {
                removePinnedMacro(reference)
                lastError = "That recorded macro is no longer available."
                return
            }
            applyActionMacro(macro)
        }
    }

    func startActionMacroRecordingWithPrompt() {
        let alert = NSAlert()
        alert.messageText = "Record Action Macro"
        alert.informativeText = "Record editor actions and text insertions so they can be replayed in any file."
        alert.addButton(withTitle: "Record")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultActionMacroTitle()
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        startActionMacroRecording(title: field.stringValue)
    }

    func stopActionMacroRecordingWithPrompt() {
        guard let recording = actionMacroRecording else { return }

        let alert = NSAlert()
        alert.messageText = "Save Action Macro"
        alert.informativeText = "Save \(recording.steps.count) recorded action\(recording.steps.count == 1 ? "" : "s")."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = recording.title
        alert.accessoryView = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            _ = stopActionMacroRecording(title: field.stringValue)
        default:
            cancelActionMacroRecording()
        }
    }

    func startActionMacroRecording(title: String? = nil) {
        guard actionMacroRecording == nil else {
            lastError = "Stop the current macro recording before starting another one."
            return
        }

        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        actionMacroRecording = ActionMacroRecording(
            title: trimmed?.isEmpty == false ? trimmed! : defaultActionMacroTitle(),
            steps: [],
            startedAt: Date()
        )
        showMacrosPanel()
        networkShare.statusMessage = "Recording macro..."
    }

    @discardableResult
    func stopActionMacroRecording(title: String? = nil) -> ActionMacro? {
        guard let recording = actionMacroRecording else { return nil }
        actionMacroRecording = nil

        guard !recording.steps.isEmpty else {
            lastError = "No actions were recorded."
            return nil
        }

        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let macro = ActionMacro.custom(
            title: trimmed?.isEmpty == false ? trimmed! : recording.title,
            steps: recording.steps
        )
        customActionMacros.insert(macro, at: 0)
        persistTextMacros()
        if let selectedBuffer {
            recordMacroUsage(
                title: "Recorded macro \(macro.title)",
                documentKey: documentKey(for: selectedBuffer),
                durationSeconds: max(1, Int(Date().timeIntervalSince(recording.startedAt).rounded()))
            )
        }
        networkShare.statusMessage = "Saved macro \(macro.title)."
        return macro
    }

    func cancelActionMacroRecording() {
        actionMacroRecording = nil
        networkShare.statusMessage = "Macro recording discarded."
    }

    func applyActionMacro(_ macro: ActionMacro) {
        guard !macro.steps.isEmpty else { return }

        let startedAt = Date()
        let selectedDocumentKey = selectedBuffer.map { documentKey(for: $0) }
        actionMacroPlaybackDepth += 1
        defer { actionMacroPlaybackDepth -= 1 }

        for step in macro.steps {
            applyActionMacroStep(step)
        }

        if let selectedDocumentKey {
            recordMacroUsage(
                title: "Played macro \(macro.title)",
                documentKey: selectedDocumentKey,
                durationSeconds: max(1, Int(Date().timeIntervalSince(startedAt).rounded()))
            )
        }
        networkShare.statusMessage = "Played macro \(macro.title)."
    }

    func deleteCustomActionMacro(_ id: String) {
        customActionMacros.removeAll { $0.id == id }
        pinnedMacros.removeAll { $0 == .action(id) }
        persistTextMacros()
    }

    func createTextMacroFromSelectionWithPrompt() {
        guard let body = selectedMacroBody() else {
            lastError = "Select text before creating a macro."
            return
        }

        let alert = NSAlert()
        alert.messageText = "New Text Macro"
        alert.informativeText = "Save the selected text as a reusable macro/template."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultMacroTitle(for: body)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        addCustomTextMacro(title: field.stringValue, body: body)
    }

    @discardableResult
    func createTextMacroFromSelection(title: String) -> TextMacro? {
        guard let body = selectedMacroBody() else {
            lastError = "Select text before creating a macro."
            return nil
        }

        return addCustomTextMacro(title: title, body: body)
    }

    @discardableResult
    func addCustomTextMacro(title: String, body: String) -> TextMacro? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              !body.isEmpty else {
            return nil
        }

        let macro = TextMacro.custom(title: trimmedTitle, body: body)
        customTextMacros.insert(macro, at: 0)
        persistTextMacros()
        return macro
    }

    func deleteCustomTextMacro(_ id: String) {
        customTextMacros.removeAll { $0.id == id && !$0.isBuiltIn }
        pinnedMacros.removeAll { $0 == .text(id) }
        persistTextMacros()
    }

    private func togglePinnedMacro(_ reference: PinnedMacroReference) {
        if pinnedMacros.contains(reference) {
            removePinnedMacro(reference)
        } else {
            guard pinnedMacros.count < Self.maxPinnedMacroButtons else {
                lastError = "Unpin another macro before adding more buttons."
                return
            }

            pinnedMacros.append(reference)
            persistTextMacros()
            networkShare.statusMessage = "Pinned macro button."
        }
    }

    private func removePinnedMacro(_ reference: PinnedMacroReference) {
        pinnedMacros.removeAll { $0 == reference }
        persistTextMacros()
        networkShare.statusMessage = "Unpinned macro button."
    }

    private func selectedMacroBody() -> String? {
        guard let selectedIndex else { return nil }
        let buffer = buffers[selectedIndex]
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        guard !ranges.isEmpty else { return nil }

        let nsText = buffer.text as NSString
        return ranges
            .map { nsText.substring(with: $0.nsRange) }
            .joined(separator: "\n")
    }

    private func defaultMacroTitle(for body: String) -> String {
        let firstLine = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Macro"
        let stripped = firstLine
            .replacingOccurrences(of: #"^[#>\-\*\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = stripped.isEmpty ? "Macro" : stripped
        if title.count <= 40 {
            return title
        }
        return "\(title.prefix(40))"
    }

    private func defaultActionMacroTitle() -> String {
        "Action Macro \(customActionMacros.count + 1)"
    }

    private func insertTextAtSelections(_ insertion: String) {
        guard let selectedIndex else {
            return
        }

        let bufferID = buffers[selectedIndex].id
        let text = buffers[selectedIndex].text
        let ranges = normalizedRanges(buffers[selectedIndex].selectionRanges, in: text)
        let targetRanges = ranges.isEmpty ? [.zero] : ranges
        guard !insertion.isEmpty || targetRanges.contains(where: { $0.length > 0 }) else {
            return
        }
        let mutable = NSMutableString(string: text)
        var newSelections: [TextRange] = []

        for range in targetRanges.sorted(by: { $0.location > $1.location }) {
            mutable.replaceCharacters(in: range.nsRange, with: insertion)
            newSelections.append(TextRange(location: range.location, length: insertion.utf16.count))
        }

        updateText(mutable as String, in: bufferID)

        guard let updatedIndex = buffers.firstIndex(where: { $0.id == bufferID }) else { return }
        buffers[updatedIndex].selectionRanges = newSelections.reversed()
        buffers[updatedIndex].updatedAt = Date()
        persistSoon()
    }

    func selectedAIChatSession(in bufferID: UUID) -> AIChatSession? {
        guard let buffer = buffers.first(where: { $0.id == bufferID }) else { return nil }

        if let selectedID = buffer.selectedAIChatSessionID,
           let session = buffer.aiSessions.first(where: { $0.id == selectedID }) {
            return session
        }

        return buffer.aiSessions.first
    }

    func createAIChat(provider: AIAgentProvider) {
        guard let selectedIndex else { return }

        let index = buffers[selectedIndex].aiSessions.filter { $0.provider == provider }.count + 1
        let session = AIChatSession.new(provider: provider, index: index)
        buffers[selectedIndex].aiSessions.append(session)
        buffers[selectedIndex].selectedAIChatSessionID = session.id
        showAIPanel()
        persistSoon()
    }

    func translateSelectionWithPrompt() {
        guard !isTranslationRunning else { return }

        let alert = NSAlert()
        alert.messageText = "Translate Selection"
        alert.informativeText = "Replace the selected text using the configured HTTP LLM provider."
        alert.addButton(withTitle: "Translate")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "Target language"
        input.stringValue = UserDefaults.standard.string(forKey: Self.translationTargetDefaultsKey) ?? "English"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let targetLanguage = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetLanguage.isEmpty else {
            lastError = "Enter a target language for translation."
            return
        }

        UserDefaults.standard.set(targetLanguage, forKey: Self.translationTargetDefaultsKey)
        translateSelectedText(targetLanguage: targetLanguage)
    }

    func translateSelectedText(targetLanguage: String) {
        guard !isTranslationRunning else { return }
        guard let selectedIndex else { return }

        let targetLanguage = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetLanguage.isEmpty else {
            lastError = "Enter a target language for translation."
            return
        }

        let buffer = buffers[selectedIndex]
        guard !buffer.language.isBinaryPreview else {
            lastError = "Translation works with text buffers."
            return
        }
        guard !hasStructuredFolds(for: buffer) else {
            lastError = "Unfold the source before translating selected text."
            return
        }

        let selectedRanges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        guard !selectedRanges.isEmpty else {
            lastError = "Select text to translate first."
            return
        }

        let nsText = buffer.text as NSString
        let sourceSegments = selectedRanges.map { nsText.substring(with: $0.nsRange) }
        let client: any HTTPAICompleting
        do {
            client = httpAIClientFactory(try httpAIConfigurationProvider())
        } catch {
            lastError = "Translation requires HTTP LLM settings: \(error.localizedDescription)"
            return
        }

        let bufferID = buffer.id
        let originalText = buffer.text
        isTranslationRunning = true
        translationStatus = "Translating selection to \(targetLanguage)..."

        Task { [weak self] in
            do {
                let response = try await client.complete(
                    messages: [
                        HTTPAIChatMessage(
                            role: "user",
                            content: AITranslationRequest.userPrompt(
                                targetLanguage: targetLanguage,
                                segments: sourceSegments
                            )
                        )
                    ],
                    systemPrompt: AITranslationRequest.systemPrompt
                )
                let translations = try AITranslationResponseParser.translations(
                    from: response,
                    expectedCount: sourceSegments.count
                )

                try Task.checkCancellation()
                await MainActor.run {
                    self?.applyTranslations(
                        translations,
                        replacing: selectedRanges,
                        in: bufferID,
                        originalText: originalText,
                        targetLanguage: targetLanguage
                    )
                }
            } catch {
                await MainActor.run {
                    self?.isTranslationRunning = false
                    self?.translationStatus = nil
                    if Task.isCancelled {
                        self?.lastError = "Translation cancelled."
                    } else {
                        self?.lastError = "Translation failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func selectAIChat(_ sessionID: UUID?, in bufferID: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }) else { return }
        buffers[index].selectedAIChatSessionID = sessionID
        persistSoon()
    }

    func deleteAIChat(_ sessionID: UUID, in bufferID: UUID) {
        guard let bufferIndex = buffers.firstIndex(where: { $0.id == bufferID }),
              let sessionIndex = buffers[bufferIndex].aiSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        aiClients.removeValue(forKey: sessionID)?.stop()
        aiHTTPTasks.removeValue(forKey: sessionID)?.cancel()
        aiRunningSessions.remove(sessionID)
        aiSessionStatuses.removeValue(forKey: sessionID)
        aiStreamingMessageIDs.removeValue(forKey: sessionID)
        buffers[bufferIndex].aiSessions.remove(at: sessionIndex)
        buffers[bufferIndex].selectedAIChatSessionID = buffers[bufferIndex].aiSessions.first?.id
        persistSoon()
    }

    func isAIRunning(_ sessionID: UUID) -> Bool {
        aiRunningSessions.contains(sessionID)
    }

    func aiStatus(for sessionID: UUID) -> String? {
        aiSessionStatuses[sessionID]
    }

    func sendAIMessage(_ text: String, in bufferID: UUID, sessionID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let location = aiChatLocation(sessionID),
              buffers[location.bufferIndex].id == bufferID else {
            return
        }

        let provider = buffers[location.bufferIndex].aiSessions[location.sessionIndex].provider
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.append(.user(trimmed))
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].updatedAt = Date()
        aiRunningSessions.insert(sessionID)
        aiSessionStatuses[sessionID] = "Starting \(provider.displayName)..."
        aiStreamingMessageIDs.removeValue(forKey: sessionID)
        persistSoon()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runAIPrompt(bufferID: bufferID, chatID: sessionID, userText: trimmed)
        }

        if !provider.usesACP {
            aiHTTPTasks[sessionID]?.cancel()
            aiHTTPTasks[sessionID] = task
        }
    }

    func cancelAIChat(_ sessionID: UUID) {
        if let location = aiChatLocation(sessionID),
           !buffers[location.bufferIndex].aiSessions[location.sessionIndex].provider.usesACP {
            aiHTTPTasks.removeValue(forKey: sessionID)?.cancel()
            finishAIChat(sessionID, status: "Cancelled")
            return
        }

        guard let agentSessionID = aiChatIDsByAgentSession.first(where: { $0.value == sessionID })?.key else {
            return
        }

        aiClients[sessionID]?.cancel(sessionID: agentSessionID)
        aiSessionStatuses[sessionID] = "Cancelling..."
    }

    func selectNextTab() {
        guard !buffers.isEmpty else { return }
        let currentIndex = selectedIndex ?? -1
        let nextIndex = (currentIndex + 1) % buffers.count
        selectedBufferID = buffers[nextIndex].id
        persistSoon()
    }

    func selectPreviousTab() {
        guard !buffers.isEmpty else { return }
        let currentIndex = selectedIndex ?? 0
        let previousIndex = (currentIndex - 1 + buffers.count) % buffers.count
        selectedBufferID = buffers[previousIndex].id
        persistSoon()
    }

    func registerEditorCommandHandler(_ handler: @escaping (EditorCommand) -> Bool) {
        editorCommandHandler = handler
    }

    func newScratch() {
        let nextIndex = buffers.filter { $0.kind == .scratch }.count + 1
        let buffer = EditorBuffer.scratch(index: nextIndex)
        buffers.append(buffer)
        selectedBufferID = buffer.id
        persistSoon()
    }

    func newDrawingBoard() {
        let nextIndex = buffers.filter { $0.language == .drawing }.count + 1
        let now = Date()
        let buffer = EditorBuffer(
            id: UUID(),
            title: "Drawing Board \(nextIndex)",
            kind: .scratch,
            filePath: nil,
            text: "",
            language: .drawing,
            createdAt: now,
            updatedAt: now,
            isDirty: false,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id
        showSourceMode()
        persistSoon()
    }

    func closeSelected() {
        guard let selectedBufferID else { return }
        closeBuffer(id: selectedBufferID)
    }

    func forceCloseSelected() {
        guard let selectedBufferID else { return }
        if pendingCloseBuffer?.id == selectedBufferID {
            pendingCloseBuffer = nil
            pendingCloseSuspendedBuffer = nil
        }
        forceCloseBuffer(id: selectedBufferID)
    }

    @discardableResult
    func forceCloseBuffer(matching target: String) -> Bool {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let id = bufferID(matchingForceCloseTarget: trimmed) else {
            return false
        }

        if pendingCloseBuffer?.id == id {
            pendingCloseBuffer = nil
            pendingCloseSuspendedBuffer = nil
        }
        forceCloseBuffer(id: id)
        return true
    }

    func closeBuffer(id: UUID) {
        let telemetry = EditorPerformanceTelemetry.begin("EditorCloseBufferRequest")
        defer { EditorPerformanceTelemetry.end("EditorCloseBufferRequest", telemetry) }

        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        let buffer = buffers[index]

        if shouldConfirmClose(buffer) {
            restorePendingCloseSuspensionIfNeeded()
            let suspension = suspendRenderingForPendingCloseIfNeeded(at: index)
            pendingCloseSuspendedBuffer = suspension
            pendingCloseBuffer = PendingCloseBuffer(
                id: buffer.id,
                displayTitle: buffer.displayTitle
            )
            return
        }

        forceCloseBuffer(id: id)
    }

    private func shouldConfirmClose(_ buffer: EditorBuffer) -> Bool {
        if bufferCanEditLargeFileChunk(buffer) {
            return buffer.isDirty
        }

        if isLargeReadOnlyFilePreview(buffer) {
            return false
        }

        switch buffer.kind {
        case .scratch:
            return buffer.isDirty || !buffer.text.isEmpty
        case .file:
            guard buffer.isDirty else { return false }
            return !Self.fileBackedBufferMatchesDisk(buffer)
        }
    }

    private func bufferID(matchingForceCloseTarget target: String) -> UUID? {
        let normalizedPath = Self.normalizedAutomationPathTarget(target)
        let normalizedName = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return buffers.first { buffer in
            if let normalizedPath,
               let filePath = buffer.filePath,
               Self.normalizedAutomationPathTarget(filePath) == normalizedPath {
                return true
            }

            let candidates = [
                buffer.displayTitle,
                buffer.title,
                buffer.filePath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            return candidates.contains(normalizedName)
        }?.id
    }

    private nonisolated static func normalizedAutomationPathTarget(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.contains("/") else {
            return nil
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func isLargeReadOnlyFilePreview(_ buffer: EditorBuffer) -> Bool {
        if buffer.isLargeFileMode {
            return true
        }

        let language = Self.fileDetectionLanguage(for: buffer)
        let size: Int64?
        if let filePath = buffer.filePath {
            let url = URL(fileURLWithPath: filePath)
            size = buffer.fileSizeBytes ?? Self.fileSizeBytes(at: url)
        } else {
            size = buffer.fileSizeBytes
        }

        return Self.shouldUseLargeFileMode(fileSizeBytes: size, language: language)
    }

    private nonisolated static func fileDetectionLanguage(for buffer: EditorBuffer) -> EditorLanguage {
        if let filePath = buffer.filePath {
            let url = URL(fileURLWithPath: filePath)
            return EditorLanguage.detect(fileName: url.lastPathComponent, text: "")
        }

        return EditorLanguage.detect(fileName: buffer.title, text: "")
    }

    @discardableResult
    private func suspendRenderingForPendingCloseIfNeeded(at index: Int) -> EditorBuffer? {
        guard buffers.indices.contains(index),
              isExpensivePendingCloseBuffer(buffers[index]) else {
            return nil
        }

        let snapshot = buffers[index]
        buffers[index].text = ""
        buffers[index].selectionRanges = [.zero]
        foldedRangesByBufferID[snapshot.id] = nil
        return snapshot
    }

    private func restorePendingCloseSuspensionIfNeeded() {
        guard let suspendedBuffer = pendingCloseSuspendedBuffer else {
            return
        }
        pendingCloseSuspendedBuffer = nil

        guard let index = buffers.firstIndex(where: { $0.id == suspendedBuffer.id }) else {
            return
        }

        buffers[index] = suspendedBuffer
    }

    private func isExpensivePendingCloseBuffer(_ buffer: EditorBuffer) -> Bool {
        if buffer.isLargeFileMode || isLargeReadOnlyFilePreview(buffer) {
            return true
        }

        if let fileSizeBytes = buffer.fileSizeBytes,
           fileSizeBytes >= Self.closeConfirmationRenderSuspensionThresholdBytes {
            return true
        }

        return buffer.text.utf8.count >= Self.closeConfirmationRenderSuspensionThresholdBytes
    }

    @discardableResult
    private func normalizeExistingLargeFilePreviewIfNeeded(at index: Int) -> Bool {
        guard buffers.indices.contains(index),
              let filePath = buffers[index].filePath,
              !buffers[index].isEncrypted else {
            return false
        }

        let url = URL(fileURLWithPath: filePath)
        let language = EditorLanguage.detect(fileName: url.lastPathComponent, text: "")
        let fileSizeBytes = buffers[index].fileSizeBytes ?? Self.fileSizeBytes(at: url)
        guard Self.shouldUseLargeFileMode(fileSizeBytes: fileSizeBytes, language: language) else {
            return false
        }

        let bufferID = buffers[index].id
        if buffers[index].isLargeFileMode,
           buffers[index].savePolicy == .readOnly,
           !buffers[index].isDirty {
            if buffers[index].text.isEmpty, !pendingFileLoadIDs.contains(bufferID) {
                startLargeFilePreviewLoad(
                    bufferID: bufferID,
                    url: url,
                    fileSizeBytes: fileSizeBytes,
                    language: language
                )
            }
            return true
        }

        buffers[index].language = language
        buffers[index].text = ""
        buffers[index].savePolicy = .readOnly
        buffers[index].isLargeFileMode = true
        buffers[index].isDirty = false
        buffers[index].fileSizeBytes = fileSizeBytes
        buffers[index].selectionRanges = [.zero]
        buffers[index].largeFilePreviewStartOffsetBytes = nil
        buffers[index].largeFilePreviewByteCount = nil
        foldedRangesByBufferID[bufferID] = nil

        if !pendingFileLoadIDs.contains(bufferID) {
            startLargeFilePreviewLoad(
                bufferID: bufferID,
                url: url,
                fileSizeBytes: fileSizeBytes,
                language: language
            )
        }

        persistSoon()
        return true
    }

    func detachSelectedBufferForNewWindow() -> EditorBuffer? {
        guard let selectedBufferID else { return nil }
        return detachBuffer(id: selectedBufferID)
    }

    func copySelectedBufferForNewWindow() -> EditorBuffer? {
        guard var buffer = selectedBuffer else { return nil }
        let now = Date()
        buffer.id = UUID()
        buffer.createdAt = now
        buffer.updatedAt = now
        buffer.aiSessions = []
        buffer.selectedAIChatSessionID = nil
        return buffer
    }

    func detachBuffer(id: UUID) -> EditorBuffer? {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return nil }
        let buffer = buffers[index]
        stopAIClients(for: buffer)
        let wasSelected = selectedBufferID == id
        editableLargeFilePreviewIDs.remove(id)
        largeFileVisibleLineRangesByBufferID[id] = nil
        buffers.remove(at: index)

        if buffers.isEmpty {
            let replacement = EditorBuffer.scratch(index: 1)
            buffers = [replacement]
            selectedBufferID = replacement.id
        } else if wasSelected {
            let nextIndex = min(index, buffers.count - 1)
            selectedBufferID = buffers[nextIndex].id
        }

        persistSoon()
        return buffer
    }

    func appendMovedBuffer(_ buffer: EditorBuffer) {
        if buffers.count == 1, let only = buffers.first, only.kind == .scratch, only.text.isEmpty, !only.isDirty {
            buffers = [buffer]
        } else {
            buffers.append(buffer)
        }

        selectedBufferID = buffer.id
        persistSoon()
    }

    func moveTabFromGroup(_ sourceGroupID: UUID, bufferID: UUID) {
        guard sourceGroupID != windowGroupID else { return }
        onMoveTabBetweenGroups?(sourceGroupID, windowGroupID, bufferID)
    }

    func confirmPendingClose() {
        guard let pendingCloseBuffer else { return }
        let id = pendingCloseBuffer.id
        self.pendingCloseBuffer = nil
        pendingCloseSuspendedBuffer = nil
        forceCloseBuffer(id: id)
    }

    func cancelPendingClose() {
        restorePendingCloseSuspensionIfNeeded()
        pendingCloseBuffer = nil
    }

    private func forceCloseBuffer(id: UUID) {
        let telemetry = EditorPerformanceTelemetry.begin("EditorForceCloseBuffer")
        defer { EditorPerformanceTelemetry.end("EditorForceCloseBuffer", telemetry) }

        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedBufferID == id
        foldedRangesByBufferID[id] = nil
        editableLargeFilePreviewIDs.remove(id)
        largeFileVisibleLineRangesByBufferID[id] = nil
        pendingFileLoadIDs.remove(id)
        pendingFileLoadTasks.removeValue(forKey: id)?.cancel()
        pendingFileLineJumps[id] = nil
        buffers.remove(at: index)

        if buffers.isEmpty {
            let buffer = EditorBuffer.scratch(index: 1)
            buffers = [buffer]
            selectedBufferID = buffer.id
        } else if wasSelected {
            let nextIndex = min(index, buffers.count - 1)
            selectedBufferID = buffers[nextIndex].id
        }

        persistSoon()
    }

    func updateSelectedText(_ text: String) {
        guard let selectedBufferID else { return }
        updateText(text, in: selectedBufferID)
    }

    func updateText(_ text: String, in id: UUID) {
        let telemetry = EditorPerformanceTelemetry.begin("EditorStoreUpdateText")
        defer { EditorPerformanceTelemetry.end("EditorStoreUpdateText", telemetry) }

        guard let index = buffers.firstIndex(where: { $0.id == id }),
              buffers[index].text != text else {
            return
        }

        if buffers[index].isLargeFileMode {
            let editingCapability = largeFileEditingCapability(for: buffers[index])
            guard editingCapability.canEditLoadedText,
                  attachLargeFileChunkSourceIfNeeded(at: index) else {
                lastError = editingCapability.saveUnavailableMessage
                return
            }
        }

        let previousText = buffers[index].text
        let previousSelectionRanges = buffers[index].selectionRanges
        recordActionMacroTextEditIfNeeded(
            oldText: previousText,
            newText: text,
            oldSelectionRanges: previousSelectionRanges
        )
        buffers[index].text = text
        buffers[index].updatedAt = Date()
        buffers[index].isDirty = buffers[index].kind == .scratch ? !text.isEmpty : true
        foldedRangesByBufferID[id] = nil
        recordEdit(oldText: previousText, newText: text, buffer: buffers[index])
        reanchorComments(for: buffers[index], newText: text)
        sendCollaborationPatchIfNeeded(bufferID: id, oldText: previousText, newText: text)
        scheduleCompanionAutoScanIfNeeded(for: id)
        scheduleTaskAIAutoInferenceIfNeeded(for: id)
        persistSoon()
    }

    func updateSelectedSelection(_ ranges: [TextRange]) {
        guard let selectedBufferID else { return }
        updateSelection(ranges, in: selectedBufferID)
    }

    func updateSelection(_ ranges: [TextRange], in id: UUID) {
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return }
        let normalized = ranges.isEmpty ? [.zero] : ranges

        guard buffers[index].selectionRanges != normalized else { return }
        if id == selectedBufferID, shouldCaptureRawActionMacroEdit {
            appendActionMacroStep(.select(normalized))
        }
        buffers[index].selectionRanges = normalized
        buffers[index].updatedAt = Date()
        sendCollaborationSelectionIfNeeded(bufferID: id, selectionRanges: normalized)
        scheduleCompanionAutoScanIfNeeded(for: id)
        persistSoon()
    }

    func setLanguage(_ language: EditorLanguage) {
        guard let selectedIndex else { return }
        buffers[selectedIndex].language = language
        foldedRangesByBufferID[buffers[selectedIndex].id] = nil
        buffers[selectedIndex].updatedAt = Date()
        persistSoon()
    }

    func setSelectedSavePolicy(_ policy: BufferSavePolicy) {
        guard let selectedIndex else { return }
        if buffers[selectedIndex].isLargeFileMode, policy == .normal {
            lastError = "Large-file previews stay read-only to avoid overwriting the full file."
            return
        }
        guard buffers[selectedIndex].savePolicy != policy else { return }
        buffers[selectedIndex].savePolicy = policy
        buffers[selectedIndex].updatedAt = Date()
        persistSoon()
    }

    func toggleReadOnlyMode() {
        setSelectedSavePolicy(selectedSavePolicy == .readOnly ? .normal : .readOnly)
    }

    func toggleTemporaryMode() {
        setSelectedSavePolicy(selectedSavePolicy == .temporary ? .normal : .temporary)
    }

    func addFinderTagToSelectedFileWithPrompt() {
        guard selectedBuffer?.filePath != nil else {
            lastError = "Save this buffer to a file before adding Finder tags."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Add Finder Tag"
        alert.informativeText = "Add a macOS Finder tag to the current file."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Tag"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        addFinderTagToSelectedFile(field.stringValue)
    }

    func addFinderTagToSelectedFile(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let filePath = selectedBuffer?.filePath else {
            lastError = "Save this buffer to a file before adding Finder tags."
            return
        }

        do {
            try FinderTagService.addTag(trimmed, to: URL(fileURLWithPath: filePath))
            objectWillChange.send()
        } catch {
            lastError = "Could not update Finder tags: \(error.localizedDescription)"
        }
    }

    func clearFinderTagsForSelectedFile() {
        guard let filePath = selectedBuffer?.filePath else {
            lastError = "Save this buffer to a file before clearing Finder tags."
            return
        }

        do {
            try FinderTagService.setTags([], for: URL(fileURLWithPath: filePath))
            objectWillChange.send()
        } catch {
            lastError = "Could not clear Finder tags: \(error.localizedDescription)"
        }
    }

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            openFile(at: url)
        }
    }

    func openFiles(at urls: [URL]) {
        for url in urls {
            if Self.isDirectoryURL(url) {
                openFolder(at: url)
            } else {
                openFile(at: url)
            }
        }
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        openFolder(at: url)
    }

    func openFolder(at url: URL) {
        documentCatalogRootPath = url.path
        documentCatalogQuery = ""
        isDocumentCatalogVisible = true
        isOutlineVisible = false
        refreshDocumentCatalog()
        onDocumentCatalogRootChanged?(documentCatalogRootPath)
        persistSoon()
    }

    func closeFolder() {
        documentCatalogRootPath = nil
        documentCatalogNodes = []
        documentCatalogTasks = []
        documentCatalogQuery = ""
        poModeReport = nil
        isPOModePanelVisible = false
        documentCatalogTaskScanTask?.cancel()
        documentCatalogTaskScanTask = nil
        onDocumentCatalogRootChanged?(nil)
        persistSoon()
    }

    func applyWorkspaceDocumentCatalogRoot(_ rootPath: String?) {
        documentCatalogRootPath = rootPath
        documentCatalogQuery = ""
        poModeReport = nil

        guard let rootPath else {
            documentCatalogNodes = []
            documentCatalogTasks = []
            isPOModePanelVisible = false
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            documentCatalogNodes = []
            documentCatalogTasks = []
            return
        }

        refreshDocumentCatalog()
    }

    func toggleDocumentCatalog() {
        if isDocumentCatalogVisible {
            isDocumentCatalogVisible = false
        } else {
            isDocumentCatalogVisible = true
            isOutlineVisible = false
        }
    }

    func refreshDocumentCatalog() {
        guard let rootPath = documentCatalogRootPath else {
            documentCatalogNodes = []
            documentCatalogTasks = []
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        Task { [weak self, rootPath, rootURL] in
            let nodes = await Task.detached(priority: .userInitiated) {
                Self.buildDocumentCatalogNodes(rootURL: rootURL)
            }.value

            guard self?.documentCatalogRootPath == rootPath else { return }
            self?.documentCatalogNodes = nodes
            self?.refreshDocumentCatalogTasks(nodes: nodes, rootPath: rootPath)
        }
    }

    func refreshDocumentCatalogTasks() {
        refreshDocumentCatalogTasks(nodes: documentCatalogNodes, rootPath: documentCatalogRootPath)
    }

    private func refreshDocumentCatalogTasks(nodes: [DocumentCatalogNode], rootPath: String?) {
        documentCatalogTaskScanTask?.cancel()
        guard let rootPath, !nodes.isEmpty else {
            documentCatalogTasks = []
            return
        }

        documentCatalogTaskScanTask = Task { [weak self, nodes, rootPath] in
            let tasks = await Task.detached(priority: .utility) {
                Self.scanDocumentCatalogTasks(nodes: nodes, rootPath: rootPath)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.documentCatalogRootPath == rootPath else { return }
                self?.documentCatalogTasks = tasks
                self?.documentCatalogTaskScanTask = nil
            }
        }
    }

    func documentCatalogFileMatches(for query: String, limit: Int = 30) -> [DocumentCatalogFileMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = documentCatalogFileNodes(documentCatalogNodes)

        if trimmed.isEmpty {
            return files.prefix(limit).map {
                DocumentCatalogFileMatch(
                    url: $0.url,
                    displayPath: documentCatalogDisplayPath(for: $0.url),
                    score: 0
                )
            }
        }

        return files.compactMap { node -> DocumentCatalogFileMatch? in
            let displayPath = documentCatalogDisplayPath(for: node.url)
            let candidate = "\(displayPath) \(node.name)"
            guard let score = Self.fuzzyScore(candidate: candidate, query: trimmed) else {
                return nil
            }

            return DocumentCatalogFileMatch(url: node.url, displayPath: displayPath, score: score)
        }
        .sorted {
            if $0.score == $1.score {
                return $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
            }
            return $0.score > $1.score
        }
        .prefix(limit)
        .map(\.self)
    }

    func openFile(at url: URL) {
        let telemetry = EditorPerformanceTelemetry.begin("EditorOpenFile")
        defer { EditorPerformanceTelemetry.end("EditorOpenFile", telemetry) }

        if let existingIndex = buffers.firstIndex(where: { $0.filePath == url.path }) {
            normalizeExistingLargeFilePreviewIfNeeded(at: existingIndex)
            selectedBufferID = buffers[existingIndex].id
            return
        }

        if EncryptedDocumentService.isEncryptedDocument(at: url) {
            openEncryptedFileWithPrompt(at: url)
            return
        }

        let detectedLanguage = EditorLanguage.detect(fileName: url.lastPathComponent, text: "")
        if detectedLanguage == .plain, Self.shouldOpenAsHexPreview(at: url) {
            openBinaryPreviewFile(at: url, language: .hex)
            return
        }

        if detectedLanguage.isBinaryPreview {
            openBinaryPreviewFile(at: url, language: detectedLanguage)
            return
        }

        let fileSizeBytes = Self.fileSizeBytes(at: url)
        let isLargeFileMode = Self.shouldUseLargeFileMode(fileSizeBytes: fileSizeBytes, language: detectedLanguage)
        EditorPerformanceTelemetry.logger.info("Open file requested ext=\(url.pathExtension, privacy: .public) language=\(detectedLanguage.rawValue, privacy: .public) bytes=\(fileSizeBytes ?? -1, privacy: .public) large=\(isLargeFileMode, privacy: .public)")
        let now = Date()
        let bufferID = UUID()
        let buffer = EditorBuffer(
            id: bufferID,
            title: url.lastPathComponent,
            kind: .file,
            filePath: url.path,
            text: "",
            language: detectedLanguage,
            createdAt: now,
            updatedAt: now,
            isDirty: false,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil,
            savePolicy: isLargeFileMode ? .readOnly : .normal,
            isLargeFileMode: isLargeFileMode,
            fileSizeBytes: fileSizeBytes
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id
        recordUsageEvent(
            \.openCount,
            documentKey: documentKey(for: buffer),
            timelineKind: .open,
            timelineTitle: "Opened \(buffer.displayTitle)"
        )
        startFileLoad(
            bufferID: bufferID,
            url: url,
            fileSizeBytes: fileSizeBytes,
            isLargeFileMode: isLargeFileMode,
            language: detectedLanguage
        )
    }

    func openFile(at url: URL, lineNumber: Int) {
        openFile(at: url)
        guard let selectedBuffer,
              selectedBuffer.filePath == url.path else {
            return
        }

        if pendingFileLoadIDs.contains(selectedBuffer.id) {
            pendingFileLineJumps[selectedBuffer.id] = max(1, lineNumber)
        } else {
            jumpToLine(lineNumber)
        }
    }

    func openPOModeReference(_ reference: DocumentFolderAnalysis.LineReference) {
        openFile(at: reference.url, lineNumber: reference.lineNumber)
    }

    func showLargeFileFirstChunk() {
        showSelectedLargeFileChunk(startOffset: 0)
    }

    func showLargeFilePreviousChunk() {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode else {
            return
        }

        let byteLimit = Self.largeFilePreviewByteLimit(for: buffer.language)
        let current = buffer.largeFilePreviewStartOffsetBytes ?? 0
        let previous = max(0, current - Int64(byteLimit))
        showSelectedLargeFileChunk(startOffset: previous)
    }

    func showLargeFileNextChunk() {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode else {
            return
        }

        let byteLimit = Self.largeFilePreviewByteLimit(for: buffer.language)
        let current = buffer.largeFilePreviewStartOffsetBytes ?? 0
        let next = current + Int64(byteLimit)
        showSelectedLargeFileChunk(startOffset: next)
    }

    func showLargeFileLastChunk() {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              let fileSizeBytes = buffer.fileSizeBytes else {
            return
        }

        let byteLimit = Self.largeFilePreviewByteLimit(for: buffer.language)
        let finalStart = max(0, fileSizeBytes - Int64(byteLimit))
        showSelectedLargeFileChunk(startOffset: finalStart)
    }

    func searchSelectedLargeFileWithPrompt() {
        guard selectedBuffer?.isLargeFileMode == true else { return }

        let alert = NSAlert()
        alert.messageText = "Search Large File"
        alert.informativeText = "Find exact text across the full file without loading it into the editor."
        alert.addButton(withTitle: "Search")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "Exact text"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        searchSelectedLargeFile(field.stringValue)
    }

    func jumpSelectedLargeFileToLineWithPrompt() {
        guard selectedBuffer?.isLargeFileMode == true else { return }

        let alert = NSAlert()
        alert.messageText = "Jump to Line"
        alert.informativeText = "Jump across the full large file without loading it into the editor."
        alert.addButton(withTitle: "Jump")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        field.placeholderString = "Line number"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let lineNumber = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              lineNumber > 0 else {
            largeFileSearchStatus = "Enter a positive line number."
            return
        }

        jumpSelectedLargeFileToLine(lineNumber)
    }

    func editSelectedLargeFileChunk(containingLine lineNumber: Int) {
        jumpSelectedLargeFileToLine(lineNumber, openEditableChunk: true)
    }

    func editSelectedLargeFileChunk(containingVisibleLineRange lineRange: ClosedRange<Int>?) {
        guard selectedBuffer?.isLargeFileMode == true else {
            largeFileSearchStatus = "Open a large-file preview before editing a visible chunk."
            return
        }

        editSelectedLargeFileChunk(containingLine: max(1, lineRange?.lowerBound ?? 1))
    }

    func updateLargeFileVisibleLineRange(_ lineRange: ClosedRange<Int>, for bufferID: UUID) {
        guard let buffer = buffers.first(where: { $0.id == bufferID }),
              buffer.isLargeFileMode else {
            largeFileVisibleLineRangesByBufferID[bufferID] = nil
            return
        }

        let normalizedRange = max(1, lineRange.lowerBound)...max(1, lineRange.upperBound)
        if largeFileVisibleLineRangesByBufferID[bufferID] != normalizedRange {
            largeFileVisibleLineRangesByBufferID[bufferID] = normalizedRange
        }
    }

    func replaceSelectedLargeFileLineWithPrompt() {
        guard selectedLargeFileCanReplaceLine else {
            largeFileSearchStatus = "Open a large-file preview before replacing a virtual line."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Replace Large-File Line"
        alert.informativeText = "Rewrite one source line without loading the full file into the editor."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")

        let lineField = NSTextField(frame: .zero)
        lineField.placeholderString = "Line number"
        lineField.stringValue = selectedLargeFileDefaultLineNumberForLineEdit.map(String.init) ?? ""

        let replacementField = NSTextField(frame: .zero)
        replacementField.placeholderString = "Replacement text"

        let stack = NSStackView(views: [lineField, replacementField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lineField.widthAnchor.constraint(equalToConstant: 420),
            replacementField.widthAnchor.constraint(equalTo: lineField.widthAnchor)
        ])
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let trimmedLine = lineField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lineNumber = Int(trimmedLine),
              lineNumber > 0 else {
            largeFileSearchStatus = "Enter a positive line number."
            return
        }

        let replacement = replacementField.stringValue
        guard !replacement.contains(where: { $0 == "\n" || $0 == "\r" }) else {
            largeFileSearchStatus = "Virtual line replacement accepts one replacement line."
            return
        }

        replaceSelectedLargeFileLine(lineNumber, with: replacement)
    }

    func insertSelectedLargeFileLineWithPrompt() {
        guard selectedLargeFileCanReplaceLine else {
            largeFileSearchStatus = "Open a large-file preview before inserting a virtual line."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Insert Large-File Line"
        alert.informativeText = "Insert one source line without loading the full file into the editor."
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let lineField = NSTextField(frame: .zero)
        lineField.placeholderString = "Insert before line number"
        lineField.stringValue = selectedLargeFileDefaultLineNumberForLineEdit.map(String.init) ?? ""

        let insertedTextField = NSTextField(frame: .zero)
        insertedTextField.placeholderString = "Inserted text"

        let stack = NSStackView(views: [lineField, insertedTextField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lineField.widthAnchor.constraint(equalToConstant: 420),
            insertedTextField.widthAnchor.constraint(equalTo: lineField.widthAnchor)
        ])
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let trimmedLine = lineField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lineNumber = Int(trimmedLine),
              lineNumber > 0 else {
            largeFileSearchStatus = "Enter a positive line number."
            return
        }

        let insertedText = insertedTextField.stringValue
        guard !insertedText.contains(where: { $0 == "\n" || $0 == "\r" }) else {
            largeFileSearchStatus = "Virtual line insertion accepts one inserted line."
            return
        }

        insertSelectedLargeFileLine(lineNumber, text: insertedText)
    }

    func deleteSelectedLargeFileLineWithPrompt() {
        guard selectedLargeFileCanReplaceLine else {
            largeFileSearchStatus = "Open a large-file preview before deleting a virtual line."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Large-File Line"
        alert.informativeText = "Delete one source line without loading the full file into the editor."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let lineField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        lineField.placeholderString = "Line number"
        lineField.stringValue = selectedLargeFileDefaultLineNumberForLineEdit.map(String.init) ?? ""
        alert.accessoryView = lineField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let trimmedLine = lineField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lineNumber = Int(trimmedLine),
              lineNumber > 0 else {
            largeFileSearchStatus = "Enter a positive line number."
            return
        }

        deleteSelectedLargeFileLine(lineNumber)
    }

    func replaceSelectedLargeFileLinesWithPrompt() {
        guard selectedLargeFileCanReplaceLine else {
            largeFileSearchStatus = "Open a large-file preview before replacing virtual lines."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Replace Large-File Lines"
        alert.informativeText = "Rewrite a source line range without loading the full file into the editor."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")

        let startField = NSTextField(frame: .zero)
        startField.placeholderString = "Start line"
        startField.stringValue = selectedLargeFileDefaultLineNumberForLineEdit.map(String.init) ?? ""

        let endField = NSTextField(frame: .zero)
        endField.placeholderString = "End line"
        endField.stringValue = startField.stringValue

        let replacementView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 140))
        replacementView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        replacementView.isRichText = false
        replacementView.usesFindPanel = false

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 140))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = replacementView

        let stack = NSStackView(views: [startField, endField, scrollView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            startField.widthAnchor.constraint(equalToConstant: 520),
            endField.widthAnchor.constraint(equalTo: startField.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: startField.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 140)
        ])
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let lineRange = Self.promptLineRange(start: startField.stringValue, end: endField.stringValue) else {
            largeFileSearchStatus = "Enter a positive line range."
            return
        }

        replaceSelectedLargeFileLines(lineRange, with: replacementView.string)
    }

    func insertSelectedLargeFileLinesWithPrompt() {
        guard selectedLargeFileCanReplaceLine else {
            largeFileSearchStatus = "Open a large-file preview before inserting virtual lines."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Insert Large-File Lines"
        alert.informativeText = "Insert one or more source lines without loading the full file into the editor."
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let lineField = NSTextField(frame: .zero)
        lineField.placeholderString = "Insert before line number"
        lineField.stringValue = selectedLargeFileDefaultLineNumberForLineEdit.map(String.init) ?? ""

        let insertedTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 140))
        insertedTextView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        insertedTextView.isRichText = false
        insertedTextView.usesFindPanel = false

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 140))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = insertedTextView

        let stack = NSStackView(views: [lineField, scrollView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lineField.widthAnchor.constraint(equalToConstant: 520),
            scrollView.widthAnchor.constraint(equalTo: lineField.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 140)
        ])
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmedLine = lineField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lineNumber = Int(trimmedLine),
              lineNumber > 0 else {
            largeFileSearchStatus = "Enter a positive line number."
            return
        }

        insertSelectedLargeFileLines(lineNumber, text: insertedTextView.string)
    }

    func deleteSelectedLargeFileLinesWithPrompt() {
        guard selectedLargeFileCanReplaceLine else {
            largeFileSearchStatus = "Open a large-file preview before deleting virtual lines."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Large-File Lines"
        alert.informativeText = "Delete a source line range without loading the full file into the editor."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let startField = NSTextField(frame: .zero)
        startField.placeholderString = "Start line"
        startField.stringValue = selectedLargeFileDefaultLineNumberForLineEdit.map(String.init) ?? ""

        let endField = NSTextField(frame: .zero)
        endField.placeholderString = "End line"
        endField.stringValue = startField.stringValue

        let stack = NSStackView(views: [startField, endField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            startField.widthAnchor.constraint(equalToConstant: 260),
            endField.widthAnchor.constraint(equalTo: startField.widthAnchor)
        ])
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let lineRange = Self.promptLineRange(start: startField.stringValue, end: endField.stringValue) else {
            largeFileSearchStatus = "Enter a positive line range."
            return
        }

        deleteSelectedLargeFileLines(lineRange)
    }

    func replaceSelectedLargeFileLine(_ lineNumber: Int, with replacementText: String) {
        performSelectedLargeFileLineEdit(
            action: .replace(lineRange: lineNumber...lineNumber, text: replacementText)
        )
    }

    func insertSelectedLargeFileLine(_ lineNumber: Int, text insertedText: String) {
        performSelectedLargeFileLineEdit(
            action: .insert(lineNumber: lineNumber, text: insertedText)
        )
    }

    func deleteSelectedLargeFileLine(_ lineNumber: Int) {
        performSelectedLargeFileLineEdit(
            action: .delete(lineRange: lineNumber...lineNumber)
        )
    }

    func replaceSelectedLargeFileLines(_ lineRange: ClosedRange<Int>, with replacementText: String) {
        performSelectedLargeFileLineEdit(
            action: .replace(lineRange: lineRange, text: replacementText)
        )
    }

    func insertSelectedLargeFileLines(_ lineNumber: Int, text insertedText: String) {
        performSelectedLargeFileLineEdit(
            action: .insert(lineNumber: lineNumber, text: insertedText)
        )
    }

    func deleteSelectedLargeFileLines(_ lineRange: ClosedRange<Int>) {
        performSelectedLargeFileLineEdit(
            action: .delete(lineRange: lineRange)
        )
    }

    private static func promptLineRange(start: String, end: String) -> ClosedRange<Int>? {
        let trimmedStart = start.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnd = end.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startLine = Int(trimmedStart),
              startLine > 0 else {
            return nil
        }

        let endLine: Int
        if trimmedEnd.isEmpty {
            endLine = startLine
        } else if let parsedEnd = Int(trimmedEnd),
                  parsedEnd >= startLine {
            endLine = parsedEnd
        } else {
            return nil
        }

        return startLine...endLine
    }

    private enum LargeFileVirtualLineEditAction {
        case replace(lineRange: ClosedRange<Int>, text: String)
        case insert(lineNumber: Int, text: String)
        case delete(lineRange: ClosedRange<Int>)

        var lineNumber: Int {
            switch self {
            case .replace(let lineRange, _), .delete(let lineRange):
                return max(1, lineRange.lowerBound)
            case .insert(let lineNumber, _):
                return max(1, lineNumber)
            }
        }

        var statusLineTarget: String {
            switch self {
            case .replace(let lineRange, _), .delete(let lineRange):
                return Self.lineRangeDescription(lineRange)
            case .insert(let lineNumber, _):
                return "\(max(1, lineNumber))"
            }
        }

        var indexingStatusVerb: String {
            switch self {
            case .replace:
                return "replace"
            case .insert:
                return "insert"
            case .delete:
                return "delete"
            }
        }

        var runningStatusVerb: String {
            switch self {
            case .replace:
                return "Replacing"
            case .insert:
                return "Inserting"
            case .delete:
                return "Deleting"
            }
        }

        var cancellationMessage: String {
            switch self {
            case .replace:
                return "Line replacement cancelled."
            case .insert:
                return "Line insertion cancelled."
            case .delete:
                return "Line deletion cancelled."
            }
        }

        var failurePrefix: String {
            switch self {
            case .replace:
                return "Line replacement failed"
            case .insert:
                return "Line insertion failed"
            case .delete:
                return "Line deletion failed"
            }
        }

        func apply(to document: LargeFileVirtualTextDocument, lineNumber: Int) throws -> LargeFileVirtualLineEditResult {
            switch self {
            case .replace(let lineRange, let replacementText):
                if Self.isSingleLineRange(lineRange) {
                    return try document.replacingLine(lineNumber, with: replacementText)
                }
                return try document.replacingLines(lineRange, with: replacementText)
            case .insert(_, let insertedText):
                if Self.isSingleLineText(insertedText) {
                    return try document.insertingLine(lineNumber, text: insertedText)
                }
                return try document.insertingLines(lineNumber, text: insertedText)
            case .delete(let lineRange):
                if Self.isSingleLineRange(lineRange) {
                    return try document.deletingLine(lineNumber)
                }
                return try document.deletingLines(lineRange)
            }
        }

        func completionMessage(for result: LargeFileVirtualLineEditResult, fileName: String) -> String {
            switch self {
            case .replace(let lineRange, _):
                if Self.isSingleLineRange(lineRange) {
                    return "Replaced line \(result.lineNumber) in \(fileName)."
                }
                return "Replaced lines \(Self.lineRangeDescription(lineRange)) in \(fileName)."
            case .insert(_, let text):
                let insertedLineCount = Self.lineCount(in: text)
                if insertedLineCount == 1 {
                    return "Inserted line \(result.lineNumber) in \(fileName)."
                }
                return "Inserted \(insertedLineCount) lines before line \(result.lineNumber) in \(fileName)."
            case .delete(let lineRange):
                if Self.isSingleLineRange(lineRange) {
                    return "Deleted line \(result.lineNumber) in \(fileName)."
                }
                return "Deleted lines \(Self.lineRangeDescription(lineRange)) in \(fileName)."
            }
        }

        func usageTitle(for result: LargeFileVirtualLineEditResult, fileName: String) -> String {
            switch self {
            case .replace(let lineRange, _):
                if Self.isSingleLineRange(lineRange) {
                    return "Replaced line \(result.lineNumber) in \(fileName)"
                }
                return "Replaced lines \(Self.lineRangeDescription(lineRange)) in \(fileName)"
            case .insert(_, let text):
                let insertedLineCount = Self.lineCount(in: text)
                if insertedLineCount == 1 {
                    return "Inserted line \(result.lineNumber) in \(fileName)"
                }
                return "Inserted \(insertedLineCount) lines before line \(result.lineNumber) in \(fileName)"
            case .delete(let lineRange):
                if Self.isSingleLineRange(lineRange) {
                    return "Deleted line \(result.lineNumber) in \(fileName)"
                }
                return "Deleted lines \(Self.lineRangeDescription(lineRange)) in \(fileName)"
            }
        }

        private static func isSingleLineRange(_ range: ClosedRange<Int>) -> Bool {
            range.lowerBound == range.upperBound
        }

        private static func isSingleLineText(_ text: String) -> Bool {
            !text.contains(where: { $0 == "\n" || $0 == "\r" })
        }

        private static func lineRangeDescription(_ range: ClosedRange<Int>) -> String {
            let lower = max(1, range.lowerBound)
            let upper = max(lower, range.upperBound)
            return lower == upper ? "\(lower)" : "\(lower)-\(upper)"
        }

        private static func lineCount(in text: String) -> Int {
            let normalized = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let withoutTrailingLineEnding = normalized.hasSuffix("\n") ? String(normalized.dropLast()) : normalized
            return max(1, withoutTrailingLineEnding.split(separator: "\n", omittingEmptySubsequences: false).count)
        }
    }

    private func performSelectedLargeFileLineEdit(
        action: LargeFileVirtualLineEditAction
    ) {
        let lineNumber = action.lineNumber
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              let filePath = buffer.filePath else {
            largeFileSearchStatus = "Open a large-file preview before editing a virtual line."
            return
        }

        let bufferID = buffer.id
        let url = URL(fileURLWithPath: filePath)
        let cacheKey = Self.largeFileLineIndexCacheKey(for: url)
        let fileSignature = try? LargeFileLineIndexer.fileSignature(at: url)
        let cachedIndex = largeFileLineIndexes[cacheKey].flatMap { index -> LargeFileLineIndex? in
            guard let fileSignature,
                  index.isValid(
                      fileSizeBytes: fileSignature.fileSizeBytes,
                      modificationDate: fileSignature.modificationDate
                  ) else {
                return nil
            }
            return index
        }
        if cachedIndex == nil {
            largeFileLineIndexes.removeValue(forKey: cacheKey)
        }

        largeFileLineEditTask?.cancel()
        largeFileSearchStatus = cachedIndex == nil
            ? "Indexing large file to \(action.indexingStatusVerb) line \(action.statusLineTarget)..."
            : "\(action.runningStatusVerb) line \(action.statusLineTarget)..."

        largeFileLineEditTask = Task { [weak self, url, bufferID, lineNumber, action, cacheKey, cachedIndex] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let document = try LargeFileVirtualTextDocument.open(
                        at: url,
                        cachedIndex: cachedIndex
                    )
                    return try action.apply(to: document, lineNumber: lineNumber)
                }.value

                guard !Task.isCancelled else { return }
                guard let self,
                      self.buffers.contains(where: { $0.id == bufferID }) else {
                    return
                }

                self.largeFileLineIndexes[cacheKey] = result.index
                self.refreshLargeFilePreviews(
                    for: url,
                    changedRangeStartOffset: result.byteOffset,
                    originalFileSizeBytes: result.index.fileSizeBytes - Int64(result.newByteCount - result.oldByteCount),
                    oldByteCount: result.oldByteCount,
                    newByteCount: result.newByteCount,
                    newFileSizeBytes: result.fileSizeBytes,
                    savedBufferID: bufferID
                )
                if let currentIndex = self.buffers.firstIndex(where: { $0.id == bufferID }),
                   self.buffers[currentIndex].isLargeFileMode {
                    self.showLargeFileChunk(at: currentIndex, startOffset: result.byteOffset)
                    self.selectLargeFileByteOffset(bufferID: bufferID, byteOffset: result.byteOffset)
                }
                self.largeFileSearchStatus = action.completionMessage(for: result, fileName: url.lastPathComponent)
                self.largeFileLineEditTask = nil
                self.recordUsageEvent(
                    \.saveCount,
                    documentKey: url.standardizedFileURL.path,
                    timelineKind: .save,
                    timelineTitle: action.usageTitle(for: result, fileName: url.lastPathComponent)
                )
                self.persistSoon()
            } catch is CancellationError {
                self?.largeFileSearchStatus = action.cancellationMessage
                self?.largeFileLineEditTask = nil
            } catch {
                self?.largeFileSearchStatus = "\(action.failurePrefix): \(error.localizedDescription)"
                self?.largeFileLineEditTask = nil
            }
        }
    }

    private func selectedLargeFileLineNumberForPreviewStartOffset() -> Int? {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              let filePath = buffer.filePath,
              let byteOffset = buffer.largeFilePreviewStartOffsetBytes else {
            return nil
        }

        let url = URL(fileURLWithPath: filePath)
        let cacheKey = Self.largeFileLineIndexCacheKey(for: url)
        let fileSignature = try? LargeFileLineIndexer.fileSignature(at: url)
        guard let index = largeFileLineIndexes[cacheKey],
              let fileSignature,
              index.isValid(
                  fileSizeBytes: fileSignature.fileSizeBytes,
                  modificationDate: fileSignature.modificationDate
              ),
              let lineNumber = try? LargeFileVirtualTextDocument(
                  url: url,
                  fileSizeBytes: index.fileSizeBytes,
                  modificationDate: index.modificationDate,
                  index: index
              ).lineNumber(containingByteOffset: byteOffset) else {
            return nil
        }

        return lineNumber
    }

    func openSelectedLargeFileChunkAsScratch() {
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode else {
            largeFileSearchStatus = "Open a large-file preview before creating a chunk scratch."
            return
        }

        let chunkText = Self.largeFilePreviewContentWithoutMarker(buffer.text)
        let startOffset = buffer.largeFilePreviewStartOffsetBytes ?? 0
        let sourceByteCount = buffer.largeFilePreviewByteCount
        let hasExactByteRange = sourceByteCount == chunkText.utf8.count
        appendLargeFileChunkScratch(
            from: buffer,
            chunkText: chunkText,
            startOffset: startOffset,
            sourceByteCount: sourceByteCount,
            hasExactByteRange: hasExactByteRange,
            statusLineNumber: nil
        )
    }

    func openSelectedLargeFileChunkAsScratch(containingVisibleLineRange lineRange: ClosedRange<Int>?) {
        guard selectedLargeFileCanOpenVisibleChunkForEditing else {
            openSelectedLargeFileChunkAsScratch()
            return
        }

        openSelectedLargeFileChunkAsScratch(containingLine: max(1, lineRange?.lowerBound ?? 1))
    }

    private func openSelectedLargeFileChunkAsScratch(containingLine lineNumber: Int) {
        let lineNumber = max(1, lineNumber)
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              let filePath = buffer.filePath else {
            largeFileSearchStatus = "Open a large-file preview before creating a chunk scratch."
            return
        }

        let bufferID = buffer.id
        let url = URL(fileURLWithPath: filePath)
        let fileSizeBytes = buffer.fileSizeBytes ?? Self.fileSizeBytes(at: url)
        let language = buffer.language
        let byteLimit = Self.largeFilePreviewByteLimit(for: language)
        let cacheKey = Self.largeFileLineIndexCacheKey(for: url)
        let fileSignature = try? LargeFileLineIndexer.fileSignature(at: url)
        let cachedIndex = largeFileLineIndexes[cacheKey].flatMap { index -> LargeFileLineIndex? in
            guard let fileSignature,
                  index.isValid(
                      fileSizeBytes: fileSignature.fileSizeBytes,
                      modificationDate: fileSignature.modificationDate
                  ) else {
                return nil
            }
            return index
        }
        if cachedIndex == nil {
            largeFileLineIndexes.removeValue(forKey: cacheKey)
        }

        largeFileLineJumpTask?.cancel()
        largeFileSearchStatus = cachedIndex == nil
            ? "Indexing large file to open line \(lineNumber) as scratch..."
            : "Opening line \(lineNumber) as editable scratch..."

        largeFileLineJumpTask = Task { [weak self, url, fileSizeBytes, lineNumber, bufferID, cacheKey, cachedIndex, byteLimit] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let locationResult = try LargeFileLineIndexer.lineLocation(
                        at: url,
                        lineNumber: lineNumber,
                        cachedIndex: cachedIndex
                    )
                    guard let location = locationResult.location else {
                        return (location: LargeFileLineLocation?.none, index: locationResult.index, preview: LargeFilePreview?.none)
                    }
                    let preview = try Self.largeFilePreview(
                        at: url,
                        fileSizeBytes: fileSizeBytes,
                        startOffset: location.byteOffset,
                        byteLimit: byteLimit
                    )
                    return (location: Optional(location), index: locationResult.index, preview: Optional(preview))
                }.value

                guard !Task.isCancelled else { return }
                guard let self,
                      let currentIndex = self.buffers.firstIndex(where: { $0.id == bufferID }),
                      self.buffers[currentIndex].isLargeFileMode else {
                    return
                }

                self.largeFileLineIndexes[cacheKey] = result.index
                guard let location = result.location,
                      let preview = result.preview else {
                    self.largeFileSearchStatus = "Line \(lineNumber) is past the end of the file."
                    self.largeFileLineJumpTask = nil
                    return
                }

                let sourceBuffer = self.buffers[currentIndex]
                let chunkText = Self.largeFilePreviewContentWithoutMarker(preview.text)
                let hasExactByteRange = preview.byteCount == chunkText.utf8.count
                self.appendLargeFileChunkScratch(
                    from: sourceBuffer,
                    chunkText: chunkText,
                    startOffset: preview.startOffsetBytes,
                    sourceByteCount: preview.byteCount,
                    hasExactByteRange: hasExactByteRange,
                    statusLineNumber: location.lineNumber
                )
                self.largeFileLineJumpTask = nil
            } catch is CancellationError {
                self?.largeFileSearchStatus = "Open chunk scratch cancelled."
                self?.largeFileLineJumpTask = nil
            } catch {
                self?.largeFileSearchStatus = "Open chunk scratch failed: \(error.localizedDescription)"
                self?.largeFileLineJumpTask = nil
            }
        }
    }

    private func appendLargeFileChunkScratch(
        from buffer: EditorBuffer,
        chunkText: String,
        startOffset: Int64,
        sourceByteCount: Int?,
        hasExactByteRange: Bool,
        statusLineNumber: Int?
    ) {
        let now = Date()
        let title = "\(buffer.displayTitle) chunk \(Self.formattedByteOffset(startOffset, fileSizeBytes: buffer.fileSizeBytes))"
        let scratch = EditorBuffer(
            id: UUID(),
            title: title,
            kind: .scratch,
            filePath: nil,
            text: chunkText,
            language: buffer.language,
            createdAt: now,
            updatedAt: now,
            isDirty: !chunkText.isEmpty,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil,
            savePolicy: .normal,
            isLargeFileMode: false,
            fileSizeBytes: nil,
            largeFilePreviewStartOffsetBytes: nil,
            largeFilePreviewByteCount: nil,
            largeFileSourcePath: hasExactByteRange ? buffer.filePath : nil,
            largeFileSourceStartOffsetBytes: hasExactByteRange ? startOffset : nil,
            largeFileSourceByteCount: hasExactByteRange ? sourceByteCount : nil,
            largeFileSourceFileSizeBytes: hasExactByteRange ? buffer.fileSizeBytes : nil,
            isEncrypted: false
        )
        buffers.append(scratch)
        selectedBufferID = scratch.id
        showSourceMode()
        let target = statusLineNumber.map { "line \($0)" } ?? "current chunk"
        largeFileSearchStatus = hasExactByteRange
            ? "Opened \(target) as editable scratch. It can be saved back to the source file."
            : "Opened \(target) as editable scratch. Save Back is disabled because the chunk cuts through a UTF-8 boundary."
        recordUsageEvent(
            \.openCount,
            documentKey: documentKey(for: scratch),
            timelineKind: .open,
            timelineTitle: "Opened \(scratch.displayTitle)"
        )
        persistSoon()
    }

    func enableSelectedLargeFileChunkEditing() {
        guard let index = selectedIndex,
              buffers[index].isLargeFileMode else {
            largeFileSearchStatus = "Open a large-file preview before editing a chunk."
            return
        }

        let editingCapability = largeFileEditingCapability(for: buffers[index])
        guard editingCapability.canEnableInPlaceChunkEditing else {
            largeFileSearchStatus = editingCapability.editUnavailableMessage
            return
        }

        let chunkText = Self.largeFilePreviewContentWithoutMarker(buffers[index].text)
        buffers[index].text = chunkText
        buffers[index].selectionRanges = [.zero]
        buffers[index].updatedAt = Date()
        editableLargeFilePreviewIDs.insert(buffers[index].id)
        largeFileSearchStatus = "Current chunk is editable. Cmd-S saves only this chunk back to the source file."
        persistSoon()
    }

    private func largeFileChunkHasExactByteRange(_ buffer: EditorBuffer) -> Bool {
        guard buffer.isLargeFileMode,
              buffer.filePath != nil,
              buffer.fileSizeBytes != nil,
              let byteCount = buffer.largeFilePreviewByteCount else {
            return false
        }

        let chunkText = Self.largeFilePreviewContentWithoutMarker(buffer.text)
        return byteCount == chunkText.utf8.count
    }

    private func selectedLargeFileChunkSourceIsLinked(_ buffer: EditorBuffer) -> Bool {
        buffer.largeFileSourcePath != nil &&
            buffer.largeFileSourceStartOffsetBytes != nil &&
            buffer.largeFileSourceByteCount != nil &&
            buffer.largeFileSourceFileSizeBytes != nil
    }

    private func attachLargeFileChunkSourceIfNeeded(at index: Int) -> Bool {
        guard buffers.indices.contains(index), buffers[index].isLargeFileMode else { return false }
        if selectedLargeFileChunkSourceIsLinked(buffers[index]) { return true }

        guard editableLargeFilePreviewIDs.contains(buffers[index].id),
              largeFileChunkHasExactByteRange(buffers[index]),
              let filePath = buffers[index].filePath,
              let sourceByteCount = buffers[index].largeFilePreviewByteCount,
              let sourceFileSizeBytes = buffers[index].fileSizeBytes else {
            return false
        }

        buffers[index].largeFileSourcePath = filePath
        buffers[index].largeFileSourceStartOffsetBytes = buffers[index].largeFilePreviewStartOffsetBytes ?? 0
        buffers[index].largeFileSourceByteCount = sourceByteCount
        buffers[index].largeFileSourceFileSizeBytes = sourceFileSizeBytes
        return true
    }

    @discardableResult
    func saveSelectedLargeFileChunkBackToSource() -> Bool {
        guard let index = selectedIndex else { return false }
        guard let sourcePath = buffers[index].largeFileSourcePath,
              let startOffset = buffers[index].largeFileSourceStartOffsetBytes,
              let sourceByteCount = buffers[index].largeFileSourceByteCount,
              let originalFileSizeBytes = buffers[index].largeFileSourceFileSizeBytes else {
            lastError = largeFileEditingCapability(for: buffers[index]).saveUnavailableMessage
            return false
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let currentFileSizeBytes = Self.fileSizeBytes(at: sourceURL)
        guard currentFileSizeBytes == originalFileSizeBytes else {
            lastError = "Could not save chunk back because the source file changed on disk. Reopen the chunk before applying edits."
            return false
        }

        let replacement = Data(buffers[index].text.utf8)
        do {
            let newFileSizeBytes = try Self.replaceFileBytes(
                at: sourceURL,
                startOffset: startOffset,
                byteCount: sourceByteCount,
                replacement: replacement
            )
            largeFileLineIndexes.removeValue(forKey: Self.largeFileLineIndexCacheKey(for: sourceURL))
            buffers[index].isDirty = false
            buffers[index].updatedAt = Date()
            buffers[index].largeFileSourceByteCount = replacement.count
            buffers[index].largeFileSourceFileSizeBytes = newFileSizeBytes
            largeFileSearchStatus = "Saved chunk back to \(sourceURL.lastPathComponent)."
            refreshLargeFilePreviews(
                for: sourceURL,
                changedRangeStartOffset: startOffset,
                originalFileSizeBytes: originalFileSizeBytes,
                oldByteCount: sourceByteCount,
                newByteCount: replacement.count,
                newFileSizeBytes: newFileSizeBytes,
                savedBufferID: buffers[index].id
            )
            recordUsageEvent(
                \.saveCount,
                documentKey: sourceURL.standardizedFileURL.path,
                timelineKind: .save,
                timelineTitle: "Saved chunk to \(sourceURL.lastPathComponent)"
            )
            persistSoon()
            return true
        } catch {
            lastError = "Could not save chunk back to \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    func searchSelectedLargeFile(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            largeFileSearchStatus = "Enter text to search."
            return
        }

        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              let filePath = buffer.filePath,
              let index = selectedIndex else {
            largeFileSearchStatus = "Open a large-file preview before searching."
            return
        }

        let bufferID = buffer.id
        let url = URL(fileURLWithPath: filePath)
        let fileSizeBytes = buffer.fileSizeBytes ?? Self.fileSizeBytes(at: url)
        let byteLimit = Self.largeFilePreviewByteLimit(for: buffer.language)
        largeFileSearchTask?.cancel()
        largeFileSearchStatus = "Searching large file..."

        largeFileSearchTask = Task { [weak self, trimmed, url, fileSizeBytes, byteLimit, bufferID] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try Self.firstLargeFileMatch(at: url, query: trimmed)
                }.value

                guard !Task.isCancelled else { return }
                guard let self,
                      let currentIndex = self.buffers.firstIndex(where: { $0.id == bufferID }),
                      self.buffers[currentIndex].isLargeFileMode else {
                    return
                }

                if let result {
                    let contextOffset = max(0, result.byteOffset - Int64(byteLimit / 4))
                    self.showLargeFileChunk(at: currentIndex, startOffset: contextOffset)
                    self.selectLargeFileSearchMatch(bufferID: bufferID, query: trimmed)
                    self.largeFileSearchStatus = "Found at \(Self.formattedByteOffset(result.byteOffset, fileSizeBytes: fileSizeBytes))."
                } else {
                    self.largeFileSearchStatus = "No matches for \"\(trimmed)\"."
                }
                self.largeFileSearchTask = nil
            } catch is CancellationError {
                self?.largeFileSearchStatus = "Search cancelled."
                self?.largeFileSearchTask = nil
            } catch {
                self?.largeFileSearchStatus = "Search failed: \(error.localizedDescription)"
                self?.largeFileSearchTask = nil
            }
        }

        if !buffers.indices.contains(index) {
            largeFileSearchTask?.cancel()
            largeFileSearchTask = nil
        }
    }

    private func jumpSelectedLargeFileToLine(_ lineNumber: Int, openEditableChunk: Bool = false) {
        let lineNumber = max(1, lineNumber)
        guard let buffer = selectedBuffer,
              buffer.isLargeFileMode,
              let filePath = buffer.filePath else {
            largeFileSearchStatus = "Open a large-file preview before jumping to a line."
            return
        }

        let bufferID = buffer.id
        let url = URL(fileURLWithPath: filePath)
        let fileSizeBytes = buffer.fileSizeBytes ?? Self.fileSizeBytes(at: url)
        let cacheKey = Self.largeFileLineIndexCacheKey(for: url)
        let fileSignature = try? LargeFileLineIndexer.fileSignature(at: url)
        let cachedIndex = largeFileLineIndexes[cacheKey].flatMap { index -> LargeFileLineIndex? in
            guard let fileSignature,
                  index.isValid(
                      fileSizeBytes: fileSignature.fileSizeBytes,
                      modificationDate: fileSignature.modificationDate
                  ) else {
                return nil
            }
            return index
        }
        if cachedIndex == nil {
            largeFileLineIndexes.removeValue(forKey: cacheKey)
        }
        largeFileLineJumpTask?.cancel()
        largeFileSearchStatus = if openEditableChunk {
            cachedIndex == nil
                ? "Indexing large file to edit line \(lineNumber)..."
                : "Opening editable chunk for line \(lineNumber)..."
        } else {
            cachedIndex == nil
                ? "Indexing large file for line \(lineNumber)..."
                : "Jumping to line \(lineNumber)..."
        }

        largeFileLineJumpTask = Task { [weak self, url, fileSizeBytes, lineNumber, bufferID, cacheKey, cachedIndex, openEditableChunk] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LargeFileLineIndexer.lineLocation(
                        at: url,
                        lineNumber: lineNumber,
                        cachedIndex: cachedIndex
                    )
                }.value

                guard !Task.isCancelled else { return }
                guard let self,
                      let currentIndex = self.buffers.firstIndex(where: { $0.id == bufferID }),
                      self.buffers[currentIndex].isLargeFileMode else {
                    return
                }

                self.largeFileLineIndexes[cacheKey] = result.index
                if let location = result.location {
                    self.showLargeFileChunk(at: currentIndex, startOffset: location.byteOffset)
                    self.selectLargeFileByteOffset(bufferID: bufferID, byteOffset: location.byteOffset)
                    if openEditableChunk {
                        self.enableSelectedLargeFileChunkEditing()
                        if let editedIndex = self.buffers.firstIndex(where: { $0.id == bufferID }),
                           self.bufferCanEditLargeFileChunk(self.buffers[editedIndex]) {
                            self.selectLargeFileByteOffset(bufferID: bufferID, byteOffset: location.byteOffset)
                            self.largeFileSearchStatus = "Line \(location.lineNumber) opened as editable chunk. Cmd-S saves only this chunk back to the source file."
                        } else if self.largeFileSearchStatus == nil ||
                                    self.largeFileSearchStatus?.hasPrefix("Line ") == true {
                            self.largeFileSearchStatus = "Line \(location.lineNumber) loaded, but this chunk cannot be edited safely."
                        }
                    } else {
                        self.largeFileSearchStatus = "Line \(location.lineNumber) at \(Self.formattedByteOffset(location.byteOffset, fileSizeBytes: fileSizeBytes))."
                    }
                } else {
                    self.largeFileSearchStatus = "Line \(lineNumber) is past the end of the file."
                }
                self.largeFileLineJumpTask = nil
            } catch is CancellationError {
                self?.largeFileSearchStatus = "Line jump cancelled."
                self?.largeFileLineJumpTask = nil
            } catch {
                self?.largeFileSearchStatus = "Line jump failed: \(error.localizedDescription)"
                self?.largeFileLineJumpTask = nil
            }
        }
    }

    private func selectLargeFileSearchMatch(bufferID: UUID, query: String) {
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }) else { return }
        let nsText = buffers[index].text as NSString
        let range = nsText.range(of: query)
        guard range.location != NSNotFound else { return }
        buffers[index].selectionRanges = [TextRange(location: range.location, length: range.length)]
    }

    private func selectLargeFileByteOffset(bufferID: UUID, byteOffset: Int64) {
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }),
              let chunkStart = buffers[index].largeFilePreviewStartOffsetBytes,
              let chunkByteCount = buffers[index].largeFilePreviewByteCount else {
            return
        }

        let relativeOffset = byteOffset - chunkStart
        guard relativeOffset >= 0,
              relativeOffset <= Int64(chunkByteCount) else {
            buffers[index].selectionRanges = [.zero]
            return
        }

        let text = buffers[index].text
        let clampedUTF8Offset = min(max(0, Int(relativeOffset)), text.utf8.count)
        let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: clampedUTF8Offset)
        guard let stringIndex = String.Index(utf8Index, within: text),
              let utf16Index = stringIndex.samePosition(in: text.utf16) else {
            buffers[index].selectionRanges = [.zero]
            return
        }

        let location = text.utf16.distance(from: text.utf16.startIndex, to: utf16Index)
        buffers[index].selectionRanges = [TextRange(location: location, length: 0)]
    }

    private func showSelectedLargeFileChunk(startOffset: Int64) {
        guard let index = selectedIndex else { return }
        showLargeFileChunk(at: index, startOffset: startOffset)
    }

    private func showLargeFileChunk(at index: Int, startOffset: Int64) {
        guard buffers.indices.contains(index),
              buffers[index].isLargeFileMode,
              let filePath = buffers[index].filePath else {
            return
        }

        if buffers[index].isDirty, bufferCanEditLargeFileChunk(buffers[index]) {
            lastError = "Save or close the edited chunk before loading another large-file chunk."
            return
        }

        let url = URL(fileURLWithPath: filePath)
        do {
            let byteLimit = Self.largeFilePreviewByteLimit(for: buffers[index].language)
            let preview = try Self.largeFilePreview(
                at: url,
                fileSizeBytes: buffers[index].fileSizeBytes,
                startOffset: startOffset,
                byteLimit: byteLimit
            )
            buffers[index].text = preview.text
            buffers[index].language = EditorLanguage.detect(fileName: url.lastPathComponent, text: preview.text)
            buffers[index].savePolicy = .readOnly
            buffers[index].isDirty = false
            buffers[index].selectionRanges = [.zero]
            buffers[index].largeFilePreviewStartOffsetBytes = preview.startOffsetBytes
            buffers[index].largeFilePreviewByteCount = preview.byteCount
            buffers[index].largeFileSourcePath = nil
            buffers[index].largeFileSourceStartOffsetBytes = nil
            buffers[index].largeFileSourceByteCount = nil
            buffers[index].largeFileSourceFileSizeBytes = nil
            editableLargeFilePreviewIDs.remove(buffers[index].id)
            buffers[index].updatedAt = Date()
            foldedRangesByBufferID[buffers[index].id] = nil
            lastError = nil
            persistSoon()
        } catch {
            lastError = "Could not read large-file chunk: \(error.localizedDescription)"
        }
    }

    private func refreshLargeFilePreviews(
        for sourceURL: URL,
        changedRangeStartOffset: Int64,
        originalFileSizeBytes: Int64,
        oldByteCount: Int,
        newByteCount: Int,
        newFileSizeBytes: Int64,
        savedBufferID: UUID
    ) {
        let sourcePath = sourceURL.standardizedFileURL.path
        let delta = Int64(newByteCount - oldByteCount)
        let changedRangeEndOffset = changedRangeStartOffset + Int64(oldByteCount)

        for index in buffers.indices {
            if buffers[index].filePath.map({ URL(fileURLWithPath: $0).standardizedFileURL.path }) == sourcePath,
               buffers[index].isLargeFileMode {
                let chunkStart = buffers[index].largeFilePreviewStartOffsetBytes ?? 0
                let adjustedStart = chunkStart > changedRangeStartOffset
                    ? max(0, chunkStart + delta)
                    : chunkStart
                buffers[index].fileSizeBytes = newFileSizeBytes
                showLargeFileChunk(at: index, startOffset: adjustedStart)
                continue
            }

            guard buffers[index].id != savedBufferID,
                  buffers[index].largeFileSourcePath.map({ URL(fileURLWithPath: $0).standardizedFileURL.path }) == sourcePath,
                  buffers[index].largeFileSourceFileSizeBytes == originalFileSizeBytes,
                  let chunkStart = buffers[index].largeFileSourceStartOffsetBytes,
                  let chunkByteCount = buffers[index].largeFileSourceByteCount else {
                continue
            }

            let chunkEnd = chunkStart + Int64(chunkByteCount)
            if chunkEnd <= changedRangeStartOffset {
                buffers[index].largeFileSourceFileSizeBytes = newFileSizeBytes
            } else if chunkStart >= changedRangeEndOffset {
                buffers[index].largeFileSourceStartOffsetBytes = max(0, chunkStart + delta)
                buffers[index].largeFileSourceFileSizeBytes = newFileSizeBytes
            } else {
                buffers[index].largeFileSourcePath = nil
                buffers[index].largeFileSourceStartOffsetBytes = nil
                buffers[index].largeFileSourceByteCount = nil
                buffers[index].largeFileSourceFileSizeBytes = nil
            }
        }
    }

    nonisolated static func shouldUseLargeFileMode(fileSizeBytes: Int64?, language: EditorLanguage) -> Bool {
        LargeFileConfiguration.shouldUseLargeFileMode(fileSizeBytes: fileSizeBytes, language: language)
    }

    nonisolated static func largeFilePreviewByteLimit(for language: EditorLanguage) -> Int {
        LargeFileConfiguration.previewByteLimit(for: language)
    }

    private nonisolated static func fileSizeBytes(at url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }

        return Int64(size)
    }

    private nonisolated static func largeFileLineIndexCacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func shouldOpenAsHexPreview(at url: URL) -> Bool {
        HexDump.isLikelyBinaryFile(at: url)
    }

    private static func migratedRestoredBuffers(_ buffers: [EditorBuffer]) -> [EditorBuffer] {
        buffers.map(migratedRestoredBuffer)
    }

    private static func migratedRestoredBuffer(_ buffer: EditorBuffer) -> EditorBuffer {
        guard buffer.kind == .file,
              let filePath = buffer.filePath,
              !buffer.isEncrypted else {
            return buffer
        }

        var migrated = buffer
        let url = URL(fileURLWithPath: filePath)
        let detectedLanguage = EditorLanguage.detect(fileName: url.lastPathComponent, text: buffer.text)
        let size = fileSizeBytes(at: url) ?? buffer.fileSizeBytes
        migrated.language = detectedLanguage
        migrated.fileSizeBytes = size

        if buffer.isLargeFileMode,
           buffer.isDirty,
           buffer.largeFileSourcePath != nil,
           buffer.largeFileSourceStartOffsetBytes != nil,
           buffer.largeFileSourceByteCount != nil,
           buffer.largeFileSourceFileSizeBytes != nil {
            return migrated
        }

        let shouldUseLargePreview = shouldUseLargeFileMode(fileSizeBytes: size, language: detectedLanguage)
        let canReplaceTextWithDiskPreview = shouldUseLargePreview || !buffer.isDirty || fileBackedBufferMatchesDisk(buffer)
        if canReplaceTextWithDiskPreview {
            migrated.isDirty = false
        }

        guard canReplaceTextWithDiskPreview,
              shouldUseLargePreview else {
            return migrated
        }

        migrated.text = ""
        migrated.language = detectedLanguage
        migrated.savePolicy = .readOnly
        migrated.isLargeFileMode = true
        migrated.isDirty = false
        migrated.largeFilePreviewStartOffsetBytes = nil
        migrated.largeFilePreviewByteCount = nil
        migrated.selectionRanges = [.zero]
        return migrated
    }

    private func loadRestoredLargeFilePreviews() {
        for buffer in buffers where buffer.kind == .file && buffer.isLargeFileMode && buffer.text.isEmpty {
            guard let filePath = buffer.filePath,
                  !pendingFileLoadIDs.contains(buffer.id) else {
                continue
            }

            let bufferID = buffer.id
            let url = URL(fileURLWithPath: filePath)
            let fileSizeBytes = buffer.fileSizeBytes ?? Self.fileSizeBytes(at: url)
            let language = buffer.language
            startFileLoad(
                bufferID: bufferID,
                url: url,
                fileSizeBytes: fileSizeBytes,
                isLargeFileMode: true,
                language: language
            )
        }
    }

    private func startLargeFilePreviewLoad(
        bufferID: UUID,
        url: URL,
        fileSizeBytes: Int64?,
        language: EditorLanguage
    ) {
        startFileLoad(
            bufferID: bufferID,
            url: url,
            fileSizeBytes: fileSizeBytes,
            isLargeFileMode: true,
            language: language
        )
    }

    private func startFileLoad(
        bufferID: UUID,
        url: URL,
        fileSizeBytes: Int64?,
        isLargeFileMode: Bool,
        language: EditorLanguage
    ) {
        guard !pendingFileLoadIDs.contains(bufferID) else { return }

        pendingFileLoadIDs.insert(bufferID)
        let task = Task.detached(priority: .userInitiated) { [weak self, bufferID, url, fileSizeBytes, isLargeFileMode, language] in
            do {
                try Task.checkCancellation()
                let openedFile = try Self.openedTextFile(
                    at: url,
                    fileSizeBytes: fileSizeBytes,
                    isLargeFileMode: isLargeFileMode,
                    language: language
                )
                try Task.checkCancellation()
                await self?.completeOpenFile(
                    bufferID: bufferID,
                    url: url,
                    result: .success(openedFile)
                )
            } catch is CancellationError {
                await self?.cancelPendingFileLoad(bufferID: bufferID)
            } catch {
                await self?.completeOpenFile(bufferID: bufferID, url: url, result: .failure(error))
            }
        }
        pendingFileLoadTasks[bufferID] = task
    }

    private static func fileBackedBufferMatchesDisk(_ buffer: EditorBuffer) -> Bool {
        if buffer.isLargeFileMode {
            return true
        }

        guard buffer.kind == .file,
              let filePath = buffer.filePath,
              !buffer.isEncrypted else {
            return false
        }

        let url = URL(fileURLWithPath: filePath)
        let language = EditorLanguage.detect(fileName: url.lastPathComponent, text: "")
        let size = buffer.fileSizeBytes ?? fileSizeBytes(at: url)
        if shouldUseLargeFileMode(fileSizeBytes: size, language: language) {
            return true
        }

        guard let diskText = try? String(contentsOf: url) else {
            return false
        }

        return diskText == buffer.text
    }

    private nonisolated static func openedTextFile(
        at url: URL,
        fileSizeBytes: Int64?,
        isLargeFileMode: Bool,
        language: EditorLanguage
    ) throws -> OpenedTextFile {
        let text: String
        let previewStartOffset: Int64?
        let previewByteCount: Int?
        if isLargeFileMode {
            let preview = try largeFilePreview(
                at: url,
                fileSizeBytes: fileSizeBytes,
                startOffset: 0,
                byteLimit: largeFilePreviewByteLimit(for: language)
            )
            text = preview.text
            previewStartOffset = preview.startOffsetBytes
            previewByteCount = preview.byteCount
        } else {
            var encoding = String.Encoding.utf8
            text = try String(contentsOf: url, usedEncoding: &encoding)
            previewStartOffset = nil
            previewByteCount = nil
        }

        return OpenedTextFile(
            text: text,
            language: EditorLanguage.detect(fileName: url.lastPathComponent, text: text),
            isLargeFileMode: isLargeFileMode,
            fileSizeBytes: fileSizeBytes,
            largeFilePreviewStartOffsetBytes: previewStartOffset,
            largeFilePreviewByteCount: previewByteCount
        )
    }

    private nonisolated static func largeFilePreview(
        at url: URL,
        fileSizeBytes: Int64?,
        startOffset: Int64,
        byteLimit: Int = largeFilePreviewByteLimit
    ) throws -> LargeFilePreview {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let resolvedStart = clampedLargeFilePreviewStart(
            startOffset,
            fileSizeBytes: fileSizeBytes,
            byteLimit: byteLimit
        )
        try fileHandle.seek(toOffset: UInt64(resolvedStart))
        let data = try fileHandle.read(upToCount: byteLimit) ?? Data()
        let preview = decodedTextPreview(from: data, trimLeadingPartialScalar: resolvedStart > 0)
        let marker = largeFilePreviewMarker(
            fileSizeBytes: fileSizeBytes,
            startOffset: resolvedStart,
            previewBytes: data.count
        )
        let separator = preview.hasSuffix("\n") ? "\n" : "\n\n"
        return LargeFilePreview(
            text: preview + separator + marker,
            startOffsetBytes: resolvedStart,
            byteCount: data.count
        )
    }

    private nonisolated static func firstLargeFileMatch(
        at url: URL,
        query: String,
        chunkSize: Int = 256 * 1024
    ) throws -> LargeFileSearchResult? {
        let needle = Data(query.utf8)
        guard !needle.isEmpty else { return nil }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let overlapLimit = max(0, min(needle.count - 1, chunkSize / 2))
        var overlap = Data()
        var offset: Int64 = 0

        while true {
            try Task.checkCancellation()
            let chunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                return nil
            }

            var searchData = Data()
            searchData.reserveCapacity(overlap.count + chunk.count)
            searchData.append(overlap)
            searchData.append(chunk)

            if let range = searchData.range(of: needle) {
                let matchOffset = offset - Int64(overlap.count) + Int64(range.lowerBound)
                return LargeFileSearchResult(byteOffset: max(0, matchOffset))
            }

            if overlapLimit > 0 {
                overlap = searchData.suffix(overlapLimit)
            } else {
                overlap = Data()
            }

            offset += Int64(chunk.count)
        }
    }

    private nonisolated static func replaceFileBytes(
        at url: URL,
        startOffset: Int64,
        byteCount: Int,
        replacement: Data,
        chunkSize: Int = 256 * 1024,
        fileManager: FileManager = .default
    ) throws -> Int64 {
        let currentSize = fileSizeBytes(at: url)
        guard let currentSize,
              startOffset >= 0,
              byteCount >= 0,
              startOffset + Int64(byteCount) <= currentSize else {
            throw LargeFileChunkWriteError.invalidRange
        }

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).simplelime-\(UUID().uuidString).tmp", isDirectory: false)
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw LargeFileChunkWriteError.couldNotCreateTemporaryFile
        }

        let input = try FileHandle(forReadingFrom: url)
        let output = try FileHandle(forWritingTo: temporaryURL)
        do {
            try copyFileHandleBytes(from: input, to: output, byteCount: startOffset, chunkSize: chunkSize)
            try output.write(contentsOf: replacement)
            try input.seek(toOffset: UInt64(startOffset + Int64(byteCount)))
            try copyFileHandleRemainder(from: input, to: output, chunkSize: chunkSize)
            try output.close()
            try input.close()
        } catch {
            try? output.close()
            try? input.close()
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }

        do {
            _ = try fileManager.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            try? fileManager.removeItem(at: url)
            do {
                try fileManager.moveItem(at: temporaryURL, to: url)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw LargeFileChunkWriteError.couldNotReplaceSource
            }
        }

        return currentSize - Int64(byteCount) + Int64(replacement.count)
    }

    private nonisolated static func copyFileHandleBytes(
        from input: FileHandle,
        to output: FileHandle,
        byteCount: Int64,
        chunkSize: Int
    ) throws {
        var remaining = byteCount
        while remaining > 0 {
            try Task.checkCancellation()
            let readCount = min(chunkSize, Int(remaining))
            let data = try input.read(upToCount: readCount) ?? Data()
            guard !data.isEmpty else {
                throw LargeFileChunkWriteError.invalidRange
            }
            try output.write(contentsOf: data)
            remaining -= Int64(data.count)
        }
    }

    private nonisolated static func copyFileHandleRemainder(
        from input: FileHandle,
        to output: FileHandle,
        chunkSize: Int
    ) throws {
        while true {
            try Task.checkCancellation()
            let data = try input.read(upToCount: chunkSize) ?? Data()
            guard !data.isEmpty else { return }
            try output.write(contentsOf: data)
        }
    }

    private nonisolated static func clampedLargeFilePreviewStart(
        _ startOffset: Int64,
        fileSizeBytes: Int64?,
        byteLimit: Int
    ) -> Int64 {
        let nonNegative = max(0, startOffset)
        guard let fileSizeBytes,
              fileSizeBytes > 0 else {
            return nonNegative
        }

        let finalStart = max(0, fileSizeBytes - Int64(byteLimit))
        return min(nonNegative, finalStart)
    }

    private nonisolated static func decodedTextPreview(
        from data: Data,
        trimLeadingPartialScalar: Bool = false
    ) -> String {
        let previewData = trimLeadingPartialScalar ? trimmingLeadingUTF8ContinuationBytes(data) : data
        for encoding in [
            String.Encoding.utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1
        ] {
            if let text = decodeTruncatedText(previewData, encoding: encoding) {
                return text
            }
        }

        return String(decoding: previewData, as: UTF8.self)
    }

    private nonisolated static func trimmingLeadingUTF8ContinuationBytes(_ data: Data) -> Data {
        var trimmed = data
        var removed = 0
        while let first = trimmed.first,
              first & 0b1100_0000 == 0b1000_0000,
              removed < 4 {
            trimmed.removeFirst()
            removed += 1
        }
        return trimmed
    }

    private nonisolated static func decodeTruncatedText(
        _ data: Data,
        encoding: String.Encoding
    ) -> String? {
        var candidate = data
        for _ in 0...8 {
            if let text = String(data: candidate, encoding: encoding) {
                return text
            }
            guard !candidate.isEmpty else { return nil }
            candidate.removeLast()
        }

        return nil
    }

    private nonisolated static func largeFilePreviewMarker(
        fileSizeBytes: Int64?,
        startOffset: Int64,
        previewBytes: Int
    ) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let start = formatter.string(fromByteCount: startOffset)
        let end = formatter.string(fromByteCount: startOffset + Int64(previewBytes))
        let shown = formatter.string(fromByteCount: Int64(previewBytes))
        let total = fileSizeBytes.map { formatter.string(fromByteCount: $0) } ?? "the file"
        return "[SimpleLime large-file preview: showing \(shown) from \(start)-\(end) of \(total). Use the status-bar arrows to page through the file. Saving is disabled to avoid overwriting the full file.]"
    }

    nonisolated static func largeFilePreviewContentWithoutMarker(_ text: String) -> String {
        let markerPrefix = "[SimpleLime large-file preview:"
        guard let markerRange = text.range(of: markerPrefix, options: .backwards) else {
            return text
        }

        var trimmed = String(text[..<markerRange.lowerBound])
        while trimmed.last == "\n" || trimmed.last == "\r" {
            trimmed.removeLast()
        }
        return trimmed
    }

    private nonisolated static func formattedByteOffset(_ byteOffset: Int64, fileSizeBytes: Int64?) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if let fileSizeBytes {
            return "\(formatter.string(fromByteCount: byteOffset)) of \(formatter.string(fromByteCount: fileSizeBytes))"
        }
        return formatter.string(fromByteCount: byteOffset)
    }

    private func openBinaryPreviewFile(at url: URL, language: EditorLanguage) {
        let now = Date()
        let buffer = EditorBuffer(
            id: UUID(),
            title: url.lastPathComponent,
            kind: .file,
            filePath: url.path,
            text: "",
            language: language,
            createdAt: now,
            updatedAt: now,
            isDirty: false,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil,
            savePolicy: .readOnly
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id
        recordUsageEvent(
            \.openCount,
            documentKey: documentKey(for: buffer),
            timelineKind: .open,
            timelineTitle: "Opened \(buffer.displayTitle)"
        )
        persistSoon()
    }

    private func completeOpenFile(
        bufferID: UUID,
        url: URL,
        result: Result<OpenedTextFile, Error>
    ) {
        pendingFileLoadTasks[bufferID] = nil
        guard pendingFileLoadIDs.remove(bufferID) != nil,
              let index = buffers.firstIndex(where: { $0.id == bufferID }) else {
            return
        }

        let pendingLineJump = pendingFileLineJumps.removeValue(forKey: bufferID)

        switch result {
        case .success(let payload):
            guard buffers[index].filePath == url.path,
                  !buffers[index].isDirty || payload.isLargeFileMode else { return }
            buffers[index].text = payload.text
            buffers[index].language = payload.language
            buffers[index].isLargeFileMode = payload.isLargeFileMode
            buffers[index].fileSizeBytes = payload.fileSizeBytes
            buffers[index].largeFilePreviewStartOffsetBytes = payload.largeFilePreviewStartOffsetBytes
            buffers[index].largeFilePreviewByteCount = payload.largeFilePreviewByteCount
            if payload.isLargeFileMode {
                buffers[index].savePolicy = .readOnly
                buffers[index].isDirty = false
            }
            buffers[index].updatedAt = Date()
            buffers[index].selectionRanges = [.zero]
            if let lineNumber = pendingLineJump {
                selectedBufferID = bufferID
                jumpToLine(lineNumber)
            }
            if selectedBufferID == bufferID {
                scheduleTaskAIAutoInferenceIfNeeded(for: bufferID)
            }
        case .failure(let error):
            let wasSelected = selectedBufferID == bufferID
            largeFileVisibleLineRangesByBufferID[bufferID] = nil
            buffers.remove(at: index)
            if wasSelected {
                if buffers.isEmpty {
                    let buffer = EditorBuffer.scratch(index: 1)
                    buffers.append(buffer)
                    selectedBufferID = buffer.id
                } else {
                    selectedBufferID = buffers[min(index, buffers.count - 1)].id
                }
            }
            lastError = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }

        persistSoon()
    }

    private func cancelPendingFileLoad(bufferID: UUID) {
        pendingFileLoadIDs.remove(bufferID)
        pendingFileLoadTasks[bufferID] = nil
        pendingFileLineJumps[bufferID] = nil
    }

    func pairNetworkPeer(_ deviceID: String) {
        networkShare.pair(with: deviceID)
    }

    func sendSelectedBuffer(to deviceID: String) {
        guard let selectedBuffer else {
            return
        }

        let note = SharedNotePayload(
            id: UUID(),
            title: selectedBuffer.displayTitle,
            text: selectedBuffer.text,
            language: selectedBuffer.language,
            sentAt: Date(),
            sourceDeviceID: networkShare.localDeviceID,
            sourceDeviceName: networkShare.localDisplayName,
            sourceToken: nil
        )
        networkShare.send(note: note, to: deviceID)
    }

    func inviteNetworkPeerToCollaborate(_ deviceID: String) {
        guard let selectedBuffer else { return }
        let peer = networkShare.peers.first { $0.deviceID == deviceID }
        guard peer?.isTrusted == true else {
            lastError = "Pair this device before starting collaboration."
            return
        }

        var session = collaborationSessionFor(buffer: selectedBuffer, isHost: true)
        upsertCollaborator(
            deviceID: deviceID,
            name: peer?.name ?? "Remote Mac",
            selectionRanges: [],
            in: &session
        )
        collaborationSession = session
        showNetworkPanel()

        sendCollaborationPayload(
            collaborationPayload(
                kind: .invite,
                session: session,
                buffer: selectedBuffer,
                text: selectedBuffer.text,
                patch: nil,
                selectionRanges: selectedBuffer.selectionRanges
            ),
            to: deviceID
        )
    }

    private func sendCollaborationPayload(_ payload: CollaborationPayload, to deviceID: String) {
        if let server = collaborationRelayServer {
            server.publish(payload)
            collaborationRelayStatus = "Relayed \(payload.kind.rawValue)."
            return
        }

        if let client = collaborationRelayClient {
            Task { [weak self] in
                do {
                    _ = try await client.send(payload)
                    await MainActor.run {
                        self?.collaborationRelayStatus = "Relayed \(payload.kind.rawValue)."
                    }
                } catch {
                    await MainActor.run {
                        self?.collaborationRelayStatus = "Relay send error: \(error.localizedDescription)"
                        self?.lastError = self?.collaborationRelayStatus
                    }
                }
            }
            return
        }

        networkShare.send(collaboration: payload, to: deviceID)
    }

    private var isCollaborationRelayActive: Bool {
        collaborationRelayServer != nil || collaborationRelayClient != nil
    }

    private func sendCollaborationPayloadToCollaborators(
        _ payload: CollaborationPayload,
        collaborators: [RemoteCollaborator]
    ) {
        if isCollaborationRelayActive {
            sendCollaborationPayload(payload, to: "relay")
            return
        }

        collaborators.forEach { collaborator in
            sendCollaborationPayload(payload, to: collaborator.deviceID)
        }
    }

    private func stopCollaborationRelay(keepsSession: Bool) {
        collaborationRelayClient?.stop()
        collaborationRelayClient = nil
        collaborationRelayServer?.stop()
        collaborationRelayServer = nil
        collaborationRelayState = collaborationRelayState.map {
            CollaborationRelayState(role: $0.role, link: $0.link, lastEventID: $0.lastEventID, isRunning: false)
        }
        collaborationRelayStatus = "Collaboration relay stopped."
        if !keepsSession {
            collaborationSession = nil
        }
    }

    func startSelfHostedCollaborationRelay(port: UInt16 = CollaborationRelayServer.defaultPort) {
        guard let selectedBuffer else { return }
        stopCollaborationRelay(keepsSession: true)

        let server = CollaborationRelayServer(port: port) { [weak self] payload in
            guard let self,
                  payload.sourceDeviceID != self.networkShare.localDeviceID else {
                return
            }
            self.handleCollaborationPayload(payload)
        }

        do {
            try server.start()
        } catch {
            lastError = "Could not start collaboration relay: \(error.localizedDescription)"
            return
        }

        let session = collaborationSessionFor(buffer: selectedBuffer, isHost: true)
        collaborationSession = session
        showNetworkPanel()

        let invite = collaborationPayload(
            kind: .invite,
            session: session,
            buffer: selectedBuffer,
            text: selectedBuffer.text,
            patch: nil,
            selectionRanges: selectedBuffer.selectionRanges
        )
        let event = server.publish(invite)
        let link = server.link
        collaborationRelayServer = server
        collaborationRelayState = CollaborationRelayState(
            role: .host,
            link: link,
            lastEventID: event.id,
            isRunning: true
        )
        collaborationRelayStatus = "Relay hosting at \(link.url.absoluteString)"
        networkShare.statusMessage = "Collaboration relay link ready."
    }

    func joinCollaborationRelay(link rawLink: String) {
        let trimmed = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let link = CollaborationRelayLink(url: url) else {
            lastError = "Paste a valid SimpleLime collaboration relay link."
            return
        }

        stopCollaborationRelay(keepsSession: true)
        let client = CollaborationRelayClient(link: link)
        collaborationRelayClient = client
        collaborationRelayState = CollaborationRelayState(
            role: .guest,
            link: link,
            lastEventID: 0,
            isRunning: true
        )
        collaborationRelayStatus = "Connecting to relay..."
        showNetworkPanel()

        client.startPolling(
            localDeviceID: networkShare.localDeviceID,
            onPayload: { [weak self] payload in
                self?.handleCollaborationPayload(payload)
                self?.collaborationRelayStatus = "Relay synced."
            },
            onStatus: { [weak self] status in
                self?.collaborationRelayStatus = status
            }
        )
    }

    func joinCollaborationRelayWithPrompt() {
        let alert = NSAlert()
        alert.messageText = "Join Collaboration Relay"
        alert.informativeText = "Paste a SimpleLime relay link from the host."
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.placeholderString = "simplelime://collab?server=..."
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        joinCollaborationRelay(link: field.stringValue)
    }

    func copyCollaborationRelayLink() {
        guard let url = collaborationRelayState?.shareURL else {
            lastError = "Start a self-hosted relay before copying a collaboration link."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        networkShare.statusMessage = "Copied collaboration relay link."
    }

    func stopCollaborationRelay() {
        stopCollaborationRelay(keepsSession: true)
    }

    func endCollaboration() {
        guard let session = collaborationSession,
              let buffer = buffers.first(where: { $0.id == session.bufferID }) else {
            collaborationSession = nil
            stopCollaborationRelay(keepsSession: true)
            return
        }

        let payload = collaborationPayload(
            kind: .leave,
            session: session,
            buffer: buffer,
            text: nil,
            patch: nil,
            selectionRanges: buffer.selectionRanges
        )
        sendCollaborationPayloadToCollaborators(payload, collaborators: session.collaborators)
        collaborationSession = nil
        stopCollaborationRelay(keepsSession: true)
        networkShare.statusMessage = "Collaboration ended. Your local copy remains open."
    }

    func removeTrustedNetworkDevice(_ deviceID: String) {
        networkShare.removeTrustedDevice(deviceID)
    }

    func collaborators(for buffer: EditorBuffer) -> [RemoteCollaborator] {
        guard collaborationSession?.bufferID == buffer.id else { return [] }
        return collaborationSession?.collaborators ?? []
    }

    func canHandleCollaborationPayload(_ payload: CollaborationPayload) -> Bool {
        collaborationSession?.id == payload.sessionID
    }

    func handleCollaborationPayload(_ payload: CollaborationPayload) {
        switch payload.kind {
        case .invite:
            joinCollaboration(from: payload)
        case .accept:
            acceptCollaboration(from: payload)
        case .patch:
            applyCollaborationPatch(from: payload)
        case .selection:
            updateRemoteCollaborator(from: payload)
        case .leave:
            removeRemoteCollaborator(from: payload)
        }
    }

    func importSharedNote(_ note: SharedNotePayload) {
        let now = Date()
        let baseTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Shared Note"
            : note.title
        let buffer = EditorBuffer(
            id: UUID(),
            title: uniqueSharedTitle(baseTitle),
            kind: .scratch,
            filePath: nil,
            text: note.text,
            language: note.language,
            createdAt: now,
            updatedAt: now,
            isDirty: !note.text.isEmpty,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id
        persistSoon()
    }

    @discardableResult
    func appendScribeTranscript(_ request: LocalAutomationScribeRequest) -> LocalAutomationBridgeResponse {
        let transcriptLine = request.formattedTranscriptLine
        guard !transcriptLine.isEmpty else {
            return LocalAutomationBridgeResponse(ok: false, message: "Scribe text is empty.", bufferTitle: nil)
        }

        let title = request.normalizedTitle
        let language = request.language ?? .markdown
        let shouldCreateNewBuffer = request.mode == .newBuffer
        let now = Date()
        let targetIndex: Int

        if !shouldCreateNewBuffer,
           let existingIndex = buffers.firstIndex(where: { $0.kind == .scratch && $0.title == title }) {
            targetIndex = existingIndex
        } else {
            let buffer = EditorBuffer(
                id: UUID(),
                title: title,
                kind: .scratch,
                filePath: nil,
                text: "",
                language: language,
                createdAt: now,
                updatedAt: now,
                isDirty: false,
                selectionRanges: [.zero],
                aiSessions: [],
                selectedAIChatSessionID: nil
            )
            buffers.append(buffer)
            targetIndex = buffers.count - 1
        }

        var updatedText = buffers[targetIndex].text
        if !updatedText.isEmpty, !updatedText.hasSuffix("\n") {
            updatedText += "\n"
        }
        updatedText += transcriptLine
        if !updatedText.hasSuffix("\n") {
            updatedText += "\n"
        }

        buffers[targetIndex].text = updatedText
        buffers[targetIndex].language = language
        buffers[targetIndex].isDirty = true
        buffers[targetIndex].updatedAt = now
        buffers[targetIndex].selectionRanges = [TextRange(location: (updatedText as NSString).length, length: 0)]
        selectedBufferID = buffers[targetIndex].id
        persistSoon()

        return LocalAutomationBridgeResponse(
            ok: true,
            message: "Appended transcript.",
            bufferTitle: buffers[targetIndex].displayTitle
        )
    }

    func toggleVoiceScribe() {
        if isVoiceScribeRunning {
            stopVoiceScribe()
        } else {
            startVoiceScribe()
        }
    }

    @discardableResult
    func checkVoiceScribeAutoMeetingNow() -> Bool {
        guard isVoiceScribeAutoMeetingEnabled else {
            voiceScribeAutoMeetingStatus = nil
            return false
        }
        guard !isVoiceScribeRunning else {
            voiceScribeAutoMeetingStatus = "Voice scribe is already running."
            return false
        }

        let detectedMeetingApp = voiceScribeMeetingAppDetector()
        voiceScribeDetectedMeetingApp = detectedMeetingApp
        guard let detectedMeetingApp else {
            voiceScribeAutoMeetingStatus = "Watching for meeting apps..."
            return false
        }

        voiceScribeAudioSource = .autoMeeting
        voiceScribeAutoMeetingStatus = "Detected \(detectedMeetingApp.displayName). Starting scribe..."
        startVoiceScribe(detectedMeetingApp: detectedMeetingApp)

        if isVoiceScribeRunning {
            isVoiceScribeStartedByAutoMeetingWatcher = true
            voiceScribeAutoMeetingStatus = "Started \(detectedMeetingApp.displayName) transcript."
        }
        return isVoiceScribeRunning
    }

    private func startVoiceScribeAutoMeetingMonitor() {
        voiceScribeAutoMeetingTask?.cancel()
        voiceScribeAutoMeetingStatus = "Watching for meeting apps..."
        let interval = voiceScribeAutoMeetingPollIntervalNanoseconds
        voiceScribeAutoMeetingTask = Task { [weak self, interval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    break
                }
                self?.checkVoiceScribeAutoMeetingNow()
            }
        }
    }

    private func stopVoiceScribeAutoMeetingMonitor(clearStatus: Bool) {
        voiceScribeAutoMeetingTask?.cancel()
        voiceScribeAutoMeetingTask = nil
        if clearStatus {
            voiceScribeAutoMeetingStatus = nil
        }
    }

    func startVoiceScribe(detectedMeetingApp: VoiceScribeMeetingAppDetection? = nil) {
        guard !isVoiceScribeRunning else { return }

        let sourceResolution = resolveVoiceScribeAudioSource(detectedMeetingApp: detectedMeetingApp)
        let configuration = VoiceScribeConfiguration(
            title: voiceScribeTitle,
            speaker: voiceScribeSpeaker,
            capturesCommands: isVoiceScribeCommandCaptureEnabled,
            detectedMeetingApp: sourceResolution.detectedMeetingApp
        )
        guard let recognizer = makeVoiceScribeRecognizer(for: sourceResolution.audioSource) else {
            voiceScribeStatus = sourceResolution.audioSource.unavailableMessage
            lastError = voiceScribeStatus
            return
        }

        voiceScribeRecognizer = recognizer
        voiceScribePartialTranscript = ""
        voiceScribeStatus = sourceResolution.status
        showScribePanel()
        isVoiceScribeRunning = true
        voiceScribeStatus = "Listening..."

        recognizer.start(
            onPartial: { [weak self] text in
                self?.handleVoiceScribePartial(text)
            },
            onFinal: { [weak self] text in
                self?.handleVoiceScribeFinal(text, configuration: configuration)
            },
            onError: { [weak self] message in
                self?.handleVoiceScribeError(message)
            },
            onStatus: { [weak self] message in
                self?.handleVoiceScribeStatus(message)
            }
        )
    }

    private func resolveVoiceScribeAudioSource(
        detectedMeetingApp suppliedDetectedMeetingApp: VoiceScribeMeetingAppDetection? = nil
    ) -> VoiceScribeAudioSourceResolution {
        guard voiceScribeAudioSource == .autoMeeting else {
            voiceScribeDetectedMeetingApp = nil
            return VoiceScribeAudioSourceResolution(
                audioSource: voiceScribeAudioSource,
                detectedMeetingApp: nil,
                status: voiceScribeAudioSource.permissionStatus
            )
        }

        let detectedMeetingApp = suppliedDetectedMeetingApp ?? voiceScribeMeetingAppDetector()
        voiceScribeDetectedMeetingApp = detectedMeetingApp

        if let detectedMeetingApp {
            return VoiceScribeAudioSourceResolution(
                audioSource: .meetingAudio,
                detectedMeetingApp: detectedMeetingApp,
                status: "Detected \(detectedMeetingApp.displayName). Requesting microphone and system audio access..."
            )
        }

        return VoiceScribeAudioSourceResolution(
            audioSource: .microphone,
            detectedMeetingApp: nil,
            status: "No meeting app detected. Requesting microphone access..."
        )
    }

    private func makeVoiceScribeRecognizer(for source: VoiceScribeAudioSource) -> VoiceScribeRecognizing? {
        switch source {
        case .autoMeeting:
            return makeVoiceScribeRecognizer(for: resolveVoiceScribeAudioSource().audioSource)
        case .microphone:
            return voiceScribeRecognizerFactory()
        case .systemAudio:
            return systemAudioScribeRecognizerFactory()
        case .meetingAudio:
            let recognizers = [
                voiceScribeRecognizerFactory(),
                systemAudioScribeRecognizerFactory()
            ].compactMap { $0 }
            guard !recognizers.isEmpty else { return nil }
            return CombinedVoiceScribeRecognizer(recognizers: recognizers)
        }
    }

    func stopVoiceScribe() {
        let shouldDisableAutoMeeting = isVoiceScribeStartedByAutoMeetingWatcher
        voiceScribeRecognizer?.stop()
        voiceScribeRecognizer = nil
        isVoiceScribeRunning = false
        isVoiceScribeStartedByAutoMeetingWatcher = false
        voiceScribePartialTranscript = ""
        voiceScribeStatus = "Voice scribe stopped."
        if shouldDisableAutoMeeting {
            isVoiceScribeAutoMeetingEnabled = false
        }
    }

    private func handleVoiceScribePartial(_ text: String) {
        voiceScribePartialTranscript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVoiceScribeRunning {
            voiceScribeStatus = "Listening..."
        }
    }

    private func handleVoiceScribeStatus(_ message: String) {
        guard isVoiceScribeRunning else { return }
        voiceScribeStatus = message
    }

    private func handleVoiceScribeFinal(_ text: String, configuration: VoiceScribeConfiguration) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        voiceScribePartialTranscript = ""

        if configuration.capturesCommands,
           let command = VoiceScribeCommandInterpreter.commandRequest(from: trimmed) {
            let response = performLocalAutomationCommand(command)
            voiceScribeStatus = response.ok ? "Voice command handled." : response.message
            if !response.ok {
                lastError = response.message
            }
            return
        }

        let response = appendScribeTranscript(
            LocalAutomationScribeRequest(
                title: configuration.normalizedTitle,
                text: trimmed,
                speaker: configuration.normalizedSpeaker,
                timestamp: VoiceScribeTimestamp.current(),
                language: .markdown,
                mode: nil
            )
        )
        voiceScribeStatus = response.message
        if !response.ok {
            lastError = response.message
        }
    }

    private func handleVoiceScribeError(_ message: String) {
        let shouldDisableAutoMeeting = isVoiceScribeStartedByAutoMeetingWatcher
        voiceScribeRecognizer?.stop()
        voiceScribeRecognizer = nil
        isVoiceScribeRunning = false
        isVoiceScribeStartedByAutoMeetingWatcher = false
        voiceScribeStatus = message
        lastError = message
        if shouldDisableAutoMeeting {
            isVoiceScribeAutoMeetingEnabled = false
        }
    }

    @discardableResult
    func performLocalAutomationCommand(_ request: LocalAutomationCommandRequest) -> LocalAutomationBridgeResponse {
        switch request.command {
        case .newScratch:
            newScratch()
        case .save:
            saveSelected()
        case .close:
            closeSelected()
        case .forceClose:
            forceCloseSelected()
        case .forceClosePath:
            guard let target = request.text?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
                return LocalAutomationBridgeResponse(ok: false, message: "forceClosePath requires a file path, file name, or tab title.", bufferTitle: selectedBuffer?.displayTitle)
            }
            guard forceCloseBuffer(matching: target) else {
                return LocalAutomationBridgeResponse(ok: false, message: "No open tab matches \(target).", bufferTitle: selectedBuffer?.displayTitle)
            }
        case .toggleCompanion:
            toggleCompanionPanel()
        case .runCompanionScan:
            runCompanionScan()
        case .toggleTasks:
            toggleTasksPanel()
        case .toggleTerminal:
            toggleTerminalPanel()
        case .toggleMacros:
            toggleMacrosPanel()
        case .toggleStats:
            toggleStatsPanel()
        case .toggleActivityWatch:
            toggleUsageActivityWatch()
        case .toggleScribe:
            toggleScribePanel()
        case .showCommandPalette:
            showCommandPalette()
        case .replaceLargeFileLine:
            guard selectedLargeFileCanReplaceLine else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "Open a large-file preview before replacing a virtual line.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let lineNumber = request.lineNumber, lineNumber > 0 else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "replaceLargeFileLine requires a positive lineNumber.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let replacement = request.text else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "replaceLargeFileLine requires replacement text.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard !replacement.contains(where: { $0 == "\n" || $0 == "\r" }) else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "Virtual line replacement accepts one replacement line.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }

            replaceSelectedLargeFileLine(lineNumber, with: replacement)
        case .insertLargeFileLine:
            guard selectedLargeFileCanReplaceLine else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "Open a large-file preview before inserting a virtual line.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let lineNumber = request.lineNumber, lineNumber > 0 else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "insertLargeFileLine requires a positive lineNumber.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let insertedText = request.text else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "insertLargeFileLine requires inserted text.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard !insertedText.contains(where: { $0 == "\n" || $0 == "\r" }) else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "Virtual line insertion accepts one inserted line.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }

            insertSelectedLargeFileLine(lineNumber, text: insertedText)
        case .deleteLargeFileLine:
            guard selectedLargeFileCanReplaceLine else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "Open a large-file preview before deleting a virtual line.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let lineNumber = request.lineNumber, lineNumber > 0 else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "deleteLargeFileLine requires a positive lineNumber.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }

            deleteSelectedLargeFileLine(lineNumber)
        case .replaceLargeFileLines:
            guard selectedLargeFileCanReplaceLine else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "Open a large-file preview before replacing virtual lines.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let lineNumber = request.lineNumber, lineNumber > 0 else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "replaceLargeFileLines requires a positive lineNumber.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            let endLineNumber = request.endLineNumber ?? lineNumber
            guard endLineNumber >= lineNumber else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "replaceLargeFileLines requires endLineNumber greater than or equal to lineNumber.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let replacement = request.text else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "replaceLargeFileLines requires replacement text.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }

            replaceSelectedLargeFileLines(lineNumber...endLineNumber, with: replacement)
        case .insertLargeFileLines:
            guard selectedLargeFileCanReplaceLine else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "Open a large-file preview before inserting virtual lines.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let lineNumber = request.lineNumber, lineNumber > 0 else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "insertLargeFileLines requires a positive lineNumber.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let insertedText = request.text else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "insertLargeFileLines requires inserted text.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }

            insertSelectedLargeFileLines(lineNumber, text: insertedText)
        case .deleteLargeFileLines:
            guard selectedLargeFileCanReplaceLine else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "Open a large-file preview before deleting virtual lines.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            guard let lineNumber = request.lineNumber, lineNumber > 0 else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "deleteLargeFileLines requires a positive lineNumber.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }
            let endLineNumber = request.endLineNumber ?? lineNumber
            guard endLineNumber >= lineNumber else {
                return LocalAutomationBridgeResponse(
                    ok: false,
                    message: "deleteLargeFileLines requires endLineNumber greater than or equal to lineNumber.",
                    bufferTitle: selectedBuffer?.displayTitle
                )
            }

            deleteSelectedLargeFileLines(lineNumber...endLineNumber)
        case .insertText:
            guard let text = request.text, !text.isEmpty else {
                return LocalAutomationBridgeResponse(ok: false, message: "insertText requires non-empty text.", bufferTitle: selectedBuffer?.displayTitle)
            }
            guard selectedBuffer.map({ !hasStructuredFolds(for: $0) }) != false else {
                return LocalAutomationBridgeResponse(ok: false, message: "Unfold the source before inserting text.", bufferTitle: selectedBuffer?.displayTitle)
            }
            if let selectedBuffer, selectedBuffer.isLargeFileMode {
                let editingCapability = largeFileEditingCapability(for: selectedBuffer)
                guard editingCapability.canEditLoadedText else {
                    return LocalAutomationBridgeResponse(
                        ok: false,
                        message: editingCapability.saveUnavailableMessage,
                        bufferTitle: selectedBuffer.displayTitle
                    )
                }
            }
            insertTextAtSelections(text)
        }

        return LocalAutomationBridgeResponse(
            ok: true,
            message: "Command handled: \(request.command.rawValue).",
            bufferTitle: selectedBuffer?.displayTitle
        )
    }

    private func collaborationSessionFor(buffer: EditorBuffer, isHost: Bool) -> CollaborationSessionState {
        if let session = collaborationSession, session.bufferID == buffer.id {
            return session
        }

        return CollaborationSessionState(
            id: UUID(),
            bufferID: buffer.id,
            title: buffer.displayTitle,
            localRevision: 0,
            isHost: isHost,
            startedAt: Date(),
            collaborators: []
        )
    }

    private func upsertCollaborator(
        deviceID: String,
        name: String,
        selectionRanges: [TextRange],
        in session: inout CollaborationSessionState
    ) {
        guard deviceID != networkShare.localDeviceID else { return }
        let resolvedSelection = selectionRanges.isEmpty ? [.zero] : selectionRanges

        if let index = session.collaborators.firstIndex(where: { $0.deviceID == deviceID }) {
            session.collaborators[index].name = name
            session.collaborators[index].selectionRanges = resolvedSelection
            session.collaborators[index].lastSeenAt = Date()
        } else {
            let colorIndex = abs(deviceID.hashValue) % Self.collaborationColors.count
            session.collaborators.append(
                RemoteCollaborator(
                    deviceID: deviceID,
                    name: name,
                    selectionRanges: resolvedSelection,
                    colorIndex: colorIndex,
                    lastSeenAt: Date()
                )
            )
        }
    }

    private func collaborationPayload(
        kind: CollaborationMessageKind,
        session: CollaborationSessionState,
        buffer: EditorBuffer,
        text: String?,
        patch: CollaborationTextPatch?,
        selectionRanges: [TextRange]
    ) -> CollaborationPayload {
        CollaborationPayload(
            kind: kind,
            sessionID: session.id,
            title: buffer.displayTitle,
            text: text,
            language: buffer.language,
            patch: patch,
            selectionRanges: selectionRanges,
            revision: session.localRevision,
            sentAt: Date(),
            sourceDeviceID: networkShare.localDeviceID,
            sourceDeviceName: networkShare.localDisplayName,
            sourceToken: nil
        )
    }

    private func sendCollaborationPatchIfNeeded(bufferID: UUID, oldText: String, newText: String) {
        guard !isApplyingCollaborationUpdate,
              var session = collaborationSession,
              session.bufferID == bufferID,
              !session.collaborators.isEmpty,
              let index = buffers.firstIndex(where: { $0.id == bufferID }),
              let patch = CollaborationTextPatch.make(oldText: oldText, newText: newText) else {
            return
        }

        session.localRevision += 1
        collaborationSession = session
        let buffer = buffers[index]
        let payload = collaborationPayload(
            kind: .patch,
            session: session,
            buffer: buffer,
            text: nil,
            patch: patch,
            selectionRanges: buffer.selectionRanges
        )
        sendCollaborationPayloadToCollaborators(payload, collaborators: session.collaborators)
    }

    private func sendCollaborationSelectionIfNeeded(bufferID: UUID, selectionRanges: [TextRange]) {
        guard !isApplyingCollaborationUpdate,
              let session = collaborationSession,
              session.bufferID == bufferID,
              !session.collaborators.isEmpty,
              let buffer = buffers.first(where: { $0.id == bufferID }) else {
            return
        }

        let payload = collaborationPayload(
            kind: .selection,
            session: session,
            buffer: buffer,
            text: nil,
            patch: nil,
            selectionRanges: selectionRanges
        )
        sendCollaborationPayloadToCollaborators(payload, collaborators: session.collaborators)
    }

    private func joinCollaboration(from payload: CollaborationPayload) {
        guard let text = payload.text else { return }
        let now = Date()
        let title = uniqueSharedTitle(payload.title.isEmpty ? "Collaborative Note" : payload.title)
        let buffer = EditorBuffer(
            id: UUID(),
            title: title,
            kind: .scratch,
            filePath: nil,
            text: text,
            language: payload.language ?? .markdown,
            createdAt: now,
            updatedAt: now,
            isDirty: !text.isEmpty,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id

        var session = CollaborationSessionState(
            id: payload.sessionID,
            bufferID: buffer.id,
            title: title,
            localRevision: payload.revision,
            isHost: false,
            startedAt: now,
            collaborators: []
        )
        upsertCollaborator(
            deviceID: payload.collaboratorDeviceID,
            name: payload.collaboratorName,
            selectionRanges: payload.selectionRanges,
            in: &session
        )
        collaborationSession = session
        showNetworkPanel()

        let response = collaborationPayload(
            kind: .accept,
            session: session,
            buffer: buffer,
            text: nil,
            patch: nil,
            selectionRanges: buffer.selectionRanges
        )
        sendCollaborationPayload(response, to: payload.sourceDeviceID)
        persistSoon()
    }

    private func acceptCollaboration(from payload: CollaborationPayload) {
        guard var session = collaborationSession,
              session.id == payload.sessionID else {
            return
        }

        upsertCollaborator(
            deviceID: payload.collaboratorDeviceID,
            name: payload.collaboratorName,
            selectionRanges: payload.selectionRanges,
            in: &session
        )
        collaborationSession = session
        showNetworkPanel()
    }

    private func applyCollaborationPatch(from payload: CollaborationPayload) {
        guard var session = collaborationSession,
              session.id == payload.sessionID,
              let patch = payload.patch,
              let index = buffers.firstIndex(where: { $0.id == session.bufferID }) else {
            return
        }

        let oldText = buffers[index].text
        let newText = patch.apply(to: oldText)
        guard oldText != newText else {
            updateRemoteCollaborator(from: payload)
            return
        }

        isApplyingCollaborationUpdate = true
        buffers[index].text = newText
        buffers[index].updatedAt = Date()
        buffers[index].isDirty = buffers[index].kind == .scratch ? !newText.isEmpty : true
        reanchorComments(for: buffers[index], newText: newText)
        upsertCollaborator(
            deviceID: payload.collaboratorDeviceID,
            name: payload.collaboratorName,
            selectionRanges: payload.selectionRanges,
            in: &session
        )
        session.localRevision = max(session.localRevision + 1, payload.revision)
        collaborationSession = session
        isApplyingCollaborationUpdate = false
        relayCollaborationPayloadIfHost(payload, session: session, buffer: buffers[index])
        persistSoon()
    }

    private func updateRemoteCollaborator(from payload: CollaborationPayload) {
        guard var session = collaborationSession,
              session.id == payload.sessionID else {
            return
        }

        upsertCollaborator(
            deviceID: payload.collaboratorDeviceID,
            name: payload.collaboratorName,
            selectionRanges: payload.selectionRanges,
            in: &session
        )
        collaborationSession = session
        if let buffer = buffers.first(where: { $0.id == session.bufferID }) {
            relayCollaborationPayloadIfHost(payload, session: session, buffer: buffer)
        }
    }

    private func removeRemoteCollaborator(from payload: CollaborationPayload) {
        guard var session = collaborationSession,
              session.id == payload.sessionID else {
            return
        }

        session.collaborators.removeAll { $0.deviceID == payload.collaboratorDeviceID }
        collaborationSession = session.collaborators.isEmpty ? nil : session
        if let buffer = buffers.first(where: { $0.id == session.bufferID }) {
            relayCollaborationPayloadIfHost(payload, session: session, buffer: buffer)
        }
        networkShare.statusMessage = "\(payload.collaboratorName) left collaboration. Your local copy remains open."
    }

    private func relayCollaborationPayloadIfHost(
        _ payload: CollaborationPayload,
        session: CollaborationSessionState,
        buffer: EditorBuffer
    ) {
        guard session.isHost else { return }
        guard !isCollaborationRelayActive else { return }

        switch payload.kind {
        case .patch, .selection, .leave:
            break
        case .invite, .accept:
            return
        }

        let actorDeviceID = payload.collaboratorDeviceID
        var relayed = payload
        relayed.title = buffer.displayTitle
        relayed.language = buffer.language
        relayed.revision = session.localRevision
        relayed.sentAt = Date()
        relayed.sourceDeviceID = networkShare.localDeviceID
        relayed.sourceDeviceName = networkShare.localDisplayName
        relayed.sourceToken = nil
        relayed.actorDeviceID = actorDeviceID
        relayed.actorDeviceName = payload.collaboratorName

        for collaborator in session.collaborators
            where collaborator.deviceID != actorDeviceID &&
                collaborator.deviceID != payload.sourceDeviceID {
            sendCollaborationPayload(relayed, to: collaborator.deviceID)
        }
    }

    private func uniqueSharedTitle(_ title: String) -> String {
        guard buffers.contains(where: { $0.title == title }) else {
            return title
        }

        var index = 2
        while buffers.contains(where: { $0.title == "\(title) \(index)" }) {
            index += 1
        }

        return "\(title) \(index)"
    }

    func compareSelectedBufferWithPreviousTab() {
        guard let selectedIndex else { return }
        guard selectedIndex > 0 else {
            lastError = "Select a tab after the file you want to compare against."
            return
        }

        let old = buffers[selectedIndex - 1]
        let new = buffers[selectedIndex]

        do {
            appendDiffBuffer(
                from: try Self.diffPreviewDocument(for: old),
                to: try Self.diffPreviewDocument(for: new)
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func compareSelectedBufferWithFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        compareSelectedBuffer(withFileAt: url)
    }

    func compareSelectedBuffer(withFileAt url: URL) {
        guard let selectedBuffer else { return }

        let detectedLanguage = EditorLanguage.detect(fileName: url.lastPathComponent, text: "")
        if detectedLanguage.isBinaryPreview || Self.shouldOpenAsHexPreview(at: url) {
            lastError = "Select a text-readable file to compare."
            return
        }

        do {
            appendDiffBuffer(
                from: try Self.diffPreviewDocument(for: selectedBuffer),
                to: try Self.diffPreviewDocument(title: url.lastPathComponent, url: url)
            )
        } catch let error as DiffInputError {
            lastError = error.localizedDescription
        } catch {
            lastError = "Could not read comparison file: \(error.localizedDescription)"
        }
    }

    private func appendDiffBuffer(from old: TextDiff.PreviewDocument, to new: TextDiff.PreviewDocument) {
        let diff = TextDiff.unifiedDiffPreview(
            from: old,
            to: new,
            limitDescription: Self.diffInputLimitDescription
        )
        let now = Date()
        let title = uniqueSharedTitle("Diff: \(old.title) vs \(new.title)")
        let buffer = EditorBuffer(
            id: UUID(),
            title: title,
            kind: .scratch,
            filePath: nil,
            text: diff,
            language: .plain,
            createdAt: now,
            updatedAt: now,
            isDirty: true,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id
        persistSoon()
    }

    private static func diffPreviewDocument(title: String, url: URL) throws -> TextDiff.PreviewDocument {
        let fileSizeBytes = fileSizeBytes(at: url).map(Int.init)
        if let fileSizeBytes,
           fileSizeBytes > maxDiffInputBytes {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }
            let data = try fileHandle.read(upToCount: maxDiffInputBytes) ?? Data()
            return diffPreviewDocument(
                title: title,
                text: decodedTextPreview(from: data),
                knownOriginalByteCount: fileSizeBytes,
                knownOriginalLineCount: nil,
                originalLineCountIsKnown: false,
                forceTruncated: true
            )
        }

        var encoding = String.Encoding.utf8
        let text = try String(contentsOf: url, usedEncoding: &encoding)
        return diffPreviewDocument(title: title, text: text)
    }

    private static func diffPreviewDocument(for buffer: EditorBuffer) throws -> TextDiff.PreviewDocument {
        guard buffer.isLargeFileMode else {
            return diffPreviewDocument(title: buffer.displayTitle, text: buffer.text)
        }

        guard let filePath = buffer.filePath else {
            throw DiffInputError.largePreviewMissingSource
        }

        do {
            return try diffPreviewDocument(
                title: buffer.displayTitle,
                url: URL(fileURLWithPath: filePath)
            )
        } catch {
            throw DiffInputError.sourceReadFailed(buffer.displayTitle, error.localizedDescription)
        }
    }

    private static func diffPreviewDocument(
        title: String,
        text: String,
        knownOriginalByteCount: Int? = nil,
        knownOriginalLineCount: Int? = nil,
        originalLineCountIsKnown: Bool = true,
        forceTruncated: Bool = false
    ) -> TextDiff.PreviewDocument {
        let originalByteCount = knownOriginalByteCount ?? text.utf8.count
        let measuredLineCount = diffLineCount(in: text)
        let originalLineCount = knownOriginalLineCount ?? measuredLineCount
        let reportedOriginalLineCount = originalLineCountIsKnown ? originalLineCount : nil
        let limitedText = limitedDiffText(text)
        let isTruncated = forceTruncated ||
            limitedText.isTruncated ||
            originalByteCount > maxDiffInputBytes ||
            originalLineCount > maxDiffInputLines
        return TextDiff.PreviewDocument(
            title: title,
            text: limitedText.text,
            originalByteCount: originalByteCount,
            originalLineCount: reportedOriginalLineCount,
            isTruncated: isTruncated
        )
    }

    private static func limitedDiffText(_ text: String) -> (text: String, lineCount: Int, isTruncated: Bool) {
        guard !text.isEmpty else { return ("", 0, false) }

        var limited = ""
        var byteCount = 0
        var lineCount = 1
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maxDiffInputBytes else { break }

            limited.append(character)
            byteCount += characterByteCount
            index = text.index(after: index)

            if character.isNewline, index < text.endIndex {
                lineCount += 1
                if lineCount > maxDiffInputLines {
                    return (limited, min(lineCount, maxDiffInputLines), true)
                }
            }
        }

        return (limited, min(lineCount, maxDiffInputLines), index < text.endIndex)
    }

    private static func diffLineCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var count = text.reduce(0) { partial, character in
            partial + (character.isNewline ? 1 : 0)
        }
        if text.last?.isNewline != true {
            count += 1
        }
        return count
    }

    func generatePOModeBriefForDocumentCatalog() {
        guard let report = refreshPOModeAnalysisForDocumentCatalog(showPanel: false) else {
            return
        }

        let text = DocumentFolderAnalysis.markdownReport(
            rootURL: report.rootURL,
            files: report.files,
            generatedAt: report.generatedAt
        )
        let now = Date()
        let buffer = EditorBuffer(
            id: UUID(),
            title: uniqueSharedTitle("PO Mode: \(report.rootName)"),
            kind: .scratch,
            filePath: nil,
            text: text,
            language: .markdown,
            createdAt: now,
            updatedAt: now,
            isDirty: true,
            selectionRanges: [.zero],
            aiSessions: [],
            selectedAIChatSessionID: nil
        )

        buffers.append(buffer)
        selectedBufferID = buffer.id
        networkShare.statusMessage = "Generated PO mode analysis for \(report.rootName)."
        persistSoon()
    }

    @discardableResult
    func addPOModeGapsAsTasks(scope: ManualTaskScope = .workspace) -> Int {
        guard let report = poModeReport ?? refreshPOModeAnalysisForDocumentCatalog(showPanel: false) else {
            return 0
        }

        let gaps = report.gaps
        guard !gaps.isEmpty else {
            networkShare.statusMessage = "No PO gaps to add as tasks."
            return 0
        }

        var existingTitles = Set((manualTasks + globalManualTasks).map { normalizedTaskTitle($0.title) })
        var addedCount = 0
        for reference in gaps.prefix(100) {
            let title = Self.poModeGapTaskTitle(for: reference)
            let key = normalizedTaskTitle(title)
            guard !key.isEmpty,
                  existingTitles.insert(key).inserted else {
                continue
            }

            addManualTask(title: title, status: .todo, scope: scope)
            addedCount += 1
        }

        networkShare.statusMessage = addedCount == 0
            ? "No new PO gap tasks."
            : "Added \(addedCount) PO gap task\(addedCount == 1 ? "" : "s")."
        return addedCount
    }

    func runPOModeAIInterpretationForDocumentCatalog() {
        guard let report = poModeReport ?? refreshPOModeAnalysisForDocumentCatalog(showPanel: false) else {
            return
        }

        let client: any HTTPAICompleting
        do {
            client = httpAIClientFactory(try httpAIConfigurationProvider())
        } catch {
            lastError = "PO mode AI interpretation requires HTTP LLM settings: \(error.localizedDescription)"
            return
        }

        poModeAIInterpretationTask?.cancel()
        hideRightPanels()
        isPOModePanelVisible = true
        isPOModeAIInterpretationRunning = true
        poModeAIInterpretationStatus = "Interpreting \(report.rootName)..."

        let reportSnapshot = report
        let prompt = Self.poModeAIInterpretationUserPrompt(for: reportSnapshot)
        poModeAIInterpretationTask = Task { [weak self] in
            do {
                let response = try await client.complete(
                    messages: [
                        HTTPAIChatMessage(
                            role: "user",
                            content: prompt
                        )
                    ],
                    systemPrompt: Self.poModeAIInterpretationSystemPrompt
                )
                let interpretation = response.trimmingCharacters(in: .whitespacesAndNewlines)

                try Task.checkCancellation()
                await MainActor.run {
                    guard self?.poModeReport?.rootURL == reportSnapshot.rootURL,
                          self?.poModeReport?.generatedAt == reportSnapshot.generatedAt else {
                        return
                    }
                    self?.poModeAIInterpretation = interpretation.isEmpty ? "No interpretation returned." : interpretation
                    self?.poModeAIInterpretationStatus = "AI interpretation ready."
                    self?.isPOModeAIInterpretationRunning = false
                    self?.poModeAIInterpretationTask = nil
                }
            } catch {
                await MainActor.run {
                    if Task.isCancelled {
                        self?.poModeAIInterpretationStatus = "Cancelled."
                    } else {
                        self?.poModeAIInterpretationStatus = "PO mode AI error: \(error.localizedDescription)"
                    }
                    self?.isPOModeAIInterpretationRunning = false
                    self?.poModeAIInterpretationTask = nil
                }
            }
        }
    }

    @discardableResult
    func refreshPOModeAnalysisForDocumentCatalog(showPanel: Bool = true) -> DocumentFolderAnalysis.Report? {
        guard let rootPath = documentCatalogRootPath else {
            lastError = "Open a documents folder before generating PO mode analysis."
            return nil
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let nodes = documentCatalogNodes.isEmpty ? Self.buildDocumentCatalogNodes(rootURL: rootURL) : documentCatalogNodes
        if documentCatalogNodes.isEmpty {
            documentCatalogNodes = nodes
        }

        let fileURLs = documentCatalogFileNodes(nodes).map(\.url)
        guard !fileURLs.isEmpty else {
            lastError = "The opened folder does not contain readable documents."
            return nil
        }

        let inputFiles = DocumentFolderAnalysis.loadInputFiles(rootURL: rootURL, fileURLs: fileURLs)
        guard !inputFiles.isEmpty else {
            lastError = "The opened folder does not contain readable text documents for PO mode."
            return nil
        }

        let report = DocumentFolderAnalysis.analyze(rootURL: rootURL, files: inputFiles)
        poModeAIInterpretationTask?.cancel()
        poModeReport = report
        poModeAIInterpretation = nil
        poModeAIInterpretationStatus = nil
        isPOModeAIInterpretationRunning = false
        if showPanel {
            hideRightPanels()
            isPOModePanelVisible = true
        }
        networkShare.statusMessage = "Updated PO mode analysis for \(rootURL.lastPathComponent)."
        return report
    }

    private static let poModeAIInterpretationSystemPrompt = """
    You are a product owner reviewing a folder of product and feature documents. Be concise, concrete, and evidence-based. Identify the likely intent, the highest-risk gaps, missing decisions, duplicated or conflicting requirements, and the next actions. Keep the output in Markdown with these sections: Product Reading, Gaps, Risks, Next Actions.
    """

    private nonisolated static func poModeGapTaskTitle(for reference: DocumentFolderAnalysis.LineReference) -> String {
        let title = reference.title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let fallbackTitle = title.isEmpty ? reference.excerpt : title
        return "Resolve gap: \(fallbackTitle) (\(reference.relativePath):\(reference.lineNumber))"
    }

    nonisolated static func poModeAIInterpretationUserPrompt(
        for report: DocumentFolderAnalysis.Report
    ) -> String {
        let markdown = DocumentFolderAnalysis.markdownReport(
            rootURL: report.rootURL,
            files: report.files,
            generatedAt: report.generatedAt
        )
        let boundedReport = String(markdown.prefix(16_000))
        let truncatedNote = markdown.count > boundedReport.count
            ? "\n\n[SimpleLime note: report truncated to \(boundedReport.count) characters for the LLM request.]"
            : ""
        return """
        Interpret this SimpleLime PO mode report.

        Folder: \(report.rootName)
        Documents: \(report.documentCount)
        Headings: \(report.headingCount)
        Tasks: \(report.taskCount)
        Gaps: \(report.gapCount)

        \(boundedReport)\(truncatedNote)
        """
    }

    nonisolated static func suggestedSaveFileName(for buffer: EditorBuffer, fileType: SaveFileType? = nil) -> String {
        let fileType = fileType ?? SaveFileType.preferred(for: buffer.language)
        let baseName = suggestedSaveBaseName(for: buffer)
        return fileName(baseName, changingExtensionTo: fileType.fileExtension)
    }

    nonisolated static func suggestedSaveFileNameFromAIResponse(
        _ response: String,
        fileType: SaveFileType
    ) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = aiFileNameCandidate(from: trimmed)
        return fileName(candidate.isEmpty ? "Untitled" : candidate, changingExtensionTo: fileType.fileExtension)
    }

    nonisolated static func fileName(_ fileName: String, changingExtensionTo fileExtension: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let sanitized = sanitizedFileBaseName(base.isEmpty ? fileName : base) ?? "Untitled"
        return "\(sanitized).\(fileExtension)"
    }

    nonisolated static func url(_ url: URL, withExtension fileExtension: String) -> URL {
        guard url.pathExtension.lowercased() != fileExtension.lowercased() else {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    nonisolated static func encryptedURL(for url: URL) -> URL {
        Self.url(url, withExtension: EncryptedDocumentService.fileExtension)
    }

    private nonisolated static let aiSaveFileNameSystemPrompt = """
    You suggest concise, human-readable file names for a macOS editor.
    Return only a file name, without directories, explanations, Markdown, or quotes.
    Use 2 to 6 words when possible.
    """

    private nonisolated static func aiSaveFileNameUserPrompt(buffer: EditorBuffer, fileType: SaveFileType) -> String {
        """
        Suggest a useful file name for this document.
        Required extension: .\(fileType.fileExtension)
        Current tab title: \(buffer.displayTitle)
        Language: \(buffer.language.displayName)

        Document excerpt:
        \(aiSaveFileNameExcerpt(buffer.text))
        """
    }

    private nonisolated static func aiSaveFileNameExcerpt(_ text: String) -> String {
        let limit = 4_000
        guard text.count > limit else { return text }

        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<endIndex]) + "\n\n[truncated]"
    }

    func saveSelected() {
        guard let selectedIndex else { return }
        if buffers[selectedIndex].isLargeFileMode {
            if selectedBufferCanSaveLargeFileChunkBack {
                _ = saveSelectedLargeFileChunkBackToSource()
            } else {
                lastError = largeFileEditingCapability(for: buffers[selectedIndex]).saveUnavailableMessage
            }
            return
        }

        guard canSaveBuffer(at: selectedIndex) else { return }

        if buffers[selectedIndex].kind == .scratch || buffers[selectedIndex].filePath == nil {
            saveSelectedAs()
            return
        }

        guard let path = buffers[selectedIndex].filePath else { return }
        saveBuffer(at: selectedIndex, to: URL(fileURLWithPath: path))
    }

    func saveSelectedAs() {
        guard let selectedIndex else { return }
        guard canSaveBuffer(at: selectedIndex) else { return }

        let buffer = buffers[selectedIndex]
        let initialType = SaveFileType.preferred(for: buffer.language)
        let initialFileName = Self.suggestedSaveFileName(for: buffer, fileType: initialType)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = initialFileName
        let accessory = SaveFileTypeAccessoryController(
            panel: panel,
            initialFileName: initialFileName,
            initialType: initialType,
            aiSuggestionHandler: { [weak self, buffer] fileType, completion in
                self?.suggestSaveFileNameWithAI(
                    for: buffer,
                    fileType: fileType,
                    completion: completion
                )
            }
        )
        panel.accessoryView = accessory.view

        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveBuffer(
            at: selectedIndex,
            to: Self.url(url, withExtension: accessory.selectedFileType.fileExtension),
            languageOverride: accessory.selectedFileType.language,
            preserveEncryption: false
        )
    }

    func saveSelected(to url: URL, as fileType: SaveFileType? = nil) {
        guard let selectedIndex else { return }
        guard canSaveBuffer(at: selectedIndex) else { return }

        let targetURL = fileType.map { Self.url(url, withExtension: $0.fileExtension) } ?? url
        saveBuffer(at: selectedIndex, to: targetURL, languageOverride: fileType?.language, preserveEncryption: false)
    }

    private func suggestSaveFileNameWithAI(
        for buffer: EditorBuffer,
        fileType: SaveFileType,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let client: any HTTPAICompleting
        do {
            client = httpAIClientFactory(try httpAIConfigurationProvider())
        } catch {
            completion(.failure(error))
            return
        }

        Task {
            do {
                let response = try await client.complete(
                    messages: [
                        HTTPAIChatMessage(
                            role: "user",
                            content: Self.aiSaveFileNameUserPrompt(buffer: buffer, fileType: fileType)
                        )
                    ],
                    systemPrompt: Self.aiSaveFileNameSystemPrompt
                )
                let fileName = Self.suggestedSaveFileNameFromAIResponse(response, fileType: fileType)
                completion(.success(fileName))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func saveSelectedEncryptedWithPrompt() {
        guard let selectedIndex else { return }
        guard canSaveBuffer(at: selectedIndex) else { return }

        let buffer = buffers[selectedIndex]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(buffer.displayTitle, changingExtensionTo: EncryptedDocumentService.fileExtension)

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        let targetURL = Self.encryptedURL(for: url)
        guard let password = promptForNewEncryptedDocumentPassword(
            documentName: targetURL.lastPathComponent,
            url: targetURL
        ) else {
            return
        }

        saveSelectedEncrypted(to: targetURL, password: password)
    }

    @discardableResult
    func saveSelectedEncrypted(to url: URL, password: String) -> Bool {
        guard let selectedIndex else { return false }
        guard canSaveBuffer(at: selectedIndex) else { return false }
        return saveEncryptedBuffer(at: selectedIndex, to: Self.encryptedURL(for: url), password: password)
    }

    func openEncryptedFileWithPrompt() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        if let encryptedType = UTType(filenameExtension: EncryptedDocumentService.fileExtension) {
            panel.allowedContentTypes = [encryptedType]
        }

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        openEncryptedFileWithPrompt(at: url)
    }

    func openEncryptedFileWithPrompt(at url: URL) {
        if let existing = buffers.first(where: { $0.filePath == url.path }) {
            selectedBufferID = existing.id
            return
        }

        if let password = passwordForEncryptedDocument(at: url, documentName: url.lastPathComponent, isNewPassword: false) {
            openEncryptedFile(at: url, password: password)
        }
    }

    func openEncryptedFile(at url: URL, password: String) {
        if let existing = buffers.first(where: { $0.filePath == url.path }) {
            selectedBufferID = existing.id
            cacheEncryptionPassword(password, for: url)
            return
        }

        do {
            let encryptedData = try Data(contentsOf: url)
            let text = try EncryptedDocumentService.decryptText(from: encryptedData, password: password)
            let now = Date()
            let buffer = EditorBuffer(
                id: UUID(),
                title: url.lastPathComponent,
                kind: .file,
                filePath: url.path,
                text: text,
                language: Self.detectEncryptedDocumentLanguage(url: url, text: text),
                createdAt: now,
                updatedAt: now,
                isDirty: false,
                selectionRanges: [.zero],
                aiSessions: [],
                selectedAIChatSessionID: nil,
                savePolicy: .normal,
                isLargeFileMode: false,
                fileSizeBytes: Int64(encryptedData.count),
                isEncrypted: true
            )

            buffers.append(buffer)
            selectedBufferID = buffer.id
            cacheEncryptionPassword(password, for: url)
            recordUsageEvent(
                \.openCount,
                documentKey: documentKey(for: buffer),
                timelineKind: .open,
                timelineTitle: "Opened \(buffer.displayTitle)"
            )
            persistSoon()
        } catch {
            lastError = "Could not unlock \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func exportSelectedAsHTML() {
        guard let buffer = selectedBuffer else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFileName(for: buffer, extension: "html")
        panel.allowedContentTypes = [.html]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = DocumentExportService.htmlDocument(
            title: buffer.displayTitle,
            text: buffer.text,
            language: buffer.language
        )
        writeExport(html, to: url)
    }

    func exportSelectedAsWord() {
        guard let buffer = selectedBuffer else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFileName(for: buffer, extension: "docx")
        if let docxType = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [docxType]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = DocumentExportService.wordDocumentData(
            title: buffer.displayTitle,
            text: buffer.text,
            language: buffer.language
        )
        writeExport(data, to: url)
    }

    func exportSelectedAsPDF() {
        guard let buffer = selectedBuffer else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFileName(for: buffer, extension: "pdf")
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try DocumentExportService.pdfData(
                title: buffer.displayTitle,
                text: buffer.text,
                language: buffer.language
            )
            writeExport(data, to: url)
        } catch {
            lastError = "Could not export \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func exportSelectedDrawingAsSVG() {
        guard let buffer = selectedBuffer, buffer.language.isWhiteboard else {
            lastError = "Open a drawing board before exporting SVG."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFileName(for: buffer, extension: "svg")
        if let svgType = UTType(filenameExtension: "svg") {
            panel.allowedContentTypes = [svgType]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let svg = WhiteboardExportService.svgDocument(
            title: buffer.displayTitle,
            document: WhiteboardDocument.decode(from: buffer.text)
        )
        writeExport(svg, to: url)
    }

    func exportSelectedDrawingAsPNG() {
        guard let buffer = selectedBuffer, buffer.language.isWhiteboard else {
            lastError = "Open a drawing board before exporting PNG."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFileName(for: buffer, extension: "png")
        panel.allowedContentTypes = [.png]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = WhiteboardExportService.pngData(document: WhiteboardDocument.decode(from: buffer.text)) else {
            lastError = "Could not render \(buffer.displayTitle) as PNG."
            return
        }
        writeExport(data, to: url)
    }

    func copySelectedDrawingAsPNG(to pasteboard: NSPasteboard = .general) {
        guard let buffer = selectedBuffer, buffer.language.isWhiteboard else {
            lastError = "Open a drawing board before copying it as PNG."
            return
        }

        let document = WhiteboardDocument.decode(from: buffer.text)
        guard WhiteboardExportService.writePNGToPasteboard(document: document, pasteboard: pasteboard) else {
            lastError = "Could not render \(buffer.displayTitle) as PNG."
            return
        }

        networkShare.statusMessage = "Copied \(buffer.displayTitle) as PNG."
    }

    func insertDrawingWidgetIntoMarkdown() {
        guard let selectedBuffer else { return }
        let drawingBuffer: EditorBuffer
        if selectedBuffer.language.isWhiteboard {
            drawingBuffer = selectedBuffer
        } else if selectedBuffer.language.isMarkdown,
                  let latestDrawing = buffers.last(where: { $0.language.isWhiteboard }) {
            drawingBuffer = latestDrawing
        } else {
            lastError = "Open a drawing board or Markdown document before inserting a drawing widget."
            return
        }

        let widget = """


        ```sldraw
        \(WhiteboardDocument.decode(from: drawingBuffer.text).encodedText().trimmingCharacters(in: .whitespacesAndNewlines))
        ```

        """

        if selectedBuffer.language.isMarkdown {
            insertTextAtSelections(widget)
        } else {
            let now = Date()
            let buffer = EditorBuffer(
                id: UUID(),
                title: "\(drawingBuffer.displayTitle) Widget",
                kind: .scratch,
                filePath: nil,
                text: widget.trimmingCharacters(in: .newlines),
                language: .markdown,
                createdAt: now,
                updatedAt: now,
                isDirty: true,
                selectionRanges: [.zero],
                aiSessions: [],
                selectedAIChatSessionID: nil
            )
            buffers.append(buffer)
            selectedBufferID = buffer.id
            showMarkdownPreviewMode()
            persistSoon()
        }
    }

    func exportSelectedDelimitedTableAsExcel() {
        guard let buffer = selectedBuffer else { return }
        guard buffer.language.isDelimitedTable else {
            lastError = "Open a CSV or TSV file before exporting to Excel."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFileName(for: buffer, extension: "xlsx")
        if let xlsxType = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [xlsxType]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = DocumentExportService.excelWorkbookData(
            title: buffer.displayTitle,
            text: buffer.text,
            language: buffer.language
        )
        writeExport(data, to: url)
    }

    func saveVersionedCopyOfSelected() {
        guard let selectedIndex else { return }
        guard canSaveBuffer(at: selectedIndex) else { return }
        guard let filePath = buffers[selectedIndex].filePath else {
            lastError = "Save this scratch buffer before creating numbered versions."
            return
        }

        let sourceURL = URL(fileURLWithPath: filePath)
        let versionURL = Self.nextVersionedCopyURL(for: sourceURL)

        do {
            if buffers[selectedIndex].isEncrypted {
                guard let password = passwordForEncryptedDocument(
                    at: sourceURL,
                    documentName: sourceURL.lastPathComponent,
                    isNewPassword: false
                ) else {
                    return
                }
                let encryptedData = try EncryptedDocumentService.encrypt(text: buffers[selectedIndex].text, password: password)
                try encryptedData.write(to: versionURL, options: .atomic)
            } else {
                try buffers[selectedIndex].text.write(to: versionURL, atomically: true, encoding: .utf8)
            }
        } catch {
            lastError = "Could not save \(versionURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func saveSelectedWithNumberedBackup() {
        guard let selectedIndex else { return }
        guard canSaveBuffer(at: selectedIndex) else { return }
        guard let filePath = buffers[selectedIndex].filePath else {
            lastError = "Save this scratch buffer before creating numbered backups."
            return
        }

        let sourceURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            lastError = "Save \(sourceURL.lastPathComponent) before creating numbered backups."
            return
        }

        let versionURL = Self.nextVersionedCopyURL(for: sourceURL)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: versionURL)
        } catch {
            lastError = "Could not create \(versionURL.lastPathComponent): \(error.localizedDescription)"
            return
        }

        if saveBuffer(at: selectedIndex, to: sourceURL) {
            networkShare.statusMessage = "Saved \(sourceURL.lastPathComponent) with backup \(versionURL.lastPathComponent)."
        }
    }

    static func nextVersionedCopyURL(for url: URL, fileManager: FileManager = .default) -> URL {
        let directory = url.deletingLastPathComponent()
        let fileExtension = url.pathExtension
        let baseName = fileExtension.isEmpty
            ? url.lastPathComponent
            : url.deletingPathExtension().lastPathComponent

        var index = 1
        while true {
            let fileName = fileExtension.isEmpty
                ? "\(baseName).\(index)"
                : "\(baseName).\(index).\(fileExtension)"
            let candidate = directory.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    func commitSelectedFileWithPrompt() {
        guard let buffer = selectedBuffer,
              let filePath = buffer.filePath else {
            lastError = "Save this scratch buffer before committing it."
            return
        }
        guard GitRepositoryService.repository(containingFileAt: URL(fileURLWithPath: filePath)) != nil else {
            lastError = "The selected file is not inside a git repository."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Commit Current File"
        alert.informativeText = "SimpleLime will save, stage, and commit only \(buffer.displayTitle)."
        alert.addButton(withTitle: "Commit")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = "Update \(buffer.displayTitle)"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        commitSelectedFile(message: field.stringValue)
    }

    func commitSelectedFile(message: String) {
        guard let selectedIndex else { return }
        guard canSaveBuffer(at: selectedIndex) else { return }
        guard let filePath = buffers[selectedIndex].filePath else {
            lastError = "Save this scratch buffer before committing it."
            return
        }

        let url = URL(fileURLWithPath: filePath)
        if buffers[selectedIndex].isDirty,
           !saveBuffer(at: selectedIndex, to: url) {
            return
        }

        do {
            try GitRepositoryService.commit(fileURL: url, message: message)
            networkShare.statusMessage = "Committed \(url.lastPathComponent)."
        } catch {
            lastError = "Could not commit \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func persistNow() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        persistCommentsNow()
        persistUsageStats()

        if let onPersistRequested {
            onPersistRequested()
            return
        }

        guard let persistence else { return }

        do {
            try persistence.save(buffers: buffersForPersistence, selectedID: selectedBufferID)
        } catch {
            lastError = "Could not persist session: \(error.localizedDescription)"
        }
    }

    func persistSoon() {
        pendingSaveTask?.cancel()

        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                self?.persistNow()
            }
        }
    }

    func persistCommentsNow() {
        pendingCommentSaveTask?.cancel()
        pendingCommentSaveTask = nil

        guard let commentPersistence else { return }

        do {
            try commentPersistence.save(documentComments)
        } catch {
            lastError = "Could not persist comments: \(error.localizedDescription)"
        }
    }

    private func persistCommentsSoon() {
        pendingCommentSaveTask?.cancel()

        pendingCommentSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                self?.persistCommentsNow()
            }
        }
    }

    private func persistManualTasks() {
        guard let taskPersistence else { return }

        do {
            try taskPersistence.save(manualTasks)
        } catch {
            lastError = "Could not persist tasks: \(error.localizedDescription)"
        }
    }

    private func persistGlobalManualTasks() {
        guard let globalTaskPersistence else { return }

        do {
            try globalTaskPersistence.save(globalManualTasks)
        } catch {
            lastError = "Could not persist global tasks: \(error.localizedDescription)"
        }
    }

    private func persistTextMacros() {
        pendingTextMacroSaveTask?.cancel()
        pendingTextMacroSaveTask = nil
        guard let textMacroPersistence else { return }

        do {
            try textMacroPersistence.save(
                textMacros: customTextMacros,
                actionMacros: customActionMacros,
                pinnedMacros: pinnedMacros
            )
        } catch {
            lastError = "Could not persist macros: \(error.localizedDescription)"
        }
    }

    private func recordEdit(oldText: String, newText: String, buffer: EditorBuffer, now: Date = Date()) {
        let oldCount = oldText.utf16.count
        let newCount = newText.utf16.count
        let added = max(0, newCount - oldCount)
        let removed = max(0, oldCount - newCount)
        let documentKey = documentKey(for: buffer)
        let editDuration: Int
        if let lastEditingActivityAt {
            let delta = now.timeIntervalSince(lastEditingActivityAt)
            editDuration = delta > 0 && delta <= Self.usageTimelineMergeWindow ? max(1, Int(delta.rounded())) : 0
        } else {
            editDuration = 0
        }

        mutateTodayUsageStats(now: now, documentKey: documentKey) { day in
            day.editCount += 1
            day.charactersAdded += added
            day.charactersRemoved += removed
            day.activeEditingSeconds += editDuration
            Self.appendUsageTimelineEntry(
                kind: .edit,
                title: "Edited \(buffer.displayTitle)",
                documentKey: documentKey,
                durationSeconds: editDuration,
                timestamp: now,
                to: &day
            )
        }
        lastEditingActivityAt = now
    }

    private func recordMacroUsage(
        title: String,
        documentKey: String,
        durationSeconds: Int = 0,
        now: Date = Date()
    ) {
        mutateTodayUsageStats(now: now, documentKey: documentKey) { day in
            day.macroCount += 1
            Self.appendUsageTimelineEntry(
                kind: .macro,
                title: title,
                documentKey: documentKey,
                durationSeconds: durationSeconds,
                timestamp: now,
                to: &day
            )
        }
    }

    private static func appendUsageTimelineEntry(
        kind: UsageTimelineEntry.Kind,
        title: String,
        documentKey: String,
        durationSeconds: Int,
        timestamp: Date,
        to day: inout DailyUsageStats
    ) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        let durationSeconds = max(0, durationSeconds)
        if let lastIndex = day.timelineEntries.indices.last {
            let last = day.timelineEntries[lastIndex]
            if last.kind == kind,
               last.title == cleanedTitle,
               last.documentKey == documentKey,
               timestamp.timeIntervalSince(last.timestamp) <= usageTimelineMergeWindow {
                day.timelineEntries[lastIndex].timestamp = timestamp
                day.timelineEntries[lastIndex].durationSeconds += durationSeconds
                return
            }
        }

        day.timelineEntries.append(
            UsageTimelineEntry(
                timestamp: timestamp,
                kind: kind,
                title: cleanedTitle,
                documentKey: documentKey,
                durationSeconds: durationSeconds
            )
        )

        if day.timelineEntries.count > maxUsageTimelineEntriesPerDay {
            day.timelineEntries.removeFirst(day.timelineEntries.count - maxUsageTimelineEntriesPerDay)
        }
    }

    private func recordUsageEvent(
        _ counter: WritableKeyPath<DailyUsageStats, Int>,
        documentKey: String,
        timelineKind: UsageTimelineEntry.Kind? = nil,
        timelineTitle: String? = nil,
        durationSeconds: Int = 0,
        now: Date = Date()
    ) {
        mutateTodayUsageStats(now: now, documentKey: documentKey) { day in
            day[keyPath: counter] += 1
            if let timelineKind, let timelineTitle {
                Self.appendUsageTimelineEntry(
                    kind: timelineKind,
                    title: timelineTitle,
                    documentKey: documentKey,
                    durationSeconds: durationSeconds,
                    timestamp: now,
                    to: &day
                )
            }
        }
    }

    private func recordUsageTimelineActivity(
        kind: UsageTimelineEntry.Kind,
        title: String,
        documentKey: String,
        durationSeconds: Int = 0,
        countsAsDocument: Bool = false,
        now: Date = Date()
    ) {
        mutateTodayUsageStats(
            now: now,
            documentKey: countsAsDocument ? documentKey : nil
        ) { day in
            Self.appendUsageTimelineEntry(
                kind: kind,
                title: title,
                documentKey: documentKey,
                durationSeconds: durationSeconds,
                timestamp: now,
                to: &day
            )
        }
    }

    private func mutateTodayUsageStats(
        now: Date,
        documentKey: String?,
        mutate: (inout DailyUsageStats) -> Void
    ) {
        let dayID = UsageStatsClock.dayIdentifier(for: now)
        let index = usageStats.firstIndex { $0.day == dayID }
        let targetIndex: Int
        if let index {
            targetIndex = index
        } else {
            usageStats.append(.empty(day: dayID))
            targetIndex = usageStats.count - 1
        }

        if let documentKey {
            usageStats[targetIndex].uniqueDocumentKeys.insert(documentKey)
        }
        mutate(&usageStats[targetIndex])
        persistUsageStatsSoon()
    }

    private func persistUsageStats() {
        pendingUsageStatsSaveTask?.cancel()
        pendingUsageStatsSaveTask = nil
        guard let usageStatsPersistence else { return }

        do {
            try usageStatsPersistence.save(usageStats)
        } catch {
            lastError = "Could not persist usage stats: \(error.localizedDescription)"
        }
    }

    private func persistUsageStatsSoon() {
        pendingUsageStatsSaveTask?.cancel()

        pendingUsageStatsSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                self?.persistUsageStats()
            }
        }
    }

    private func installOpenCommentObserver() {
        openCommentObserver = NotificationCenter.default.addObserver(
            forName: .simpleLimeOpenComment,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let commentID = notification.userInfo?["commentID"] as? UUID else { return }
            Task { @MainActor in
                self?.jumpToComment(commentID)
            }
        }
    }

    func showFind() {
        findPanelMode = .find
    }

    func showReplace() {
        findPanelMode = .replace
    }

    func showGlobalFind() {
        findPanelMode = .global
    }

    func hideFindPanel() {
        findPanelMode = .hidden
    }

    func escape() {
        if findPanelMode != .hidden {
            hideFindPanel()
        } else {
            clearAdditionalCursors()
        }
    }

    func increaseFontSize() {
        fontSize = min(32, fontSize + 1)
    }

    func decreaseFontSize() {
        fontSize = max(10, fontSize - 1)
    }

    func toggleWrapLines() {
        wrapsLines.toggle()
    }

    func toggleRenderedPreview() {
        if isPreviewVisible {
            showSourceMode()
        } else {
            showRenderedPreviewMode()
        }
    }

    func toggleMarkdownPreview() {
        toggleRenderedPreview()
    }

    func toggleMarkdownOutline() {
        if isOutlineVisible {
            isOutlineVisible = false
        } else {
            isOutlineVisible = true
            isDocumentCatalogVisible = false
        }
    }

    func toggleFocusMode() {
        guard !selectedBufferIsLargeFileMode else {
            lastError = "Large-file mode keeps focus mode disabled for performance."
            return
        }

        if isWysiwygModeEnabled {
            isWysiwygModeEnabled = false
        }
        isFocusModeEnabled.toggle()
    }

    func toggleTypewriterMode() {
        isTypewriterModeEnabled.toggle()
    }

    func toggleMiniMap() {
        let telemetry = EditorPerformanceTelemetry.begin("EditorToggleMiniMap")
        defer { EditorPerformanceTelemetry.end("EditorToggleMiniMap", telemetry) }

        guard !selectedBufferIsLargeFileMode else {
            lastError = "Large-file mode keeps the minimap disabled for performance."
            return
        }

        if isWysiwygModeEnabled {
            isWysiwygModeEnabled = false
        }
        isMiniMapVisible.toggle()
        EditorPerformanceTelemetry.logger.info("Toggle minimap visible=\(self.isMiniMapVisible, privacy: .public)")
    }

    func toggleWysiwygMode() {
        if isWysiwygModeEnabled {
            showSourceMode()
        } else {
            showMarkdownWysiwygMode()
        }
    }

    func showSourceMode() {
        isPreviewVisible = false
        isWysiwygModeEnabled = false
    }

    func showRenderedPreviewMode() {
        guard !selectedBufferIsLargeFileMode || selectedBuffer?.language.isDelimitedTable == true else {
            lastError = "Large-file mode keeps rendered previews disabled for performance."
            return
        }

        isPreviewVisible = true
        isWysiwygModeEnabled = false
    }

    func showMarkdownPreviewMode() {
        showRenderedPreviewMode()
    }

    func showDelimitedTablePreviewMode() {
        showRenderedPreviewMode()
    }

    func showMarkdownWysiwygMode() {
        guard !selectedBufferIsLargeFileMode else {
            lastError = "Large-file mode keeps WYSIWYG disabled for performance."
            return
        }

        isPreviewVisible = false
        isWysiwygModeEnabled = true
        isMiniMapVisible = false
        isFocusModeEnabled = false
    }

    private func normalizeLoadedEditorModeState() {
        guard isWysiwygModeEnabled else { return }

        isPreviewVisible = false
        if isMiniMapVisible {
            isMiniMapVisible = false
            UserDefaults.standard.set(false, forKey: Self.miniMapDefaultsKey)
        }
        if isFocusModeEnabled {
            isFocusModeEnabled = false
            UserDefaults.standard.set(false, forKey: Self.focusModeDefaultsKey)
        }
    }

    func showCommandPalette() {
        findPanelMode = .hidden
        isCommandPaletteVisible = true
    }

    func hideCommandPalette() {
        isCommandPaletteVisible = false
    }

    func toggleCommandPalette() {
        if isCommandPaletteVisible {
            hideCommandPalette()
        } else {
            showCommandPalette()
        }
    }

    func jumpToHeading(_ heading: MarkdownHeading) {
        guard let selectedIndex else { return }

        buffers[selectedIndex].selectionRanges = [TextRange(location: heading.location, length: 0)]
        persistSoon()
    }

    func jumpToLine(_ lineNumber: Int) {
        guard let selectedIndex else { return }

        if buffers[selectedIndex].isLargeFileMode {
            jumpSelectedLargeFileToLine(lineNumber)
            return
        }

        let lineNumber = max(1, lineNumber)
        let nsText = buffers[selectedIndex].text as NSString
        var currentLine = 1
        var location = 0

        while location < nsText.length, currentLine < lineNumber {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let nextLocation = lineRange.location + max(lineRange.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
            currentLine += 1
        }

        buffers[selectedIndex].selectionRanges = [TextRange(location: min(location, nsText.length), length: 0)]
        persistSoon()
    }

    func findNext() {
        if findQuery.isEmpty {
            showFind()
            return
        }

        find(direction: .next)
    }

    func findPrevious() {
        if findQuery.isEmpty {
            showFind()
            return
        }

        find(direction: .previous)
    }

    func replaceCurrent() {
        guard let selectedIndex,
              !findQuery.isEmpty else {
            return
        }

        let buffer = buffers[selectedIndex]
        guard let selected = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text).first else {
            findNext()
            return
        }

        guard let match = firstMatch(in: buffer.text, range: selected.nsRange),
              match.range.location == selected.location,
              match.range.length == selected.length else {
            findNext()
            return
        }

        let replacement = replacementString(for: match, in: buffer.text)
        replaceRanges([selected]) { _ in replacement }
    }

    func replaceAll() {
        guard let selectedIndex,
              !findQuery.isEmpty else {
            return
        }

        let buffer = buffers[selectedIndex]
        guard let replacement = replacingAllMatches(in: buffer.text) else { return }

        buffers[selectedIndex].text = replacement.text
        buffers[selectedIndex].isDirty = true
        buffers[selectedIndex].updatedAt = Date()
        buffers[selectedIndex].selectionRanges = [replacement.firstSelection]
        reanchorComments(for: buffers[selectedIndex], newText: replacement.text)
        persistSoon()
    }

    @discardableResult
    func replaceAllGlobalMatches() -> Int {
        guard !findQuery.isEmpty else {
            showGlobalFind()
            return 0
        }

        if let findValidationError {
            globalReplaceStatusText = findValidationError
            return 0
        }

        var replacementCount = 0
        var changedDocumentCount = 0
        var firstOpenChange: (index: Int, selection: TextRange)?
        var openFileIdentities = Set<String>()

        for index in buffers.indices {
            if let path = buffers[index].filePath {
                openFileIdentities.insert(fileIdentity(forPath: path))
            }

            guard let replacement = replacingAllMatches(in: buffers[index].text) else {
                continue
            }

            buffers[index].text = replacement.text
            buffers[index].isDirty = true
            buffers[index].updatedAt = Date()
            buffers[index].selectionRanges = [replacement.firstSelection]
            reanchorComments(for: buffers[index], newText: replacement.text)
            replacementCount += replacement.count
            changedDocumentCount += 1

            if firstOpenChange == nil {
                firstOpenChange = (index, replacement.firstSelection)
            }
        }

        var failedNames: [String] = []

        for node in documentCatalogFileNodes(documentCatalogNodes) {
            let identity = fileIdentity(forURL: node.url)
            guard !openFileIdentities.contains(identity) else { continue }

            do {
                var encoding = String.Encoding.utf8
                let text = try String(contentsOf: node.url, usedEncoding: &encoding)
                guard let replacement = replacingAllMatches(in: text) else {
                    continue
                }

                try replacement.text.write(to: node.url, atomically: true, encoding: encoding)
                replacementCount += replacement.count
                changedDocumentCount += 1
            } catch {
                failedNames.append(node.name)
            }
        }

        if let firstOpenChange {
            selectedBufferID = buffers[firstOpenChange.index].id
            buffers[firstOpenChange.index].selectionRanges = [firstOpenChange.selection]
        }

        if replacementCount > 0 {
            persistSoon()
        }

        globalReplaceStatusText = replacementCount == 0
            ? "No replacements"
            : "Replaced \(replacementCount) \(replacementCount == 1 ? "match" : "matches") in \(changedDocumentCount) \(changedDocumentCount == 1 ? "document" : "documents")"

        if !failedNames.isEmpty {
            lastError = "Could not replace in \(failedNames.prefix(3).joined(separator: ", "))"
        }

        return replacementCount
    }

    func addNextOccurrence() {
        addOccurrence(direction: .next)
    }

    func addPreviousOccurrence() {
        addOccurrence(direction: .previous)
    }

    private func addOccurrence(direction: FindDirection) {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let selections = normalizedRanges(buffer.selectionRanges, in: buffer.text)
        let primarySelection = selections.first(where: { $0.length > 0 })

        let query: String
        if let primarySelection {
            query = nsText.substring(with: primarySelection.nsRange)
        } else if !findQuery.isEmpty {
            query = findQuery
        } else if let word = wordRange(at: selections.first?.location ?? 0, in: nsText) {
            buffers[selectedIndex].selectionRanges = [word]
            persistSoon()
            return
        } else {
            return
        }

        guard !query.isEmpty else { return }

        let start: Int
        switch direction {
        case .next:
            start = selections.map { $0.location + $0.length }.max() ?? 0
        case .previous:
            start = selections.map(\.location).min() ?? 0
        }

        if let occurrence = findRange(query: query, in: buffer.text, from: start, direction: direction, forceLiteral: true),
           !selections.contains(occurrence) {
            let updated = (selections + [occurrence]).sorted { first, second in
                first.location == second.location ? first.length < second.length : first.location < second.location
            }
            buffers[selectedIndex].selectionRanges = updated
            persistSoon()
        }
    }

    private func wordRange(at location: Int, in nsText: NSString) -> TextRange? {
        guard nsText.length > 0 else { return nil }

        let characterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < nsText.length,
                  let scalar = UnicodeScalar(nsText.character(at: index)) else {
                return false
            }
            return characterSet.contains(scalar)
        }

        var index = min(max(0, location), nsText.length - 1)
        if !isWordCharacter(index) {
            if location > 0, isWordCharacter(location - 1) {
                index = location - 1
            } else {
                return nil
            }
        }

        var start = index
        while start > 0, isWordCharacter(start - 1) {
            start -= 1
        }

        var end = index + 1
        while end < nsText.length, isWordCharacter(end) {
            end += 1
        }

        guard end > start else { return nil }
        return TextRange(location: start, length: end - start)
    }

    func clearAdditionalCursors() {
        guard let selectedIndex else { return }
        let first = buffers[selectedIndex].selectionRanges.first ?? .zero
        buffers[selectedIndex].selectionRanges = [first]
        persistSoon()
    }

    func selectSearchResult(_ result: SearchResult) {
        if let bufferID = result.bufferID {
            selectedBufferID = bufferID

            if let index = buffers.firstIndex(where: { $0.id == bufferID }) {
                buffers[index].selectionRanges = [result.range]
                persistSoon()
            }
            return
        }

        guard let filePath = result.filePath else { return }
        if let index = buffers.firstIndex(where: { $0.filePath == filePath }) {
            selectedBufferID = buffers[index].id
            buffers[index].selectionRanges = [result.range]
            persistSoon()
            return
        }

        do {
            let url = URL(fileURLWithPath: filePath)
            var encoding = String.Encoding.utf8
            let text = try String(contentsOf: url, usedEncoding: &encoding)
            let now = Date()
            let buffer = EditorBuffer(
                id: UUID(),
                title: url.lastPathComponent,
                kind: .file,
                filePath: filePath,
                text: text,
                language: EditorLanguage.detect(fileName: url.lastPathComponent, text: text),
                createdAt: now,
                updatedAt: now,
                isDirty: false,
                selectionRanges: [result.range]
            )
            buffers.append(buffer)
            selectedBufferID = buffer.id
            persistSoon()
        } catch {
            lastError = "Could not open \(URL(fileURLWithPath: filePath).lastPathComponent): \(error.localizedDescription)"
        }
    }

    func selectAllMatches() {
        guard let selectedIndex,
              !findQuery.isEmpty else {
            showFind()
            return
        }

        let ranges = allMatches(in: buffers[selectedIndex].text).map { TextRange($0.range) }
        guard !ranges.isEmpty else { return }
        buffers[selectedIndex].selectionRanges = ranges
        persistSoon()
    }

    func performTextTransform(_ transform: TextTransform) {
        performActionMacroStep(.transform(transform), recordsWhenCapturing: true) {
            if editorCommandHandler?(.transform(transform)) == true {
                return
            }

            transformSelection(transform)
        }
    }

    func performEditorCommand(_ command: EditorCommand) {
        performActionMacroStep(.editor(command), recordsWhenCapturing: true) {
            if editorCommandHandler?(command) == true {
                return
            }

            performEditorCommandFallback(command)
        }
    }

    func performMarkdownCommand(_ command: MarkdownCommand) {
        performActionMacroStep(.markdown(command), recordsWhenCapturing: true) {
            if editorCommandHandler?(.markdown(command)) == true {
                return
            }

            performMarkdownCommandFallback(command)
        }
    }

    func transformSelection(_ transform: TextTransform) {
        switch transform {
        case .uppercase:
            replaceTargetText { $0.uppercased() }
        case .lowercase:
            replaceTargetText { $0.lowercased() }
        case .titlecase:
            replaceTargetText { $0.capitalized }
        case .swapCase:
            replaceTargetText { $0.swappingCase() }
        case .reverseSelection:
            replaceTargetText { String($0.reversed()) }
        case .sortLines:
            replaceTargetLines { text in
                preserveTrailingNewline(text) { lines in
                    lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }
            }
        case .uniqueLines:
            replaceTargetLines { text in
                preserveTrailingNewline(text) { lines in
                    var seen = Set<String>()
                    return lines.filter { seen.insert($0).inserted }
                }
            }
        case .trimTrailingWhitespace:
            replaceTargetLines { text in
                text.components(separatedBy: .newlines)
                    .map { $0.trimmingTrailingWhitespace() }
                    .joined(separator: "\n")
            }
        case .duplicateLine:
            duplicateSelectedLinesOrCurrentLine()
        case .joinLines:
            replaceTargetLines { text in
                text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
        case .formatJSON:
            formatJSONSelection(prettyPrinted: true)
        case .minifyJSON:
            formatJSONSelection(prettyPrinted: false)
        case .formatMarkdownTables:
            replaceTargetLines { MarkdownTableFormatter.format($0) }
        }
    }

    private var shouldCaptureActionMacroStep: Bool {
        actionMacroRecording != nil && actionMacroPlaybackDepth == 0
    }

    private var shouldCaptureRawActionMacroEdit: Bool {
        shouldCaptureActionMacroStep && actionMacroCommandDepth == 0
    }

    private func performActionMacroStep(
        _ step: ActionMacroStep,
        recordsWhenCapturing: Bool,
        perform: () -> Void
    ) {
        guard recordsWhenCapturing, shouldCaptureActionMacroStep else {
            perform()
            return
        }

        appendActionMacroStep(step)
        actionMacroCommandDepth += 1
        defer { actionMacroCommandDepth -= 1 }
        perform()
    }

    private func applyActionMacroStep(_ step: ActionMacroStep) {
        switch step {
        case .select(let ranges):
            guard let buffer = selectedBuffer else { return }
            updateSelection(normalizedRanges(ranges, in: buffer.text), in: buffer.id)
        case .replaceSelection(let text):
            insertTextAtSelections(text)
        case .deleteBackward(let count):
            deleteCharactersAroundSelections(count: count, direction: .backward)
        case .deleteForward(let count):
            deleteCharactersAroundSelections(count: count, direction: .forward)
        case .transform(let transform):
            performTextTransform(transform)
        case .markdown(let command):
            performMarkdownCommand(command)
        case .editor(let command):
            performEditorCommand(command)
        }
    }

    private func appendActionMacroStep(_ step: ActionMacroStep) {
        guard var recording = actionMacroRecording else { return }

        if case .select = step,
           case .select = recording.steps.last {
            recording.steps[recording.steps.count - 1] = step
        } else if case .replaceSelection(let text) = step,
                  case .replaceSelection(let previousText) = recording.steps.last,
                  !text.isEmpty,
                  !previousText.isEmpty {
            recording.steps[recording.steps.count - 1] = .replaceSelection(previousText + text)
        } else {
            recording.steps.append(step)
        }

        actionMacroRecording = recording
    }

    private func recordActionMacroTextEditIfNeeded(
        oldText: String,
        newText: String,
        oldSelectionRanges: [TextRange]
    ) {
        guard shouldCaptureRawActionMacroEdit,
              let step = actionMacroStepForTextEdit(
                oldText: oldText,
                newText: newText,
                oldSelectionRanges: oldSelectionRanges
              ) else {
            return
        }

        appendActionMacroStep(step)
    }

    private func actionMacroStepForTextEdit(
        oldText: String,
        newText: String,
        oldSelectionRanges: [TextRange]
    ) -> ActionMacroStep? {
        guard oldText != newText else { return nil }

        if let multiSelectionStep = actionMacroStepForMultiSelectionTextEdit(
            oldText: oldText,
            newText: newText,
            oldSelectionRanges: oldSelectionRanges
        ) {
            return multiSelectionStep
        }

        let oldNSString = oldText as NSString
        let newNSString = newText as NSString
        let oldLength = oldNSString.length
        let newLength = newNSString.length
        let sharedLimit = min(oldLength, newLength)
        var prefix = 0

        while prefix < sharedLimit,
              oldNSString.character(at: prefix) == newNSString.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        while suffix < oldLength - prefix,
              suffix < newLength - prefix,
              oldNSString.character(at: oldLength - suffix - 1) == newNSString.character(at: newLength - suffix - 1) {
            suffix += 1
        }

        let removedLength = oldLength - prefix - suffix
        let insertedLength = newLength - prefix - suffix
        let insertedText = insertedLength > 0
            ? newNSString.substring(with: NSRange(location: prefix, length: insertedLength))
            : ""
        let primarySelection = normalizedRanges(oldSelectionRanges, in: oldText).first ?? .zero

        if insertedText.isEmpty, removedLength > 0 {
            if primarySelection.length > 0 {
                return .replaceSelection("")
            }
            if prefix + removedLength == primarySelection.location {
                return .deleteBackward(removedLength)
            }
            if prefix == primarySelection.location {
                return .deleteForward(removedLength)
            }
            return nil
        }

        if !insertedText.isEmpty {
            return .replaceSelection(insertedText)
        }

        return nil
    }

    private func actionMacroStepForMultiSelectionTextEdit(
        oldText: String,
        newText: String,
        oldSelectionRanges: [TextRange]
    ) -> ActionMacroStep? {
        let oldNSString = oldText as NSString
        let newNSString = newText as NSString
        let oldLength = oldNSString.length
        let newLength = newNSString.length
        let ranges = normalizedRanges(oldSelectionRanges, in: oldText)
            .sorted { lhs, rhs in
                if lhs.location == rhs.location {
                    return lhs.length < rhs.length
                }
                return lhs.location < rhs.location
            }
        guard ranges.count > 1 else { return nil }

        var previousEnd = 0
        var removedLength = 0
        for range in ranges {
            guard range.location >= previousEnd else { return nil }
            previousEnd = range.location + range.length
            removedLength += range.length
        }

        let replacementDelta = newLength - oldLength + removedLength
        guard replacementDelta >= 0, replacementDelta % ranges.count == 0 else { return nil }
        let replacementLength = replacementDelta / ranges.count
        guard replacementLength > 0 || ranges.contains(where: { $0.length > 0 }) else { return nil }

        var oldCursor = 0
        var newCursor = 0
        var replacement: String?

        for range in ranges {
            let unchangedLength = range.location - oldCursor
            guard unchangedLength >= 0,
                  newCursor + unchangedLength <= newLength,
                  oldNSString.substring(with: NSRange(location: oldCursor, length: unchangedLength)) ==
                    newNSString.substring(with: NSRange(location: newCursor, length: unchangedLength)) else {
                return nil
            }

            oldCursor += unchangedLength + range.length
            newCursor += unchangedLength

            guard newCursor + replacementLength <= newLength else { return nil }
            let currentReplacement = newNSString.substring(
                with: NSRange(location: newCursor, length: replacementLength)
            )
            if let replacement, replacement != currentReplacement {
                return nil
            }
            replacement = currentReplacement
            newCursor += replacementLength
        }

        guard oldNSString.substring(from: oldCursor) == newNSString.substring(from: newCursor) else {
            return nil
        }

        return .replaceSelection(replacement ?? "")
    }

    private enum ActionMacroDeleteDirection {
        case backward
        case forward
    }

    private func deleteCharactersAroundSelections(count: Int, direction: ActionMacroDeleteDirection) {
        guard count > 0,
              let selectedIndex else {
            return
        }

        let bufferID = buffers[selectedIndex].id
        let text = buffers[selectedIndex].text
        let nsText = text as NSString
        let ranges = normalizedRanges(buffers[selectedIndex].selectionRanges, in: text)
        let deletionRanges = ranges.compactMap { range -> TextRange? in
            if range.length > 0 {
                return range
            }

            switch direction {
            case .backward:
                let location = max(0, range.location - count)
                let length = range.location - location
                return length > 0 ? TextRange(location: location, length: length) : nil
            case .forward:
                let length = min(count, nsText.length - range.location)
                return length > 0 ? TextRange(location: range.location, length: length) : nil
            }
        }

        guard !deletionRanges.isEmpty else { return }

        let mutable = NSMutableString(string: text)
        var newSelections: [TextRange] = []
        for range in deletionRanges.sorted(by: { $0.location > $1.location }) {
            mutable.replaceCharacters(in: range.nsRange, with: "")
            newSelections.append(TextRange(location: range.location, length: 0))
        }

        updateText(mutable as String, in: bufferID)
        guard let updatedIndex = buffers.firstIndex(where: { $0.id == bufferID }) else { return }
        buffers[updatedIndex].selectionRanges = newSelections.reversed()
        buffers[updatedIndex].updatedAt = Date()
        persistSoon()
    }

    private func runAIPrompt(bufferID: UUID, chatID: UUID, userText: String) async {
        do {
            guard let buffer = buffers.first(where: { $0.id == bufferID }),
                  let chatLocation = aiChatLocation(chatID) else {
                finishAIChat(chatID, status: "Chat is no longer available.")
                return
            }

            let session = buffers[chatLocation.bufferIndex].aiSessions[chatLocation.sessionIndex]
            if !session.provider.usesACP {
                try await runHTTPAIPrompt(buffer: buffer, chatID: chatID, session: session)
                return
            }

            try aiFileBridge.mirror(buffer)

            let hadClient = aiClients[chatID] != nil
            let client = configuredAIClient(for: session, buffer: buffer)
            let agentSessionID: String

            if let existingAgentSessionID = buffers[chatLocation.bufferIndex].aiSessions[chatLocation.sessionIndex].agentSessionID,
               hadClient {
                agentSessionID = existingAgentSessionID
            } else {
                aiChatIDsByAgentSession = aiChatIDsByAgentSession.filter { $0.value != chatID }
                agentSessionID = try await client.newSession(cwd: aiWorkingDirectory(for: buffer).path)
                if let updatedLocation = aiChatLocation(chatID) {
                    buffers[updatedLocation.bufferIndex].aiSessions[updatedLocation.sessionIndex].agentSessionID = agentSessionID
                    buffers[updatedLocation.bufferIndex].aiSessions[updatedLocation.sessionIndex].updatedAt = Date()
                    persistSoon()
                }
                aiChatIDsByAgentSession[agentSessionID] = chatID
            }

            let editableURL = aiFileBridge.editableURL(for: buffer)
            let prompt = aiPromptBlocks(userText: userText, buffer: buffer, editableURL: editableURL, client: client)
            let stopReason = try await client.prompt(sessionID: agentSessionID, prompt: prompt)
            let didApplyEdits = applyAIMirroredFileIfNeeded(bufferID: bufferID, chatID: chatID)
            aiStreamingMessageIDs.removeValue(forKey: chatID)
            let status = didApplyEdits
                ? "Applied edits to the current tab"
                : (stopReason == "end_turn" ? "Done" : "Stopped: \(stopReason)")
            finishAIChat(chatID, status: status)
        } catch {
            if Task.isCancelled {
                finishAIChat(chatID, status: "Cancelled")
                return
            }
            appendAISystemMessage("AI error: \(error.localizedDescription)", to: chatID)
            finishAIChat(chatID, status: "Failed")
        }
    }

    private func runHTTPAIPrompt(buffer: EditorBuffer, chatID: UUID, session: AIChatSession) async throws {
        aiSessionStatuses[chatID] = "Sending request..."
        let configuration = try HTTPAIConfiguration.current(provider: session.provider.httpProvider ?? .openAICompatible)
        let client = httpAIClientFactory(configuration)
        let response = try await client.complete(
            messages: httpAIMessages(for: session),
            systemPrompt: httpAISystemPrompt(for: buffer)
        )

        try Task.checkCancellation()
        appendAIAssistantMessage(response, to: chatID)
        finishAIChat(chatID, status: "Done")
    }

    private func configuredAIClient(for session: AIChatSession, buffer: EditorBuffer) -> ACPAgentClient {
        if let client = aiClients[session.id] {
            return client
        }

        let executable = configuredExecutable(for: session.provider)
        let arguments = ShellArguments.split(configuredArguments(for: session.provider))
        let client = ACPAgentClient(
            provider: session.provider,
            executable: executable,
            arguments: arguments,
            workingDirectory: aiWorkingDirectory(for: buffer)
        )

        client.onAssistantText = { [weak self] agentSessionID, text in
            Task { @MainActor in
                self?.appendAIAssistantText(text, agentSessionID: agentSessionID)
            }
        }

        client.onStatus = { [weak self] agentSessionID, status in
            Task { @MainActor in
                self?.updateAIStatus(status, agentSessionID: agentSessionID, fallbackChatID: session.id)
            }
        }

        client.onReadTextFile = { [weak self] path, line, limit in
            await MainActor.run {
                self?.readAITextFile(path: path, line: line, limit: limit)
            }
        }

        client.onWriteTextFile = { [weak self] path, content in
            await MainActor.run {
                self?.writeAITextFile(path: path, content: content) ?? false
            }
        }

        aiClients[session.id] = client
        return client
    }

    private func aiPromptBlocks(userText: String, buffer: EditorBuffer, editableURL: URL, client: ACPAgentClient) -> [ACPJSON] {
        let path = editableURL.path
        let originalPath = buffer.filePath ?? "Scratch buffer, not saved to disk"
        let instruction = """
        You are assisting inside SimpleLime, a macOS text editor.
        The current open buffer has been mirrored into a temporary editable file.
        Editable buffer path: \(path)
        Original document path: \(originalPath)
        Language: \(buffer.language.displayName)

        To change the editor text, rewrite the full corrected content into the editable buffer path above. You may use fs/write_text_file if available. If your environment exposes shell/file tools instead, modify only that editable buffer file. Do not edit the original document path directly and do not edit unrelated files.
        If the user asks to check grammar, punctuation, wording, or rewrite text, apply the corrected version to the editable buffer file instead of only describing the fixes.

        User task:
        \(userText)
        """

        var blocks: [ACPJSON] = [
            [
                "type": "text",
                "text": instruction
            ]
        ]

        if client.supportsEmbeddedContext {
            blocks.append([
                "type": "resource",
                "resource": [
                    "uri": editableURL.absoluteString,
                    "mimeType": aiFileBridge.mimeType(for: buffer),
                    "text": buffer.text
                ]
            ])
        } else {
            blocks.append([
                "type": "resource_link",
                "uri": editableURL.absoluteString,
                "name": buffer.displayTitle,
                "title": buffer.displayTitle,
                "mimeType": aiFileBridge.mimeType(for: buffer),
                "size": buffer.text.utf8.count
            ])
        }

        return blocks
    }

    private func appendAIAssistantText(_ text: String, agentSessionID: String) {
        guard !text.isEmpty,
              let chatID = aiChatIDsByAgentSession[agentSessionID],
              let location = aiChatLocation(chatID) else {
            return
        }

        if let messageID = aiStreamingMessageIDs[chatID],
           let messageIndex = buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.firstIndex(where: { $0.id == messageID }) {
            buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages[messageIndex].text += text
        } else {
            let message = AIChatMessage.assistant(text)
            buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.append(message)
            aiStreamingMessageIDs[chatID] = message.id
        }

        buffers[location.bufferIndex].aiSessions[location.sessionIndex].updatedAt = Date()
        persistSoon()
    }

    private func appendAISystemMessage(_ text: String, to chatID: UUID) {
        guard let location = aiChatLocation(chatID) else { return }
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.append(.system(text))
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].updatedAt = Date()
        persistSoon()
    }

    private func appendAIAssistantMessage(_ text: String, to chatID: UUID) {
        guard let location = aiChatLocation(chatID) else { return }
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].messages.append(.assistant(text))
        buffers[location.bufferIndex].aiSessions[location.sessionIndex].updatedAt = Date()
        persistSoon()
    }

    private func httpAIMessages(for session: AIChatSession) -> [HTTPAIChatMessage] {
        session.messages.compactMap { message in
            switch message.role {
            case .user:
                HTTPAIChatMessage(role: "user", content: message.text)
            case .assistant:
                HTTPAIChatMessage(role: "assistant", content: message.text)
            case .system:
                nil
            }
        }
    }

    private func httpAISystemPrompt(for buffer: EditorBuffer) -> String {
        let originalPath = buffer.filePath ?? "Scratch buffer, not saved to disk"
        let context = truncatedHTTPAIContext(buffer.text)
        return """
        You are assisting inside SimpleLime, a macOS text editor.
        The user is working in the current editor tab.
        You can explain, analyze, rewrite, draft, translate, and suggest concrete edits.
        This HTTP provider does not expose editor file tools yet. If the user asks for edits, return a clear replacement, patch, or exact instructions that can be applied in the editor.

        Current tab:
        Title: \(buffer.displayTitle)
        Original document path: \(originalPath)
        Language: \(buffer.language.displayName)

        Current document text:
        \(context)
        """
    }

    private func truncatedHTTPAIContext(_ text: String) -> String {
        let limit = 120_000
        guard text.count > limit else { return text }

        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<endIndex])
            + "\n\n[SimpleLime truncated the current document context after \(limit) characters.]"
    }

    private func updateAIStatus(_ status: String, agentSessionID: String, fallbackChatID: UUID) {
        let chatID = aiChatIDsByAgentSession[agentSessionID] ?? fallbackChatID
        guard aiChatLocation(chatID) != nil else { return }
        aiSessionStatuses[chatID] = status
    }

    private func finishAIChat(_ chatID: UUID, status: String) {
        aiRunningSessions.remove(chatID)
        aiHTTPTasks.removeValue(forKey: chatID)
        aiSessionStatuses[chatID] = status
        persistSoon()
    }

    private func readAITextFile(path: String, line: Int?, limit: Int?) -> String? {
        guard let index = bufferIndexForAIPath(path) else { return nil }
        return slicedText(buffers[index].text, line: line, limit: limit)
    }

    private func writeAITextFile(path: String, content: String) -> Bool {
        guard let index = bufferIndexForAIPath(path) else { return false }

        buffers[index].text = content
        buffers[index].updatedAt = Date()
        buffers[index].isDirty = buffers[index].kind == .scratch ? !content.isEmpty : true
        reanchorComments(for: buffers[index], newText: content)

        try? aiFileBridge.mirror(buffers[index])

        persistSoon()
        return true
    }

    @discardableResult
    private func applyAIMirroredFileIfNeeded(bufferID: UUID, chatID: UUID) -> Bool {
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }),
              let mirroredText = aiFileBridge.readMirroredText(for: buffers[index]),
              mirroredText != buffers[index].text else {
            return false
        }

        buffers[index].text = mirroredText
        buffers[index].updatedAt = Date()
        buffers[index].isDirty = buffers[index].kind == .scratch ? !mirroredText.isEmpty : true
        reanchorComments(for: buffers[index], newText: mirroredText)
        aiSessionStatuses[chatID] = "Applied edits to the current tab"
        persistSoon()
        return true
    }

    private func bufferIndexForAIPath(_ path: String) -> Int? {
        let normalizedPath = normalizedPath(path)

        for index in buffers.indices {
            if aiFileBridge.editableURL(for: buffers[index]).path == normalizedPath {
                return index
            }

            if let filePath = buffers[index].filePath,
               URL(fileURLWithPath: filePath, isDirectory: false).standardizedFileURL.path == normalizedPath {
                return index
            }
        }

        return nil
    }

    private func normalizedPath(_ path: String) -> String {
        if path.hasPrefix("file://"),
           let url = URL(string: path) {
            return url.standardizedFileURL.path
        }

        return URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL.path
    }

    private static func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func slicedText(_ text: String, line: Int?, limit: Int?) -> String {
        guard line != nil || limit != nil else {
            return text
        }

        let lines = text.components(separatedBy: "\n")
        let start = min(max(0, (line ?? 1) - 1), lines.count)
        guard start < lines.count else { return "" }

        if let limit {
            let end = min(lines.count, start + max(0, limit))
            return lines[start..<end].joined(separator: "\n")
        }

        return lines[start...].joined(separator: "\n")
    }

    func companionSuggestions(for bufferID: UUID) -> [CompanionSuggestion] {
        companionSuggestionsByBufferID[bufferID] ?? []
    }

    func replaceCompanionSuggestions(_ suggestions: [CompanionSuggestion], for bufferID: UUID? = nil) {
        guard let bufferID = bufferID ?? selectedBufferID else { return }
        companionSuggestionsByBufferID[bufferID] = suggestions
    }

    private var shouldMonitorCompanionSystemContext: Bool {
        isUsageActivityWatchEnabled ||
            (isCompanionAutoScanEnabled && companionIncludesSystemContextProvider())
    }

    private func startCompanionSystemContextMonitoring() {
        guard shouldMonitorCompanionSystemContext else {
            stopCompanionSystemContextMonitoring()
            return
        }

        guard companionSystemContextMonitorTask == nil else { return }

        companionSystemContextMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                do {
                    await self?.handleCompanionSystemContextPoll()
                    let interval = await MainActor.run {
                        self?.companionSystemContextPollIntervalNanoseconds
                    }
                    guard let interval else { return }
                    if interval > 0 {
                        try await Task.sleep(nanoseconds: interval)
                    } else {
                        await Task.yield()
                    }
                    try Task.checkCancellation()
                } catch {
                    await MainActor.run {
                        self?.companionSystemContextMonitorTask = nil
                    }
                    return
                }
            }
        }
    }

    private func stopCompanionSystemContextMonitoring() {
        companionSystemContextMonitorTask?.cancel()
        companionSystemContextMonitorTask = nil
        lastCompanionSystemContextSignature = nil
        finalizeCompanionUsageActivityTracking()
    }

    private func handleCompanionSystemContextPoll() async {
        guard shouldMonitorCompanionSystemContext else {
            stopCompanionSystemContextMonitoring()
            return
        }

        let context = await companionSystemContextProvider()
        recordCompanionSystemActivity(context)

        guard isCompanionAutoScanEnabled,
              companionIncludesSystemContextProvider() else {
            lastCompanionSystemContextSignature = nil
            return
        }

        let signature = context.map(companionSystemContextSignature)
        guard signature != lastCompanionSystemContextSignature else { return }
        lastCompanionSystemContextSignature = signature
        scheduleCompanionAutoScanIfNeeded(for: selectedBufferID)
    }

    private func companionSystemContextSignature(_ context: CompanionSystemContext) -> String {
        [
            context.frontmostApplicationName,
            context.frontmostBundleIdentifier ?? "",
            context.frontmostWindowTitle ?? "",
            context.focusedElementRole ?? "",
            context.focusedElementTitle ?? "",
            context.selectedText ?? "",
            context.focusedValue ?? "",
            context.screenText ?? ""
        ].joined(separator: "\u{1F}")
    }

    private func recordCompanionSystemActivity(_ context: CompanionSystemContext?, now: Date = Date()) {
        guard let context,
              !context.frontmostApplicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finalizeCompanionUsageActivityTracking(now: now)
            return
        }

        let signature = companionUsageActivitySignature(context)
        let title = companionUsageActivityTitle(context)
        let documentKey = companionUsageActivityDocumentKey(context)

        guard lastCompanionUsageActivitySignature != signature else { return }

        finalizeCompanionUsageActivityTracking(now: now)

        recordUsageTimelineActivity(
            kind: .app,
            title: title,
            documentKey: documentKey,
            durationSeconds: 0,
            now: now
        )

        lastCompanionUsageActivitySignature = signature
        lastCompanionUsageActivityTitle = title
        lastCompanionUsageActivityDocumentKey = documentKey
        lastCompanionUsageActivityAt = now
    }

    private func finalizeCompanionUsageActivityTracking(now: Date = Date()) {
        defer { resetCompanionUsageActivityTracking() }

        guard let previousTitle = lastCompanionUsageActivityTitle,
              let previousDocumentKey = lastCompanionUsageActivityDocumentKey,
              let previousDate = lastCompanionUsageActivityAt else {
            return
        }

        let delta = now.timeIntervalSince(previousDate)
        let duration = delta > 0 && delta <= 8 * 60 * 60 ? max(1, Int(delta.rounded())) : 0
        guard duration > 0 else { return }

        recordUsageTimelineActivity(
            kind: .app,
            title: previousTitle,
            documentKey: previousDocumentKey,
            durationSeconds: duration,
            now: now
        )
    }

    private func resetCompanionUsageActivityTracking() {
        lastCompanionUsageActivitySignature = nil
        lastCompanionUsageActivityTitle = nil
        lastCompanionUsageActivityDocumentKey = nil
        lastCompanionUsageActivityAt = nil
    }

    private func companionUsageActivitySignature(_ context: CompanionSystemContext) -> String {
        [
            context.frontmostApplicationName,
            context.frontmostBundleIdentifier ?? "",
            context.frontmostWindowTitle ?? ""
        ].joined(separator: "\u{1F}")
    }

    private func companionUsageActivityTitle(_ context: CompanionSystemContext) -> String {
        let appName = companionPromptSnippet(context.frontmostApplicationName, limit: 80)
        let windowTitle = context.frontmostWindowTitle
            .map { companionPromptSnippet($0, limit: 120) }
            .flatMap { $0.isEmpty ? nil : $0 }
        if let windowTitle {
            return "Active in \(appName): \(windowTitle)"
        }
        return "Active in \(appName)"
    }

    private func companionUsageActivityDocumentKey(_ context: CompanionSystemContext) -> String {
        let identifier = context.frontmostBundleIdentifier
            .map { companionPromptSnippet($0, limit: 160) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? companionPromptSnippet(context.frontmostApplicationName, limit: 160)
        return "app:\(identifier)"
    }

    private func scheduleCompanionAutoScanIfNeeded(for bufferID: UUID?) {
        guard isCompanionAutoScanEnabled,
              let bufferID,
              bufferID == selectedBufferID,
              selectedBuffer?.language.isBinaryPreview != true else {
            return
        }

        companionAutoScanTask?.cancel()
        companionStatus = "Companion scan queued..."
        companionAutoScanTask = Task { [weak self] in
            do {
                let delay = await MainActor.run { self?.companionAutoScanDelayNanoseconds ?? 0 }
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
                try Task.checkCancellation()
                await MainActor.run {
                    self?.companionAutoScanTask = nil
                    self?.runCompanionScan()
                }
            } catch {
                await MainActor.run {
                    if self?.companionStatus == "Companion scan queued..." {
                        self?.companionStatus = nil
                    }
                    self?.companionAutoScanTask = nil
                }
            }
        }
    }

    func runCompanionScan() {
        guard let buffer = selectedBuffer else { return }
        guard !buffer.language.isBinaryPreview else {
            lastError = "Companion mode works with text buffers."
            showCompanionPanel()
            return
        }

        showCompanionPanel()
        companionTask?.cancel()
        isCompanionRunning = true
        companionStatus = "Scanning \(buffer.displayTitle)..."

        let bufferSnapshot = buffer
        companionTask = Task { [weak self] in
            do {
                guard let self else { return }
                let prompt = CompanionSuggestionParser.userPrompt(
                    title: bufferSnapshot.displayTitle,
                    language: bufferSnapshot.language,
                    text: self.truncatedHTTPAIContext(bufferSnapshot.text),
                    workspaceContext: await self.companionWorkspaceContext(for: bufferSnapshot)
                )
                let configuration = try self.httpAIConfigurationProvider()
                let client = self.httpAIClientFactory(configuration)
                let response = try await client.complete(
                    messages: [
                        HTTPAIChatMessage(
                            role: "user",
                            content: prompt
                        )
                    ],
                    systemPrompt: CompanionSuggestionParser.systemPrompt
                )
                let suggestions = CompanionSuggestionParser.parse(response)

                try Task.checkCancellation()
                await MainActor.run {
                    guard self.buffers.contains(where: { $0.id == bufferSnapshot.id }) else { return }
                    self.companionSuggestionsByBufferID[bufferSnapshot.id] = suggestions
                    self.companionStatus = suggestions.isEmpty
                        ? "No applicable suggestions returned."
                        : "\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s") ready."
                    self.isCompanionRunning = false
                    self.companionTask = nil
                }
            } catch {
                await MainActor.run {
                    if Task.isCancelled {
                        self?.companionStatus = "Cancelled."
                    } else {
                        self?.companionStatus = "Companion error: \(error.localizedDescription)"
                    }
                    self?.isCompanionRunning = false
                    self?.companionTask = nil
                }
            }
        }
    }

    private func companionWorkspaceContext(for buffer: EditorBuffer) async -> String {
        var sections: [String] = []
        let includesSystemContext = companionIncludesSystemContextProvider()

        sections.append(companionCurrentBufferContext(for: buffer))

        if includesSystemContext,
           let systemContext = await companionSystemContextProvider() {
            sections.append(companionSystemContextSection(systemContext))
        }

        let openTabLines = buffers
            .prefix(8)
            .map { companionOpenTabLine(for: $0, currentBufferID: buffer.id) }
        if !openTabLines.isEmpty {
            sections.append("Open tabs:\n" + openTabLines.joined(separator: "\n"))
        }

        let commentLines = comments(for: buffer)
            .prefix(5)
            .map { comment in
                let body = comment.body.isEmpty ? "No comment body" : comment.body
                return "- \(companionPromptSnippet(comment.quote, limit: 80)): \(companionPromptSnippet(body, limit: 120))"
            }
        if !commentLines.isEmpty {
            sections.append("Open comments on current tab:\n" + commentLines.joined(separator: "\n"))
        }

        let taskLines = companionTaskContextLines(limit: 8)
        if !taskLines.isEmpty {
            sections.append("Tasks:\n" + taskLines.joined(separator: "\n"))
        }

        let activityLines = todayUsageTimeline
            .filter { includesSystemContext || $0.kind != .app }
            .prefix(8)
            .map { entry in
                let duration = entry.durationSeconds > 0 ? " (\(entry.durationSeconds)s)" : ""
                return "- \(entry.kind.rawValue): \(companionPromptSnippet(entry.title, limit: 120))\(duration)"
            }
        if !activityLines.isEmpty {
            sections.append("Recent activity today:\n" + activityLines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private func companionSystemContextSection(_ context: CompanionSystemContext) -> String {
        var pieces = [
            "frontmost app: \(companionPromptSnippet(context.frontmostApplicationName, limit: 80))"
        ]
        if let bundleIdentifier = context.frontmostBundleIdentifier, !bundleIdentifier.isEmpty {
            pieces.append("bundle: \(companionPromptSnippet(bundleIdentifier, limit: 100))")
        }
        if let windowTitle = context.frontmostWindowTitle, !windowTitle.isEmpty {
            pieces.append("window: \(companionPromptSnippet(windowTitle, limit: 120))")
        }
        if let role = context.focusedElementRole, !role.isEmpty {
            pieces.append("focused role: \(companionPromptSnippet(role, limit: 80))")
        }
        if let title = context.focusedElementTitle, !title.isEmpty {
            pieces.append("focused title: \(companionPromptSnippet(title, limit: 120))")
        }
        if let selectedText = context.selectedText, !selectedText.isEmpty {
            pieces.append("selected text: \(companionPromptSnippet(selectedText, limit: 500))")
        } else if let focusedValue = context.focusedValue, !focusedValue.isEmpty {
            pieces.append("focused value: \(companionPromptSnippet(focusedValue, limit: 500))")
        }
        if let screenText = context.screenText, !screenText.isEmpty {
            pieces.append("screen text: \(companionPromptSnippet(screenText, limit: 900))")
        }
        return "System context:\n- " + pieces.joined(separator: ", ")
    }

    private func companionCurrentBufferContext(for buffer: EditorBuffer) -> String {
        var pieces: [String] = []
        pieces.append(buffer.kind == .file ? "file" : "scratch")
        pieces.append(buffer.isDirty ? "modified" : "saved")
        pieces.append(buffer.savePolicy.displayName)
        if buffer.isLargeFileMode {
            pieces.append("large-file preview")
        }
        if let filePath = buffer.filePath {
            pieces.append("path: \(filePath)")
        }
        if let selection = normalizedRanges(buffer.selectionRanges, in: buffer.text).first {
            let lineNumber = StructuredTextFolder.lineNumber(at: selection.location, in: buffer.text)
            if selection.length > 0 {
                let selectedText = (buffer.text as NSString).substring(with: selection.nsRange)
                pieces.append("selection line \(lineNumber): \(companionPromptSnippet(selectedText, limit: 120))")
            } else {
                pieces.append("cursor line \(lineNumber)")
            }
        }
        return "Current buffer state: " + pieces.joined(separator: ", ")
    }

    private func companionOpenTabLine(for tab: EditorBuffer, currentBufferID: UUID) -> String {
        var flags: [String] = [tab.language.displayName]
        if tab.id == currentBufferID {
            flags.append("current")
        }
        flags.append(tab.isDirty ? "modified" : "saved")
        if tab.kind == .scratch {
            flags.append("scratch")
        }
        if tab.isLargeFileMode {
            flags.append("large-file")
        }
        return "- \(tab.displayTitle) (\(flags.joined(separator: ", ")))"
    }

    private func companionTaskContextLines(limit: Int) -> [String] {
        let manualLines = (globalManualTasks + manualTasks).map { task in
            "- \(task.scope.title) \(task.status.title): \(companionPromptSnippet(task.title, limit: 120))"
        }
        let detectedLines = detectedTasks.map { task in
            "- \(task.status.title): \(companionPromptSnippet(task.title, limit: 120)) (\(task.sourceLabel))"
        }
        return Array((manualLines + detectedLines).prefix(limit))
    }

    private func companionPromptSnippet(_ text: String, limit: Int) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: max(0, limit - 1))
        return String(collapsed[..<end]) + "..."
    }

    static func currentCompanionSystemContext(
        includeAccessibilityContext: Bool = CompanionSettings.includesAccessibilityContext(),
        includeScreenTextContext: Bool = CompanionSettings.includesScreenTextContext()
    ) async -> CompanionSystemContext? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = (application.localizedName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = application.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = appName.isEmpty ? (bundleIdentifier ?? "") : appName
        guard !resolvedName.isEmpty else {
            return nil
        }

        var context = CompanionSystemContext(
            frontmostApplicationName: resolvedName,
            frontmostBundleIdentifier: bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil,
            frontmostWindowTitle: frontmostWindowTitle(forProcessIdentifier: application.processIdentifier)
        )

        if includeAccessibilityContext,
           let accessibilityContext = frontmostAccessibilityContext(
            forProcessIdentifier: application.processIdentifier
           ) {
            context.focusedElementRole = accessibilityContext.focusedElementRole
            context.focusedElementTitle = accessibilityContext.focusedElementTitle
            context.selectedText = accessibilityContext.selectedText
            context.focusedValue = accessibilityContext.focusedValue
        }

        if includeScreenTextContext {
            context.screenText = await frontmostWindowScreenText(
                forProcessIdentifier: application.processIdentifier
            )
        }

        return context
    }

    private static func frontmostAccessibilityContext(
        forProcessIdentifier processIdentifier: pid_t
    ) -> CompanionSystemContext? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        guard let focusedElement = axElementAttribute(appElement, kAXFocusedUIElementAttribute) else {
            return nil
        }

        return CompanionSystemContext(
            frontmostApplicationName: "",
            frontmostBundleIdentifier: nil,
            frontmostWindowTitle: nil,
            focusedElementRole: axStringAttribute(focusedElement, kAXRoleAttribute),
            focusedElementTitle: axStringAttribute(focusedElement, kAXTitleAttribute)
                ?? axStringAttribute(focusedElement, kAXDescriptionAttribute),
            selectedText: axStringAttribute(focusedElement, kAXSelectedTextAttribute),
            focusedValue: axStringAttribute(focusedElement, kAXValueAttribute),
            screenText: nil
        )
    }

    private static func axElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axAttribute(element, attribute) else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = axAttribute(element, attribute) else {
            return nil
        }

        let text: String?
        if let string = value as? String {
            text = string
        } else if let attributedString = value as? NSAttributedString {
            text = attributedString.string
        } else if let number = value as? NSNumber {
            text = number.stringValue
        } else {
            text = nil
        }

        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func axAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        return value
    }

    private static func frontmostWindowTitle(forProcessIdentifier processIdentifier: pid_t) -> String? {
        let title = frontmostWindowInfo(forProcessIdentifier: processIdentifier)
            .flatMap { $0[kCGWindowName as String] as? String }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }

    private static func frontmostWindowScreenText(forProcessIdentifier processIdentifier: pid_t) async -> String? {
        guard CGPreflightScreenCaptureAccess(),
              let image = await frontmostWindowImage(forProcessIdentifier: processIdentifier) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return nil
        }

        let text = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text?.isEmpty == false ? text : nil
    }

    private static func frontmostWindowImage(forProcessIdentifier processIdentifier: pid_t) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { window in
                window.isOnScreen &&
                    window.windowLayer == 0 &&
                    window.owningApplication?.processID == processIdentifier
            }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width.rounded(.up)))
            configuration.height = max(1, Int(window.frame.height.rounded(.up)))
            configuration.showsCursor = false
            configuration.scalesToFit = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            return nil
        }
    }

    private static func frontmostWindowInfo(forProcessIdentifier processIdentifier: pid_t) -> [String: Any]? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard let ownerPID = windowIntegerValue(window[kCGWindowOwnerPID as String]),
                  ownerPID == Int(processIdentifier),
                  windowIntegerValue(window[kCGWindowLayer as String]) == 0 else {
                continue
            }

            return window
        }

        return nil
    }

    private static func windowIntegerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }

    func cancelCompanionScan() {
        companionTask?.cancel()
        companionAutoScanTask?.cancel()
        companionTask = nil
        companionAutoScanTask = nil
        isCompanionRunning = false
        companionStatus = "Cancelled."
    }

    func applyCompanionSuggestion(_ suggestionID: UUID, in bufferID: UUID) {
        guard let suggestion = companionSuggestionsByBufferID[bufferID]?.first(where: { $0.id == suggestionID }) else {
            return
        }
        guard suggestion.canApplyEdit else {
            lastError = "This companion suggestion has no edit to apply."
            return
        }
        guard let index = buffers.firstIndex(where: { $0.id == bufferID }) else { return }

        let text = buffers[index].text
        if suggestion.hasPatchEdit {
            guard let patchText = suggestion.patchText,
                  let application = CompanionUnifiedDiffApplier.apply(patchText, to: text) else {
                lastError = "Could not apply companion patch because its context no longer matches this document."
                return
            }

            updateText(application.text, in: bufferID)

            if let updatedIndex = buffers.firstIndex(where: { $0.id == bufferID }),
               buffers[updatedIndex].text == application.text {
                buffers[updatedIndex].selectionRanges = [application.selection]
                buffers[updatedIndex].updatedAt = Date()
                markCompanionSuggestion(suggestionID, asAppliedIn: bufferID)
            }
            return
        }

        guard let range = CompanionSuggestionAnchorResolver.range(of: suggestion.findText, in: text) else {
            lastError = "Could not apply companion suggestion because the original text was not found."
            return
        }

        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: range, with: suggestion.replacementText)
        updateText(mutable as String, in: bufferID)

        if let updatedIndex = buffers.firstIndex(where: { $0.id == bufferID }) {
            buffers[updatedIndex].selectionRanges = [
                TextRange(location: range.location, length: suggestion.replacementText.utf16.count)
            ]
            buffers[updatedIndex].updatedAt = Date()
        }

        markCompanionSuggestion(suggestionID, asAppliedIn: bufferID)
    }

    @discardableResult
    func addCompanionSuggestionAsComment(_ suggestionID: UUID, in bufferID: UUID) -> DocumentComment? {
        guard let suggestion = companionSuggestionsByBufferID[bufferID]?.first(where: { $0.id == suggestionID }) else {
            return nil
        }
        guard suggestion.canAddComment,
              let index = buffers.firstIndex(where: { $0.id == bufferID }) else {
            lastError = "This companion suggestion has no comment anchor."
            return nil
        }

        guard let range = CompanionSuggestionAnchorResolver.range(of: suggestion.findText, in: buffers[index].text) else {
            lastError = "Could not add companion comment because the original text was not found."
            return nil
        }

        return addComment(to: TextRange(range), in: bufferID, body: suggestion.comment)
    }

    private func markCompanionSuggestion(_ suggestionID: UUID, asAppliedIn bufferID: UUID) {
        guard var suggestions = companionSuggestionsByBufferID[bufferID],
              let index = suggestions.firstIndex(where: { $0.id == suggestionID }) else {
            return
        }

        suggestions[index].appliedAt = Date()
        companionSuggestionsByBufferID[bufferID] = suggestions
    }

    private func aiWorkingDirectory(for buffer: EditorBuffer) -> URL {
        return aiFileBridge.editableURL(for: buffer)
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    private func configuredExecutable(for provider: AIAgentProvider) -> String {
        let configured = UserDefaults.standard.string(forKey: provider.settingsExecutableKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return provider.defaultExecutable
    }

    private func configuredArguments(for provider: AIAgentProvider) -> String {
        let configured = UserDefaults.standard.string(forKey: provider.settingsArgumentsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return provider.defaultArguments
    }

    private func canSaveBuffer(at index: Int) -> Bool {
        guard buffers.indices.contains(index) else { return false }
        guard !buffers[index].isLargeFileMode else {
            lastError = "Large-file previews cannot be saved because only the first part of the file is loaded."
            return false
        }
        let policy = buffers[index].savePolicy
        guard !policy.blocksSaving else {
            lastError = policy.blockedSaveMessage(for: buffers[index].displayTitle)
            return false
        }

        return true
    }

    private func encryptionPasswordKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func cacheEncryptionPassword(_ password: String, for url: URL) {
        encryptionPasswordsByPath[encryptionPasswordKey(for: url)] = password
    }

    private func cachedEncryptionPassword(for url: URL) -> String? {
        encryptionPasswordsByPath[encryptionPasswordKey(for: url)]
    }

    private func passwordForEncryptedDocument(
        at url: URL,
        documentName: String,
        isNewPassword: Bool
    ) -> String? {
        if let cached = cachedEncryptionPassword(for: url) {
            return cached
        }

        if !isNewPassword,
           let touchIDPassword = try? EncryptedDocumentPasswordStore.loadPassword(
            for: url,
            reason: "Unlock \(documentName)"
           ) {
            cacheEncryptionPassword(touchIDPassword, for: url)
            return touchIDPassword
        }

        if isNewPassword {
            return promptForNewEncryptedDocumentPassword(documentName: documentName, url: url)
        }

        guard let result = EncryptedDocumentPasswordPrompt.askForExistingPassword(documentName: documentName) else {
            return nil
        }
        if result.rememberWithTouchID {
            do {
                try EncryptedDocumentPasswordStore.save(password: result.password, for: url)
            } catch {
                lastError = "Could not enable Touch ID unlock: \(error.localizedDescription)"
            }
        }
        cacheEncryptionPassword(result.password, for: url)
        return result.password
    }

    private func promptForNewEncryptedDocumentPassword(documentName: String, url: URL) -> String? {
        guard let result = EncryptedDocumentPasswordPrompt.askForNewPassword(documentName: documentName) else {
            return nil
        }
        if result.rememberWithTouchID {
            do {
                try EncryptedDocumentPasswordStore.save(password: result.password, for: url)
            } catch {
                lastError = "Could not enable Touch ID unlock: \(error.localizedDescription)"
            }
        }
        cacheEncryptionPassword(result.password, for: url)
        return result.password
    }

    private func exportFileName(for buffer: EditorBuffer, extension fileExtension: String) -> String {
        let baseName: String
        if let filePath = buffer.filePath {
            baseName = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        } else {
            baseName = buffer.displayTitle
        }

        let cleaned = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\((cleaned.isEmpty ? "Untitled" : cleaned)).\(fileExtension)"
    }

    private func writeExport(_ text: String, to url: URL) {
        writeExport(Data(text.utf8), to: url)
    }

    private func writeExport(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            networkShare.statusMessage = "Exported \(url.lastPathComponent)."
            if let selectedBuffer {
                recordUsageEvent(
                    \.exportCount,
                    documentKey: documentKey(for: selectedBuffer),
                    timelineKind: .export,
                    timelineTitle: "Exported \(selectedBuffer.displayTitle)"
                )
            }
        } catch {
            lastError = "Could not export \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func aiChatLocation(_ chatID: UUID) -> (bufferIndex: Int, sessionIndex: Int)? {
        for bufferIndex in buffers.indices {
            if let sessionIndex = buffers[bufferIndex].aiSessions.firstIndex(where: { $0.id == chatID }) {
                return (bufferIndex, sessionIndex)
            }
        }

        return nil
    }

    private func stopAIClients(for buffer: EditorBuffer) {
        for session in buffer.aiSessions {
            aiClients.removeValue(forKey: session.id)?.stop()
            aiRunningSessions.remove(session.id)
            aiSessionStatuses.removeValue(forKey: session.id)
            aiStreamingMessageIDs.removeValue(forKey: session.id)
            aiChatIDsByAgentSession = aiChatIDsByAgentSession.filter { $0.value != session.id }
        }
    }

    @discardableResult
    private func saveBuffer(
        at index: Int,
        to url: URL,
        languageOverride: EditorLanguage? = nil,
        preserveEncryption: Bool = true
    ) -> Bool {
        guard canSaveBuffer(at: index) else {
            return false
        }

        if preserveEncryption, buffers[index].isEncrypted {
            guard let password = passwordForEncryptedDocument(
                at: url,
                documentName: url.lastPathComponent,
                isNewPassword: false
            ) else {
                return false
            }

            return saveEncryptedBuffer(at: index, to: url, password: password, languageOverride: languageOverride)
        }

        do {
            let oldDocumentKey = documentKey(for: buffers[index])
            try buffers[index].text.write(to: url, atomically: true, encoding: .utf8)
            buffers[index].kind = .file
            buffers[index].filePath = url.path
            buffers[index].title = url.lastPathComponent
            buffers[index].language = languageOverride ?? EditorLanguage.detect(fileName: url.lastPathComponent, text: buffers[index].text)
            buffers[index].isEncrypted = false
            buffers[index].updatedAt = Date()
            buffers[index].isDirty = false
            recordUsageEvent(
                \.saveCount,
                documentKey: documentKey(for: buffers[index]),
                timelineKind: .save,
                timelineTitle: "Saved \(buffers[index].displayTitle)"
            )
            rekeyComments(from: oldDocumentKey, to: documentKey(for: buffers[index]))
            persistSoon()
            return true
        } catch {
            lastError = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    private func saveEncryptedBuffer(
        at index: Int,
        to url: URL,
        password: String,
        languageOverride: EditorLanguage? = nil
    ) -> Bool {
        guard canSaveBuffer(at: index) else {
            return false
        }

        do {
            let oldDocumentKey = documentKey(for: buffers[index])
            let data = try EncryptedDocumentService.encrypt(text: buffers[index].text, password: password)
            try data.write(to: url, options: .atomic)
            buffers[index].kind = .file
            buffers[index].filePath = url.path
            buffers[index].title = url.lastPathComponent
            buffers[index].language = languageOverride
                ?? Self.detectEncryptedDocumentLanguage(url: url, text: buffers[index].text)
            buffers[index].updatedAt = Date()
            buffers[index].isDirty = false
            buffers[index].isEncrypted = true
            buffers[index].fileSizeBytes = Int64(data.count)
            cacheEncryptionPassword(password, for: url)
            recordUsageEvent(
                \.saveCount,
                documentKey: documentKey(for: buffers[index]),
                timelineKind: .save,
                timelineTitle: "Saved \(buffers[index].displayTitle)"
            )
            rekeyComments(from: oldDocumentKey, to: documentKey(for: buffers[index]))
            persistSoon()
            return true
        } catch {
            lastError = "Could not encrypt \(url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    private nonisolated static func buildDocumentCatalogNodes(rootURL: URL) -> [DocumentCatalogNode] {
        var remainingItems = 3000
        return documentCatalogChildren(in: rootURL, remainingItems: &remainingItems)
    }

    private nonisolated static func documentCatalogChildren(in directoryURL: URL, remainingItems: inout Int) -> [DocumentCatalogNode] {
        guard remainingItems > 0,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var nodes: [DocumentCatalogNode] = []

        for url in urls where remainingItems > 0 {
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else { continue }

            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if resourceValues?.isDirectory == true {
                guard shouldIncludeDocumentCatalogDirectory(name) else { continue }

                var childRemaining = remainingItems - 1
                let children = documentCatalogChildren(in: url, remainingItems: &childRemaining)
                remainingItems = childRemaining

                if !children.isEmpty {
                    nodes.append(DocumentCatalogNode(url: url, isDirectory: true, children: children))
                    remainingItems -= 1
                }
            } else if resourceValues?.isRegularFile == true, shouldIncludeDocumentCatalogFile(url) {
                nodes.append(DocumentCatalogNode(url: url, isDirectory: false))
                remainingItems -= 1
            }
        }

        return nodes.sorted { first, second in
            if first.isDirectory != second.isDirectory {
                return first.isDirectory && !second.isDirectory
            }

            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    private nonisolated static func shouldIncludeDocumentCatalogDirectory(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        let excluded = [
            ".build",
            "build",
            "deriveddata",
            "dist",
            "node_modules",
            "packages",
            "vendor"
        ]

        return !excluded.contains(lowercased)
    }

    private nonisolated static func shouldIncludeDocumentCatalogFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let allowedExtensions: Set<String> = [
            "bash",
            "c",
            "cc",
            "conf",
            "cpp",
            "css",
            "csv",
            "env",
            "fish",
            "go",
            "h",
            "hpp",
            "htm",
            "html",
            "ini",
            "js",
            "json",
            "jsonl",
            "log",
            "markdown",
            "md",
            "mdown",
            "mjs",
            "plist",
            "py",
            "rb",
            "rs",
            "sass",
            "scss",
            "sh",
            "swift",
            "text",
            "toml",
            "ts",
            "tsx",
            "txt",
            "xml",
            "yaml",
            "yml",
            "zsh"
        ]

        if allowedExtensions.contains(ext) {
            return true
        }

        return [
            "changelog",
            "dockerfile",
            "gemfile",
            "license",
            "makefile",
            "rakefile",
            "readme"
        ].contains(name)
    }

    private nonisolated static func scanDocumentCatalogTasks(
        nodes: [DocumentCatalogNode],
        rootPath: String
    ) -> [DetectedTask] {
        var tasks: [DetectedTask] = []
        for node in documentCatalogFileNodes(nodes) where tasks.count < maxDocumentCatalogDetectedTasks {
            let language = EditorLanguage.detect(fileName: node.url.lastPathComponent, text: "")
            guard language.supportsTaskScanning,
                  let fileSizeBytes = fileSizeBytes(at: node.url),
                  fileSizeBytes <= maxDocumentCatalogTaskScanFileSizeBytes else {
                continue
            }

            guard let text = try? String(contentsOf: node.url) else {
                continue
            }

            let displayPath = documentCatalogDisplayPath(for: node.url, rootPath: rootPath)
            let matches = MarkdownTaskScanner.scan(text)
            for match in matches where tasks.count < maxDocumentCatalogDetectedTasks {
                tasks.append(
                    DetectedTask(
                        bufferID: nil,
                        bufferTitle: displayPath,
                        filePath: node.url.path,
                        title: match.title,
                        status: match.status,
                        lineNumber: match.lineNumber,
                        lineRange: match.lineRange,
                        markerRange: match.markerRange,
                        updateMode: match.updateMode
                    )
                )
            }
        }

        return tasks
    }

    private func searchAllSources(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        var results = searchAllTabs(query: query, limit: 500)
        guard results.count < 500 else { return results }

        let openFilePaths = Set(buffers.compactMap(\.filePath))
        for node in documentCatalogFileNodes(documentCatalogNodes) where results.count < 500 {
            let path = node.url.path
            guard !openFilePaths.contains(path),
                  let text = try? String(contentsOf: node.url) else {
                continue
            }

            results.append(
                contentsOf: searchResults(
                    in: text,
                    title: documentCatalogDisplayPath(for: node.url),
                    bufferID: nil,
                    filePath: path,
                    limit: 500 - results.count
                )
            )
        }

        return results
    }

    private func searchAllTabs(query: String, limit: Int) -> [SearchResult] {
        guard !query.isEmpty, limit > 0 else { return [] }

        var results: [SearchResult] = []

        for buffer in buffers {
            results.append(
                contentsOf: searchResults(
                    in: buffer.text,
                    title: buffer.displayTitle,
                    bufferID: buffer.id,
                    filePath: buffer.filePath,
                    limit: limit - results.count
                )
            )
            if results.count >= limit { break }
        }

        return results
    }

    private func searchResults(
        in text: String,
        title: String,
        bufferID: UUID?,
        filePath: String?,
        limit: Int
    ) -> [SearchResult] {
        guard limit > 0 else { return [] }

        let nsText = text as NSString
        return allMatches(in: text)
            .prefix(limit)
            .map { match in
                let lineRange = nsText.lineRange(for: match.range)
                let excerpt = nsText.substring(with: lineRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                return SearchResult(
                    bufferID: bufferID,
                    filePath: filePath,
                    bufferTitle: title,
                    lineNumber: lineNumber(at: match.range.location, in: text),
                    excerpt: excerpt.isEmpty ? " " : excerpt,
                    range: TextRange(match.range)
                )
            }
    }

    private nonisolated static func documentCatalogFileNodes(_ nodes: [DocumentCatalogNode]) -> [DocumentCatalogNode] {
        nodes.flatMap { node -> [DocumentCatalogNode] in
            node.isDirectory ? documentCatalogFileNodes(node.children) : [node]
        }
    }

    private func documentCatalogFileNodes(_ nodes: [DocumentCatalogNode]) -> [DocumentCatalogNode] {
        Self.documentCatalogFileNodes(nodes)
    }

    private func documentCatalogDisplayPath(for url: URL) -> String {
        Self.documentCatalogDisplayPath(for: url, rootPath: documentCatalogRootPath)
    }

    private nonisolated static func documentCatalogDisplayPath(for url: URL, rootPath: String?) -> String {
        guard let rootPath else {
            return url.lastPathComponent
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let fileURL = url.standardizedFileURL
        let root = rootURL.path
        let path = fileURL.path
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }

        return url.lastPathComponent
    }

    private nonisolated static func fuzzyScore(candidate: String, query: String) -> Int? {
        let candidate = Array(candidate.lowercased())
        let query = Array(query.lowercased())
        guard !query.isEmpty else { return 0 }

        var candidateIndex = 0
        var score = 0
        var previousMatchIndex: Int?

        for queryCharacter in query {
            var foundIndex: Int?
            while candidateIndex < candidate.count {
                if candidate[candidateIndex] == queryCharacter {
                    foundIndex = candidateIndex
                    break
                }
                candidateIndex += 1
            }

            guard let matchIndex = foundIndex else { return nil }

            score += 10
            if let previousMatchIndex, matchIndex == previousMatchIndex + 1 {
                score += 14
            }
            if matchIndex == 0 || Self.isFuzzyWordBoundary(candidate[matchIndex - 1]) {
                score += 10
            }

            previousMatchIndex = matchIndex
            candidateIndex = matchIndex + 1
        }

        if String(candidate).contains(String(query)) {
            score += 30
        }

        return score - candidate.count / 20
    }

    private nonisolated static func isFuzzyWordBoundary(_ character: Character) -> Bool {
        character == "/" || character == "-" || character == "_" || character == "." || character == " "
    }

    private func fileIdentity(forURL url: URL) -> String {
        fileIdentity(forPath: url.path)
    }

    private func fileIdentity(forPath path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private struct FindMatch {
        let range: NSRange
        let regexResult: NSTextCheckingResult?
    }

    private struct ReplacementResult {
        let text: String
        let count: Int
        let firstSelection: TextRange
    }

    private func makeFindRegex() throws -> NSRegularExpression {
        let options: NSRegularExpression.Options = findMatchesCase ? [] : [.caseInsensitive]
        return try NSRegularExpression(pattern: findQuery, options: options)
    }

    private func replacingAllMatches(in text: String) -> ReplacementResult? {
        let matches = allMatches(in: text)
        guard !matches.isEmpty else { return nil }

        let replacements = matches.map { replacementString(for: $0, in: text) }
        let mutable = NSMutableString(string: text)

        for (match, replacement) in zip(matches, replacements).reversed() {
            mutable.replaceCharacters(in: match.range, with: replacement)
        }

        return ReplacementResult(
            text: mutable as String,
            count: matches.count,
            firstSelection: TextRange(location: matches[0].range.location, length: replacements[0].utf16.count)
        )
    }

    private func allMatches(in text: String) -> [FindMatch] {
        guard !findQuery.isEmpty else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if findUsesRegex {
            guard let regex = try? makeFindRegex() else {
                return []
            }

            return regex.matches(in: text, range: fullRange)
                .filter { $0.range.location != NSNotFound && $0.range.length > 0 }
                .filter { !findWholeWord || isWholeWordMatch($0.range, in: nsText) }
                .map { FindMatch(range: $0.range, regexResult: $0) }
        }

        var matches: [FindMatch] = []
        var searchLocation = 0
        let options: NSString.CompareOptions = findMatchesCase ? [] : [.caseInsensitive]

        while searchLocation < nsText.length {
            let searchRange = NSRange(location: searchLocation, length: nsText.length - searchLocation)
            let found = nsText.range(of: findQuery, options: options, range: searchRange)
            if found.location == NSNotFound { break }
            if !findWholeWord || isWholeWordMatch(found, in: nsText) {
                matches.append(FindMatch(range: found, regexResult: nil))
            }
            searchLocation = found.location + max(found.length, 1)
        }

        return matches
    }

    private func isWholeWordMatch(_ range: NSRange, in nsText: NSString) -> Bool {
        let beforeIndex = range.location - 1
        let afterIndex = range.location + range.length
        let beforeIsWord = beforeIndex >= 0 && isFindWordCharacter(nsText.character(at: beforeIndex))
        let afterIsWord = afterIndex < nsText.length && isFindWordCharacter(nsText.character(at: afterIndex))
        return !beforeIsWord && !afterIsWord
    }

    private func isFindWordCharacter(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar)
    }

    private func firstMatch(in text: String, range: NSRange) -> FindMatch? {
        allMatches(in: text).first { NSEqualRanges($0.range, range) }
    }

    private func replacementString(for match: FindMatch, in text: String) -> String {
        guard findUsesRegex,
              let regexResult = match.regexResult,
              let regex = try? makeFindRegex() else {
            return replaceText
        }

        return regex.replacementString(for: regexResult, in: text, offset: 0, template: replaceText)
    }

    private func lineNumber(at location: Int, in text: String) -> Int {
        let nsText = text as NSString
        let location = min(max(0, location), nsText.length)
        guard location > 0 else { return 1 }

        let prefix = nsText.substring(to: location)
        return prefix.reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
    }

    private enum FindDirection {
        case next
        case previous
    }

    private func find(direction: FindDirection) {
        guard let selectedIndex,
              !findQuery.isEmpty else {
            return
        }

        let buffer = buffers[selectedIndex]
        let selected = normalizedRanges(buffer.selectionRanges, in: buffer.text).first ?? .zero
        let start: Int

        switch direction {
        case .next:
            start = selected.location + selected.length
        case .previous:
            start = selected.location
        }

        guard let found = findRange(query: findQuery, in: buffer.text, from: start, direction: direction) else {
            return
        }

        buffers[selectedIndex].selectionRanges = [found]
        persistSoon()
    }

    private func findRange(
        query: String,
        in text: String,
        from rawStart: Int,
        direction: FindDirection,
        forceLiteral: Bool = false
    ) -> TextRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let start = min(max(0, rawStart), nsText.length)

        if findUsesRegex, !forceLiteral, query == findQuery {
            let matches = allMatches(in: text)
            guard !matches.isEmpty else { return nil }

            switch direction {
            case .next:
                return TextRange(matches.first { $0.range.location >= start }?.range ?? matches[0].range)
            case .previous:
                return TextRange(matches.last { $0.range.location < start }?.range ?? matches[matches.count - 1].range)
            }
        }

        var options: NSString.CompareOptions = findMatchesCase ? [] : [.caseInsensitive]
        if direction == .previous {
            options.insert(.backwards)
        }

        switch direction {
        case .next:
            let firstRange = NSRange(location: start, length: nsText.length - start)
            let found = nsText.range(of: query, options: options, range: firstRange)
            if found.location != NSNotFound {
                return TextRange(found)
            }

            let wrapRange = NSRange(location: 0, length: start)
            let wrapped = nsText.range(of: query, options: options, range: wrapRange)
            return wrapped.location == NSNotFound ? nil : TextRange(wrapped)

        case .previous:
            let firstRange = NSRange(location: 0, length: start)
            let found = nsText.range(of: query, options: options, range: firstRange)
            if found.location != NSNotFound {
                return TextRange(found)
            }

            let wrapRange = NSRange(location: start, length: nsText.length - start)
            let wrapped = nsText.range(of: query, options: options, range: wrapRange)
            return wrapped.location == NSNotFound ? nil : TextRange(wrapped)
        }
    }

    private func replaceTargetText(_ transform: (String) -> String) {
        guard let selectedIndex else { return }
        let buffer = buffers[selectedIndex]
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        let targetRanges = ranges.isEmpty ? [TextRange(location: 0, length: (buffer.text as NSString).length)] : ranges
        replaceRanges(targetRanges, transform: transform)
    }

    private func replaceTargetLines(_ transform: (String) -> String) {
        guard let selectedIndex else { return }
        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        let targetRanges = ranges.isEmpty ? [TextRange(location: 0, length: nsText.length)] : mergedLineRanges(for: ranges, in: buffer.text)
        replaceRanges(targetRanges, transform: transform)
    }

    private func formatJSONSelection(prettyPrinted: Bool) {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        let targetRanges = ranges.isEmpty
            ? [TextRange(location: 0, length: (buffer.text as NSString).length)]
            : ranges
        let nsText = buffer.text as NSString
        var replacements: [String] = []

        do {
            for range in targetRanges {
                let original = nsText.substring(with: range.nsRange)
                replacements.append(try JSONTextFormatter.format(original, prettyPrinted: prettyPrinted))
            }
        } catch {
            lastError = "Could not \(prettyPrinted ? "format" : "minify") JSON: \(error.localizedDescription)"
            return
        }

        replaceRanges(targetRanges, replacements: replacements)
    }

    private func replaceRanges(_ ranges: [TextRange], transform: (String) -> String) {
        guard let selectedIndex else { return }
        let text = buffers[selectedIndex].text
        let nsText = text as NSString
        let normalizedRanges = normalizedRanges(ranges, in: text)
        let replacements = normalizedRanges.map { range -> String in
            transform(nsText.substring(with: range.nsRange))
        }
        replaceRanges(normalizedRanges, replacements: replacements)
    }

    private func replaceRanges(_ ranges: [TextRange], replacements: [String]) {
        guard let selectedIndex else { return }
        let text = buffers[selectedIndex].text
        let mutable = NSMutableString(string: text)
        let edits = zip(normalizedRanges(ranges, in: text), replacements)
            .sorted { $0.0.location > $1.0.location }
        var newSelections: [TextRange] = []

        for (range, replacement) in edits {
            mutable.replaceCharacters(in: range.nsRange, with: replacement)
            newSelections.append(TextRange(location: range.location, length: replacement.utf16.count))
        }

        let updatedText = mutable as String
        buffers[selectedIndex].text = updatedText
        buffers[selectedIndex].selectionRanges = newSelections.reversed()
        buffers[selectedIndex].isDirty = true
        buffers[selectedIndex].updatedAt = Date()
        reanchorComments(for: buffers[selectedIndex], newText: updatedText)
        persistSoon()
    }

    private func applyTranslations(
        _ translations: [String],
        replacing ranges: [TextRange],
        in bufferID: UUID,
        originalText: String,
        targetLanguage: String
    ) {
        defer {
            isTranslationRunning = false
        }

        guard translations.count == ranges.count,
              let index = buffers.firstIndex(where: { $0.id == bufferID }) else {
            translationStatus = nil
            return
        }

        guard buffers[index].text == originalText else {
            translationStatus = nil
            lastError = "Translation skipped because the buffer changed."
            return
        }

        let mutable = NSMutableString(string: originalText)
        let normalized = normalizedRanges(ranges, in: originalText)
        let edits = zip(normalized, translations)
            .sorted { $0.0.location > $1.0.location }
        var newSelections: [TextRange] = []

        for (range, replacement) in edits {
            mutable.replaceCharacters(in: range.nsRange, with: replacement)
            newSelections.append(TextRange(location: range.location, length: replacement.utf16.count))
        }

        updateText(mutable as String, in: bufferID)
        guard let updatedIndex = buffers.firstIndex(where: { $0.id == bufferID }) else {
            translationStatus = nil
            return
        }
        buffers[updatedIndex].selectionRanges = newSelections.reversed()
        buffers[updatedIndex].updatedAt = Date()
        translationStatus = "Translated \(translations.count) selection\(translations.count == 1 ? "" : "s") to \(targetLanguage)."
        persistSoon()
    }

    private func duplicateSelectedLinesOrCurrentLine() {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)

        if !ranges.isEmpty {
            replaceRanges(ranges) { "\($0)\($0)" }
            return
        }

        let cursor = normalizedRanges(buffer.selectionRanges, in: buffer.text).first ?? .zero
        let lineRange = nsText.lineRange(for: NSRange(location: min(cursor.location, nsText.length), length: 0))
        let line = nsText.substring(with: lineRange)
        let insertion = line.hasSuffix("\n") ? line : "\n\(line)"

        let mutable = NSMutableString(string: buffer.text)
        mutable.insert(insertion, at: lineRange.location + lineRange.length)

        let updatedText = mutable as String
        buffers[selectedIndex].text = updatedText
        buffers[selectedIndex].selectionRanges = [TextRange(location: lineRange.location + lineRange.length, length: insertion.utf16.count)]
        buffers[selectedIndex].isDirty = true
        buffers[selectedIndex].updatedAt = Date()
        reanchorComments(for: buffers[selectedIndex], newText: updatedText)
        persistSoon()
    }

    private func performEditorCommandFallback(_ command: EditorCommand) {
        switch command {
        case .transform(let transform):
            transformSelection(transform)
        case .markdown(let command):
            performMarkdownCommandFallback(command)
        case .splitSelectionIntoLines:
            splitSelectionIntoLinesFallback()
        case .expandSelectionToLine:
            expandSelectionToLineFallback()
        case .deleteLine:
            deleteSelectedLinesOrCurrentLineFallback()
        case .moveLineUp:
            moveSelectedLinesFallback(direction: -1)
        case .moveLineDown:
            moveSelectedLinesFallback(direction: 1)
        case .indentLines:
            transformSelectedLinesFallback { lines in
                lines.map { line in
                    line.isEmpty ? line : "\t\(line)"
                }
            }
        case .outdentLines:
            transformSelectedLinesFallback { lines in
                lines.map { line in
                    if line.hasPrefix("\t") {
                        return String(line.dropFirst())
                    }
                    if line.hasPrefix("    ") {
                        return String(line.dropFirst(4))
                    }
                    if line.hasPrefix("  ") {
                        return String(line.dropFirst(2))
                    }
                    if line.hasPrefix(" ") {
                        return String(line.dropFirst())
                    }
                    return line
                }
            }
        case .toggleComment:
            toggleLineCommentsFallback()
        }
    }

    private func performMarkdownCommandFallback(_ command: MarkdownCommand) {
        switch command {
        case .bold:
            wrapSelectionsFallback(left: "**", right: "**")
        case .italic:
            wrapSelectionsFallback(left: "*", right: "*")
        case .inlineCode:
            wrapSelectionsFallback(left: "`", right: "`")
        case .strikethrough:
            wrapSelectionsFallback(left: "~~", right: "~~")
        case .highlight:
            wrapSelectionsFallback(left: "==", right: "==")
        case .subscriptText:
            wrapSelectionsFallback(left: "~", right: "~")
        case .superscriptText:
            wrapSelectionsFallback(left: "^", right: "^")
        case .heading1:
            transformSelectedLinesFallback { lines in
                lines.map { applyMarkdownHeadingFallback(level: 1, to: $0) }
            }
        case .heading2:
            transformSelectedLinesFallback { lines in
                lines.map { applyMarkdownHeadingFallback(level: 2, to: $0) }
            }
        case .heading3:
            transformSelectedLinesFallback { lines in
                lines.map { applyMarkdownHeadingFallback(level: 3, to: $0) }
            }
        case .unorderedList:
            transformSelectedLinesFallback { lines in
                lines.map { toggleMarkdownLinePrefixFallback("- ", in: $0, matching: #"^[-*+]\s+"#) }
            }
        case .orderedList:
            transformSelectedLinesFallback { lines in
                lines.enumerated().map { index, line in
                    toggleMarkdownLinePrefixFallback("\(index + 1). ", in: line, matching: #"^\d+[.)]\s+"#)
                }
            }
        case .taskList:
            transformSelectedLinesFallback { lines in
                lines.map { toggleMarkdownLinePrefixFallback("- [ ] ", in: $0, matching: #"^[-*+]\s+\[[ xX]\]\s+"#) }
            }
        case .link:
            insertMarkdownLinkFallback()
        case .image:
            insertMarkdownSnippetFallback("![image](image.png)", selectOffset: 9, selectLength: 9)
        case .table:
            insertMarkdownSnippetFallback("| Column 1 | Column 2 |\n| --- | --- |\n|  |  |", selectOffset: 2, selectLength: 8)
        case .quote:
            transformSelectedLinesFallback { lines in
                lines.map { toggleMarkdownLinePrefixFallback("> ", in: $0, matching: #"^>\s?"#) }
            }
        case .codeFence:
            insertCodeFenceFallback()
        case .mathBlock:
            insertMarkdownSnippetFallback("$$\nx = y\n$$", selectOffset: 3, selectLength: 5)
        case .mermaidDiagram:
            insertMarkdownSnippetFallback("```mermaid\ngraph TD\n  A-->B\n```", selectOffset: 11, selectLength: 16)
        }
    }

    private func splitSelectionIntoLinesFallback() {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        guard !ranges.isEmpty else {
            expandSelectionToLineFallback()
            return
        }

        let splitRanges = ranges.flatMap { range in
            lineContentRangesFallback(intersecting: range, in: nsText)
        }
        guard !splitRanges.isEmpty else { return }

        buffers[selectedIndex].selectionRanges = splitRanges
        persistSoon()
    }

    private func expandSelectionToLineFallback() {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = buffer.selectionRanges.isEmpty ? [.zero] : normalizedRanges(buffer.selectionRanges, in: buffer.text)
        let lineRanges = ranges.map { TextRange(nsText.lineRange(for: $0.nsRange)) }
        buffers[selectedIndex].selectionRanges = mergeRangesFallback(lineRanges)
        persistSoon()
    }

    private func deleteSelectedLinesOrCurrentLineFallback() {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        let targetRanges = ranges.isEmpty
            ? [TextRange(nsText.lineRange(for: NSRange(location: min(buffer.selectionRanges.last?.location ?? 0, nsText.length), length: 0)))]
            : mergedLineRanges(for: ranges, in: buffer.text)
        guard !targetRanges.isEmpty else { return }

        replaceRanges(
            targetRanges,
            replacements: Array(repeating: "", count: targetRanges.count),
            selectionMode: .custom([TextRange(location: targetRanges.first?.location ?? 0, length: 0)])
        )
    }

    private func moveSelectedLinesFallback(direction: Int) {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        guard nsText.length > 0 else { return }

        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        let cursor = normalizedRanges(buffer.selectionRanges, in: buffer.text).last ?? .zero
        let targetRange = ranges.isEmpty
            ? TextRange(nsText.lineRange(for: NSRange(location: min(cursor.location, nsText.length), length: 0)))
            : mergedLineRanges(for: ranges, in: buffer.text).reduce(nil) { result, range -> TextRange? in
                guard let result else { return range }
                let start = min(result.location, range.location)
                let end = max(result.location + result.length, range.location + range.length)
                return TextRange(location: start, length: end - start)
            } ?? .zero

        if direction < 0 {
            guard targetRange.location > 0 else { return }
            let previousLine = TextRange(nsText.lineRange(for: NSRange(location: max(0, targetRange.location - 1), length: 0)))
            let targetText = nsText.substring(with: targetRange.nsRange)
            let previousText = nsText.substring(with: previousLine.nsRange)
            let replacementRange = TextRange(location: previousLine.location, length: previousLine.length + targetRange.length)
            replaceRanges(
                [replacementRange],
                replacements: [swapAdjacentLineTextsFallback(previousText, targetText)],
                selectionMode: .custom([TextRange(location: previousLine.location, length: targetRange.length)])
            )
            return
        }

        let targetEnd = targetRange.location + targetRange.length
        guard targetEnd < nsText.length else { return }

        let nextLine = TextRange(nsText.lineRange(for: NSRange(location: targetEnd, length: 0)))
        let targetText = nsText.substring(with: targetRange.nsRange)
        let nextText = nsText.substring(with: nextLine.nsRange)
        let replacementRange = TextRange(location: targetRange.location, length: targetRange.length + nextLine.length)
        replaceRanges(
            [replacementRange],
            replacements: [swapAdjacentLineTextsFallback(targetText, nextText)],
            selectionMode: .custom([
                TextRange(
                    location: targetRange.location + firstLineOffsetAfterSwapFallback(first: targetText, second: nextText),
                    length: firstLineLengthAfterSwapFallback(first: targetText, second: nextText)
                )
            ])
        )
    }

    private func transformSelectedLinesFallback(_ transform: ([String]) -> [String]) {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)
        let targetRanges = ranges.isEmpty
            ? [TextRange(nsText.lineRange(for: NSRange(location: min(buffer.selectionRanges.last?.location ?? 0, nsText.length), length: 0)))]
            : mergedLineRanges(for: ranges, in: buffer.text)
        let replacements = targetRanges.map { range in
            preserveTrailingNewline(nsText.substring(with: range.nsRange), transform: transform)
        }
        replaceRanges(targetRanges, replacements: replacements)
    }

    private func toggleLineCommentsFallback() {
        guard let selectedBuffer,
              let prefix = lineCommentPrefix(for: selectedBuffer.language) else {
            return
        }

        transformSelectedLinesFallback { lines in
            let meaningfulLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let shouldUncomment = !meaningfulLines.isEmpty && meaningfulLines.allSatisfy { line in
                let (_, body) = splitIndentFallback(line)
                return body.hasPrefix(prefix)
            }

            return lines.map { line in
                let (indent, body) = splitIndentFallback(line)
                guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return line }

                if shouldUncomment, body.hasPrefix(prefix) {
                    var uncommented = String(body.dropFirst(prefix.count))
                    if uncommented.hasPrefix(" ") {
                        uncommented.removeFirst()
                    }
                    return "\(indent)\(uncommented)"
                }

                return "\(indent)\(prefix) \(body)"
            }
        }
    }

    private func wrapSelectionsFallback(left: String, right: String) {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let targetRanges = normalizedRanges(buffer.selectionRanges, in: buffer.text)
        guard !targetRanges.isEmpty else { return }

        let replacements = targetRanges.map { range in
            "\(left)\(nsText.substring(with: range.nsRange))\(right)"
        }
        var delta = 0
        let selections = zip(targetRanges, replacements).map { range, replacement in
            let selection = TextRange(location: range.location + delta + left.utf16.count, length: range.length)
            delta += replacement.utf16.count - range.length
            return selection
        }

        replaceRanges(targetRanges, replacements: replacements, selectionMode: .custom(selections))
    }

    private func insertMarkdownLinkFallback() {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let ranges = buffer.selectionRanges.isEmpty ? [.zero] : normalizedRanges(buffer.selectionRanges, in: buffer.text)
        let replacements = ranges.map { range -> String in
            let selectedText = nsText.substring(with: range.nsRange)
            let text = selectedText.isEmpty ? "link" : selectedText
            return "[\(text)](https://example.com)"
        }
        var delta = 0
        let selections = zip(ranges, replacements).map { range, replacement in
            let selectedText = nsText.substring(with: range.nsRange)
            let linkTextLength = selectedText.isEmpty ? "link".utf16.count : selectedText.utf16.count
            let selection = TextRange(location: range.location + delta + 1, length: linkTextLength)
            delta += replacement.utf16.count - range.length
            return selection
        }

        replaceRanges(ranges, replacements: replacements, selectionMode: .custom(selections))
    }

    private func insertMarkdownSnippetFallback(_ snippet: String, selectOffset: Int, selectLength: Int) {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let range = normalizedRanges(buffer.selectionRanges, in: buffer.text).last ?? .zero
        let location = min(range.location, nsText.length)
        let prefix = needsLeadingBlankLineFallback(before: location, in: nsText) ? "\n\n" : ""
        let suffix = needsTrailingBlankLineFallback(after: location + range.length, in: nsText) ? "\n\n" : ""
        let insertion = "\(prefix)\(snippet)\(suffix)"

        replaceRanges(
            [range],
            replacements: [insertion],
            selectionMode: .custom([
                TextRange(location: location + prefix.utf16.count + selectOffset, length: selectLength)
            ])
        )
    }

    private func insertCodeFenceFallback() {
        guard let selectedIndex else { return }

        let buffer = buffers[selectedIndex]
        let nsText = buffer.text as NSString
        let selectedRanges = normalizedNonEmptyRanges(buffer.selectionRanges, in: buffer.text)

        if selectedRanges.isEmpty {
            let cursor = normalizedRanges(buffer.selectionRanges, in: buffer.text).last ?? .zero
            let location = min(cursor.location, nsText.length)
            let insertion = "```\n\n```"
            replaceRanges(
                [TextRange(location: location, length: 0)],
                replacements: [insertion],
                selectionMode: .custom([TextRange(location: location + 4, length: 0)])
            )
            return
        }

        let targetRanges = mergedLineRanges(for: selectedRanges, in: buffer.text)
        let replacements = targetRanges.map { range -> String in
            let text = nsText.substring(with: range.nsRange)
            return "```\n\(text.hasSuffix("\n") ? text : "\(text)\n")```"
        }
        var delta = 0
        let selections = zip(targetRanges, replacements).map { range, replacement in
            let selection = TextRange(location: range.location + delta + 4, length: range.length)
            delta += replacement.utf16.count - range.length
            return selection
        }

        replaceRanges(targetRanges, replacements: replacements, selectionMode: .custom(selections))
    }

    private enum ReplacementSelectionMode {
        case selectReplacement
        case custom([TextRange])
    }

    private func replaceRanges(
        _ ranges: [TextRange],
        replacements: [String],
        selectionMode: ReplacementSelectionMode
    ) {
        guard ranges.count == replacements.count,
              let selectedIndex else { return }

        let text = buffers[selectedIndex].text
        let normalized = normalizedRanges(ranges, in: text)
        let mutable = NSMutableString(string: text)
        let edits = zip(normalized, replacements)
            .sorted { $0.0.location > $1.0.location }

        for (range, replacement) in edits {
            mutable.replaceCharacters(in: range.nsRange, with: replacement)
        }

        let updatedText = mutable as String
        let selections: [TextRange]
        switch selectionMode {
        case .selectReplacement:
            selections = zip(normalized, replacements).map { range, replacement in
                TextRange(location: range.location, length: replacement.utf16.count)
            }
        case .custom(let custom):
            selections = normalizedRanges(custom, in: updatedText)
        }

        buffers[selectedIndex].text = updatedText
        buffers[selectedIndex].selectionRanges = selections
        buffers[selectedIndex].isDirty = true
        buffers[selectedIndex].updatedAt = Date()
        reanchorComments(for: buffers[selectedIndex], newText: updatedText)
        persistSoon()
    }

    private func lineContentRangesFallback(intersecting range: TextRange, in nsText: NSString) -> [TextRange] {
        var output: [TextRange] = []
        var location = range.location
        let end = range.location + range.length

        while location < end {
            let lineRange = nsText.lineRange(for: NSRange(location: min(location, nsText.length), length: 0))
            let contentRange = contentRangeFallback(for: lineRange, in: nsText)
            let start = max(contentRange.location, range.location)
            let finish = min(contentRange.location + contentRange.length, end)
            output.append(TextRange(location: start, length: max(0, finish - start)))

            let nextLocation = lineRange.location + max(lineRange.length, 1)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        return output
    }

    private func contentRangeFallback(for lineRange: NSRange, in nsText: NSString) -> NSRange {
        var length = min(lineRange.length, max(0, nsText.length - lineRange.location))

        while length > 0 {
            let character = nsText.character(at: lineRange.location + length - 1)
            guard character == 10 || character == 13 else { break }
            length -= 1
        }

        return NSRange(location: lineRange.location, length: length)
    }

    private func mergeRangesFallback(_ ranges: [TextRange]) -> [TextRange] {
        ranges.sorted { first, second in
            if first.location == second.location {
                return first.length < second.length
            }
            return first.location < second.location
        }
        .reduce(into: [TextRange]()) { output, range in
            guard let last = output.last else {
                output.append(range)
                return
            }

            let lastEnd = last.location + last.length
            let rangeEnd = range.location + range.length
            if range.location <= lastEnd {
                output[output.count - 1] = TextRange(location: last.location, length: max(lastEnd, rangeEnd) - last.location)
            } else {
                output.append(range)
            }
        }
    }

    private func applyMarkdownHeadingFallback(level: Int, to line: String) -> String {
        let (indent, body) = splitIndentFallback(line)
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
        let cleaned = removeMarkdownPrefixFallback(in: body, matching: #"^#{1,6}\s+"#)
        return "\(indent)\(String(repeating: "#", count: level)) \(cleaned)"
    }

    private func toggleMarkdownLinePrefixFallback(_ prefix: String, in line: String, matching pattern: String) -> String {
        let (indent, body) = splitIndentFallback(line)
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return line }

        let cleaned = removeMarkdownPrefixFallback(in: body, matching: pattern)
        if cleaned != body {
            return "\(indent)\(cleaned)"
        }

        return "\(indent)\(prefix)\(body)"
    }

    private func splitIndentFallback(_ line: String) -> (String, String) {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        return (String(indent), String(line.dropFirst(indent.count)))
    }

    private func removeMarkdownPrefixFallback(in body: String, matching pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }

        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, range: fullRange),
              match.range.location == 0 else {
            return body
        }

        return nsBody.substring(from: match.range.length)
    }

    private func needsLeadingBlankLineFallback(before location: Int, in text: NSString) -> Bool {
        guard location > 0 else { return false }
        let prefix = text.substring(to: min(location, text.length))
        return !prefix.hasSuffix("\n\n")
    }

    private func needsTrailingBlankLineFallback(after location: Int, in text: NSString) -> Bool {
        guard location < text.length else { return false }
        let suffix = text.substring(from: max(0, location))
        return !suffix.hasPrefix("\n\n")
    }

    private func lineCommentPrefix(for language: EditorLanguage) -> String? {
        switch language {
        case .swift, .javascript, .typescript, .go, .rust:
            return "//"
        case .python, .ruby, .shell, .yaml:
            return "#"
        case .plain, .markdown, .json, .html, .css, .csv, .tsv, .image, .pdf, .hex, .drawing:
            return nil
        }
    }

    private func swapAdjacentLineTextsFallback(_ first: String, _ second: String) -> String {
        if trailingLineBreakFallback(in: second) != nil {
            return "\(second)\(first)"
        }

        if let firstBreak = trailingLineBreakFallback(in: first) {
            return "\(second)\(firstBreak)\(removingTrailingLineBreakFallback(from: first))"
        }

        return "\(second)\n\(first)"
    }

    private func firstLineOffsetAfterSwapFallback(first: String, second: String) -> Int {
        if trailingLineBreakFallback(in: second) != nil {
            return second.utf16.count
        }

        if let firstBreak = trailingLineBreakFallback(in: first) {
            return second.utf16.count + firstBreak.utf16.count
        }

        return second.utf16.count + 1
    }

    private func firstLineLengthAfterSwapFallback(first: String, second: String) -> Int {
        if trailingLineBreakFallback(in: second) != nil {
            return first.utf16.count
        }

        if trailingLineBreakFallback(in: first) != nil {
            return removingTrailingLineBreakFallback(from: first).utf16.count
        }

        return first.utf16.count
    }

    private func trailingLineBreakFallback(in text: String) -> String? {
        if text.hasSuffix("\r\n") { return "\r\n" }
        if text.hasSuffix("\n") { return "\n" }
        if text.hasSuffix("\r") { return "\r" }
        return nil
    }

    private func removingTrailingLineBreakFallback(from text: String) -> String {
        if text.hasSuffix("\r\n") { return String(text.dropLast(2)) }
        if text.hasSuffix("\n") || text.hasSuffix("\r") { return String(text.dropLast()) }
        return text
    }

    private nonisolated static func suggestedSaveBaseName(for buffer: EditorBuffer) -> String {
        let title = buffer.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !isDefaultScratchTitle(title) {
            return sanitizedFileBaseName((title as NSString).deletingPathExtension) ?? "Untitled"
        }

        if let textName = suggestedTextFileName(from: buffer.text) {
            return textName
        }

        return "Untitled"
    }

    private nonisolated static func aiFileNameCandidate(from response: String) -> String {
        if let data = response.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["fileName", "filename", "name", "title"] {
                if let value = object[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }

        let withoutFence = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        let firstLine = withoutFence
            .components(separatedBy: .newlines)
            .first ?? withoutFence
        return firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
    }

    private nonisolated static func suggestedTextFileName(from text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let heading = trimmed.replacingOccurrences(
                of: #"^#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
            return sanitizedFileBaseName(heading)
        }

        return nil
    }

    private nonisolated static func sanitizedFileBaseName(_ rawName: String) -> String? {
        let replaced = rawName.map { character -> Character in
            switch character {
            case "/", ":", "\0":
                return " "
            default:
                return character
            }
        }
        let collapsed = String(replaced)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(60))
    }

    private nonisolated static func isDefaultScratchTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        guard lower.hasPrefix("scratch ") else { return false }
        return lower.dropFirst("scratch ".count).allSatisfy { $0.isNumber }
    }

    private nonisolated static func detectEncryptedDocumentLanguage(url: URL, text: String) -> EditorLanguage {
        let originalFileName = url.deletingPathExtension().lastPathComponent
        let fileNameForDetection = (originalFileName as NSString).pathExtension.isEmpty ? nil : originalFileName
        return EditorLanguage.detect(fileName: fileNameForDetection, text: text)
    }

    private func documentKey(for buffer: EditorBuffer) -> String {
        if let path = buffer.filePath {
            return "file:\(fileIdentity(forPath: path))"
        }

        return "scratch:\(buffer.id.uuidString)"
    }

    private func filePath(fromDocumentKey documentKey: String) -> String? {
        guard documentKey.hasPrefix("file:") else { return nil }
        return String(documentKey.dropFirst("file:".count))
    }

    private func normalizedRange(_ range: TextRange, in text: String) -> TextRange {
        normalizedRanges([range], in: text).first ?? .zero
    }

    private func rekeyComments(from oldKey: String, to newKey: String) {
        guard oldKey != newKey else { return }

        var changed = false
        for index in documentComments.indices where documentComments[index].documentKey == oldKey {
            documentComments[index].documentKey = newKey
            documentComments[index].updatedAt = Date()
            changed = true
        }

        if changed {
            persistCommentsSoon()
        }
    }

    private func reanchorComments(for buffer: EditorBuffer, newText: String) {
        let key = documentKey(for: buffer)
        guard documentComments.contains(where: { $0.documentKey == key && !$0.isResolved }) else { return }

        let nsNewText = newText as NSString
        var changed = false

        for index in documentComments.indices where documentComments[index].documentKey == key && !documentComments[index].isResolved {
            let comment = documentComments[index]
            let normalized = normalizedRange(comment.range, in: newText)

            if normalized.length > 0,
               normalized.location + normalized.length <= nsNewText.length,
               nsNewText.substring(with: normalized.nsRange) == comment.quote {
                if normalized != comment.range {
                    documentComments[index].range = normalized
                    documentComments[index].updatedAt = Date()
                    changed = true
                }
                continue
            }

            if !comment.quote.isEmpty {
                let found = nsNewText.range(of: comment.quote)
                if found.location != NSNotFound {
                    let updatedRange = TextRange(found)
                    if updatedRange != comment.range {
                        documentComments[index].range = updatedRange
                        documentComments[index].updatedAt = Date()
                        changed = true
                    }
                    continue
                }
            }

            let fallback = TextRange(
                location: min(max(0, normalized.location), nsNewText.length),
                length: min(normalized.length, max(0, nsNewText.length - normalized.location))
            )
            if fallback != comment.range {
                documentComments[index].range = fallback
                documentComments[index].updatedAt = Date()
                changed = true
            }
        }

        if changed {
            persistCommentsSoon()
        }
    }

    private func normalizedRanges(_ ranges: [TextRange], in text: String) -> [TextRange] {
        let length = (text as NSString).length
        return ranges.map { range in
            let location = min(max(0, range.location), length)
            return TextRange(location: location, length: min(max(0, range.length), length - location))
        }
    }

    private func normalizedNonEmptyRanges(_ ranges: [TextRange], in text: String) -> [TextRange] {
        normalizedRanges(ranges, in: text)
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
    }

    private func mergedLineRanges(for ranges: [TextRange], in text: String) -> [TextRange] {
        let nsText = text as NSString
        let lineRanges = ranges.map { TextRange(nsText.lineRange(for: $0.nsRange)) }
            .sorted { $0.location < $1.location }

        var merged: [TextRange] = []
        for range in lineRanges {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            let lastEnd = last.location + last.length
            let rangeEnd = range.location + range.length
            if range.location <= lastEnd {
                merged[merged.count - 1] = TextRange(location: last.location, length: max(lastEnd, rangeEnd) - last.location)
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    private func preserveTrailingNewline(_ text: String, transform: ([String]) -> [String]) -> String {
        let hasTrailingNewline = text.hasSuffix("\n") || text.hasSuffix("\r")
        var lines = text.components(separatedBy: .newlines)
        if hasTrailingNewline, lines.last == "" {
            lines.removeLast()
        }

        let output = transform(lines).joined(separator: "\n")
        return hasTrailingNewline ? "\(output)\n" : output
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }

    func swappingCase() -> String {
        map { character in
            let value = String(character)
            let uppercased = value.uppercased()
            let lowercased = value.lowercased()

            if value == uppercased, value != lowercased {
                return lowercased
            }

            if value == lowercased, value != uppercased {
                return uppercased
            }

            return value
        }
        .joined()
    }
}
