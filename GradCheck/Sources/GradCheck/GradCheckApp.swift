import SwiftUI

@main
struct GradCheckApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 지원 목표") {
                    state.showNewWorkspace = true
                }
                .keyboardShortcut("n")
            }
            CommandMenu("검수") {
                Button("지원 패키지 재검수") {
                    state.runAudit()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.isAuditing || state.isImporting)
            }
        }
    }
}
