import SwiftUI

@main
struct ApplicationWorkspaceApp: App {
    @StateObject private var viewModel: RootViewModel

    init() {
        _viewModel = StateObject(
            wrappedValue: RootViewModel(dependencies: .localDevelopment())
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .preferredColorScheme(.light)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 900)
    }
}
