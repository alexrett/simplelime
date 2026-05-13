import Foundation

enum SourceEditorFeature: String, CaseIterable, Codable, Equatable, Hashable {
    case textEditing
    case multipleSelections
    case columnSelection
    case selectionReporting
    case commandRouting
    case visibleRangeReporting
    case syntaxHighlighting
    case structuredFolding
    case comments
    case collaborationSelections
    case findReplaceBridge
    case minimapSource
    case macrosTemplates
    case formattingCommands
    case largeFileSearchJump
    case readOnlyTemporaryMode
    case diagnostics
    case largeFileChunkEditing
    case largeFileFullEditing

    var title: String {
        switch self {
        case .textEditing:
            return "Source text editing"
        case .multipleSelections:
            return "Multiple selections"
        case .columnSelection:
            return "Column selection"
        case .selectionReporting:
            return "Selection reporting"
        case .commandRouting:
            return "Command routing"
        case .visibleRangeReporting:
            return "Visible range reporting"
        case .syntaxHighlighting:
            return "Syntax highlighting"
        case .structuredFolding:
            return "Structured folding"
        case .comments:
            return "Comments"
        case .collaborationSelections:
            return "Collaboration selections"
        case .findReplaceBridge:
            return "Find/replace bridge"
        case .minimapSource:
            return "Minimap source"
        case .macrosTemplates:
            return "Macros/templates"
        case .formattingCommands:
            return "Formatting commands"
        case .largeFileSearchJump:
            return "Large-file search/jump"
        case .readOnlyTemporaryMode:
            return "Read-only/temp mode"
        case .diagnostics:
            return "Diagnostics"
        case .largeFileChunkEditing:
            return "Large-file chunk editing"
        case .largeFileFullEditing:
            return "Large-file full editing"
        }
    }
}

enum SourceEditorEngine: String, CaseIterable, Codable, Equatable, Identifiable {
    case nativeSTTextView
    case codeMirrorWebViewPrototype

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nativeSTTextView:
            return "Native STTextView"
        case .codeMirrorWebViewPrototype:
            return "CodeMirror 6 WebView Prototype"
        }
    }

    var isPrototypeReplacement: Bool {
        switch self {
        case .nativeSTTextView:
            return false
        case .codeMirrorWebViewPrototype:
            return true
        }
    }

    var supportedFeatures: Set<SourceEditorFeature> {
        switch self {
        case .nativeSTTextView:
            return [
                .textEditing,
                .multipleSelections,
                .columnSelection,
                .selectionReporting,
                .commandRouting,
                .visibleRangeReporting,
                .syntaxHighlighting,
                .structuredFolding,
                .comments,
                .collaborationSelections,
                .findReplaceBridge,
                .minimapSource,
                .macrosTemplates,
                .formattingCommands,
                .largeFileSearchJump,
                .readOnlyTemporaryMode,
                .diagnostics,
                .largeFileChunkEditing
            ]
        case .codeMirrorWebViewPrototype:
            return [
                .textEditing,
                .multipleSelections,
                .selectionReporting,
                .commandRouting,
                .visibleRangeReporting,
                .syntaxHighlighting,
                .comments,
                .collaborationSelections,
                .findReplaceBridge,
                .formattingCommands,
                .readOnlyTemporaryMode,
                .diagnostics
            ]
        }
    }

    func supports(_ feature: SourceEditorFeature) -> Bool {
        supportedFeatures.contains(feature)
    }
}

struct SourceEditorConfiguration: Equatable {
    var engine: SourceEditorEngine
    var language: EditorLanguage
    var fontSize: Double
    var wrapsLines: Bool
    var columnGuide: Int
    var foldedRanges: [StructuredFoldRange]
    var syntaxHighlightingEnabled: Bool
    var isEditable: Bool
    var focusModeEnabled: Bool
    var typewriterModeEnabled: Bool

    init(
        engine: SourceEditorEngine = .nativeSTTextView,
        language: EditorLanguage,
        fontSize: Double,
        wrapsLines: Bool,
        columnGuide: Int,
        foldedRanges: [StructuredFoldRange] = [],
        syntaxHighlightingEnabled: Bool = true,
        isEditable: Bool = true,
        focusModeEnabled: Bool,
        typewriterModeEnabled: Bool
    ) {
        self.engine = engine
        self.language = language
        self.fontSize = fontSize
        self.wrapsLines = wrapsLines
        self.columnGuide = columnGuide
        self.foldedRanges = foldedRanges
        self.syntaxHighlightingEnabled = syntaxHighlightingEnabled
        self.isEditable = isEditable
        self.focusModeEnabled = focusModeEnabled
        self.typewriterModeEnabled = typewriterModeEnabled
    }

    var renderPath: String {
        "\(engine.title) source editor"
    }

    var isReadOnly: Bool {
        !isEditable
    }
}

enum SourceEditorAcceptanceGateStatus: String, Codable, Equatable {
    case pass
    case warning
    case manual
    case fail

    var title: String {
        switch self {
        case .pass:
            return "Pass"
        case .warning:
            return "Warning"
        case .manual:
            return "Manual"
        case .fail:
            return "Fail"
        }
    }
}

struct SourceEditorAcceptanceGateCheck: Equatable {
    var title: String
    var status: SourceEditorAcceptanceGateStatus
    var evidence: String
    var nextAction: String
}

struct SourceEditorAcceptanceGateContext: Equatable {
    var language: EditorLanguage
    var isLargeFileMode: Bool
    var fileSizeBytes: Int64
    var loadedByteCount: Int
    var lineCount: Int
    var wouldUseLargeFileMode: Bool
    var isMiniMapVisible: Bool
    var canSaveLargeFileChunkBack: Bool
    var hasLargeFileSourcePath: Bool
}

enum SourceEditorAcceptanceGate {
    static func evaluate(_ context: SourceEditorAcceptanceGateContext) -> [SourceEditorAcceptanceGateCheck] {
        [
            openLargeFileGate(context),
            wholeFileNavigationGate(context),
            typingLatencyGate(context),
            selectionGate(context),
            boundedDecorationGate(context),
            featureContractGate(context),
            largeFilePolicyGate(context),
            fullVirtualEditingGate(context)
        ]
    }

    private static func openLargeFileGate(_ context: SourceEditorAcceptanceGateContext) -> SourceEditorAcceptanceGateCheck {
        if context.wouldUseLargeFileMode && !context.isLargeFileMode {
            return SourceEditorAcceptanceGateCheck(
                title: "Open large files without UI blocking",
                status: .fail,
                evidence: "Metadata says this buffer should use large-file mode, but it is loaded in the normal source editor.",
                nextAction: "Reopen through the large-file path before profiling."
            )
        }

        if context.isLargeFileMode {
            return SourceEditorAcceptanceGateCheck(
                title: "Open large files without UI blocking",
                status: .pass,
                evidence: "Large-file mode keeps the loaded buffer bounded and defers full-file work to virtual indexes.",
                nextAction: "Verify visible pause in the real app with telemetry when GUI testing is allowed."
            )
        }

        return SourceEditorAcceptanceGateCheck(
            title: "Open large files without UI blocking",
            status: .pass,
            evidence: "Current buffer is below the configured large-file policy for this language.",
            nextAction: "No large-file open action for this buffer."
        )
    }

    private static func wholeFileNavigationGate(_ context: SourceEditorAcceptanceGateContext) -> SourceEditorAcceptanceGateCheck {
        if context.isLargeFileMode {
            if context.hasLargeFileSourcePath {
                return SourceEditorAcceptanceGateCheck(
                    title: "Whole-file navigation",
                    status: .pass,
                    evidence: "Virtual source metadata is present, so line jumps/search can address the source file beyond the loaded chunk.",
                    nextAction: "Use line jump/search for full-file navigation; edit through exact chunks."
                )
            }
            return SourceEditorAcceptanceGateCheck(
                title: "Whole-file navigation",
                status: .warning,
                evidence: "Large-file mode is active, but source metadata is missing.",
                nextAction: "Reopen the file from disk to restore virtual source metadata."
            )
        }

        return SourceEditorAcceptanceGateCheck(
            title: "Whole-file navigation",
            status: .pass,
            evidence: "Normal source buffers keep the loaded document directly navigable.",
            nextAction: "Use regular find and line navigation."
        )
    }

    private static func typingLatencyGate(_ context: SourceEditorAcceptanceGateContext) -> SourceEditorAcceptanceGateCheck {
        SourceEditorAcceptanceGateCheck(
            title: "Typing latency under 32 ms p95",
            status: .manual,
            evidence: "Headless tests cover model/index/highlight work, and the live smoke script can collect p95 key/text/selection telemetry from a built app.",
            nextAction: "Run script/editor_live_latency_smoke.sh and inspect EditorPerformance p95 metrics."
        )
    }

    private static func selectionGate(_ context: SourceEditorAcceptanceGateContext) -> SourceEditorAcceptanceGateCheck {
        if context.isLargeFileMode {
            return SourceEditorAcceptanceGateCheck(
                title: "Selection and autoscroll",
                status: .warning,
                evidence: "The virtual full-file preview intentionally avoids editable text selection; selection QA applies to opened chunks.",
                nextAction: "Open an editable chunk and test shift-selection across viewport boundaries."
            )
        }

        return SourceEditorAcceptanceGateCheck(
            title: "Selection and autoscroll",
            status: .pass,
            evidence: "Source tests cover empty-area click fallback, cached line metrics, and selection scroll-to-range paths.",
            nextAction: "Confirm in the real app for representative files before accepting the core."
        )
    }

    private static func boundedDecorationGate(_ context: SourceEditorAcceptanceGateContext) -> SourceEditorAcceptanceGateCheck {
        if context.isLargeFileMode {
            return SourceEditorAcceptanceGateCheck(
                title: "Bounded syntax/fold/minimap work",
                status: .pass,
                evidence: "Large-file mode uses visible virtual rows and disables fold/minimap paths that touch the full loaded text.",
                nextAction: "Keep large-file decoration work visible-range bounded."
            )
        }

        if context.lineCount >= 20_000 || context.isMiniMapVisible && context.lineCount >= 10_000 {
            return SourceEditorAcceptanceGateCheck(
                title: "Bounded syntax/fold/minimap work",
                status: .warning,
                evidence: "A large normal buffer can still amplify source-editor decoration and minimap work.",
                nextAction: "Prefer large-file mode or profile this buffer with EditorPerformance signposts."
            )
        }

        return SourceEditorAcceptanceGateCheck(
            title: "Bounded syntax/fold/minimap work",
            status: .pass,
            evidence: "The current buffer is within the normal source path, with debounced syntax and cached line metrics.",
            nextAction: "Keep syntax and folding off the keystroke hot path."
        )
    }

    private static func featureContractGate(_ context: SourceEditorAcceptanceGateContext) -> SourceEditorAcceptanceGateCheck {
        if context.isLargeFileMode {
            return SourceEditorAcceptanceGateCheck(
                title: "Feature contract preservation",
                status: .warning,
                evidence: "Large-file preview preserves navigation/search/chunk editing and a single-line virtual replace primitive, but comments and collaboration selections remain chunk-only.",
                nextAction: "Use the compatibility matrix to choose which integrations a replacement core must support."
            )
        }

        return SourceEditorAcceptanceGateCheck(
            title: "Feature contract preservation",
            status: .pass,
            evidence: "The native source editor advertises the current source editing, comments, collaboration, macro, folding, minimap, and formatting contracts.",
            nextAction: "Keep replacement prototypes behind the same SourceEditorView contract."
        )
    }

    private static func largeFilePolicyGate(_ context: SourceEditorAcceptanceGateContext) -> SourceEditorAcceptanceGateCheck {
        if context.wouldUseLargeFileMode && !context.isLargeFileMode {
            return SourceEditorAcceptanceGateCheck(
                title: "Clear large-file policy",
                status: .fail,
                evidence: "The policy says this buffer should be virtualized, but the active buffer is normal source text.",
                nextAction: "Force the safe large-file path for this file type and size."
            )
        }

        if context.isLargeFileMode {
            let saveBack = context.canSaveLargeFileChunkBack ? "save-back metadata is present" : "save-back metadata is missing"
            return SourceEditorAcceptanceGateCheck(
                title: "Clear large-file policy",
                status: .pass,
                evidence: "Policy is explicit: read-only virtual browsing, bounded chunks, and file-backed single-line virtual replacement; \(saveBack).",
                nextAction: "Expose full-file editing only after a true virtual editable model exists."
            )
        }

        return SourceEditorAcceptanceGateCheck(
            title: "Clear large-file policy",
            status: .pass,
            evidence: "Normal editing is allowed by current file size and language policy.",
            nextAction: "No large-file policy action for this buffer."
        )
    }

    private static func fullVirtualEditingGate(_ context: SourceEditorAcceptanceGateContext) -> SourceEditorAcceptanceGateCheck {
        if context.isLargeFileMode || context.wouldUseLargeFileMode {
            return SourceEditorAcceptanceGateCheck(
                title: "Full-file virtual editing",
                status: .fail,
                evidence: "The current implementation does not provide a true editable full-file virtual document model.",
                nextAction: "Prototype CodeMirror or Scintilla behind SourceEditorView, or build a custom virtual editor only if those fail."
            )
        }

        return SourceEditorAcceptanceGateCheck(
            title: "Full-file virtual editing",
            status: .manual,
            evidence: "This buffer does not exercise the large-file editable model requirement.",
            nextAction: "Evaluate this gate with a large JSON/text fixture."
        )
    }
}

enum SourceEditorWebSelection {
    static func normalizedRanges(_ ranges: [TextRange], textLength: Int) -> [TextRange] {
        let textLength = max(0, textLength)
        let sourceRanges = ranges.isEmpty ? [.zero] : ranges
        return sourceRanges.map { range in
            let location = min(max(0, range.location), textLength)
            let length = min(max(0, range.length), textLength - location)
            return TextRange(location: location, length: length)
        }
    }
}

struct SourceEditorDecorations: Equatable {
    var comments: [DocumentComment]
    var activeCommentID: UUID?
    var collaborators: [RemoteCollaborator]

    init(
        comments: [DocumentComment] = [],
        activeCommentID: UUID? = nil,
        collaborators: [RemoteCollaborator] = []
    ) {
        self.comments = comments
        self.activeCommentID = activeCommentID
        self.collaborators = collaborators
    }

    func webDecorations(textLength: Int) -> [SourceEditorWebDecoration] {
        let textLength = max(0, textLength)
        var output: [SourceEditorWebDecoration] = []

        for comment in comments where !comment.isResolved {
            let range = normalizedRange(comment.range, textLength: textLength)
            guard range.length > 0 else { continue }
            output.append(
                SourceEditorWebDecoration(
                    kind: comment.id == activeCommentID ? .activeComment : .comment,
                    range: range,
                    color: nil,
                    label: comment.displayQuote
                )
            )
        }

        for collaborator in collaborators {
            for selection in collaborator.selectionRanges {
                let range = normalizedRange(selection, textLength: textLength)
                if range.length > 0 {
                    output.append(
                        SourceEditorWebDecoration(
                            kind: .collaboratorSelection,
                            range: range,
                            color: collaborator.cssColor,
                            label: collaborator.name
                        )
                    )
                } else if range.location <= textLength {
                    output.append(
                        SourceEditorWebDecoration(
                            kind: .collaboratorCaret,
                            range: range,
                            color: collaborator.cssColor,
                            label: collaborator.name
                        )
                    )
                }
            }
        }

        return output
    }

    private func normalizedRange(_ range: TextRange, textLength: Int) -> TextRange {
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return TextRange(location: location, length: length)
    }
}

enum SourceEditorWebDecorationKind: String, Codable, Equatable {
    case comment
    case activeComment
    case collaboratorSelection
    case collaboratorCaret
}

struct SourceEditorWebDecoration: Codable, Equatable {
    var kind: SourceEditorWebDecorationKind
    var range: TextRange
    var color: String?
    var label: String?
}
