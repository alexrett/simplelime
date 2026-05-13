import Foundation

struct WorkspaceProfile: Identifiable, Codable, Equatable {
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var documentCatalogRootPath: String?

    static var `default`: WorkspaceProfile {
        WorkspaceProfile(
            id: defaultID,
            name: "Default",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            documentCatalogRootPath: nil
        )
    }
}

struct WorkspaceIndex: Equatable {
    var profiles: [WorkspaceProfile]
    var selectedWorkspaceID: UUID?
}
