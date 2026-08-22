import SwiftUI

@main
struct GradCheckApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1_180, minHeight: 760)
        }
        .defaultSize(width: 1_440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("지원 추가") {
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
