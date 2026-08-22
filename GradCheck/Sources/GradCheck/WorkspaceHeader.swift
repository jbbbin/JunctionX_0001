import SwiftUI

struct WorkspaceHeader: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(state.workspace.school)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(GCTheme.ink)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(state.workspace.degree)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GCTheme.secondaryInk)
                    WorkspaceBadge(status: state.workspace.status)
                    if state.workspace.isSample {
                        Text("SAMPLE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(GCTheme.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(GCTheme.blue.opacity(0.09))
                            .clipShape(Capsule())
                    }
                }
                Text("\(state.workspace.program) · \(state.workspace.intake)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GCTheme.secondaryInk)
                    .lineLimit(1)
            }
            Spacer()
            if state.hasCurrentAudit, let lastAuditedAt = state.workspace.lastAuditedAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("최근 검수")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(lastAuditedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GCTheme.secondaryInk)
                }
            }
            Button {
                state.runAudit()
            } label: {
                Label(state.isImporting ? "문서 분석 중" : "지원 패키지 검수", systemImage: state.isImporting ? "hourglass" : "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(GCTheme.brand)
            .disabled(state.isAuditing || state.isImporting)
        }
        .padding(.horizontal, 28)
        .padding(.top, 19)
        .padding(.bottom, 17)
        .background(.regularMaterial)
    }
}
