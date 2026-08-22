import SwiftUI

struct WorkspaceHeader: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(state.workspace.compactTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GCTheme.ink)
                WorkspaceBadge(status: state.workspace.status)
            }
            Text(state.workspace.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(GCTheme.secondaryInk)
                .lineLimit(1)
            Spacer()
            if state.hasCurrentAudit, let lastAuditedAt = state.workspace.lastAuditedAt {
                Text("최근 검수 \(lastAuditedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(GCTheme.secondaryInk)
                    .monospacedDigit()
            }
            Button {
                state.runAudit()
            } label: {
                Label(state.isImporting ? "문서 분석 중" : "점검 실행", systemImage: state.isImporting ? "hourglass" : "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.isAuditing || state.isImporting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
    }
}
