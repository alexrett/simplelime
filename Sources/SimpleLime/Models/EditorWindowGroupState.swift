import Foundation

struct EditorWindowGroupState: Identifiable, Equatable {
    var id: UUID
    var selectedBufferID: UUID?
    var buffers: [EditorBuffer]
}
