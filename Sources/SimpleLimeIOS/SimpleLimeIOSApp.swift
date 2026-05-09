import SwiftUI

@main
struct SimpleLimeIOSApp: App {
    @StateObject private var store = MobileEditorStore()

    var body: some Scene {
        WindowGroup {
            MobileContentView(store: store)
        }
    }
}
