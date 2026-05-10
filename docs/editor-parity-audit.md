# SimpleLime Typora/Sublime Parity Audit

Current status: completion audit passed for the requested high-value Typora/Sublime parity scope: stable WYSIWYG Markdown, local image rendering, Mermaid/math/table/list behavior, folder catalog, minimap, search/replace, and compact UI controls are implemented and covered by automated tests plus manual screenshots.

This checklist maps the requested Typora/Sublime gaps to concrete implementation and verification artifacts.

## Markdown / Typora Surface

| Requirement | Status | Evidence |
| --- | --- | --- |
| WYSIWYG Markdown mode | Implemented | `Sources/SimpleLime/Views/MarkdownWYSIWYGEditorView.swift`; mode wiring in `Sources/SimpleLime/Stores/EditorStore.swift` |
| Local and remote images, including raw HTML images and paths with spaces | Implemented and tested | `MarkdownWYSIWYGEditorViewTests.testAbsoluteMarkdownImageWithSpacesLoadsThroughLocalImageScheme`, `testRelativeMarkdownImageLoadsThroughLocalImageScheme`, `testTypingMarkdownImageAutoNormalizesAndLoadsWithoutModeToggle`, `testMarkdownVisualFixtureRendersCoreBlocksAndLocalImages` |
| Mermaid and math render without mode toggling | Implemented with offline fallbacks and tested | `testTypingMermaidAndMathAutoNormalizesWithoutModeToggle`, `testOfflineMermaidFallbackDrawsGraphAndSequenceSVG`, `testOfflineMathFallbackRendersStructuredFormula` |
| Tables, table editing controls, callouts, front matter, TOC, footnotes, references, inline extensions | Implemented and tested | `testTableToolbarActionsUpdateMarkdownStructureAndAlignment`, `testFrontMatterAndFootnotesAutoNormalizeWithoutModeToggle`, `testReferenceLinksImagesAndAutolinksRoundTrip`, `testTyporaInlineExtensionsRoundTripToMarkdown` |
| Nested lists and keyboard indentation | Implemented and tested | `testNestedListsRenderAndRoundTripWithIndentation`, `testTabAndShiftTabIndentListItemWithoutMovingFocus`, `testCommandBracketIndentsAndOutdentsListItem`, `testEnterOnNestedListItemCreatesSameLevelBulletAndKeepsFocus` |
| Caret does not jump to document start after normalization | Implemented and tested | `testNormalizingHeadingDoesNotMoveCaretToStart`, `testNormalizingMermaidFenceDoesNotMoveCaretToStart`, `testTypingVisualFixtureAutoNormalizesWithoutModeToggleOrCaretReset` |
| WYSIWYG search/navigation scrolls to selected source offset | Implemented and tested | `testFindNextSelectionOffsetScrollsWysiwygViewportToMatch`, `testRenderedSelectionReportsMarkdownSourceOffset` |
| Visual QA fixture covering Markdown edge cases | Implemented and manually checked | `docs/markdown-visual-fixture.md` and `docs/assets/*`; source screenshot `/tmp/simplelime-source-images-sweep.png`, split preview screenshot `/tmp/simplelime-preview-images-sweep.png`, WYSIWYG screenshots `/tmp/simplelime-visual-fixture-wysiwyg.png`, `/tmp/simplelime-visual-fixture-wysiwyg-after-click-scroll.png`, `/tmp/simplelime-wysiwyg-media-sweep.png`, `/tmp/simplelime-wysiwyg-mermaid-math-sweep.png` |

## Sublime-Like Editing Surface

| Requirement | Status | Evidence |
| --- | --- | --- |
| Find, replace, regex, whole-word, match-case | Implemented and tested | `EditorStoreSearchTests.testWholeWordAndMatchCaseSelectAllMatches`, `testRegexReplaceAllUsesCaptureGroupsAndMatchCase`, `testInvalidRegexReportsStatusAndDoesNotMoveSelection` |
| Find/replace in opened folder | Implemented and tested | `testGlobalSearchIncludesDocumentCatalogFilesAndOpensResult`, `testGlobalReplaceUpdatesOpenBuffersAndClosedCatalogFiles`, `testGlobalReplaceUsesRegexCaptureGroupsAndWholeWord` |
| Text transforms | Implemented and tested | `EditorStoreTextTransformTests.testInlineTransformsApplyToSelectedTextOnly`, `testLineTransformsUseSelectedLinesAndPreserveTrailingNewline`, `testTrimJoinAndDuplicateLineFallbacks` |
| Minimap | Implemented and tested at layout/store level | `EditorMiniMapLayoutTests.*`, `EditorStoreDocumentCatalogTests.testJumpToLineUpdatesSelectionForMiniMapNavigation` |
| Folder as document catalog | Implemented and tested | `DocumentCatalogView`, `DocumentCatalogNode`, `EditorStoreDocumentCatalogTests.testOpenFolderBuildsDocumentCatalogAndSkipsIgnoredDirectories` |
| Command palette with file fuzzy navigation and `:line` | Implemented, tested, and manually checked | `ContentView.documentCatalogCommands`, `EditorStoreDocumentCatalogTests.testDocumentCatalogFileMatchesUseFuzzyPathSearch`; manual `fixture` query screenshot captured at `/tmp/simplelime-command-palette-fixture-current.png` |
| Mode shortcuts and mutual exclusion for WYSIWYG/minimap/focus | Implemented and tested | `EditorStoreModeTests.*`; shortcuts documented in `README.md` |
| Typewriter mode has visible editor behavior | Implemented and tested | Source editor centers the active line through `CodeEditorView.centerSelectionForTypewriterModeIfNeeded`; WYSIWYG toggles `body.typewriter`; `MarkdownWYSIWYGEditorViewTests.testTypewriterModeTogglesWysiwygBodyClassWithoutReload` |

## UI / Interaction Polish

| Requirement | Status | Evidence |
| --- | --- | --- |
| Footer uses icons and does not grow because of long file path | Implemented and tested | `StatusBarView` in `Sources/SimpleLime/Views/EditorWorkspaceView.swift`; `StatusBarDensityTests.*` |
| Outline sidebar is opaque/readable | Implemented | `MarkdownOutlineView` background uses control background colors |
| Small window does not place tabs under traffic lights or cut footer | Implemented, tested at status-density level, and manually checked | `TabBarControl.resolvedLeadingInset`; `StatusBarDensityTests.testSmallWindowsUseIconOnlyMinimalStatusBar`; manual window screenshots captured at `/tmp/simplelime-small-window-current.png` and `/tmp/simplelime-tiny-window-current.png` |
| Single drag on tab moves window; double-click drag starts tab move | Implemented | `TabBarControl.mouseDown(with:)` |

## Current Gates

| Gate | Last observed result |
| --- | --- |
| Unit/integration tests | `swift test` passed, 68 tests |
| Diff whitespace | `git diff --check` passed |
| App build/run smoke | `./script/build_and_run.sh --verify` passed |

## Completion Checklist

| Explicit objective item | Evidence |
| --- | --- |
| Stable WYSIWYG Markdown behavior | WYSIWYG tests cover live normalization, caret preservation, rendered selection offsets, list/table edits, and round-tripping in `MarkdownWYSIWYGEditorViewTests` |
| Images render, including local paths and spaces | Automated tests for absolute, relative, raw HTML, reference, typed, pasted, and fixture images; manual screenshot `/tmp/simplelime-wysiwyg-media-sweep.png` |
| Mermaid/math and rich Markdown variants render without mode toggles | Automated tests for typed Mermaid/math, offline fallbacks, tables, callouts, front matter, footnotes, references, and Typora inline extensions; manual Mermaid screenshot `/tmp/simplelime-wysiwyg-mermaid-math-sweep.png` |
| Sublime-style folder catalog, minimap, search, replace, regex, and transforms | `EditorStoreDocumentCatalogTests`, `EditorMiniMapLayoutTests`, `EditorStoreSearchTests`, and `EditorStoreTextTransformTests` |
| UI is predictable in constrained windows | `StatusBarDensityTests`; manual screenshots `/tmp/simplelime-small-window-current.png` and `/tmp/simplelime-tiny-window-current.png` |
| Critical scenarios are covered by tests or manual verification | `swift test` suite plus manual screenshots listed in this document |

## Residual Non-Goal Risks

- There are no dedicated AppKit drag UI tests for tab dragging or window dragging; those are manually verified.
- This does not claim literal full Typora/Sublime product parity for plugin ecosystems, every export workflow, every Sublime command, or third-party theme compatibility.
