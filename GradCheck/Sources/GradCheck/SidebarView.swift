import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    private var destinationSelection: Binding<AppDestination?> {
        Binding(
            get: { state.destination },
            set: { if let destination = $0 { state.destination = destination } }
        )
    }

    var body: some View {
        List(selection: destinationSelection) {
            Section("WORKSPACES") {
                ForEach(AppDestination.allCases) { destination in
                    HStack(spacing: 10) {
                        Label(destination.rawValue, systemImage: destination.symbol)
                            .font(.system(size: 13, weight: .regular))
                        Spacer(minLength: 0)
                        if destination == .audit && state.blockedCount > 0 {
                            Text("\(state.blockedCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(ReviewStatus.blocked.color)
                        }
                    }
                    .tag(destination)
                }
            }
            Section("내 지원") {
                currentApplicationRow
                if state.workspace.isSample {
                    referenceApplicationRow("UC Berkeley EECS", status: .humanReview)
                    referenceApplicationRow("Stanford MS CS", status: .ready)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var currentApplicationRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "building.columns")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(nsColor: .selectedMenuItemTextColor))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.workspace.compactTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: .selectedMenuItemTextColor))
                    .lineLimit(1)
                Text("\(state.workspace.degree) · \(state.workspace.intake)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .selectedMenuItemTextColor).opacity(0.78))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(Color(nsColor: .selectedMenuItemTextColor).opacity(0.9))
                .frame(width: 7, height: 7)
        }
        .padding(.vertical, 3)
        .listRowBackground(GCTheme.selected)
    }

    private func referenceApplicationRow(_ title: String, status: ReviewStatus) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(GCTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
