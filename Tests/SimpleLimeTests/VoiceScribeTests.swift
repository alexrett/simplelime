import XCTest
@testable import SimpleLime

@MainActor
final class VoiceScribeTests: XCTestCase {
    func testCommandInterpreterMapsWakePhraseCommands() {
        XCTAssertEqual(
            VoiceScribeCommandInterpreter.commandRequest(from: "SimpleLime save"),
            LocalAutomationCommandRequest(command: .save, text: nil)
        )
        XCTAssertEqual(
            VoiceScribeCommandInterpreter.commandRequest(from: "simple lime scan companion"),
            LocalAutomationCommandRequest(command: .runCompanionScan, text: nil)
        )
        XCTAssertEqual(
            VoiceScribeCommandInterpreter.commandRequest(from: "SimpleLime force close tab"),
            LocalAutomationCommandRequest(command: .forceClose, text: nil)
        )
        XCTAssertEqual(
            VoiceScribeCommandInterpreter.commandRequest(from: "SimpleLime insert Follow up tomorrow"),
            LocalAutomationCommandRequest(command: .insertText, text: "Follow up tomorrow")
        )
        XCTAssertNil(VoiceScribeCommandInterpreter.commandRequest(from: "Follow up tomorrow"))
    }

    func testCommandInterpreterMapsLargeFileLineEditCommands() {
        XCTAssertEqual(
            VoiceScribeCommandInterpreter.commandRequest(
                from: "SimpleLime replace large file line 42 with Edited JSON row"
            ),
            LocalAutomationCommandRequest(command: .replaceLargeFileLine, text: "Edited JSON row", lineNumber: 42)
        )
        XCTAssertEqual(
            VoiceScribeCommandInterpreter.commandRequest(
                from: "Simple Lime insert line 43 Inserted row"
            ),
            LocalAutomationCommandRequest(command: .insertLargeFileLine, text: "Inserted row", lineNumber: 43)
        )
        XCTAssertEqual(
            VoiceScribeCommandInterpreter.commandRequest(from: "SimpleLime delete large-file line 44"),
            LocalAutomationCommandRequest(command: .deleteLargeFileLine, text: nil, lineNumber: 44)
        )
        XCTAssertNil(
            VoiceScribeCommandInterpreter.commandRequest(from: "SimpleLime replace large file line zero with row")
        )
    }

    func testMeetingAppDetectorRecognizesKnownMeetingApps() {
        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(
                in: [
                    VoiceScribeRunningApplication(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit"),
                    VoiceScribeRunningApplication(bundleIdentifier: "us.zoom.xos", localizedName: "zoom.us")
                ]
            ),
            VoiceScribeMeetingAppDetection(displayName: "Zoom", bundleIdentifier: "us.zoom.xos")
        )

        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(
                in: [
                    VoiceScribeRunningApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome")
                ]
            ),
            nil
        )
    }

    func testMeetingAppDetectorRecognizesBrowserMeetingWindowTitles() {
        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(
                in: [
                    VoiceScribeRunningApplication(
                        bundleIdentifier: "com.google.Chrome",
                        localizedName: "Google Chrome",
                        windowTitles: ["Daily sync - Google Meet"]
                    )
                ]
            ),
            VoiceScribeMeetingAppDetection(displayName: "Google Meet", bundleIdentifier: "com.google.Chrome")
        )

        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(
                in: [
                    VoiceScribeRunningApplication(
                        bundleIdentifier: "com.apple.Safari",
                        localizedName: "Safari",
                        windowTitles: ["Planning - Microsoft Teams"]
                    )
                ]
            ),
            VoiceScribeMeetingAppDetection(displayName: "Microsoft Teams", bundleIdentifier: "com.apple.Safari")
        )
    }

    func testMeetingAppDetectorRecognizesBrowserMeetingURLsWithoutMeetingTitle() {
        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(
                in: [
                    VoiceScribeRunningApplication(
                        bundleIdentifier: "com.google.Chrome",
                        localizedName: "Google Chrome",
                        windowTitles: ["Daily sync"],
                        browserTabURLs: ["https://meet.google.com/abc-defg-hij"]
                    )
                ]
            ),
            VoiceScribeMeetingAppDetection(displayName: "Google Meet", bundleIdentifier: "com.google.Chrome")
        )

        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(
                in: [
                    VoiceScribeRunningApplication(
                        bundleIdentifier: "com.apple.Safari",
                        localizedName: "Safari",
                        windowTitles: ["Q2 planning"],
                        browserTabURLs: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting"]
                    )
                ]
            ),
            VoiceScribeMeetingAppDetection(displayName: "Microsoft Teams", bundleIdentifier: "com.apple.Safari")
        )
    }

    func testMeetingAppDetectorParsesAllScriptableBrowserTabURLs() {
        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.parseBrowserTabURLs(
                """
                  https://example.com
                https://meet.google.com/abc-defg-hij
                https://meet.google.com/abc-defg-hij

                https://teams.microsoft.com/l/meetup-join/19%3ameeting
                """
            ),
            [
                "https://example.com",
                "https://meet.google.com/abc-defg-hij",
                "https://teams.microsoft.com/l/meetup-join/19%3ameeting"
            ]
        )
    }

    func testMeetingAppDetectorCollectsTabURLsForAllSupportedRunningBrowsers() {
        var requestedBundles: [String] = []
        let applications = VoiceScribeMeetingAppDetector.applicationsForDetection(
            runningApplications: [
                VoiceScribeRunningApplication(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit"),
                VoiceScribeRunningApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
                VoiceScribeRunningApplication(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
            ],
            browserTabURLProvider: { bundleIdentifier in
                requestedBundles.append(bundleIdentifier ?? "")
                switch bundleIdentifier?.lowercased() {
                case "com.google.chrome":
                    return ["https://example.com"]
                case "com.apple.safari":
                    return [
                        "https://meet.google.com/abc-defg-hij",
                        "https://meet.google.com/abc-defg-hij"
                    ]
                default:
                    return []
                }
            }
        )

        XCTAssertEqual(requestedBundles, ["com.google.Chrome", "com.apple.Safari"])
        XCTAssertEqual(applications[0].browserTabURLs, [])
        XCTAssertEqual(applications[1].browserTabURLs, ["https://example.com"])
        XCTAssertEqual(applications[2].browserTabURLs, ["https://meet.google.com/abc-defg-hij"])
        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(in: applications),
            VoiceScribeMeetingAppDetection(displayName: "Google Meet", bundleIdentifier: "com.apple.Safari")
        )
    }

    func testMeetingAppDetectorAvoidsBroadBrowserTitleFalsePositives() {
        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(
                in: [
                    VoiceScribeRunningApplication(
                        bundleIdentifier: "com.google.Chrome",
                        localizedName: "Google Chrome",
                        windowTitles: ["Zoom valuation spreadsheet"]
                    )
                ]
            ),
            nil
        )
    }

    func testMeetingAppDetectorAvoidsBroadBrowserURLFalsePositives() {
        XCTAssertEqual(
            VoiceScribeMeetingAppDetector.detect(
                in: [
                    VoiceScribeRunningApplication(
                        bundleIdentifier: "com.google.Chrome",
                        localizedName: "Google Chrome",
                        windowTitles: ["Dashboard"],
                        browserTabURLs: ["https://example.com/articles/zoom-us-growth"]
                    )
                ]
            ),
            nil
        )
    }

    func testVoiceScribeFinalTranscriptAppendsToScratch() {
        let recognizer = FakeVoiceScribeRecognizer()
        let store = makeStore(recognizer: recognizer)
        store.voiceScribeTitle = "Standup"
        store.voiceScribeSpeaker = "Alex"

        store.startVoiceScribe()
        recognizer.sendFinal("We shipped the terminal fix")

        XCTAssertTrue(store.isVoiceScribeRunning)
        XCTAssertEqual(store.selectedBuffer?.title, "Standup")
        XCTAssertTrue(store.selectedBuffer?.text.contains("**Alex**: We shipped the terminal fix") == true)
        XCTAssertEqual(store.voiceScribePartialTranscript, "")
        XCTAssertEqual(store.voiceScribeStatus, "Appended transcript.")
    }

    func testVoiceScribeCommandUsesAutomationHandlerInsteadOfTranscript() {
        let recognizer = FakeVoiceScribeRecognizer()
        var buffer = EditorBuffer.scratch(index: 1)
        buffer.text = "Hello "
        buffer.selectionRanges = [TextRange(location: 6, length: 0)]
        let store = makeStore(buffer: buffer, recognizer: recognizer)

        store.startVoiceScribe()
        recognizer.sendFinal("SimpleLime insert world")

        XCTAssertEqual(store.selectedBuffer?.text, "Hello world")
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.voiceScribeStatus, "Voice command handled.")
    }

    func testVoiceScribeStopStopsRecognizer() {
        let recognizer = FakeVoiceScribeRecognizer()
        let store = makeStore(recognizer: recognizer)

        store.startVoiceScribe()
        store.stopVoiceScribe()

        XCTAssertEqual(recognizer.stopCount, 1)
        XCTAssertFalse(store.isVoiceScribeRunning)
        XCTAssertEqual(store.voiceScribeStatus, "Voice scribe stopped.")
    }

    func testVoiceScribeStartFailureReportsError() {
        let recognizer = FakeVoiceScribeRecognizer()
        let store = makeStore(recognizer: recognizer)

        store.startVoiceScribe()
        recognizer.sendError("Microphone permission is not granted.")

        XCTAssertFalse(store.isVoiceScribeRunning)
        XCTAssertEqual(store.voiceScribeStatus, "Microphone permission is not granted.")
        XCTAssertEqual(store.lastError, "Microphone permission is not granted.")
    }

    func testSystemAudioSourceUsesSystemAudioRecognizer() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(recognizer: microphone, systemAudioRecognizer: systemAudio)
        store.voiceScribeAudioSource = .systemAudio

        store.startVoiceScribe()
        systemAudio.sendFinal("The meeting app audio is captured")

        XCTAssertEqual(microphone.startCount, 0)
        XCTAssertEqual(systemAudio.startCount, 1)
        XCTAssertTrue(store.selectedBuffer?.text.contains("The meeting app audio is captured") == true)
    }

    func testMeetingAudioSourceStartsAndStopsBothRecognizers() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(recognizer: microphone, systemAudioRecognizer: systemAudio)
        store.voiceScribeAudioSource = .meetingAudio

        store.startVoiceScribe()
        store.stopVoiceScribe()

        XCTAssertEqual(microphone.startCount, 1)
        XCTAssertEqual(systemAudio.startCount, 1)
        XCTAssertEqual(microphone.stopCount, 1)
        XCTAssertEqual(systemAudio.stopCount, 1)
    }

    func testMeetingAudioContinuesWhenOneRecognizerFails() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(recognizer: microphone, systemAudioRecognizer: systemAudio)
        store.voiceScribeAudioSource = .meetingAudio

        store.startVoiceScribe()
        systemAudio.sendError("Screen Recording permission is not granted.")

        XCTAssertTrue(store.isVoiceScribeRunning)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.voiceScribeStatus?.contains("continuing with the remaining source") == true)

        microphone.sendFinal("Microphone still captured the fallback")

        XCTAssertTrue(store.isVoiceScribeRunning)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.voiceScribeStatus, "Appended transcript.")
        XCTAssertTrue(store.selectedBuffer?.text.contains("Microphone still captured the fallback") == true)
    }

    func testMeetingAudioReportsErrorWhenAllRecognizersFail() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(recognizer: microphone, systemAudioRecognizer: systemAudio)
        store.voiceScribeAudioSource = .meetingAudio

        store.startVoiceScribe()
        systemAudio.sendError("Screen Recording permission is not granted.")
        microphone.sendError("Microphone permission is not granted.")

        XCTAssertFalse(store.isVoiceScribeRunning)
        XCTAssertEqual(microphone.stopCount, 1)
        XCTAssertEqual(systemAudio.stopCount, 1)
        XCTAssertTrue(store.voiceScribeStatus?.contains("Screen Recording permission is not granted.") == true)
        XCTAssertTrue(store.voiceScribeStatus?.contains("Microphone permission is not granted.") == true)
    }

    func testAutoMeetingAudioDetectsMeetingAppAndUsesCombinedRecognizers() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(
            recognizer: microphone,
            systemAudioRecognizer: systemAudio,
            meetingAppDetector: {
                VoiceScribeMeetingAppDetection(displayName: "Zoom", bundleIdentifier: "us.zoom.xos")
            }
        )
        store.voiceScribeAudioSource = .autoMeeting

        store.startVoiceScribe()
        microphone.sendFinal("Daily check in")

        XCTAssertEqual(microphone.startCount, 1)
        XCTAssertEqual(systemAudio.startCount, 1)
        XCTAssertEqual(store.voiceScribeDetectedMeetingApp?.displayName, "Zoom")
        XCTAssertEqual(store.selectedBuffer?.title, "Zoom Transcript")
    }

    func testAutoMeetingAudioFallsBackToMicrophoneWhenNoMeetingAppIsDetected() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(
            recognizer: microphone,
            systemAudioRecognizer: systemAudio,
            meetingAppDetector: { nil }
        )
        store.voiceScribeAudioSource = .autoMeeting

        store.startVoiceScribe()

        XCTAssertEqual(microphone.startCount, 1)
        XCTAssertEqual(systemAudio.startCount, 0)
        XCTAssertNil(store.voiceScribeDetectedMeetingApp)
    }

    func testAutoMeetingWatcherStartsScribeWhenMeetingAppAppears() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(
            recognizer: microphone,
            systemAudioRecognizer: systemAudio,
            meetingAppDetector: {
                VoiceScribeMeetingAppDetection(displayName: "Google Meet", bundleIdentifier: "com.google.Chrome")
            }
        )

        store.isVoiceScribeAutoMeetingEnabled = true

        XCTAssertTrue(store.isScribePanelVisible)
        XCTAssertTrue(store.isVoiceScribeRunning)
        XCTAssertEqual(store.voiceScribeAudioSource, .autoMeeting)
        XCTAssertEqual(store.voiceScribeDetectedMeetingApp?.displayName, "Google Meet")
        XCTAssertEqual(store.voiceScribeAutoMeetingStatus, "Started Google Meet transcript.")
        XCTAssertEqual(microphone.startCount, 1)
        XCTAssertEqual(systemAudio.startCount, 1)

        microphone.sendFinal("Automatic transcript line")

        XCTAssertEqual(store.selectedBuffer?.title, "Google Meet Transcript")
        XCTAssertTrue(store.selectedBuffer?.text.contains("Automatic transcript line") == true)
    }

    func testStoppingAutoStartedMeetingScribeDisablesWatcher() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(
            recognizer: microphone,
            systemAudioRecognizer: systemAudio,
            meetingAppDetector: {
                VoiceScribeMeetingAppDetection(displayName: "Google Meet", bundleIdentifier: "com.google.Chrome")
            }
        )
        store.isVoiceScribeAutoMeetingEnabled = true

        store.stopVoiceScribe()
        let restarted = store.checkVoiceScribeAutoMeetingNow()

        XCTAssertFalse(restarted)
        XCTAssertFalse(store.isVoiceScribeAutoMeetingEnabled)
        XCTAssertFalse(store.isVoiceScribeRunning)
        XCTAssertEqual(microphone.stopCount, 1)
        XCTAssertEqual(microphone.startCount, 1)
        XCTAssertEqual(systemAudio.startCount, 1)
    }

    func testAutoMeetingWatcherWaitsWhenNoMeetingAppIsDetected() {
        let microphone = FakeVoiceScribeRecognizer()
        let systemAudio = FakeVoiceScribeRecognizer()
        let store = makeStore(
            recognizer: microphone,
            systemAudioRecognizer: systemAudio,
            meetingAppDetector: { nil }
        )

        store.isVoiceScribeAutoMeetingEnabled = true

        XCTAssertFalse(store.isVoiceScribeRunning)
        XCTAssertEqual(store.voiceScribeAutoMeetingStatus, "Watching for meeting apps...")
        XCTAssertEqual(microphone.startCount, 0)
        XCTAssertEqual(systemAudio.startCount, 0)
    }

    private func makeStore(
        buffer: EditorBuffer = EditorBuffer.scratch(index: 1),
        recognizer: FakeVoiceScribeRecognizer,
        systemAudioRecognizer: FakeVoiceScribeRecognizer? = nil,
        meetingAppDetector: @escaping () -> VoiceScribeMeetingAppDetection? = { nil },
        voiceScribeAutoMeetingEnabled: Bool? = nil
    ) -> EditorStore {
        EditorStore(
            initialBuffers: [buffer],
            selectedID: buffer.id,
            persistence: nil,
            voiceScribeRecognizerFactory: { recognizer },
            systemAudioScribeRecognizerFactory: { systemAudioRecognizer },
            voiceScribeMeetingAppDetector: meetingAppDetector,
            voiceScribeAutoMeetingEnabled: voiceScribeAutoMeetingEnabled,
            voiceScribeAutoMeetingPollIntervalNanoseconds: 60_000_000_000,
            autoPersistOnInit: false,
            registerNetworkReceiver: false
        )
    }
}

private final class FakeVoiceScribeRecognizer: VoiceScribeRecognizing {
    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String) -> Void)?
    private var onError: ((String) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        startCount += 1
        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onError = onError
    }

    func stop() {
        stopCount += 1
    }

    func sendPartial(_ text: String) {
        onPartial?(text)
    }

    func sendFinal(_ text: String) {
        onFinal?(text)
    }

    func sendError(_ message: String) {
        onError?(message)
    }
}
