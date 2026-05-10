import Foundation

struct DocumentCatalogNode: Identifiable, Equatable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let children: [DocumentCatalogNode]

    init(url: URL, isDirectory: Bool, children: [DocumentCatalogNode] = []) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.children = children
    }
}

struct DocumentCatalogFileMatch: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let displayPath: String
    let score: Int
}
