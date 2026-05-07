import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @ObservedObject var store: EditorStore
    let isFullScreen: Bool

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Color(nsColor: .windowBackgroundColor)
                        .frame(width: leadingInset)
                        .allowsHitTesting(false)
                    Divider()

                    ForEach(store.buffers) { buffer in
                        TabItemView(
                            buffer: buffer,
                            isSelected: buffer.id == store.selectedBufferID,
                            dragPayload: Self.tabDragPayload(groupID: store.windowGroupID, bufferID: buffer.id),
                            select: { store.select(buffer.id) },
                            close: { store.closeBuffer(id: buffer.id) }
                        )
                    }
                }
            }

            Divider()

            Button {
                store.newScratch()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("New scratch buffer")
        }
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onDrop(of: [.plainText], isTargeted: nil, perform: handleTabDrop)
    }

    private var leadingInset: CGFloat {
        isFullScreen ? 0 : 80
    }

    private static func tabDragPayload(groupID: UUID, bufferID: UUID) -> String {
        "simplelime-tab:\(groupID.uuidString):\(bufferID.uuidString)"
    }

    private func handleTabDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String,
                  let parsed = parseTabDragPayload(payload) else {
                return
            }

            DispatchQueue.main.async {
                store.moveTabFromGroup(parsed.groupID, bufferID: parsed.bufferID)
            }
        }

        return true
    }

    private func parseTabDragPayload(_ payload: String) -> (groupID: UUID, bufferID: UUID)? {
        let parts = payload.split(separator: ":").map(String.init)
        guard parts.count == 3,
              parts[0] == "simplelime-tab",
              let groupID = UUID(uuidString: parts[1]),
              let bufferID = UUID(uuidString: parts[2]) else {
            return nil
        }

        return (groupID, bufferID)
    }
}

private struct TabItemView: View {
    let buffer: EditorBuffer
    let isSelected: Bool
    let dragPayload: String
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(buffer.displayTitle)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                if buffer.isDirty {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(minWidth: 86, maxWidth: 180, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onDrag {
            NSItemProvider(object: dragPayload as NSString)
        }
        .overlay(alignment: .top) {
            if isSelected {
                Color(nsColor: .controlAccentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Divider()
        }
    }
}
