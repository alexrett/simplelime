import Darwin
import Foundation
import SwiftTerm

protocol TerminalProcessRunning: AnyObject {
    func send(_ data: ArraySlice<UInt8>)
    func resize(columns: Int, rows: Int)
    func stop()
}

extension TerminalProcessRunning {
    func resize(columns: Int, rows: Int) {}
}

typealias TerminalProcessFactory = (
    _ workingDirectory: URL,
    _ onOutput: @escaping ([UInt8]) -> Void,
    _ onExit: @escaping (Int32) -> Void
) throws -> TerminalProcessRunning

final class LocalTerminalProcess: TerminalProcessRunning, LocalProcessDelegate, @unchecked Sendable {
    private let workingDirectory: URL
    private let shellPath: String
    private let terminalType: String
    private let terminalLocale: String
    private let onOutput: ([UInt8]) -> Void
    private let onExit: (Int32) -> Void
    private let outputQueue = DispatchQueue(label: "SimpleLime.LocalTerminalProcess.output", qos: .userInitiated)

    private var process: LocalProcess!
    private var columns: Int = 120
    private var rows: Int = 24

    init(
        workingDirectory: URL,
        shellPath: String = TerminalConfiguration.currentShellPath(),
        terminalType: String = TerminalConfiguration.currentTerminalType(),
        terminalLocale: String = TerminalConfiguration.currentLocale(),
        onOutput: @escaping ([UInt8]) -> Void,
        onExit: @escaping (Int32) -> Void
    ) throws {
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath
        self.terminalType = TerminalConfiguration.sanitizedTerminalType(terminalType)
        self.terminalLocale = TerminalConfiguration.sanitizedLocale(terminalLocale)
        self.onOutput = onOutput
        self.onExit = onExit
        self.process = LocalProcess(delegate: self, dispatchQueue: outputQueue)

        try start()
    }

    func send(_ data: ArraySlice<UInt8>) {
        process.send(data: data)
    }

    func resize(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        self.columns = columns
        self.rows = rows

        var size = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        guard process.running else { return }
        _ = ioctl(process.childfd, TIOCSWINSZ, &size)
    }

    func stop() {
        process.terminate()
    }

    private func start() throws {
        let execName = "-" + URL(fileURLWithPath: shellPath).lastPathComponent
        process.startProcess(
            executable: shellPath,
            environment: processEnvironment(),
            execName: execName,
            currentDirectory: workingDirectory.path
        )
    }

    private func processEnvironment() -> [String] {
        let environment = Self.processEnvironmentDictionary(
            baseEnvironment: ProcessInfo.processInfo.environment,
            shellPath: shellPath,
            terminalType: terminalType,
            columns: columns,
            rows: rows,
            locale: terminalLocale
        )

        return environment.map { "\($0.key)=\($0.value)" }
    }

    static func processEnvironmentDictionary(
        baseEnvironment: [String: String],
        shellPath: String,
        terminalType: String,
        columns: Int,
        rows: Int,
        locale: String = TerminalConfiguration.defaultLocale
    ) -> [String: String] {
        var environment = baseEnvironment
        let fallbackLocale = TerminalConfiguration.sanitizedLocale(locale)
        environment["TERM"] = terminalType
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "SimpleLime"
        environment["LANG"] = normalizedUTF8Locale(environment["LANG"], fallback: fallbackLocale)
        environment["LC_CTYPE"] = normalizedUTF8Locale(environment["LC_CTYPE"], fallback: fallbackLocale)
        if let lcAll = environment["LC_ALL"], !TerminalConfiguration.isUTF8Locale(lcAll) {
            environment["LC_ALL"] = fallbackLocale
        }
        environment["COLUMNS"] = "\(columns)"
        environment["LINES"] = "\(rows)"
        environment["SHELL"] = shellPath

        return environment
    }

    private static func normalizedUTF8Locale(_ rawValue: String?, fallback: String) -> String {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              TerminalConfiguration.isUTF8Locale(rawValue) else {
            return fallback
        }

        return rawValue
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        onExit(exitCode.map(Self.normalizedWaitStatus) ?? -1)
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        onOutput(Array(slice))
    }

    func getWindowSize() -> winsize {
        winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
    }

    private static func normalizedWaitStatus(_ status: Int32) -> Int32 {
        guard status >= 0 else { return status }

        let signal = status & 0x7f
        if signal == 0 {
            return (status >> 8) & 0xff
        }

        return 128 + signal
    }
}

enum LocalTerminalProcessError: LocalizedError {
    case openPTYFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .openPTYFailed(let code):
            return "Could not create terminal PTY: \(String(cString: strerror(code)))."
        }
    }
}
