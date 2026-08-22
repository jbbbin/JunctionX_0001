import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var state: AppState

    private var priorityFindings: [AuditFinding] {
        Array(state.findings.filter { $0.status != .ready }.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader
                statusStrip

                HStack(alignment: .top, spacing: 18) {
                    priorityCard
                        .frame(maxWidth: .infinity)
                    sideInspector
                    .frame(width: 330)
                }

                safetyNote
            }
            .frame(maxWidth: 1160)
            .frame(maxWidth: .infinity)
            .gcPagePadding()
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            PageTitle(
                "제출 준비 현황",
                subtitle: "\(state.workspace.school) · \(state.workspace.program) · \(state.workspace.intake)"
            )
            Spacer()
            WorkspaceBadge(status: state.workspace.status)
        }
    }

    private var statusStrip: some View {
        SurfaceCard(padding: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(heroEyebrow)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GCTheme.secondaryInk)
                    Text(heroTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GCTheme.ink)
                    Text(heroMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(GCTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)

                Divider()
                    .frame(height: 76)

                HStack(spacing: 18) {
                    StatusStripMetric(status: .blocked, count: state.blockedCount)
                    StatusStripMetric(status: .humanReview, count: state.humanReviewCount)
                    StatusStripMetric(status: .ready, count: state.readyCount)
                }
                .padding(.horizontal, 20)

                Button {
                    if !state.hasCurrentAudit {
                        state.runAudit()
                    } else if state.blockedCount > 0 || state.humanReviewCount > 0 {
                        state.destination = .audit
                    } else {
                        state.runAudit()
                    }
                } label: {
                    Label(heroActionTitle, systemImage: state.hasCurrentAudit ? "arrow.right" : "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(GCTheme.brand)
                .padding(.trailing, 18)
            }
        }
    }

    private var heroEyebrow: String {
        if !state.hasCurrentAudit { return "검수 필요" }
        return state.blockedCount > 0 ? "검수 결과" : "제출 전 점검"
    }

    private var heroTitle: String {
        if !state.hasCurrentAudit { return "현재 문서로 검수를 시작해 주세요" }
        if state.blockedCount == 0 { return "제출 전 직접 확인만 남았어요" }
        return "\(state.blockedCount)개의 문제를 먼저 해결해 주세요"
    }

    private var heroMessage: String {
        if !state.hasCurrentAudit {
            return "문서가 바뀌면 이전 결과는 자동으로 무효화됩니다. 현재 파일을 기준으로 누락과 불일치, 페이지 근거를 다시 만들어요."
        }
        if state.blockedCount == 0 {
            return "업로드된 근거 기준으로 제출을 막는 문제는 발견되지 않았습니다. HUMAN REVIEW 항목은 본인 또는 기관과 최종 확인하세요."
        }
        return "가장 중요한 문제부터 문서와 페이지 근거를 연결해 두었습니다. 파일을 수정해 교체하면 영향받은 항목을 다시 검수할 수 있어요."
    }

    private var heroActionTitle: String {
        if !state.hasCurrentAudit { return "검수 시작" }
        return state.blockedCount > 0 ? "문제부터 확인" : "다시 검수"
    }

    private var priorityCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    SectionTitle(
                        "먼저 확인할 항목",
                        eyebrow: "우선순위",
                        subtitle: "수정 필요와 직접 확인 항목을 우선순위대로 보여드려요."
                    )
                    Spacer()
                    Button("전체 리포트") {
                        state.destination = .audit
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GCTheme.brand)
                }
                .padding(.bottom, 13)

                if !state.hasCurrentAudit {
                    EmptyStateView(
                        symbol: "sparkles",
                        title: "현재 문서의 검수가 필요해요",
                        message: "지원 패키지 검수를 실행하면 우선순위와 원문 근거가 여기에 표시됩니다.",
                        actionTitle: "검수 시작",
                        action: { state.runAudit() }
                    )
                } else if priorityFindings.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.seal.fill",
                        title: "우선 확인할 문제가 없어요",
                        message: "READY 결과와 직접 확인 항목을 최종 점검하세요."
                    )
                } else {
                    ForEach(Array(priorityFindings.enumerated()), id: \.element.id) { index, finding in
                        Button {
                            state.selectedFindingID = finding.id
                            state.destination = .audit
                        } label: {
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: finding.status.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(finding.status.color)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(finding.category.rawValue)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(finding.status.color)
                                        Text(finding.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(GCTheme.ink)
                                            .lineLimit(1)
                                    }
                                    Text(finding.summary)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if let evidence = finding.evidences.first {
                                        PageSourceChip(evidence: evidence)
                                    }
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 3)
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < priorityFindings.count - 1 {
                            Divider().opacity(0.65)
                        }
                    }
                }
            }
        }
    }

    private var sideInspector: some View {
        SurfaceCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                documentReadinessSection
                    .padding(18)
                Divider()
                auditHistorySection
                    .padding(18)
            }
        }
    }

    private var documentReadinessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionTitle("지원 서류", eyebrow: "제출 패키지")
                Spacer()
                Text("\(state.coreDocumentCount) / 4")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GCTheme.brand)
                    .monospacedDigit()
            }

            VStack(spacing: 0) {
                ForEach(Array([DocumentType.cv, .sop, .transcript, .englishScore].enumerated()), id: \.element.id) { index, type in
                    let exists = state.documents.contains { $0.type == type && $0.processingStatus == .ready }
                    DocumentReadinessRow(type: type, isReady: exists)
                    if index < 3 { Divider().padding(.leading, 27) }
                }
            }

            Button("서류 관리") { state.destination = .documents }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var auditHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("최근 검수", eyebrow: "기록")
            if let latest = state.history.first {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(GCTheme.secondaryInk)
                        .frame(width: 25)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(latest.note)
                            .font(.system(size: 13, weight: .medium))
                        Text(latest.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(GCTheme.secondaryInk)
                            .monospacedDigit()
                        Text("수정 \(latest.blockedCount) · 확인 \(latest.reviewCount) · 완료 \(latest.readyCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(GCTheme.secondaryInk)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("아직 검수 이력이 없습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(GCTheme.secondaryInk)
            }
        }
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(GCTheme.brand)
            Text("GradCheck는 업로드된 문서의 누락과 불일치를 확인하는 제출 전 QA 도구입니다. 합격 가능성, 공식 발급 여부, 학점 환산, 영어 면제 또는 비자 승인을 판단하지 않습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

private struct StatusStripMetric: View {
    let status: ReviewStatus
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: status.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(status.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(status.color)
            Text("\(count)")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(GCTheme.ink)
                .monospacedDigit()
        }
        .frame(minWidth: 46, alignment: .leading)
    }
}

private struct DocumentReadinessRow: View {
    let type: DocumentType
    let isReady: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isReady ? "checkmark.circle.fill" : type.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isReady ? ReviewStatus.ready.color : GCTheme.secondaryInk)
                .frame(width: 18)
            Text(type.shortTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GCTheme.ink)
            Spacer()
            Text(isReady ? "준비됨" : "필요")
                .font(.system(size: 11))
                .foregroundStyle(isReady ? ReviewStatus.ready.color : GCTheme.secondaryInk)
        }
        .padding(.vertical, 7)
    }
}
