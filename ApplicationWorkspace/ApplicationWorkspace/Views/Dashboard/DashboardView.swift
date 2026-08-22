import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var statusFilter: DashboardStatusFilter = .all
    @State private var categoryFilter: ApplicationCategory?

    let onAdd: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summary
                filters

                if filteredApplications.isEmpty {
                    SectionCard {
                        EmptyPlaceholder(
                            icon: "tray",
                            title: "조건에 맞는 지원이 없어요",
                            message: "필터를 바꾸거나 새 모집요강을 추가해 보세요."
                        )
                        .frame(height: 260)
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(filteredApplications) { application in
                            ApplicationCardView(application: application) {
                                store.route = .application(application.id)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("지원 현황")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("내 지원 현황")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("마감, 준비율, 그리고 지금 할 일을 한눈에 확인하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onAdd) {
                Label("공고 추가", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            MetricTile(
                title: "준비 중인 지원",
                value: "\(store.applications.filter { !$0.isCompleted }.count)",
                icon: "tray.full.fill",
                tint: .awAccent
            )
            MetricTile(
                title: "7일 이내 마감",
                value: "\(store.applications.filter { !$0.isCompleted && (0...7).contains($0.daysRemaining) }.count)",
                icon: "clock.badge.exclamationmark.fill",
                tint: .orange
            )
            MetricTile(
                title: "확인이 필요한 지원",
                value: "\(store.applications.filter { $0.eligibility == .needsReview }.count)",
                icon: "questionmark.circle.fill",
                tint: .blue
            )
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(DashboardStatusFilter.allCases) { filter in
                    FilterChip(title: filter.rawValue, isSelected: statusFilter == filter) {
                        withAnimation(.snappy) { statusFilter = filter }
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                FilterChip(title: "모든 분야", isSelected: categoryFilter == nil) {
                    withAnimation(.snappy) { categoryFilter = nil }
                }
                ForEach(ApplicationCategory.allCases) { category in
                    FilterChip(title: category.rawValue, isSelected: categoryFilter == category) {
                        withAnimation(.snappy) { categoryFilter = category }
                    }
                }
                Spacer()
            }
        }
    }

    private var filteredApplications: [ApplicationItem] {
        store.applications.filter { application in
            let matchesStatus: Bool
            switch statusFilter {
            case .all:
                matchesStatus = true
            case .preparing:
                matchesStatus = !application.isCompleted
            case .urgent:
                matchesStatus = !application.isCompleted && (0...7).contains(application.daysRemaining)
            case .completed:
                matchesStatus = application.isCompleted
            }

            let matchesCategory = categoryFilter == nil || application.category == categoryFilter
            return matchesStatus && matchesCategory
        }
    }
}

private struct ApplicationCardView: View {
    let application: ApplicationItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SectionCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        StatusPill(
                            application.category.rawValue,
                            icon: application.category.icon,
                            tint: application.category.tint
                        )
                        Spacer()
                        Text(application.dDayText)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(dDayColor)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(application.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                        Text(application.organization)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        StatusPill(
                            application.eligibility.rawValue,
                            icon: application.eligibility.icon,
                            tint: application.eligibility.tint
                        )
                        if application.isCompleted {
                            StatusPill("지원 완료", icon: "checkmark.seal.fill", tint: .green)
                        }
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Text("제출 준비")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(application.readyDocumentCount)/\(application.requiredDocuments.count) · \(application.progressPercent)%")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        ProgressView(value: application.progress)
                            .tint(application.category.tint)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.awAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("다음 행동")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(application.nextAction)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var dDayColor: Color {
        if application.daysRemaining <= 3 { return .red }
        if application.daysRemaining <= 7 { return .orange }
        return .primary
    }
}
