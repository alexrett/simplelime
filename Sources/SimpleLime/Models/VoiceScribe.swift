import AppKit
import Foundation

struct VoiceScribeConfiguration: Equatable {
    var title: String
    var speaker: String
    var capturesCommands: Bool
    var detectedMeetingApp: VoiceScribeMeetingAppDetection?

    var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Voice Transcript",
           let detectedMeetingApp {
            return "\(detectedMeetingApp.displayName) Transcript"
        }

        return trimmed.isEmpty ? "Voice Transcript" : trimmed
    }

    var normalizedSpeaker: String? {
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum VoiceScribeAudioSource: String, CaseIterable, Identifiable, Equatable {
    case autoMeeting
    case microphone
    case systemAudio
    case meetingAudio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .autoMeeting:
            return "Auto"
        case .microphone:
            return "Microphone"
        case .systemAudio:
            return "System Audio"
        case .meetingAudio:
            return "Mic + System"
        }
    }

    var permissionStatus: String {
        switch self {
        case .autoMeeting:
            return "Detecting meeting app..."
        case .microphone:
            return "Requesting microphone access..."
        case .systemAudio:
            return "Requesting system audio access..."
        case .meetingAudio:
            return "Requesting microphone and system audio access..."
        }
    }

    var unavailableMessage: String {
        switch self {
        case .autoMeeting:
            return "Auto meeting scribe is unavailable."
        case .microphone:
            return "Microphone scribe is unavailable."
        case .systemAudio:
            return "System audio scribe is unavailable."
        case .meetingAudio:
            return "Meeting audio scribe is unavailable."
        }
    }
}

struct VoiceScribeRunningApplication: Equatable {
    var bundleIdentifier: String?
    var localizedName: String?
    var windowTitles: [String] = []
    var browserTabURLs: [String] = []
}

struct VoiceScribeMeetingAppDetection: Equatable {
    var displayName: String
    var bundleIdentifier: String?
}

enum VoiceScribeMeetingAppDetector {
    static func detect(in applications: [VoiceScribeRunningApplication]) -> VoiceScribeMeetingAppDetection? {
        applications.compactMap(detection(for:)).first
    }

    static func detectRunningApplication() -> VoiceScribeMeetingAppDetection? {
        return detect(
            in: applicationsForDetection(
                runningApplications: NSWorkspace.shared.runningApplications.map {
                    VoiceScribeRunningApplication(
                        bundleIdentifier: $0.bundleIdentifier,
                        localizedName: $0.localizedName,
                        windowTitles: windowTitles(forProcessIdentifier: $0.processIdentifier)
                    )
                },
                browserTabURLProvider: browserTabURLs(for:)
            )
        )
    }

    static func applicationsForDetection(
        runningApplications: [VoiceScribeRunningApplication],
        browserTabURLProvider: (String?) -> [String]
    ) -> [VoiceScribeRunningApplication] {
        runningApplications.map { application in
            let browserTabURLs = scriptableBrowserBundleIdentifiers.contains(
                application.bundleIdentifier?.lowercased() ?? ""
            )
                ? uniqueBrowserTabURLs(application.browserTabURLs + browserTabURLProvider(application.bundleIdentifier))
                : application.browserTabURLs

            return VoiceScribeRunningApplication(
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                windowTitles: application.windowTitles,
                browserTabURLs: browserTabURLs
            )
        }
    }

    private static func uniqueBrowserTabURLs(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.compactMap { rawURL in
            let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, seen.insert(url).inserted else { return nil }
            return url
        }
    }

    private static let scriptableBrowserBundleIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.microsoft.edgemac",
        "com.brave.browser",
        "company.thebrowser.browser"
    ]

    static func applicationsForDetection(
        runningApplications: [NSRunningApplication]
    ) -> [VoiceScribeRunningApplication] {
        applicationsForDetection(
            runningApplications: runningApplications.map {
                VoiceScribeRunningApplication(
                    bundleIdentifier: $0.bundleIdentifier,
                    localizedName: $0.localizedName,
                    windowTitles: windowTitles(forProcessIdentifier: $0.processIdentifier)
                )
            },
            browserTabURLProvider: browserTabURLs(for:)
        )
    }

    private static func detection(for application: VoiceScribeRunningApplication) -> VoiceScribeMeetingAppDetection? {
        let bundleIdentifier = application.bundleIdentifier?.lowercased() ?? ""
        let name = application.localizedName?.lowercased() ?? ""
        let appHaystack = "\(bundleIdentifier) \(name)"

        for app in knownApps where app.matchesApplication(appHaystack) {
            return VoiceScribeMeetingAppDetection(
                displayName: app.displayName,
                bundleIdentifier: application.bundleIdentifier
            )
        }

        let browserURLHaystack = application.browserTabURLs
            .map { $0.lowercased() }
            .joined(separator: " ")
        for app in knownApps where app.matchesBrowserURL(browserURLHaystack) {
            return VoiceScribeMeetingAppDetection(
                displayName: app.displayName,
                bundleIdentifier: application.bundleIdentifier
            )
        }

        let windowHaystack = application.windowTitles
            .map { $0.lowercased() }
            .joined(separator: " ")
        for app in knownApps where app.matchesWindow(windowHaystack) {
            return VoiceScribeMeetingAppDetection(
                displayName: app.displayName,
                bundleIdentifier: application.bundleIdentifier
            )
        }

        return nil
    }

    private static let knownApps: [KnownMeetingApp] = [
        KnownMeetingApp(
            displayName: "Zoom",
            applicationTokens: ["us.zoom.xos", "zoom.us", "zoom"],
            windowTokens: ["zoom meeting", "zoom.us"],
            browserURLTokens: ["zoom.us/j/", "zoom.us/wc/", "zoom.us/my/"]
        ),
        KnownMeetingApp(
            displayName: "Microsoft Teams",
            applicationTokens: ["com.microsoft.teams", "microsoft teams", "teams"],
            windowTokens: ["microsoft teams", "teams meeting", "teams.microsoft.com"],
            browserURLTokens: ["teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft"]
        ),
        KnownMeetingApp(
            displayName: "Google Meet",
            applicationTokens: ["meet.google.com", "google meet"],
            windowTokens: ["google meet", "meet.google.com"],
            browserURLTokens: ["meet.google.com"]
        ),
        KnownMeetingApp(
            displayName: "FaceTime",
            applicationTokens: ["com.apple.facetime", "facetime"],
            windowTokens: [],
            browserURLTokens: []
        ),
        KnownMeetingApp(
            displayName: "Slack",
            applicationTokens: ["com.tinyspeck.slackmacgap", "slack"],
            windowTokens: ["slack huddle"],
            browserURLTokens: ["app.slack.com/huddle"]
        ),
        KnownMeetingApp(
            displayName: "Discord",
            applicationTokens: ["com.hnc.discord", "discord"],
            windowTokens: ["discord voice", "discord stream"],
            browserURLTokens: ["discord.com/channels/@me"]
        ),
        KnownMeetingApp(
            displayName: "Webex",
            applicationTokens: ["cisco webex", "webex"],
            windowTokens: ["webex meeting", "webex.com"],
            browserURLTokens: ["webex.com/meet", "webex.com/join", "web.webex.com"]
        )
    ]

    private struct KnownMeetingApp {
        var displayName: String
        var applicationTokens: [String]
        var windowTokens: [String]
        var browserURLTokens: [String]

        func matchesApplication(_ value: String) -> Bool {
            applicationTokens.contains { value.contains($0) }
        }

        func matchesWindow(_ value: String) -> Bool {
            windowTokens.contains { value.contains($0) }
        }

        func matchesBrowserURL(_ value: String) -> Bool {
            browserURLTokens.contains { value.contains($0) }
        }
    }

    private static func browserTabURLs(for bundleIdentifier: String?) -> [String] {
        guard let bundleIdentifier = bundleIdentifier?.lowercased(),
              let scriptSource = browserURLScriptSources[bundleIdentifier] else {
            return []
        }

        var errorInfo: NSDictionary?
        guard let result = NSAppleScript(source: scriptSource)?.executeAndReturnError(&errorInfo),
              let scriptResult = result.stringValue else {
            return []
        }

        return parseBrowserTabURLs(scriptResult)
    }

    static func parseBrowserTabURLs(_ scriptResult: String) -> [String] {
        var seen = Set<String>()
        return scriptResult
            .components(separatedBy: .newlines)
            .compactMap { rawURL in
                let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !url.isEmpty, seen.insert(url).inserted else { return nil }
                return url
            }
    }

    private static let browserURLScriptSources: [String: String] = [
        "com.apple.safari": #"""
        tell application id "com.apple.Safari"
            set output to ""
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL is not "" then set output to output & tabURL & linefeed
                end repeat
            end repeat
            return output
        end tell
        """#,
        "com.google.chrome": #"""
        tell application id "com.google.Chrome"
            set output to ""
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL is not "" then set output to output & tabURL & linefeed
                end repeat
            end repeat
            return output
        end tell
        """#,
        "com.microsoft.edgemac": #"""
        tell application id "com.microsoft.edgemac"
            set output to ""
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL is not "" then set output to output & tabURL & linefeed
                end repeat
            end repeat
            return output
        end tell
        """#,
        "com.brave.browser": #"""
        tell application id "com.brave.Browser"
            set output to ""
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL is not "" then set output to output & tabURL & linefeed
                end repeat
            end repeat
            return output
        end tell
        """#,
        "company.thebrowser.browser": #"""
        tell application id "company.thebrowser.Browser"
            set output to ""
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL is not "" then set output to output & tabURL & linefeed
                end repeat
            end repeat
            return output
        end tell
        """#
    ]

    private static func windowTitles(forProcessIdentifier processIdentifier: pid_t) -> [String] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { window in
            guard let ownerPID = windowIntegerValue(window[kCGWindowOwnerPID as String]),
                  ownerPID == Int(processIdentifier),
                  windowIntegerValue(window[kCGWindowLayer as String]) == 0 else {
                return nil
            }

            let title = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title?.isEmpty == false ? title : nil
        }
    }

    private static func windowIntegerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }
}

enum VoiceScribeCommandInterpreter {
    static let wakePhrases = ["simplelime", "simple lime"]

    static func commandRequest(from transcript: String) -> LocalAutomationCommandRequest? {
        let normalized = normalizedPhrase(transcript)
        guard let phrase = wakePhrases.first(where: { normalized == $0 || normalized.hasPrefix($0 + " ") }) else {
            return nil
        }

        let commandText = normalized
            .dropFirst(phrase.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !commandText.isEmpty else { return nil }

        if commandText == "new scratch" || commandText == "new note" || commandText == "new buffer" {
            return LocalAutomationCommandRequest(command: .newScratch, text: nil)
        }

        if commandText == "save" || commandText == "save file" {
            return LocalAutomationCommandRequest(command: .save, text: nil)
        }

        if commandText == "close" || commandText == "close tab" || commandText == "close buffer" {
            return LocalAutomationCommandRequest(command: .close, text: nil)
        }

        if commandText == "force close" || commandText == "force close tab" || commandText == "force close buffer" {
            return LocalAutomationCommandRequest(command: .forceClose, text: nil)
        }

        if commandText == "companion" || commandText == "toggle companion" {
            return LocalAutomationCommandRequest(command: .toggleCompanion, text: nil)
        }

        if commandText == "scan companion" || commandText == "run companion" || commandText == "companion scan" {
            return LocalAutomationCommandRequest(command: .runCompanionScan, text: nil)
        }

        if commandText == "tasks" || commandText == "toggle tasks" || commandText == "task board" {
            return LocalAutomationCommandRequest(command: .toggleTasks, text: nil)
        }

        if commandText == "terminal" || commandText == "toggle terminal" {
            return LocalAutomationCommandRequest(command: .toggleTerminal, text: nil)
        }

        if commandText == "macros" || commandText == "toggle macros" {
            return LocalAutomationCommandRequest(command: .toggleMacros, text: nil)
        }

        if commandText == "stats" || commandText == "toggle stats" {
            return LocalAutomationCommandRequest(command: .toggleStats, text: nil)
        }

        if commandText == "scribe" || commandText == "toggle scribe" {
            return LocalAutomationCommandRequest(command: .toggleScribe, text: nil)
        }

        if commandText == "command palette" || commandText == "show command palette" {
            return LocalAutomationCommandRequest(command: .showCommandPalette, text: nil)
        }

        if let largeFileLineCommand = largeFileLineCommandRequest(from: transcript) {
            return largeFileLineCommand
        }

        if commandText.hasPrefix("insert ") {
            let text = (preservedPayload(after: "insert", from: transcript) ?? String(commandText.dropFirst("insert ".count)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return LocalAutomationCommandRequest(command: .insertText, text: text)
        }

        if commandText.hasPrefix("dictate ") {
            let text = (preservedPayload(after: "dictate", from: transcript) ?? String(commandText.dropFirst("dictate ".count)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return LocalAutomationCommandRequest(command: .insertText, text: text)
        }

        return nil
    }

    private static func largeFileLineCommandRequest(from transcript: String) -> LocalAutomationCommandRequest? {
        if let match = firstMatch(
            in: transcript,
            pattern: #"^\s*(simple\s*lime|simplelime)\s+replace\s+(?:large[-\s]+file\s+)?line\s+([0-9]+)\s+(?:with\s+)?(.+?)\s*$"#
        ),
           let lineNumber = Int(match[2]),
           lineNumber > 0 {
            let replacement = match[3].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !replacement.isEmpty else { return nil }
            return LocalAutomationCommandRequest(
                command: .replaceLargeFileLine,
                text: replacement,
                lineNumber: lineNumber
            )
        }

        if let match = firstMatch(
            in: transcript,
            pattern: #"^\s*(simple\s*lime|simplelime)\s+insert\s+(?:large[-\s]+file\s+)?line\s+([0-9]+)\s+(?:with\s+)?(.+?)\s*$"#
        ),
           let lineNumber = Int(match[2]),
           lineNumber > 0 {
            let insertedText = match[3].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !insertedText.isEmpty else { return nil }
            return LocalAutomationCommandRequest(
                command: .insertLargeFileLine,
                text: insertedText,
                lineNumber: lineNumber
            )
        }

        if let match = firstMatch(
            in: transcript,
            pattern: #"^\s*(simple\s*lime|simplelime)\s+(?:delete|remove)\s+(?:large[-\s]+file\s+)?line\s+([0-9]+)\s*$"#
        ),
           let lineNumber = Int(match[2]),
           lineNumber > 0 {
            return LocalAutomationCommandRequest(
                command: .deleteLargeFileLine,
                text: nil,
                lineNumber: lineNumber
            )
        }

        return nil
    }

    private static func normalizedPhrase(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preservedPayload(after keyword: String, from transcript: String) -> String? {
        let pattern = #"^\s*(simple\s*lime|simplelime)\s+\#(keyword)\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsText = transcript as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: transcript, range: range),
              match.numberOfRanges >= 3 else {
            return nil
        }

        return nsText.substring(with: match.range(at: 2))
    }

    private static func firstMatch(in transcript: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsText = transcript as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: transcript, range: range) else {
            return nil
        }

        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return "" }
            return nsText.substring(with: range)
        }
    }
}

enum VoiceScribeTimestamp {
    static func current(now: Date = Date()) -> String {
        formatter.string(from: now)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
