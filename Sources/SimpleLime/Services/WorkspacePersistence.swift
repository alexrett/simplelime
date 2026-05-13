import Foundation

private struct StoredWorkspaceIndex: Codable {
    var selectedWorkspaceID: UUID?
    var profiles: [WorkspaceProfile]
}

final class WorkspacePersistence {
    private let fileManager: FileManager
    private let rootURL: URL
    private let indexURL: URL

    var appDataRootURL: URL {
        rootURL
    }

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? SessionPersistence.defaultRootURL(fileManager: fileManager)
        indexURL = self.rootURL.appendingPathComponent("workspaces.json", isDirectory: false)
    }

    func loadIndex() -> WorkspaceIndex {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder.workspaceDecoder.decode(StoredWorkspaceIndex.self, from: data) else {
            return WorkspaceIndex(profiles: [WorkspaceProfile.default], selectedWorkspaceID: WorkspaceProfile.defaultID)
        }

        var profiles = sanitizedProfiles(stored.profiles)
        if profiles.isEmpty {
            profiles = [WorkspaceProfile.default]
        } else if !profiles.contains(where: { $0.id == WorkspaceProfile.defaultID }) {
            profiles.insert(WorkspaceProfile.default, at: 0)
        }

        let selectedID = stored.selectedWorkspaceID.flatMap { selectedID in
            profiles.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? profiles.first?.id

        return WorkspaceIndex(profiles: profiles, selectedWorkspaceID: selectedID)
    }

    func save(profiles: [WorkspaceProfile], selectedWorkspaceID: UUID?) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sanitized = sanitizedProfiles(profiles)
        let selectedID = selectedWorkspaceID.flatMap { selectedID in
            sanitized.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? sanitized.first?.id
        let payload = StoredWorkspaceIndex(selectedWorkspaceID: selectedID, profiles: sanitized)
        let data = try JSONEncoder.workspaceEncoder.encode(payload)
        try data.write(to: indexURL, options: .atomic)
    }

    func sessionPersistence(for profile: WorkspaceProfile) -> SessionPersistence {
        SessionPersistence(fileManager: fileManager, rootURL: sessionRootURL(for: profile))
    }

    func taskBoardPersistence(for profile: WorkspaceProfile) -> TaskBoardPersistence {
        TaskBoardPersistence(
            fileManager: fileManager,
            boardURL: sessionRootURL(for: profile).appendingPathComponent("tasks.json", isDirectory: false)
        )
    }

    func globalTaskBoardPersistence() -> TaskBoardPersistence {
        TaskBoardPersistence(
            fileManager: fileManager,
            boardURL: rootURL.appendingPathComponent("global-tasks.json", isDirectory: false)
        )
    }

    func sessionRootURL(for profile: WorkspaceProfile) -> URL {
        if profile.id == WorkspaceProfile.defaultID {
            return rootURL
        }

        return rootURL
            .appendingPathComponent("Workspaces", isDirectory: true)
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
    }

    private func sanitizedProfiles(_ profiles: [WorkspaceProfile]) -> [WorkspaceProfile] {
        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()
        return profiles.compactMap { profile in
            let name = Self.normalizedName(profile.name)
            guard !name.isEmpty,
                  !seenIDs.contains(profile.id),
                  !seenNames.contains(name.lowercased()) else {
                return nil
            }

            seenIDs.insert(profile.id)
            seenNames.insert(name.lowercased())
            var sanitized = profile
            sanitized.name = name
            return sanitized
        }
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension JSONEncoder {
    static var workspaceEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var workspaceDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
