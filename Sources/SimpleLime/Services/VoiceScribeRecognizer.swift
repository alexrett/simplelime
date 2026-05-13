import AVFoundation
import Foundation
import CoreMedia
import ScreenCaptureKit
import Speech

protocol VoiceScribeRecognizing: AnyObject {
    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    )
    func stop()
}

final class SystemVoiceScribeRecognizer: VoiceScribeRecognizing {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isStopping = false

    init(locale: Locale = Locale.current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        guard let recognizer, recognizer.isAvailable else {
            onError("Speech recognition is unavailable.")
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                guard speechStatus == .authorized else {
                    onError("Speech recognition permission is not granted.")
                    return
                }

                self.requestMicrophoneAccess(
                    onGranted: {
                        self.startAudioRecognition(
                            recognizer: recognizer,
                            onPartial: onPartial,
                            onFinal: onFinal,
                            onError: onError
                        )
                    },
                    onDenied: {
                        onError("Microphone permission is not granted.")
                    }
                )
            }
        }
    }

    func stop() {
        isStopping = true
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func requestMicrophoneAccess(onGranted: @escaping () -> Void, onDenied: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            onGranted()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    granted ? onGranted() : onDenied()
                }
            }
        default:
            onDenied()
        }
    }

    private func startAudioRecognition(
        recognizer: SFSpeechRecognizer,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        isStopping = false

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            recognitionRequest = nil
            onError("Could not start microphone capture: \(error.localizedDescription)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinal(transcript)
                    } else {
                        onPartial(transcript)
                    }
                }

                if let error {
                    guard self?.isStopping != true else { return }
                    self?.stop()
                    onError(error.localizedDescription)
                }
            }
        }
    }
}

final class SystemAudioVoiceScribeRecognizer: NSObject, VoiceScribeRecognizing, SCStreamOutput {
    private let recognizer: SFSpeechRecognizer?
    private let sampleHandlerQueue = DispatchQueue(label: "SimpleLime.SystemAudioScribe")
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var stream: SCStream?
    private var captureTask: Task<Void, Never>?
    private var isStopping = false

    init(locale: Locale = Locale.current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        guard let recognizer, recognizer.isAvailable else {
            onError("Speech recognition is unavailable.")
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                guard speechStatus == .authorized else {
                    onError("Speech recognition permission is not granted.")
                    return
                }

                self.startSystemAudioRecognition(
                    recognizer: recognizer,
                    onPartial: onPartial,
                    onFinal: onFinal,
                    onError: onError
                )
            }
        }
    }

    func stop() {
        isStopping = true
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        captureTask?.cancel()
        captureTask = nil

        if let stream {
            Task {
                try? await stream.stopCapture()
            }
        }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        recognitionRequest?.appendAudioSampleBuffer(sampleBuffer)
    }

    private func startSystemAudioRecognition(
        recognizer: SFSpeechRecognizer,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        isStopping = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinal(transcript)
                    } else {
                        onPartial(transcript)
                    }
                }

                if let error {
                    guard self?.isStopping != true else { return }
                    self?.stop()
                    onError(error.localizedDescription)
                }
            }
        }

        captureTask = Task { [weak self] in
            guard let owner = self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    throw SystemAudioVoiceScribeError.noDisplay
                }

                let configuration = SCStreamConfiguration()
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                configuration.queueDepth = 3
                configuration.showsCursor = false
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true

                let stream = SCStream(
                    filter: SCContentFilter(display: display, excludingWindows: []),
                    configuration: configuration,
                    delegate: nil
                )
                try stream.addStreamOutput(owner, type: .audio, sampleHandlerQueue: owner.sampleHandlerQueue)

                await MainActor.run {
                    owner.stream = stream
                }
                try await stream.startCapture()
            } catch {
                await MainActor.run {
                    guard owner.isStopping != true else { return }
                    owner.stop()
                    onError("Could not start system audio capture: \(error.localizedDescription)")
                }
            }
        }
    }
}

final class CombinedVoiceScribeRecognizer: VoiceScribeRecognizing {
    private let recognizers: [VoiceScribeRecognizing]
    private let lock = NSLock()
    private var failedRecognizerIDs: Set<ObjectIdentifier> = []
    private var failureMessages: [String] = []
    private var isStopping = false

    init(recognizers: [VoiceScribeRecognizing]) {
        self.recognizers = recognizers
    }

    func start(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        guard !recognizers.isEmpty else {
            onError("Meeting audio scribe is unavailable.")
            return
        }

        lock.withLock {
            failedRecognizerIDs = []
            failureMessages = []
            isStopping = false
        }

        recognizers.forEach { recognizer in
            recognizer.start(
                onPartial: onPartial,
                onFinal: onFinal,
                onError: { [weak self, weak recognizer] message in
                    guard let self, let recognizer else { return }
                    self.handleRecognizerError(
                        message,
                        recognizer: recognizer,
                        onError: onError,
                        onStatus: onStatus
                    )
                },
                onStatus: onStatus
            )
        }
    }

    func stop() {
        lock.withLock {
            isStopping = true
        }
        recognizers.forEach { $0.stop() }
    }

    private func handleRecognizerError(
        _ message: String,
        recognizer: VoiceScribeRecognizing,
        onError: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        let shouldReport: Bool
        let shouldWarn: Bool

        (shouldReport, shouldWarn) = lock.withLock {
            guard !isStopping else { return (false, false) }
            failedRecognizerIDs.insert(ObjectIdentifier(recognizer))
            failureMessages.append(message)
            let allFailed = failedRecognizerIDs.count >= recognizers.count
            return (allFailed, !allFailed)
        }

        if shouldWarn {
            onStatus("One meeting audio source failed; continuing with the remaining source: \(message)")
            return
        }

        guard shouldReport else { return }
        let combinedMessage = lock.withLock {
            Array(Set(failureMessages)).sorted().joined(separator: " ")
        }
        onError(combinedMessage.isEmpty ? "Meeting audio scribe is unavailable." : combinedMessage)
    }
}

private enum SystemAudioVoiceScribeError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display is available for system audio capture."
        }
    }
}
