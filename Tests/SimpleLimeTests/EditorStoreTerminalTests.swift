import XCTest
@testable import SimpleLime

@MainActor
final class EditorStoreTerminalTests: XCTestCase {
    func testNewTerminalStartsInSelectedFileDirectory() throws {
        let rootURL = try makeTemporaryDirectory()
        let fileURL = rootURL.appendingPathComponent("notes.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        var buffer = EditorBuffer.scratch(index: 1)
        buffer.title = fileURL.lastPathComponent
        buffer.kind = .file
        buffer.filePath = fileURL.path

        var startedDirectory: URL?
        let store = makeStore(buffer: buffer) { workingDirectory, _, _ in
            startedDirectory = workingDirectory
            return FakeTerminalProcess()
        }

        store.createTerminalSession()

        XCTAssertEqual(startedDirectory?.standardizedFileURL, rootURL.standardizedFileURL)
        XCTAssertTrue(store.isTerminalPanelVisible)
        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertEqual(store.terminalSessions.first?.workingDirectoryPath, rootURL.standardizedFileURL.path)
    }

    func testScratchTerminalStartsInDocumentCatalogRootWhenAvailable() throws {
        let rootURL = try makeTemporaryDirectory()
        let store = makeStore { _, _, _ in FakeTerminalProcess() }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()

        XCTAssertEqual(store.terminalSessions.first?.workingDirectoryPath, rootURL.standardizedFileURL.path)
    }

    func testTerminalInputAndCloseRouteToProcess() {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, _, _ in
            let fake = FakeTerminalProcess()
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.sendInputToTerminal(sessionID, input: "pwd\r")
        store.closeTerminalSession(sessionID)

        XCTAssertEqual(fakeProcess?.sentInput, ["pwd\r"])
        XCTAssertEqual(fakeProcess?.didStop, true)
        XCTAssertFalse(store.isTerminalPanelVisible)
        XCTAssertTrue(store.terminalSessions.isEmpty)
    }

    func testTerminalInterruptSendsControlCToProcess() {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, _, _ in
            let fake = FakeTerminalProcess()
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id

        store.interruptTerminalSession(sessionID)

        XCTAssertEqual(fakeProcess?.sentInput, ["\u{3}"])
    }

    func testTerminalResetClearsOutputAndSendsSaneResetCommand() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, _ in
            let fake = FakeTerminalProcess(onOutput: onOutput)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        fakeProcess?.emit("broken tui state")
        await Task.yield()

        store.resetTerminalSession(sessionID)

        XCTAssertEqual(fakeProcess?.sentInput, ["\u{3}", "stty sane 2>/dev/null; reset\r"])
        XCTAssertEqual(store.terminalSessions[0].output, "")
        XCTAssertTrue(store.terminalSessions[0].rawOutputData.isEmpty)
        XCTAssertEqual(store.terminalSessions[0].clearGeneration, 1)
    }

    func testTerminalDiagnosticsSendEscapeAndUTF8SmokeScriptToSelectedPTY() {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, _, _ in
            let fake = FakeTerminalProcess()
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id

        store.runTerminalDiagnostics(sessionID)

        let input = fakeProcess?.sentInput.joined() ?? ""
        XCTAssertTrue(input.contains("[SimpleLime terminal diagnostics]"), input)
        XCTAssertTrue(input.contains("stty size < /dev/tty"), input)
        XCTAssertTrue(input.contains(#"\033]0;SimpleLime Terminal Diagnostics\007"#), input)
        XCTAssertTrue(input.contains(#"\033[?1049h"#), input)
        XCTAssertTrue(input.contains(#"\033[4;12Hcursor addressing OK"#), input)
        XCTAssertTrue(input.contains("python3 \"$__simplelime_py\" < /dev/tty"), input)
        XCTAssertTrue(input.contains("SimpleLime curses diagnostic"), input)
        XCTAssertTrue(input.contains("utf8: Кириллица — ✓"), input)
        XCTAssertTrue(input.contains("[SimpleLime terminal diagnostics complete]"), input)
    }

    func testTerminalRestartStopsOldProcessAndIgnoresLateExit() async {
        var startedDirectories: [URL] = []
        var processes: [FakeTerminalProcess] = []
        let store = makeStore { workingDirectory, onOutput, onExit in
            startedDirectories.append(workingDirectory)
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            processes.append(fake)
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        processes[0].emit("broken tui state")
        await Task.yield()

        store.restartTerminalSession(sessionID)
        await Task.yield()

        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(startedDirectories[1].standardizedFileURL, startedDirectories[0].standardizedFileURL)
        XCTAssertTrue(processes[0].didStop)
        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertEqual(store.selectedTerminalSessionID, sessionID)
        XCTAssertEqual(store.terminalSessions[0].output, "")
        XCTAssertTrue(store.terminalSessions[0].rawOutputData.isEmpty)
        XCTAssertEqual(store.terminalSessions[0].clearGeneration, 1)
        XCTAssertTrue(store.terminalSessions[0].isRunning)
        XCTAssertNil(store.terminalSessions[0].lastExitStatus)

        processes[0].exit(0)
        await Task.yield()
        XCTAssertTrue(store.terminalSessions[0].isRunning)

        store.sendInputToTerminal(sessionID, input: "echo after-restart\r")
        XCTAssertEqual(processes[0].sentInput, [])
        XCTAssertEqual(processes[1].sentInput, ["echo after-restart\r"])

        processes[1].exit(0)
        await Task.yield()
        XCTAssertFalse(store.terminalSessions[0].isRunning)
        XCTAssertEqual(store.terminalSessions[0].lastExitStatus, 0)
    }

    func testTerminalOutputAndExitUpdateSession() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        fakeProcess?.emit("hello\n")
        await Task.yield()

        XCTAssertEqual(store.terminalSessions.first?.output, "hello\n")

        fakeProcess?.exit(7)
        await Task.yield()

        XCTAssertEqual(store.terminalSessions.first?.isRunning, false)
        XCTAssertEqual(store.terminalSessions.first?.lastExitStatus, 7)
        XCTAssertTrue(store.terminalSessions.first?.output.contains("Process exited with status 7") == true)
    }

    func testTerminalOutputStripsANSIPromptSequences() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        fakeProcess?.emit("\u{1B}[49m\u{1B}[39m\u{1B}[38;2;87;199;255m~/docs\u{1B}[0m\u{1B}]2;title\u{7}\u{1B}[?2004h")
        await Task.yield()

        XCTAssertEqual(store.terminalSessions.first?.output, "~/docs")
    }

    func testTerminalOutputHandlesSplitANSISequence() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        fakeProcess?.emit("\u{1B}[38;2")
        await Task.yield()
        fakeProcess?.emit(";87;199;255mvisible")
        await Task.yield()

        XCTAssertEqual(store.terminalSessions.first?.output, "visible")
    }

    func testTerminalOutputHandlesCarriageReturnLineRewrite() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        fakeProcess?.emit("first\rsecond\n")
        await Task.yield()

        XCTAssertEqual(store.terminalSessions.first?.output, "second\n")
    }

    func testTerminalOutputPreservesCRLFCommandOutput() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        fakeProcess?.emit("tree\r\nfolder\r\n")
        await Task.yield()

        XCTAssertEqual(store.terminalSessions.first?.output, "tree\nfolder\n")
    }

    func testTerminalOutputPreservesSplitCRLFCommandOutput() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        fakeProcess?.emit("tree\r")
        await Task.yield()
        fakeProcess?.emit("\nfolder\r")
        await Task.yield()
        fakeProcess?.emit("\n")
        await Task.yield()

        XCTAssertEqual(store.terminalSessions.first?.output, "tree\nfolder\n")
    }

    func testTerminalRawOutputObserverReceivesReplayAndFutureOutput() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        fakeProcess?.emit("\u{1B}[31mred\u{1B}[39m")
        await Task.yield()

        var observed: [String] = []
        let observerID = store.registerTerminalOutputObserver(for: sessionID) { output in
            observed.append(String(decoding: output, as: UTF8.self))
        }

        fakeProcess?.emit("\r\nnext")
        await Task.yield()
        store.unregisterTerminalOutputObserver(observerID, for: sessionID)
        fakeProcess?.emit(" ignored")
        await Task.yield()

        XCTAssertEqual(observed, ["\u{1B}[31mred\u{1B}[39m", "\r\nnext"])
    }

    func testTerminalRawOutputPreservesAlternateScreenSequencesForEmulator() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        let alternateScreenOutput = "\u{1B}[?1049hframe\u{1B}[?1049lmain\n"
        fakeProcess?.emit(alternateScreenOutput)
        await Task.yield()

        var observed: [String] = []
        let observerID = store.registerTerminalOutputObserver(for: sessionID) { output in
            observed.append(String(decoding: output, as: UTF8.self))
        }
        store.unregisterTerminalOutputObserver(observerID, for: sessionID)

        XCTAssertEqual(String(decoding: store.terminalSessions[0].rawOutputData, as: UTF8.self), alternateScreenOutput)
        XCTAssertEqual(observed, [alternateScreenOutput])
        XCTAssertEqual(store.terminalSessions[0].output, "framemain\n")
    }

    func testTerminalRawReplayIsBoundedAndRestartsFromCleanStateAfterTruncation() async {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, onOutput, onExit in
            let fake = FakeTerminalProcess(onOutput: onOutput, onExit: onExit)
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        fakeProcess?.emit(String(repeating: "x", count: 210_000) + "tail")
        await Task.yield()

        let rawOutput = store.terminalSessions[0].rawOutputData
        XCTAssertLessThanOrEqual(rawOutput.count, 200_000)
        XCTAssertTrue(rawOutput.starts(with: Data([0x1B, 0x63])))
        XCTAssertTrue(String(decoding: rawOutput, as: UTF8.self).hasSuffix("tail"))

        var replayedOutput = Data()
        let observerID = store.registerTerminalOutputObserver(for: sessionID) { output in
            replayedOutput.append(contentsOf: output)
        }
        store.unregisterTerminalOutputObserver(observerID, for: sessionID)

        XCTAssertEqual(replayedOutput, rawOutput)
    }

    func testTerminalResizeRoutesToProcess() {
        var fakeProcess: FakeTerminalProcess?
        let store = makeStore { _, _, _ in
            let fake = FakeTerminalProcess()
            fakeProcess = fake
            return fake
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id

        store.resizeTerminalSession(sessionID, columns: 132, rows: 40)

        XCTAssertEqual(fakeProcess?.resizes, [FakeTerminalProcess.Resize(columns: 132, rows: 40)])
    }

    func testTerminalTitleUpdateSanitizesShellTitle() {
        let store = makeStore { _, _, _ in FakeTerminalProcess() }
        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id

        store.updateTerminalSessionTitle(sessionID, title: "  docs\u{7}\nignored  ")

        XCTAssertEqual(store.terminalSessions[0].title, "docsignored")
    }

    func testTerminalCurrentDirectoryUpdateTracksExistingFileURLDirectory() throws {
        let rootURL = try makeTemporaryDirectory()
        let nestedURL = rootURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        let store = makeStore { _, _, _ in FakeTerminalProcess() }
        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id

        store.updateTerminalSessionWorkingDirectory(
            sessionID,
            directory: nestedURL.absoluteString
        )

        XCTAssertEqual(
            store.terminalSessions[0].workingDirectoryPath,
            nestedURL.standardizedFileURL.path
        )

        store.updateTerminalSessionWorkingDirectory(sessionID, directory: "relative/path")
        XCTAssertEqual(
            store.terminalSessions[0].workingDirectoryPath,
            nestedURL.standardizedFileURL.path
        )
    }

    func testLocalTerminalProcessRunsThroughRealPTY() async throws {
        let rootURL = try makeTemporaryDirectory()
        var output = Data()
        var exitStatus: Int32?
        let exited = expectation(description: "terminal process exits")
        let process = try LocalTerminalProcess(
            workingDirectory: rootURL,
            shellPath: "/bin/sh",
            onOutput: { bytes in
                output.append(contentsOf: bytes)
            },
            onExit: { status in
                exitStatus = status
                exited.fulfill()
            }
        )
        defer { process.stop() }

        process.resize(columns: 80, rows: 24)
        process.send(Array("test -t 0 && echo simplelime-tty-ok; printf 'simplelime-pty-ok\\n'; exit 7\n".utf8)[...])
        await fulfillment(of: [exited], timeout: 5)

        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("simplelime-tty-ok"))
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("simplelime-pty-ok"))
        XCTAssertEqual(exitStatus, 7)
    }

    func testLocalTerminalProcessPreservesAlternateScreenSequencesForSwiftTerm() async throws {
        let rootURL = try makeTemporaryDirectory()
        var output = Data()
        let exited = expectation(description: "terminal process exits")
        let process = try LocalTerminalProcess(
            workingDirectory: rootURL,
            shellPath: "/bin/sh",
            onOutput: { bytes in
                output.append(contentsOf: bytes)
            },
            onExit: { _ in
                exited.fulfill()
            }
        )
        defer { process.stop() }

        process.resize(columns: 100, rows: 30)
        process.send(Array("printf '\\033[?1049halternate\\033[?1049lmain\\n'; exit 0\n".utf8)[...])
        await fulfillment(of: [exited], timeout: 5)

        let rawOutput = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(rawOutput.contains("\u{1B}[?1049h"))
        XCTAssertTrue(rawOutput.contains("\u{1B}[?1049l"))
        XCTAssertTrue(rawOutput.contains("alternate"))
        XCTAssertTrue(rawOutput.contains("main"))
    }

    func testLocalTerminalProcessDeliversOutputOffMainQueue() async throws {
        let rootURL = try makeTemporaryDirectory()
        let output = ThreadSafeTerminalOutputCapture()
        let exited = expectation(description: "terminal process exits")
        let process = try LocalTerminalProcess(
            workingDirectory: rootURL,
            shellPath: "/bin/sh",
            onOutput: { bytes in
                output.append(bytes)
            },
            onExit: { _ in
                exited.fulfill()
            }
        )
        defer { process.stop() }

        process.send(Array("printf 'queue-test\\n'; exit 0\n".utf8)[...])
        await fulfillment(of: [exited], timeout: 5)

        let snapshot = output.snapshot()

        XCTAssertTrue(snapshot.text.contains("queue-test"))
        XCTAssertEqual(snapshot.receivedOnMainThread, false)
    }

    func testLocalTerminalProcessDrainsNoisyPTYOutputAndExits() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
            throw XCTSkip("perl is not available on this system.")
        }

        let rootURL = try makeTemporaryDirectory()
        let output = ThreadSafeTerminalOutputCapture()
        let exited = expectation(description: "terminal process exits")
        let process = try LocalTerminalProcess(
            workingDirectory: rootURL,
            shellPath: "/bin/sh",
            terminalType: "xterm-256color",
            onOutput: { bytes in
                output.append(bytes)
            },
            onExit: { _ in
                exited.fulfill()
            }
        )
        defer { process.stop() }

        process.resize(columns: 120, rows: 32)
        let noisyCommand = "/usr/bin/perl -e 'print \"x\" x 180000; print \"\\nnoisy-done\\n\"'; " +
            "printf 'after-noisy\\n'; exit 0\n"
        process.send(Array(noisyCommand.utf8)[...])
        await fulfillment(of: [exited], timeout: 8)

        let snapshot = output.snapshot()

        XCTAssertGreaterThan(snapshot.byteCount, 180_000)
        XCTAssertTrue(snapshot.text.contains("noisy-done"), String(snapshot.text.suffix(500)))
        XCTAssertTrue(snapshot.text.contains("after-noisy"), String(snapshot.text.suffix(500)))
    }

    func testLocalTerminalProcessUsesConfiguredTerminalType() async throws {
        let rootURL = try makeTemporaryDirectory()
        var output = Data()
        let exited = expectation(description: "terminal process exits")
        let process = try LocalTerminalProcess(
            workingDirectory: rootURL,
            shellPath: "/bin/sh",
            terminalType: "vt100",
            onOutput: { bytes in
                output.append(contentsOf: bytes)
            },
            onExit: { _ in
                exited.fulfill()
            }
        )
        defer { process.stop() }

        process.send(Array("printf \"TERM=$TERM\\n\"; exit 0\n".utf8)[...])
        await fulfillment(of: [exited], timeout: 5)

        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("TERM=vt100"))
    }

    func testLocalTerminalProcessResizeUpdatesPTYWindowSize() async throws {
        let rootURL = try makeTemporaryDirectory()
        var output = Data()
        let exited = expectation(description: "terminal process exits")
        let process = try LocalTerminalProcess(
            workingDirectory: rootURL,
            shellPath: "/bin/sh",
            onOutput: { output.append(contentsOf: $0) },
            onExit: { _ in
                exited.fulfill()
            }
        )
        defer { process.stop() }

        process.resize(columns: 91, rows: 33)
        process.send(Array("stty size; exit 0\n".utf8)[...])
        await fulfillment(of: [exited], timeout: 5)

        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("33 91"))
    }

    func testLocalTerminalProcessEnvironmentForcesUTF8LocaleAndTrueColor() {
        let environment = LocalTerminalProcess.processEnvironmentDictionary(
            baseEnvironment: [
                "LANG": "C",
                "LC_CTYPE": "POSIX",
                "LC_ALL": "C",
                "PATH": "/usr/bin:/bin"
            ],
            shellPath: "/bin/zsh",
            terminalType: "xterm-256color",
            columns: 132,
            rows: 43
        )

        XCTAssertEqual(environment["TERM"], "xterm-256color")
        XCTAssertEqual(environment["COLORTERM"], "truecolor")
        XCTAssertEqual(environment["TERM_PROGRAM"], "SimpleLime")
        XCTAssertEqual(environment["LANG"], "en_US.UTF-8")
        XCTAssertEqual(environment["LC_CTYPE"], "en_US.UTF-8")
        XCTAssertEqual(environment["LC_ALL"], "en_US.UTF-8")
        XCTAssertEqual(environment["COLUMNS"], "132")
        XCTAssertEqual(environment["LINES"], "43")
        XCTAssertEqual(environment["SHELL"], "/bin/zsh")
        XCTAssertEqual(environment["PATH"], "/usr/bin:/bin")
    }

    func testLocalTerminalProcessEnvironmentKeepsExistingUTF8Locale() {
        let environment = LocalTerminalProcess.processEnvironmentDictionary(
            baseEnvironment: [
                "LANG": "de_DE.UTF-8",
                "LC_CTYPE": "ru_RU.UTF8"
            ],
            shellPath: "/bin/zsh",
            terminalType: "xterm-24bit",
            columns: 80,
            rows: 24
        )

        XCTAssertEqual(environment["LANG"], "de_DE.UTF-8")
        XCTAssertEqual(environment["LC_CTYPE"], "ru_RU.UTF8")
        XCTAssertNil(environment["LC_ALL"])
    }

    func testLocalTerminalProcessEnvironmentUsesConfiguredLocaleFallback() {
        let environment = LocalTerminalProcess.processEnvironmentDictionary(
            baseEnvironment: [
                "LANG": "C",
                "LC_CTYPE": "POSIX",
                "LC_ALL": "C"
            ],
            shellPath: "/bin/zsh",
            terminalType: "xterm-256color",
            columns: 120,
            rows: 30,
            locale: "de_DE.UTF-8"
        )

        XCTAssertEqual(environment["LANG"], "de_DE.UTF-8")
        XCTAssertEqual(environment["LC_CTYPE"], "de_DE.UTF-8")
        XCTAssertEqual(environment["LC_ALL"], "de_DE.UTF-8")
    }

    func testLocalTerminalProcessInterruptStopsForegroundPTYCommand() async throws {
        let rootURL = try makeTemporaryDirectory()
        var output = Data()
        let exited = expectation(description: "terminal process exits")
        let process = try LocalTerminalProcess(
            workingDirectory: rootURL,
            shellPath: "/bin/sh",
            onOutput: { bytes in
                output.append(contentsOf: bytes)
            },
            onExit: { _ in
                exited.fulfill()
            }
        )
        defer { process.stop() }

        process.resize(columns: 80, rows: 24)
        process.send(Array("cat\n".utf8)[...])
        try await Task.sleep(nanoseconds: 200_000_000)
        process.send([0x03][...])
        try await Task.sleep(nanoseconds: 200_000_000)
        process.send(Array("printf 'after-interrupt\\n'; exit 0\n".utf8)[...])
        await fulfillment(of: [exited], timeout: 5)

        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("after-interrupt"))
    }

    func testEditorStoreTerminalResetLeavesRealPTYUsable() async throws {
        let rootURL = try makeTemporaryDirectory()
        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/sh",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.sendInputToTerminal(sessionID, input: "cat\n")
        try await Task.sleep(nanoseconds: 200_000_000)

        store.resetTerminalSession(sessionID)
        try await Task.sleep(nanoseconds: 500_000_000)
        store.sendInputToTerminal(sessionID, input: "printf 'after-reset\\n'; exit 0\n")

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID)
        XCTAssertTrue(session.output.contains("after-reset"))
    }

    func testEditorStoreTerminalDiagnosticsRunAgainstRealPTYAndLeaveShellUsable() async throws {
        let rootURL = try makeTemporaryDirectory()
        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/sh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.resizeTerminalSession(sessionID, columns: 120, rows: 32)

        store.sendInputToTerminal(sessionID, input: "stty -echo\n")
        try await Task.sleep(nanoseconds: 200_000_000)
        store.runTerminalDiagnostics(sessionID)
        try await waitForTerminalOutput(
            in: store,
            sessionID: sessionID,
            containingAny: ["SimpleLime terminal diagnostics complete"],
            timeoutSeconds: 10
        )

        store.sendInputToTerminal(sessionID, input: "stty echo; printf 'after-diagnostics\\n'; exit 0\n")

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID, timeoutSeconds: 10)
        XCTAssertTrue(session.output.contains("SimpleLime terminal diagnostics"), session.output)
        XCTAssertTrue(session.output.contains("size=32 120"), session.output)
        XCTAssertTrue(
            session.output.contains("SimpleLime curses diagnostic complete") ||
                session.output.contains("SimpleLime curses diagnostic skipped") ||
                session.output.contains("SimpleLime curses diagnostic failed"),
            session.output
        )
        XCTAssertTrue(session.output.contains("after-diagnostics"), session.output)
        XCTAssertEqual(session.lastExitStatus, 0)
    }

    func testEditorStoreTerminalSurvivesInterruptedTopCommand() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/top") else {
            throw XCTSkip("top is not available on this system.")
        }

        let rootURL = try makeTemporaryDirectory()
        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/sh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.resizeTerminalSession(sessionID, columns: 120, rows: 32)
        store.sendInputToTerminal(
            sessionID,
            input: "/usr/bin/top -l 0 -n 2 -stats pid,command,cpu\n"
        )

        try await waitForTerminalOutput(in: store, sessionID: sessionID, containingAny: ["Processes:", "COMMAND"])

        store.interruptTerminalSession(sessionID)
        try await Task.sleep(nanoseconds: 300_000_000)
        store.sendInputToTerminal(sessionID, input: "printf 'after-top\\n'; exit 0\n")

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID, timeoutSeconds: 10)
        let rawOutput = String(decoding: session.rawOutputData, as: UTF8.self)
        XCTAssertTrue(rawOutput.contains("Processes:") || rawOutput.contains("COMMAND"), rawOutput)
        XCTAssertTrue(session.output.contains("after-top"), session.output)
        XCTAssertEqual(session.lastExitStatus, 0)
    }

    func testEditorStoreTerminalSurvivesRealHtopTUIWhenAvailable() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else {
            throw XCTSkip("zsh is not available on this system.")
        }
        guard let htopPath = firstExecutablePath(
            named: "htop",
            candidates: ["/opt/homebrew/bin/htop", "/usr/local/bin/htop", "/usr/bin/htop"]
        ) else {
            throw XCTSkip("htop is not available on this system.")
        }

        let rootURL = try makeTemporaryDirectory()
        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/zsh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.resizeTerminalSession(sessionID, columns: 120, rows: 32)
        store.sendInputToTerminal(sessionID, input: "\(shellQuoted(htopPath))\n")

        try await waitForTerminalRawOutput(
            in: store,
            sessionID: sessionID,
            containingAny: ["htop", "F1", "Help", "CPU", "Tasks"],
            timeoutSeconds: 12
        )

        store.sendInputToTerminal(sessionID, input: "q")
        try await Task.sleep(nanoseconds: 600_000_000)
        store.sendInputToTerminal(sessionID, input: "printf 'after-htop\\n'; exit 0\n")

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID, timeoutSeconds: 12)
        let rawOutput = String(decoding: session.rawOutputData, as: UTF8.self)

        XCTAssertTrue(
            rawOutput.contains("\u{1B}[?1049h") ||
                rawOutput.contains("\u{1B}[2J") ||
                rawOutput.contains("\u{1B}[H") ||
                rawOutput.localizedCaseInsensitiveContains("htop"),
            rawOutput
        )
        XCTAssertTrue(session.output.contains("after-htop"), session.output)
        XCTAssertEqual(session.lastExitStatus, 0)
    }

    func testEditorStoreTerminalPipelinePreservesRealZshTUIBytesForSwiftTerm() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else {
            throw XCTSkip("zsh is not available on this system.")
        }

        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/zsh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.sendInputToTerminal(
            sessionID,
            input: "printf '\\033[?1049h\\033[2J\\033[4;7HTUI Привет\\033[?1049lmain Привет\\n'; exit 0\n"
        )

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID)
        let rawOutput = String(decoding: session.rawOutputData, as: UTF8.self)

        XCTAssertTrue(rawOutput.contains("\u{1B}[?1049h"))
        XCTAssertTrue(rawOutput.contains("\u{1B}[2J"))
        XCTAssertTrue(rawOutput.contains("\u{1B}[4;7H"))
        XCTAssertTrue(rawOutput.contains("\u{1B}[?1049l"))
        XCTAssertTrue(rawOutput.contains("Привет"))
        XCTAssertTrue(session.output.contains("TUI Привет"))
        XCTAssertTrue(session.output.contains("main Привет"))

        var replayedOutput = Data()
        let observerID = store.registerTerminalOutputObserver(for: sessionID) { output in
            replayedOutput.append(contentsOf: output)
        }
        store.unregisterTerminalOutputObserver(observerID, for: sessionID)

        XCTAssertEqual(replayedOutput, session.rawOutputData)
    }

    func testEditorStoreTerminalSurvivesInteractiveAgentStyleTUI() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else {
            throw XCTSkip("zsh is not available on this system.")
        }

        let rootURL = try makeTemporaryDirectory()
        let scriptURL = rootURL.appendingPathComponent("agent-tui.zsh")
        let script = """
        printf '\\033]2;Agent TUI\\007'
        printf '\\033[?1049h\\033[?25l\\033[2J'
        printf '\\033[1;1Hagent-frame-1'
        printf '\\033[2;4Hagent Привет'
        printf '\\033[3;4Hwaiting-for-input'
        IFS= read -r reply
        printf '\\033[4;4Hagent-input:%s' "$reply"
        printf '\\033[5;4Hagent-frame-2'
        printf '\\033[?25h\\033[?1049l'
        printf 'agent-tui-exit\\n'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/zsh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.resizeTerminalSession(sessionID, columns: 120, rows: 32)
        store.sendInputToTerminal(sessionID, input: "/bin/zsh \(scriptURL.path)\n")

        try await waitForTerminalOutput(
            in: store,
            sessionID: sessionID,
            containingAny: ["waiting-for-input", "agent Привет"]
        )

        store.sendInputToTerminal(sessionID, input: "q\n")
        try await waitForTerminalOutput(in: store, sessionID: sessionID, containingAny: ["agent-tui-exit"])
        store.sendInputToTerminal(sessionID, input: "printf 'after-agent-tui\\n'; exit 0\n")

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID, timeoutSeconds: 10)
        let rawOutput = String(decoding: session.rawOutputData, as: UTF8.self)

        XCTAssertTrue(rawOutput.contains("\u{1B}]2;Agent TUI\u{7}"), rawOutput)
        XCTAssertTrue(rawOutput.contains("\u{1B}[?1049h"), rawOutput)
        XCTAssertTrue(rawOutput.contains("\u{1B}[?25l"), rawOutput)
        XCTAssertTrue(rawOutput.contains("\u{1B}[2J"), rawOutput)
        XCTAssertTrue(rawOutput.contains("\u{1B}[5;4H"), rawOutput)
        XCTAssertTrue(rawOutput.contains("\u{1B}[?25h"), rawOutput)
        XCTAssertTrue(rawOutput.contains("\u{1B}[?1049l"), rawOutput)
        XCTAssertTrue(session.output.contains("agent-frame-1"), session.output)
        XCTAssertTrue(session.output.contains("agent Привет"), session.output)
        XCTAssertTrue(session.output.contains("agent-input:q"), session.output)
        XCTAssertTrue(session.output.contains("agent-frame-2"), session.output)
        XCTAssertTrue(session.output.contains("after-agent-tui"), session.output)
        XCTAssertEqual(session.lastExitStatus, 0)
    }

    func testEditorStoreTerminalSurvivesRealPythonCursesTUIWhenAvailable() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else {
            throw XCTSkip("zsh is not available on this system.")
        }
        guard let pythonPath = firstExecutablePath(
            named: "python3",
            candidates: ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        ) else {
            throw XCTSkip("python3 is not available on this system.")
        }

        let rootURL = try makeTemporaryDirectory()
        let scriptURL = rootURL.appendingPathComponent("simplelime-curses-smoke.py")
        let script = """
        import curses
        import locale

        locale.setlocale(locale.LC_ALL, "")

        def safe_addstr(stdscr, row, col, text):
            try:
                stdscr.addstr(row, col, text)
            except curses.error:
                pass

        def main(stdscr):
            try:
                curses.curs_set(0)
            except curses.error:
                pass
            stdscr.keypad(True)
            stdscr.clear()
            try:
                stdscr.border()
            except curses.error:
                pass
            safe_addstr(stdscr, 1, 2, "curses-frame-1")
            safe_addstr(stdscr, 2, 2, "curses Привет")
            safe_addstr(stdscr, 3, 2, "press q to exit")
            stdscr.refresh()
            stdscr.getch()

        curses.wrapper(main)
        print("curses-tui-exit", flush=True)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/zsh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.resizeTerminalSession(sessionID, columns: 120, rows: 32)
        store.sendInputToTerminal(
            sessionID,
            input: "\(shellQuoted(pythonPath)) \(shellQuoted(scriptURL.path))\n"
        )

        try await waitForTerminalOutput(
            in: store,
            sessionID: sessionID,
            containingAny: ["curses-frame-1", "curses Привет"],
            timeoutSeconds: 10
        )

        store.sendInputToTerminal(sessionID, input: "q")
        try await waitForTerminalOutput(
            in: store,
            sessionID: sessionID,
            containingAny: ["curses-tui-exit"],
            timeoutSeconds: 10
        )
        store.sendInputToTerminal(sessionID, input: "printf 'after-curses-tui\\n'; exit 0\n")

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID, timeoutSeconds: 10)
        let rawOutput = String(decoding: session.rawOutputData, as: UTF8.self)

        XCTAssertTrue(
            rawOutput.contains("\u{1B}[?1049h") ||
                rawOutput.contains("\u{1B}[2J") ||
                rawOutput.contains("\u{1B}[H"),
            rawOutput
        )
        XCTAssertTrue(
            rawOutput.contains("\u{1B}[?1049l") ||
                rawOutput.contains("\u{1B}[2J") ||
                rawOutput.contains("curses-tui-exit"),
            rawOutput
        )
        XCTAssertTrue(rawOutput.contains("curses-frame-1"), rawOutput)
        XCTAssertTrue(rawOutput.contains("Привет"), rawOutput)
        XCTAssertTrue(session.output.contains("after-curses-tui"), session.output)
        XCTAssertEqual(session.lastExitStatus, 0)
    }

    func testEditorStoreTerminalSurvivesRealVimTUIWhenAvailable() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else {
            throw XCTSkip("zsh is not available on this system.")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/vim") else {
            throw XCTSkip("vim is not available on this system.")
        }

        let rootURL = try makeTemporaryDirectory()
        let editedURL = rootURL.appendingPathComponent("simplelime-vim-smoke.txt")
        let typedText = "SimpleLime vim Привет"
        try "\(typedText)\n".write(to: editedURL, atomically: true, encoding: .utf8)
        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/zsh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.resizeTerminalSession(sessionID, columns: 120, rows: 32)
        store.sendInputToTerminal(
            sessionID,
            input: "/usr/bin/vim -Nu NONE -n -i NONE \(editedURL.path)\n"
        )

        try await waitForTerminalOutput(
            in: store,
            sessionID: sessionID,
            containingAny: [typedText, editedURL.lastPathComponent],
            timeoutSeconds: 10
        )

        store.sendInputToTerminal(sessionID, input: "\u{1B}:q!\r")
        try await waitForTerminalRawOutput(
            in: store,
            sessionID: sessionID,
            containingAny: ["\u{1B}[?1049l"],
            timeoutSeconds: 10
        )
        store.sendInputToTerminal(
            sessionID,
            input: "printf 'after-vim\\n'; exit 0\n"
        )

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID, timeoutSeconds: 10)
        let rawOutput = String(decoding: session.rawOutputData, as: UTF8.self)

        XCTAssertTrue(rawOutput.contains("\u{1B}[?1049h"), rawOutput)
        XCTAssertTrue(rawOutput.contains("\u{1B}[?1049l"), rawOutput)
        XCTAssertTrue(rawOutput.contains("SimpleLime vim"), rawOutput)
        for character in "Привет" {
            XCTAssertTrue(rawOutput.contains(String(character)), rawOutput)
        }
        XCTAssertTrue(session.output.contains("after-vim"), session.output)
        XCTAssertEqual(session.lastExitStatus, 0)
    }

    func testEditorStoreTerminalSurvivesRealClaudeTUIWhenAvailable() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else {
            throw XCTSkip("zsh is not available on this system.")
        }
        guard let claudePath = firstExecutablePath(
            named: "claude",
            candidates: ["/Users/malikov/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        ) else {
            throw XCTSkip("claude is not available on this system.")
        }

        let rootURL = try makeTemporaryDirectory()
        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/zsh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.resizeTerminalSession(sessionID, columns: 120, rows: 32)
        store.sendInputToTerminal(sessionID, input: "\(shellQuoted(claudePath)) --bare\n")

        try await waitForTerminalRawOutput(
            in: store,
            sessionID: sessionID,
            containingAny: ["\u{1B}7", "\u{1B}[?25h", "Claude", "claude"],
            timeoutSeconds: 12
        )

        store.interruptTerminalSession(sessionID)
        try await Task.sleep(nanoseconds: 600_000_000)
        store.sendInputToTerminal(sessionID, input: "printf 'after-claude\\n'; exit 0\n")

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID, timeoutSeconds: 12)
        XCTAssertTrue(session.output.contains("after-claude"), session.output)
        XCTAssertEqual(session.lastExitStatus, 0)
    }

    func testEditorStoreTerminalCanRestartAfterRealCodexTUIWhenAvailable() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else {
            throw XCTSkip("zsh is not available on this system.")
        }
        guard let codexPath = firstExecutablePath(
            named: "codex",
            candidates: ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        ) else {
            throw XCTSkip("codex is not available on this system.")
        }

        let rootURL = try makeTemporaryDirectory()
        let store = makeStore { workingDirectory, onOutput, onExit in
            try LocalTerminalProcess(
                workingDirectory: workingDirectory,
                shellPath: "/bin/zsh",
                terminalType: "xterm-256color",
                onOutput: onOutput,
                onExit: onExit
            )
        }
        store.documentCatalogRootPath = rootURL.path

        store.createTerminalSession()
        let sessionID = store.terminalSessions[0].id
        store.resizeTerminalSession(sessionID, columns: 120, rows: 32)
        store.sendInputToTerminal(sessionID, input: "\(shellQuoted(codexPath))\n")

        try await waitForTerminalRawOutput(
            in: store,
            sessionID: sessionID,
            containingAny: ["\u{1B}[?2026h", "\u{1B}[?1004h", "Codex", "codex"],
            timeoutSeconds: 12
        )
        let codexRawOutput = String(decoding: store.terminalSessions[0].rawOutputData, as: UTF8.self)
        XCTAssertTrue(
            codexRawOutput.contains("\u{1B}[?2026h") ||
                codexRawOutput.contains("\u{1B}[?1004h") ||
                codexRawOutput.localizedCaseInsensitiveContains("codex"),
            codexRawOutput
        )

        store.restartTerminalSession(sessionID)
        try await Task.sleep(nanoseconds: 600_000_000)
        store.sendInputToTerminal(sessionID, input: "printf 'after-codex-restart\\n'; exit 0\n")

        let session = try await waitForTerminalExit(in: store, sessionID: sessionID, timeoutSeconds: 12)
        XCTAssertTrue(session.output.contains("after-codex-restart"), session.output)
        XCTAssertEqual(session.lastExitStatus, 0)
    }

    func testTerminalIsBottomPanelAndDoesNotReplaceRightSidebar() {
        let store = makeStore { _, _, _ in FakeTerminalProcess() }
        store.showCommentsPanel()

        store.toggleTerminalPanel()

        XCTAssertTrue(store.isTerminalPanelVisible)
        XCTAssertTrue(store.isCommentsPanelVisible)
        XCTAssertEqual(activeRightPanelCount(in: store), 1)
    }

    private func makeStore(
        buffer: EditorBuffer = EditorBuffer.scratch(index: 1),
        factory: @escaping TerminalProcessFactory
    ) -> EditorStore {
        EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            terminalProcessFactory: factory,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simplelime-terminal-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForTerminalExit(
        in store: EditorStore,
        sessionID: UUID,
        timeoutSeconds: Double = 8
    ) async throws -> TerminalSession {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let session = store.terminalSessions.first(where: { $0.id == sessionID }),
               !session.isRunning {
                return session
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Terminal session did not exit before timeout.")
        return try XCTUnwrap(store.terminalSessions.first { $0.id == sessionID })
    }

    private func waitForTerminalOutput(
        in store: EditorStore,
        sessionID: UUID,
        containingAny needles: [String],
        timeoutSeconds: Double = 8
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let session = store.terminalSessions.first(where: { $0.id == sessionID }),
               needles.contains(where: { session.output.contains($0) }) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let output = store.terminalSessions.first(where: { $0.id == sessionID })?.output ?? ""
        XCTFail("Terminal output did not contain any of \(needles) before timeout. Output: \(output)")
    }

    private func waitForTerminalRawOutput(
        in store: EditorStore,
        sessionID: UUID,
        containingAny needles: [String],
        timeoutSeconds: Double = 8
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let session = store.terminalSessions.first(where: { $0.id == sessionID }) {
                let rawOutput = String(decoding: session.rawOutputData, as: UTF8.self)
                if needles.contains(where: { rawOutput.contains($0) }) {
                    return
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let rawOutput = store.terminalSessions.first(where: { $0.id == sessionID })
            .map { String(decoding: $0.rawOutputData, as: UTF8.self) } ?? ""
        XCTFail("Terminal raw output did not contain any of \(needles) before timeout. Raw output: \(rawOutput)")
    }

    private func firstExecutablePath(named name: String, candidates: [String]) -> String? {
        let pathCandidates = ProcessInfo.processInfo.environment["PATH", default: ""]
            .split(separator: ":")
            .map { String($0) + "/" + name }
        for candidate in candidates + pathCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func activeRightPanelCount(in store: EditorStore) -> Int {
        [
            store.isAIPanelVisible,
            store.isNetworkPanelVisible,
            store.isCommentsPanelVisible,
            store.isTasksPanelVisible,
            store.isStatsPanelVisible,
            store.isMacrosPanelVisible
        ].filter { $0 }.count
    }
}

private final class FakeTerminalProcess: TerminalProcessRunning {
    struct Resize: Equatable {
        let columns: Int
        let rows: Int
    }

    var sentInput: [String] = []
    var resizes: [Resize] = []
    var didStop = false
    private let onOutput: (([UInt8]) -> Void)?
    private let onExit: ((Int32) -> Void)?

    init(
        onOutput: (([UInt8]) -> Void)? = nil,
        onExit: ((Int32) -> Void)? = nil
    ) {
        self.onOutput = onOutput
        self.onExit = onExit
    }

    func send(_ data: ArraySlice<UInt8>) {
        sentInput.append(String(decoding: data, as: UTF8.self))
    }

    func resize(columns: Int, rows: Int) {
        resizes.append(Resize(columns: columns, rows: rows))
    }

    func stop() {
        didStop = true
    }

    func emit(_ text: String) {
        onOutput?(Array(text.utf8))
    }

    func exit(_ status: Int32) {
        onExit?(status)
    }
}

private final class ThreadSafeTerminalOutputCapture {
    private let queue = DispatchQueue(label: "SimpleLimeTests.TerminalOutputCapture")
    private var data = Data()
    private var latestReceivedOnMainThread: Bool?

    func append(_ bytes: [UInt8]) {
        queue.sync {
            data.append(contentsOf: bytes)
            latestReceivedOnMainThread = Thread.isMainThread
        }
    }

    func snapshot() -> (text: String, byteCount: Int, receivedOnMainThread: Bool?) {
        queue.sync {
            (
                text: String(decoding: data, as: UTF8.self),
                byteCount: data.count,
                receivedOnMainThread: latestReceivedOnMainThread
            )
        }
    }
}
