import SwiftUI

@main
struct ApplicationWorkspaceApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 820)
    }
}
