import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 285)
        } detail: {
            VStack(spacing: 0) {
                if showsWorkspaceHeader {
                    WorkspaceHeader()
                    Divider().opacity(0.55)
                }
                destinationView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(GCTheme.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(GCTheme.brand)
        .background {
            LinearGradient(
                colors: [GCTheme.brand.opacity(0.12), GCTheme.canvas, GCTheme.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .sheet(isPresented: $state.showNewWorkspace) {
            NewWorkspaceSheet(appViewModel: state)
        }
        .sheet(isPresented: $state.isAuditing) {
            AuditProgressSheet()
                .environmentObject(state)
                .interactiveDismissDisabled()
        }
        .overlay(alignment: .top) {
            if let success = state.successMessage {
                ToastView(message: success)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: state.successMessage)
        .alert(
            "문서를 확인할 수 없어요",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
    }

    private var showsWorkspaceHeader: Bool {
        switch state.destination {
        case .documents: state.documentsRoute == .detail
        case .audit: state.auditRoute == .detail
        case .overview, .requirements: true
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch state.destination {
        case .overview: OverviewView()
        case .documents: DocumentsView()
        case .audit: AuditReportView()
        case .requirements: RequirementsView()
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(GCTheme.brand.opacity(0.96))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
    }
}
