import SwiftUI

/// A calm, operational overview of the active application package. The visual
/// layout mirrors a native macOS source list + content + inspector arrangement;
/// it deliberately keeps the existing single-workspace audit flow unchanged.
struct GradOpsDashboardView: View {
    @EnvironmentObject private var state: AppState

    private var readiness: Int {
        if state.workspace.isSample { return 58 }

        let sourceReady = state.documents.contains {
            $0.type == .requirements && $0.processingStatus == .ready
        } ? 1 : 0
        let base = Int((Double(state.coreDocumentCount + sourceReady) / 5.0 * 100).rounded())
        let unresolvedPenalty = min(30, (state.blockedCount + state.humanReviewCount) * 6)
        return max(0, base - unresolvedPenalty)
    }

    private var currentStatus: ReviewStatus {
        if state.blockedCount > 0 { return .blocked }
        if state.humanReviewCount > 0 { return .humanReview }
        return .ready
    }

    private var applicationRows: [ApplicationBoardItem] {
        let current = ApplicationBoardItem(
            id: "current",
            title: state.workspace.compactTitle,
            subtitle: state.workspace.isSample
                ? "MIT Graduate Application · Dec 01, 2026 23:59 ET"
                : state.workspace.subtitle,
            deadline: state.workspace.isSample ? "D-18 · Dec 01" : "마감일 미등록",
            readiness: readiness,
            status: currentStatus,
            statusLabel: currentStatus == .blocked ? "검수 필요" : currentStatus.label,
            isCurrent: true
        )

        guard state.workspace.isSample else { return [current] }
        return [
            current,
            ApplicationBoardItem(
                id: "berkeley",
                title: "UC Berkeley EECS PhD",
                subtitle: "공식 페이지 2곳 확인",
                deadline: "D-27 · Dec 10",
                readiness: 72,
                status: .humanReview,
                statusLabel: "서류 준비 중"
            ),
            ApplicationBoardItem(
                id: "stanford",
                title: "Stanford MS CS",
                subtitle: "공식 페이지 2곳 확인",
                deadline: "D-41 · Dec 24",
                readiness: 88,
                status: .ready,
                statusLabel: "제출 점검"
            ),
            ApplicationBoardItem(
                id: "cmu",
                title: "Carnegie Mellon MSML",
                subtitle: "공식 페이지 2곳 확인",
                deadline: "D-55 · Jan 07",
                readiness: 31,
                status: .blocked,
                statusLabel: "소스 추가 필요"
            )
        ]
    }

    private var priorityDescription: String {
        if state.hasCurrentAudit {
            let remaining = state.blockedCount + state.humanReviewCount
            return remaining == 0 ? "제출 전 직접 확인 1개" : "제출 전 남은 작업 (remaining)개"
        }
        return "핵심 문서 (state.coreDocumentCount) / 4개"
    }

    private var sourceStatusText: String {
        state.documents.contains(where: { $0.type == .requirements && $0.processingStatus == .ready })
            ? "공식 소스 연결됨"
            : "공식 소스 필요"
    }

    private var sourceStatusColor: Color {
        state.documents.contains(where: { $0.type == .requirements && $0.processingStatus == .ready })
            ? GCTheme.brand
            : ReviewStatus.humanReview.color
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    priorityGroup
                    applicationList
                    productBoundary
                }
                .frame(maxWidth: 1_120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 28)
            }

            Divider()

            DashboardCalendarInspector(
                createdAt: state.workspace.createdAt,
                auditedAt: state.workspace.lastAuditedAt
            )
            .frame(width: 328)
            .background(GCTheme.canvas)
        }
        .background(GCTheme.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PageTitle(
                "지원 현황",
                subtitle: "공식 소스와 내 서류를 대조해 이번 주의 우선순위를 정리했습니다."
            )
            Spacer(minLength: 20)
            Label(sourceStatusText, systemImage: "circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(sourceStatusColor)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 5)
        }
    }

    private var priorityGroup: some View {
        SurfaceCard(padding: 0) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(GCTheme.brand)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("NEXT DEADLINE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(GCTheme.brand)
                            Text(state.workspace.compactTitle)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(GCTheme.ink)
                            Text(state.workspace.isSample
                                 ? "MIT Graduate Application · Dec 01, 2026 23:59 ET"
                                 : "마감일은 공식 요건 소스에서 확인해 주세요")
                                .font(.system(size: 12))
                                .foregroundStyle(GCTheme.secondaryInk)
                        }
                        Spacer(minLength: 20)
                        VStack(alignment: .trailing, spacing: 8) {
                            DeadlineLabel(
                                title: state.workspace.isSample ? "D-18" : "일정 확인",
                                color: state.workspace.isSample ? ReviewStatus.blocked.color : ReviewStatus.humanReview.color
                            )
                            ReadinessLabel(value: readiness)
                        }
                    }

                    HStack(spacing: 14) {
                        Text(priorityDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(GCTheme.secondaryInk)
                        ProgressView(value: Double(readiness), total: 100)
                            .tint(GCTheme.brand)
                            .frame(maxWidth: 320)
                        Spacer(minLength: 12)
                        Button("자세히 보기") {
                            state.destination = state.hasCurrentAudit ? .audit : .documents
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GCTheme.brand)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
            }
            .frame(minHeight: 156)
        }
    }

    private var applicationList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("내 지원", subtitle: "마감이 가까운 순서로 지원 패키지를 확인합니다.")
                Spacer()
                Text("마감 · 요청 · 결과 발표")
                    .font(.system(size: 11))
                    .foregroundStyle(GCTheme.tertiaryInk)
            }

            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(applicationRows.enumerated()), id: \.element.id) { index, item in
                        ApplicationBoardRow(item: item) {
                            guard item.isCurrent else { return }
                            state.destination = state.hasCurrentAudit ? .audit : .documents
                        }
                        if index < applicationRows.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
        }
    }

    private var productBoundary: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "hand.raised")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GCTheme.secondaryInk)
            Text("GradCheck는 공식 원문과 업로드한 파일을 비교해 제출 전 확인 항목을 정리합니다. 외부 포털 제출과 추천서 작성은 사용자가 직접 진행합니다.")
                .font(.system(size: 12))
                .foregroundStyle(GCTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}

private struct ApplicationBoardItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let deadline: String
    let readiness: Int
    let status: ReviewStatus
    let statusLabel: String
    var isCurrent = false
}

private struct ApplicationBoardRow: View {
    let item: ApplicationBoardItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(item.title.prefix(1).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.isCurrent ? GCTheme.brand : GCTheme.secondaryInk)
                    .frame(width: 28, height: 28)
                    .background(item.isCurrent ? GCTheme.brandSoft : GCTheme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GCTheme.ink)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(GCTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 14)

                Text(item.deadline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GCTheme.secondaryInk)
                    .monospacedDigit()
                    .frame(width: 88, alignment: .trailing)

                Text("\(item.readiness)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GCTheme.ink)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)

                HStack(spacing: 5) {
                    Circle().fill(item.status.color).frame(width: 6, height: 6)
                    Text(item.statusLabel)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(item.status.color)
                .frame(width: 108, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isCurrent)
        .opacity(item.isCurrent ? 1 : 0.94)
    }
}

private struct DeadlineLabel: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }
}

private struct ReadinessLabel: View {
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(GCTheme.brand).frame(width: 6, height: 6)
            Text("준비 \(value)%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(GCTheme.brand)
    }
}

private struct DashboardCalendarInspector: View {
    let createdAt: Date
    let auditedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardMiniCalendar(createdAt: createdAt, auditedAt: auditedAt)
                .padding(.horizontal, 22)
                .padding(.top, 32)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct DashboardMiniCalendar: View {
    let createdAt: Date
    let auditedAt: Date?

    private let calendar = Calendar.current
    private var month: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
    }

    private var days: [Date?] {
        let weekday = calendar.component(.weekday, from: month)
        let prefix = Array(repeating: Optional<Date>.none, count: weekday - 1)
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<1
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        let total = prefix.count + dates.count
        return prefix + dates + Array(repeating: Optional<Date>.none, count: (7 - total % 7) % 7)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 yyyy"
        return formatter.string(from: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(monthTitle, subtitle: "마감 · 요청 · 결과 발표")
                Spacer()
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GCTheme.secondaryInk)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GCTheme.tertiaryInk)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    MiniCalendarDay(
                        date: date,
                        isToday: date.map { calendar.isDateInToday($0) } ?? false,
                        hasWorkspace: date.map { calendar.isDate($0, inSameDayAs: createdAt) } ?? false,
                        hasAudit: date.map { day in
                            guard let auditedAt else { return false }
                            return calendar.isDate(day, inSameDayAs: auditedAt)
                        } ?? false
                    )
                }
            }

        }
    }
}

private struct MiniCalendarDay: View {
    let date: Date?
    let isToday: Bool
    let hasWorkspace: Bool
    let hasAudit: Bool

    var body: some View {
        VStack(spacing: 3) {
            if let date {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? .white : GCTheme.ink)
                    .frame(width: 22, height: 22)
                    .background(isToday ? GCTheme.brand : .clear, in: Circle())
                HStack(spacing: 3) {
                    Circle().fill(hasWorkspace ? GCTheme.secondaryInk : .clear).frame(width: 3, height: 3)
                    Circle().fill(hasAudit ? ReviewStatus.ready.color : .clear).frame(width: 3, height: 3)
                }
                .frame(height: 3)
            } else {
                Color.clear.frame(height: 28)
            }
        }
        .frame(height: 36)
    }
}
