import SwiftUI

/// The dashboard is an operational home for one active application. It keeps
/// the existing audit pipeline intact while giving the user a calmer overview
/// of official sources, evidence, and submission checks.
struct ApplicationsDashboardView: View {
    @EnvironmentObject private var state: AppState

    private var readiness: Int {
        let sourceReady = state.documents.contains {
            $0.type == .requirements && $0.processingStatus == .ready
        } ? 1 : 0
        return Int((Double(state.coreDocumentCount + sourceReady) / 5.0 * 100).rounded())
    }

    private var pendingFindings: [AuditFinding] {
        state.findings
            .filter { $0.status != .ready }
            .sorted { $0.status.rank < $1.status.rank }
    }

    private var tasks: [DashboardTask] {
        if state.hasCurrentAudit {
            let auditTasks = pendingFindings.prefix(4).map { finding in
                DashboardTask(
                    id: finding.id.uuidString,
                    title: finding.title,
                    detail: finding.category.rawValue,
                    dueLabel: finding.status == .blocked ? "수정 필요" : "확인 필요",
                    status: finding.status
                ) {
                    state.selectedFindingID = finding.id
                    state.destination = .audit
                }
            }
            if !auditTasks.isEmpty { return auditTasks }
            return [
                DashboardTask(
                    id: "final-check",
                    title: "최종 제출 전 직접 확인",
                    detail: "공식 포털의 최신 안내를 확인하세요",
                    dueLabel: "다음",
                    status: .humanReview
                ) { state.destination = .audit }
            ]
        }

        var setupTasks: [DashboardTask] = []
        if !state.documents.contains(where: { $0.type == .requirements && $0.processingStatus == .ready }) {
            setupTasks.append(
                DashboardTask(
                    id: "official-source",
                    title: "공식 모집요강 추가",
                    detail: "학교 공통 및 프로그램 고유 안내",
                    dueLabel: "시작",
                    status: .humanReview
                ) { state.destination = .requirements }
            )
        }
        for type in [DocumentType.cv, .sop, .transcript, .englishScore] where !state.documents.contains(where: { $0.type == type && $0.processingStatus == .ready }) {
            setupTasks.append(
                DashboardTask(
                    id: "document-\(type.rawValue)",
                    title: "\(type.shortTitle) 추가",
                    detail: "Evidence Vault에 제출용 최신 파일을 등록하세요",
                    dueLabel: "준비",
                    status: .blocked
                ) { state.destination = .documents }
            )
        }
        if setupTasks.isEmpty {
            setupTasks.append(
                DashboardTask(
                    id: "run-audit",
                    title: "제출 점검 실행",
                    detail: "업로드된 파일을 기준으로 불일치를 확인합니다",
                    dueLabel: "다음",
                    status: .humanReview
                ) { state.runAudit() }
            )
        }
        return Array(setupTasks.prefix(4))
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader
                    currentApplicationGroup
                    workflowGroup
                    productBoundary
                }
                .frame(maxWidth: 1_120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 28)
            }

            Divider()

            dashboardInspector
                .frame(width: 328)
                .background(GCTheme.canvas)
        }
        .background(GCTheme.canvas)
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            PageTitle(
                "지원 현황",
                subtitle: "공식 요건과 내 서류를 대조해 지금 해야 할 일을 정리합니다."
            )
            Spacer(minLength: 16)
            WorkspaceBadge(status: state.workspace.status)
                .padding(.top, 5)
        }
    }

    private var currentApplicationGroup: some View {
        SurfaceCard(padding: 0) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(GCTheme.brand)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("현재 지원")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(GCTheme.secondaryInk)
                            Text(state.workspace.compactTitle)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(GCTheme.ink)
                            Text(state.workspace.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(GCTheme.secondaryInk)
                        }
                        Spacer(minLength: 20)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("준비도")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(GCTheme.secondaryInk)
                            Text("\(readiness)%")
                                .font(.system(size: 20, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(GCTheme.ink)
                        }
                    }

                    HStack(spacing: 14) {
                        Text(preparationSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(GCTheme.secondaryInk)
                        ProgressView(value: Double(readiness), total: 100)
                            .tint(GCTheme.brand)
                            .frame(maxWidth: 260)
                        Spacer(minLength: 8)
                        Button("자세히 보기") {
                            state.destination = state.hasCurrentAudit ? .audit : .documents
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GCTheme.brand)
                    }
                    .padding(.top, 18)
                }
                .padding(20)
            }
        }
    }

    private var preparationSummary: String {
        if state.hasCurrentAudit {
            let count = state.blockedCount + state.humanReviewCount
            return count == 0 ? "제출 전 직접 확인 1개" : "제출 전 남은 작업 \(count)개"
        }
        return "핵심 문서 \(state.coreDocumentCount) / 4개"
    }

    private var workflowGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("작업 공간", subtitle: "공식 소스, 증빙, 제출 점검을 한 흐름으로 관리합니다.")
                Spacer()
                Button("제출 점검") { state.destination = .audit }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GCTheme.brand)
            }

            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    WorkspaceStageRow(
                        icon: "link",
                        title: "공식 요건 소스",
                        detail: sourceDescription,
                        status: sourceStatus
                    ) { state.destination = .requirements }
                    Divider().padding(.leading, 52)
                    WorkspaceStageRow(
                        icon: "doc.on.doc",
                        title: "Evidence Vault",
                        detail: "핵심 증빙 \(state.coreDocumentCount) / 4개 준비됨",
                        status: documentStatus
                    ) { state.destination = .documents }
                    Divider().padding(.leading, 52)
                    WorkspaceStageRow(
                        icon: "checkmark.shield",
                        title: "제출 점검",
                        detail: auditDescription,
                        status: auditStatus
                    ) {
                        if state.hasCurrentAudit {
                            state.destination = .audit
                        } else {
                            state.runAudit()
                        }
                    }
                }
            }
        }
    }

    private var sourceDescription: String {
        guard let document = state.documents.first(where: { $0.type == .requirements }) else {
            return "학교 또는 프로그램의 공식 안내가 필요합니다"
        }
        return document.processingStatus == .ready ? "\(state.requirements.count)개 요건을 출처와 함께 정리함" : "공식 안내를 읽는 중입니다"
    }

    private var sourceStatus: ReviewStatus {
        state.documents.contains { $0.type == .requirements && $0.processingStatus == .ready } ? .ready : .humanReview
    }

    private var documentStatus: ReviewStatus {
        state.coreDocumentCount == 4 ? .ready : .blocked
    }

    private var auditDescription: String {
        guard state.hasCurrentAudit else { return "업로드된 문서를 기준으로 한 번 더 확인하세요" }
        if state.blockedCount > 0 { return "수정 필요 \(state.blockedCount)개 · 직접 확인 \(state.humanReviewCount)개" }
        if state.humanReviewCount > 0 { return "직접 확인 \(state.humanReviewCount)개가 남아 있습니다" }
        return "업로드된 근거 기준으로 완료되었습니다"
    }

    private var auditStatus: ReviewStatus {
        guard state.hasCurrentAudit else { return .humanReview }
        if state.blockedCount > 0 { return .blocked }
        if state.humanReviewCount > 0 { return .humanReview }
        return .ready
    }

    private var dashboardInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardCalendar(
                createdAt: state.workspace.createdAt,
                auditedAt: state.workspace.lastAuditedAt
            )
            .padding(.horizontal, 22)
            .padding(.top, 32)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var productBoundary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(GCTheme.secondaryInk)
            Text("합격 가능성, 공식 발급 여부, 학점 환산, 영어 면제 및 비자 승인은 판단하지 않습니다. 확인이 필요한 항목은 원문 근거와 함께 표시합니다.")
                .font(.system(size: 12))
                .foregroundStyle(GCTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}

private struct DashboardTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let dueLabel: String
    let status: ReviewStatus
    let action: () -> Void
}

private struct DashboardTaskRow: View {
    let task: DashboardTask

    var body: some View {
        Button(action: task.action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: task.status == .ready ? "checkmark.circle" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(task.status.color)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GCTheme.ink)
                        .lineLimit(2)
                    Text(task.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(GCTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 5)
                Text(task.dueLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(task.status.color)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceStageRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: ReviewStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(GCTheme.secondaryInk)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GCTheme.ink)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(GCTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                WorkspaceStageStatus(status: status)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GCTheme.tertiaryInk)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceStageStatus: View {
    let status: ReviewStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text(status.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(status.color)
    }
}

private struct DashboardCalendar: View {
    let createdAt: Date
    let auditedAt: Date?

    private let calendar = Calendar.current
    private var month: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now }

    private var days: [Date?] {
        let weekday = calendar.component(.weekday, from: month)
        let prefix = Array(repeating: Optional<Date>.none, count: weekday - 1)
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<1
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        let total = prefix.count + dates.count
        return prefix + dates + Array(repeating: Optional<Date>.none, count: (7 - total % 7) % 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("검수 일정", subtitle: month.formatted(.dateTime.year().month(.wide)))
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
                    CalendarDay(
                        date: date,
                        isToday: date.map { calendar.isDateInToday($0) } ?? false,
                        hasAudit: date.map { isSameDay($0, auditedAt) } ?? false,
                        hasCreated: date.map { isSameDay($0, createdAt) } ?? false
                    )
                }
            }

            HStack(spacing: 12) {
                CalendarLegend(color: GCTheme.brand, label: "오늘")
                CalendarLegend(color: GCTheme.secondaryInk, label: "워크스페이스")
                if auditedAt != nil { CalendarLegend(color: ReviewStatus.ready.color, label: "검수") }
            }
        }
    }

    private func isSameDay(_ lhs: Date, _ rhs: Date?) -> Bool {
        guard let rhs else { return false }
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }
}

private struct CalendarDay: View {
    let date: Date?
    let isToday: Bool
    let hasAudit: Bool
    let hasCreated: Bool

    var body: some View {
        VStack(spacing: 3) {
            if let date {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? .white : GCTheme.ink)
                    .frame(width: 22, height: 22)
                    .background(isToday ? GCTheme.brand : .clear, in: Circle())
                HStack(spacing: 3) {
                    Circle().fill(hasCreated ? GCTheme.secondaryInk : .clear).frame(width: 3, height: 3)
                    Circle().fill(hasAudit ? ReviewStatus.ready.color : .clear).frame(width: 3, height: 3)
                }
                .frame(height: 3)
            } else {
                Color.clear.frame(height: 28)
            }
        }
        .frame(height: 34)
    }
}

private struct CalendarLegend: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(GCTheme.secondaryInk)
        }
    }
}
