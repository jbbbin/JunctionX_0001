import AppKit
import SwiftUI

enum GCTheme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    static let brand = Color(nsColor: .systemBlue)
    static let brandBright = brand
    static let brandDeep = Color(nsColor: .systemIndigo)
    static let brandSoft = brand.opacity(0.12)
    static let line = Color(nsColor: .separatorColor)
    static let blue = brand
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(GCTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GCTheme.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.025), radius: 12, y: 4)
    }
}

struct StatusBadge: View {
    let status: ReviewStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            Text(status.rawValue)
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 6)
        .background(status.color.opacity(0.105))
        .clipShape(Capsule())
        .accessibilityLabel("\(status.rawValue), \(status.label)")
    }
}

struct WorkspaceBadge: View {
    let status: WorkspaceStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            Text(status.label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.09))
        .clipShape(Capsule())
    }
}

struct PageSourceChip: View {
    let evidence: EvidenceRef

    var body: some View {
        Label(evidence.sourceLabel, systemImage: "doc.text")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(GCTheme.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(GCTheme.secondaryInk.opacity(0.09))
            .clipShape(Capsule())
    }
}

struct SectionTitle: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(GCTheme.brandBright)
            }
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GCTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(GCTheme.brand)
                .frame(width: 64, height: 64)
                .background(GCTheme.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GCTheme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(GCTheme.brand)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(30)
    }
}

struct WorkspaceSelectionView: View {
    @EnvironmentObject private var state: AppViewModel
    @State private var pendingDeletion: ApplicationWorkspace?

    let title: String
    let eyebrow: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?
    let select: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    SectionTitle(title, eyebrow: eyebrow, subtitle: subtitle)
                    Spacer()
                    if let actionTitle, let action {
                        Button(action: action) {
                            Label(actionTitle, systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(GCTheme.brand)
                    }
                }

                LazyVStack(spacing: 12) {
                    ForEach(state.workspaces) { workspace in
                        workspaceRow(workspace)
                    }
                }
            }
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
            .gcPagePadding()
        }
        .alert(
            "지원 항목을 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { workspace in
            Button("취소", role: .cancel) { pendingDeletion = nil }
            Button("삭제", role: .destructive) {
                state.deleteWorkspace(workspace.id)
                pendingDeletion = nil
            }
        } message: { workspace in
            Text("\(workspace.school) · \(workspace.program)의 모집요강, 서류 목록과 검수 이력이 이 Mac에서 삭제됩니다.")
        }
    }

    private func workspaceRow(_ workspace: ApplicationWorkspace) -> some View {
        let isCurrent = workspace.id == state.selectedWorkspaceID

        return SurfaceCard(padding: 0) {
            HStack(spacing: 0) {
                Button {
                    select(workspace.id)
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isCurrent ? GCTheme.brandSoft : GCTheme.secondaryInk.opacity(0.07))
                            Text(workspace.school.prefix(1))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(isCurrent ? GCTheme.brand : GCTheme.secondaryInk)
                        }
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(workspace.school)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(GCTheme.ink)
                                if workspace.isSample {
                                    Text("SAMPLE")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundStyle(GCTheme.blue)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(GCTheme.blue.opacity(0.09))
                                        .clipShape(Capsule())
                                }
                            }
                            Text("\(workspace.program) · \(workspace.degree) · \(workspace.intake)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 18)
                        WorkspaceBadge(status: workspace.status)
                    }
                    .padding(.leading, 18)
                    .padding(.vertical, 16)
                    .padding(.trailing, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 44)

                Menu {
                    Button(role: .destructive) {
                        pendingDeletion = workspace
                    } label: {
                        Label("지원 항목 삭제", systemImage: "trash")
                    }
                    .disabled(state.workspaces.count <= 1)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .padding(.horizontal, 8)
                .help(state.workspaces.count <= 1 ? "마지막 지원 항목은 삭제할 수 없습니다." : "지원 항목 관리")
            }
        }
    }
}

private struct GCSidebarTabModifier: ViewModifier {
    let selected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if selected {
                content
                    .glassEffect(
                        .regular.tint(GCTheme.brand.opacity(0.18)).interactive(),
                        in: .rect(cornerRadius: 10)
                    )
            } else {
                content
            }
        } else {
            content
                .background(
                    selected ? GCTheme.brand.opacity(0.13) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
    }
}

extension View {
    func gcPagePadding() -> some View {
        padding(.horizontal, 30).padding(.vertical, 26)
    }

    func gcSidebarTab(selected: Bool) -> some View {
        modifier(GCSidebarTabModifier(selected: selected))
    }
}
