import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 232, ideal: 248, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if state.destination != .overview {
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
        .background(GCTheme.canvas)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("GradCheck")
                    .font(.system(size: 13, weight: .semibold))
            }
            ToolbarItem(placement: .principal) {
                Text(state.destination.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GCTheme.secondaryInk)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.showNewWorkspace = true
                } label: {
                    Label("지원 추가", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(GCTheme.brand)
            }
        }
        .sheet(isPresented: $state.showNewWorkspace) {
            NewWorkspaceSheet()
                .environmentObject(state)
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
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.22), value: state.successMessage)
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

    @ViewBuilder
    private var destinationView: some View {
        switch state.destination {
        case .overview: GradOpsDashboardView()
        case .documents: EvidenceVaultView()
        case .audit: AuditReportView()
        case .requirements: RequirementsView()
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(nsColor: .systemGreen))
            Text(message)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(GCTheme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(GCTheme.line.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}
