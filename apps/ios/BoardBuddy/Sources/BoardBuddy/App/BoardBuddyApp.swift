import SwiftUI

@main
struct BoardBuddyApp: App {
    @StateObject private var clipStore = ClipStore()

    var body: some Scene {
        WindowGroup {
            ClipListView()
                .environmentObject(clipStore)
        }
    }
}
