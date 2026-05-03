import Foundation

typealias ACPJSON = [String: Any]

enum ACPAgentClientError: LocalizedError {
    case invalidResponse(String)
    case processUnavailable(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message), .processUnavailable(let message), .requestFailed(let message):
            return message
        }
    }
}

final class ACPAgentClient: @unchecked Sendable {
    let provider: AIAgentProvider
    private let executable: String
    private let arguments: [String]
    private let workingDirectory: URL

    private var process: Process?
    private var inputPipe = Pipe()
    private var outputPipe = Pipe()
    private var errorPipe = Pipe()
    private let receiveQueue = DispatchQueue(label: "SimpleLime.ACPAgentClient.receive")
    private let sendQueue = DispatchQueue(label: "SimpleLime.ACPAgentClient.send")
    private var readBuffer = Data()
    private var nextRequestID = 1
    private var pendingRequests: [Int: CheckedContinuation<ACPJSON?, Error>] = [:]
    private(set) var supportsEmbeddedContext = false
    private(set) var isInitialized = false

    var onAssistantText: ((String, String) -> Void)?
    var onStatus: ((String, String) -> Void)?
    var onReadTextFile: ((String, Int?, Int?) async -> String?)?
    var onWriteTextFile: ((String, String) async -> Bool)?

    init(provider: AIAgentProvider, executable: String, arguments: [String], workingDirectory: URL) {
        self.provider = provider
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    deinit {
        stop()
    }

    func initializeIfNeeded() async throws {
        guard !isInitialized else { return }
        try startIfNeeded()

        let result = try await request(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "fs": [
                        "readTextFile": true,
                        "writeTextFile": true
                    ],
                    "terminal": false
                ],
                "clientInfo": [
                    "name": "simplelime",
                    "title": "SimpleLime",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
                ]
            ]
        )

        guard let result else {
            throw ACPAgentClientError.invalidResponse("Agent did not return initialize result.")
        }

        let version = result["protocolVersion"] as? Int ?? (result["protocolVersion"] as? NSNumber)?.intValue
        guard version == 1 else {
            throw ACPAgentClientError.invalidResponse("Agent returned unsupported ACP protocol version.")
        }

        if let capabilities = result["agentCapabilities"] as? ACPJSON,
           let prompt = capabilities["promptCapabilities"] as? ACPJSON {
            supportsEmbeddedContext = (prompt["embeddedContext"] as? Bool)
                ?? (prompt["embeddedContext"] as? NSNumber)?.boolValue
                ?? false
        }

        isInitialized = true
    }

    func newSession(cwd: String) async throws -> String {
        try await initializeIfNeeded()

        let result = try await request(
            method: "session/new",
            params: [
                "cwd": cwd,
                "mcpServers": []
            ]
        )

        guard let sessionId = result?["sessionId"] as? String else {
            throw ACPAgentClientError.invalidResponse("Agent did not return sessionId.")
        }

        return sessionId
    }

    func prompt(sessionID: String, prompt: [ACPJSON]) async throws -> String {
        try await initializeIfNeeded()

        let result = try await request(
            method: "session/prompt",
            params: [
                "sessionId": sessionID,
                "prompt": prompt
            ]
        )

        return result?["stopReason"] as? String ?? "end_turn"
    }

    func cancel(sessionID: String) {
        send([
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": ["sessionId": sessionID]
        ])
    }

    func stop() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        isInitialized = false
        supportsEmbeddedContext = false
    }

    private func startIfNeeded() throws {
        guard process == nil else { return }

        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = workingDirectory
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = processEnvironment()
        process.terminationHandler = { [weak self] process in
            self?.handleProcessExit(code: process.terminationStatus)
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.receiveQueue.async {
                self?.consume(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else {
                return
            }
            self?.emitStatus("stderr", text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        do {
            try process.run()
            self.process = process
        } catch {
            throw ACPAgentClientError.processUnavailable("Could not start \(provider.displayName): \(error.localizedDescription)")
        }
    }

    private func request(method: String, params: ACPJSON) async throws -> ACPJSON? {
        let requestID = nextID()
        return try await withCheckedThrowingContinuation { continuation in
            receiveQueue.async {
                self.pendingRequests[requestID] = continuation
                self.send([
                    "jsonrpc": "2.0",
                    "id": requestID,
                    "method": method,
                    "params": params
                ])
            }
        }
    }

    private func nextID() -> Int {
        receiveQueue.sync {
            let id = nextRequestID
            nextRequestID += 1
            return id
        }
    }

    private func consume(_ data: Data) {
        readBuffer.append(data)

        while let newlineIndex = readBuffer.firstIndex(of: 10) {
            let lineData = readBuffer[..<newlineIndex]
            readBuffer.removeSubrange(readBuffer.startIndex...newlineIndex)

            guard !lineData.isEmpty,
                  let line = String(data: lineData, encoding: .utf8) else {
                continue
            }

            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? ACPJSON else {
            emitStatus("protocol", "Ignored invalid ACP message.")
            return
        }

        if let requestID = numericRequestID(object["id"]),
           object["result"] != nil || object["error"] != nil {
            completePendingRequest(requestID, response: object)
            return
        }

        if let method = object["method"] as? String {
            let params = object["params"] as? ACPJSON ?? [:]
            if object["id"] != nil {
                handleIncomingRequest(method: method, id: object["id"] as Any, params: params)
            } else {
                handleIncomingNotification(method: method, params: params)
            }
        }
    }

    private func completePendingRequest(_ requestID: Int, response: ACPJSON) {
        guard let continuation = pendingRequests.removeValue(forKey: requestID) else {
            return
        }

        if let error = response["error"] as? ACPJSON {
            let message = error["message"] as? String ?? "ACP request failed."
            continuation.resume(throwing: ACPAgentClientError.requestFailed(message))
            return
        }

        if response["result"] is NSNull {
            continuation.resume(returning: nil)
        } else {
            continuation.resume(returning: response["result"] as? ACPJSON)
        }
    }

    private func handleIncomingNotification(method: String, params: ACPJSON) {
        guard method == "session/update",
              let sessionID = params["sessionId"] as? String,
              let update = params["update"] as? ACPJSON else {
            return
        }

        let updateType = update["sessionUpdate"] as? String ?? "update"

        switch updateType {
        case "agent_message_chunk":
            if let text = textContent(in: update["content"]) {
                onAssistantText?(sessionID, text)
            }
        case "tool_call":
            let title = update["title"] as? String ?? "Tool call"
            let status = update["status"] as? String ?? "pending"
            emitStatus(sessionID, "\(title): \(status)")
        case "tool_call_update":
            let status = update["status"] as? String ?? "updated"
            if let text = textContent(in: update["content"]) {
                emitStatus(sessionID, text)
            } else {
                emitStatus(sessionID, "Tool: \(status)")
            }
        case "plan":
            if let entries = update["entries"] as? [ACPJSON] {
                let active = entries.first { ($0["status"] as? String) == "in_progress" }
                let content = active?["content"] as? String ?? entries.first?["content"] as? String
                if let content {
                    emitStatus(sessionID, content)
                }
            }
        default:
            if let text = textContent(in: update["content"]) {
                onAssistantText?(sessionID, text)
            }
        }
    }

    private func handleIncomingRequest(method: String, id: Any, params: ACPJSON) {
        switch method {
        case "fs/read_text_file":
            let path = params["path"] as? String ?? ""
            let line = (params["line"] as? Int) ?? (params["line"] as? NSNumber)?.intValue
            let limit = (params["limit"] as? Int) ?? (params["limit"] as? NSNumber)?.intValue
            Task { [weak self] in
                guard let self else { return }
                if let content = await self.onReadTextFile?(path, line, limit) {
                    self.sendResponse(id: id, result: ["content": content])
                } else {
                    self.sendError(id: id, message: "SimpleLime can only read currently open buffers.")
                }
            }
        case "fs/write_text_file":
            let path = params["path"] as? String ?? ""
            let content = params["content"] as? String ?? ""
            Task { [weak self] in
                guard let self else { return }
                if await self.onWriteTextFile?(path, content) == true {
                    self.sendResponse(id: id, result: nil)
                } else {
                    self.sendError(id: id, message: "SimpleLime can only modify currently open buffers.")
                }
            }
        case "session/request_permission":
            let options = params["options"] as? [ACPJSON] ?? []
            if let optionID = preferredPermissionOptionID(options) {
                sendResponse(id: id, result: ["outcome": ["outcome": "selected", "optionId": optionID]])
            } else {
                sendResponse(id: id, result: ["outcome": ["outcome": "cancelled"]])
            }
        default:
            sendError(id: id, message: "SimpleLime does not implement \(method).")
        }
    }

    private func sendResponse(id: Any, result: Any?) {
        send([
            "jsonrpc": "2.0",
            "id": id,
            "result": result ?? NSNull()
        ])
    }

    private func sendError(id: Any, message: String) {
        send([
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": -32000,
                "message": message
            ]
        ])
    }

    private func send(_ message: ACPJSON) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              var line = String(data: data, encoding: .utf8) else {
            return
        }

        line.append("\n")
        guard let payload = line.data(using: .utf8) else { return }

        sendQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.inputPipe.fileHandleForWriting.write(contentsOf: payload)
            } catch {
                self.emitStatus("protocol", "Could not write ACP message: \(error.localizedDescription)")
            }
        }
    }

    private func emitStatus(_ sessionID: String, _ status: String) {
        guard !status.isEmpty else { return }
        onStatus?(sessionID, status)
    }

    private func handleProcessExit(code: Int32) {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        process = nil
        isInitialized = false
        supportsEmbeddedContext = false

        receiveQueue.async {
            let pending = self.pendingRequests
            self.pendingRequests.removeAll()
            for continuation in pending.values {
                continuation.resume(throwing: ACPAgentClientError.processUnavailable("\(self.provider.displayName) exited with code \(code)."))
            }
        }
        emitStatus("process", "\(provider.displayName) exited with code \(code).")
    }

    private func numericRequestID(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private func textContent(in value: Any?) -> String? {
        if let content = value as? ACPJSON {
            if content["type"] as? String == "text" {
                return content["text"] as? String
            }

            if let nested = content["content"] {
                return textContent(in: nested)
            }
        }

        if let items = value as? [ACPJSON] {
            return items.compactMap { item in
                if let content = item["content"] {
                    return textContent(in: content)
                }
                return textContent(in: item)
            }
            .joined(separator: "\n")
        }

        return nil
    }

    private func preferredPermissionOptionID(_ options: [ACPJSON]) -> String? {
        let preferredKinds = ["allow_once", "allow_always"]

        for kind in preferredKinds {
            if let option = options.first(where: { $0["kind"] as? String == kind }),
               let optionID = option["optionId"] as? String {
                return optionID
            }
        }

        return options.first?["optionId"] as? String
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = "\(extraPath):\(existingPath)"
        } else {
            environment["PATH"] = extraPath
        }

        return environment
    }
}
