import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 20)

            supportDocumentsButton
                .padding(.horizontal, 10)

            Spacer(minLength: 16)

            Divider()
                .padding(.horizontal, 18)

            connectionCard
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var supportDocumentsButton: some View {
        Button {
            state.showWorkspaceList()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: AppDestination.documents.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(AppDestination.documents.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(GCTheme.brand)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .gcSidebarTab(selected: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isSelected)
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
    }
}
