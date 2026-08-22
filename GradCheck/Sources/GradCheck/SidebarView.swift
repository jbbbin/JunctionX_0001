import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)

            Text("APPLICATION")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.15)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 19)
                .padding(.bottom, 8)

            applicationCard
                .padding(.horizontal, 10)

            Button {
                state.showNewWorkspace = true
            } label: {
                Label("새 지원 목표", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(GCTheme.brand)
            .padding(.horizontal, 10)
            .padding(.top, 3)

            Divider()
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            VStack(spacing: 4) {
                ForEach(AppDestination.allCases) { destination in
                    Button {
                        state.destination = destination
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: destination.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 20)
                            Text(destination.rawValue)
                                .font(.system(size: 13, weight: state.destination == destination ? .semibold : .medium))
                            Spacer()
                            if destination == .audit && state.blockedCount > 0 {
                                Text("\(state.blockedCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 19, minHeight: 19)
                                    .background(ReviewStatus.blocked.color)
                                    .clipShape(Circle())
                            }
                        }
                        .foregroundStyle(state.destination == destination ? GCTheme.brand : GCTheme.secondaryInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .gcSidebarTab(selected: state.destination == destination)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(state.destination == destination ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 16)

            connectionCard
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gcSidebarGlass()
        .padding(8)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GCTheme.brand)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("GradCheck")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(GCTheme.ink)
                Text("PRE-SUBMISSION QA")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var applicationCard: some View {
        Button {
            state.destination = .overview
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(GCTheme.brandSoft)
                        Text(state.workspace.school.prefix(1))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(GCTheme.brand)
                    }
                    .frame(width: 31, height: 31)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.workspace.school)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GCTheme.ink)
                        Text(state.workspace.program)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Circle()
                        .fill(state.workspace.status.color)
                        .frame(width: 6, height: 6)
                    Text(state.workspace.status.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(state.workspace.status.color)
                    Spacer()
                    Text(state.workspace.intake)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(11)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(GCTheme.brand.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle()
                    .fill(state.isUpstageConnected ? ReviewStatus.ready.color : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(state.providerLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GCTheme.secondaryInk)
                    .lineLimit(1)
            }
            Text(state.isUpstageConnected ? "문서는 연결된 Document Parse로 분석됩니다." : "PDF 텍스트는 이 Mac에서만 읽습니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(GCTheme.secondaryInk.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
