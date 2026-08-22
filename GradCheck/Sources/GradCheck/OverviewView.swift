import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var state: AppState

    private var priorityFindings: [AuditFinding] {
        Array(state.findings.filter { $0.status != .ready }.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summaryHero

                HStack(spacing: 14) {
                    StatusMetricCard(status: .blocked, count: state.blockedCount)
                    StatusMetricCard(status: .humanReview, count: state.humanReviewCount)
                    StatusMetricCard(status: .ready, count: state.readyCount)
                }

                HStack(alignment: .top, spacing: 18) {
                    priorityCard
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 18) {
                        documentReadinessCard
                        auditHistoryCard
                    }
                    .frame(width: 330)
                }

                safetyNote
            }
            .frame(maxWidth: 1160)
            .frame(maxWidth: .infinity)
            .gcPagePadding()
        }
    }

    private var summaryHero: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [GCTheme.brand, GCTheme.brandDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            decorativeMark
                .offset(x: 26, y: 28)

            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(heroEyebrow)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.15)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(heroTitle)
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(.white)
                    Text(heroMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 610, alignment: .leading)
                    HStack(spacing: 10) {
                        Button {
                            if !state.hasCurrentAudit {
                                state.runAudit()
                            } else if state.blockedCount > 0 || state.humanReviewCount > 0 {
                                state.destination = .audit
                            } else {
                                state.runAudit()
                            }
                        } label: {
                            Label(heroActionTitle, systemImage: "arrow.right")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(GCTheme.brand)

                        Button("지원 서류 보기") {
                            state.destination = .documents
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.9))
                        .foregroundStyle(.white)
                    }
                }
                Spacer()
                VStack(alignment: .center, spacing: 5) {
                    Text(state.hasCurrentAudit ? "\(state.blockedCount)" : "—")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(state.hasCurrentAudit ? "제출 전 수정 항목" : "검수 전")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: 150, height: 116)
                .background(.white.opacity(0.095))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            }
            .padding(28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(minHeight: 230)
    }

    private var decorativeMark: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.055), lineWidth: 38)
                .frame(width: 220, height: 220)
            Image(systemName: "checkmark")
                .font(.system(size: 90, weight: .black))
                .foregroundStyle(.white.opacity(0.045))
        }
    }

    private var heroEyebrow: String {
        if !state.hasCurrentAudit { return "AUDIT REQUIRED" }
        return state.blockedCount > 0 ? "REVIEW NEEDED" : "READY FOR FINAL REVIEW"
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
                        eyebrow: "PRIORITY",
                        subtitle: "BLOCKED와 HUMAN REVIEW를 우선순위대로 보여드려요."
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
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(finding.status.color)
                                        Text(finding.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(GCTheme.ink)
                                            .lineLimit(1)
                                    }
                                    Text(finding.summary)
                                        .font(.system(size: 12))
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

    private var documentReadinessCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle("지원 서류", eyebrow: "DOCUMENTS")
                    Spacer()
                    Text("\(state.coreDocumentCount) / 4")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(GCTheme.brand)
                }
                HStack(spacing: 8) {
                    ForEach([DocumentType.cv, .sop, .transcript, .englishScore]) { type in
                        let exists = state.documents.contains { $0.type == type && $0.processingStatus == .ready }
                        VStack(spacing: 7) {
                            Image(systemName: exists ? "checkmark.circle.fill" : type.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(exists ? ReviewStatus.ready.color : Color.secondary)
                            Text(type.shortTitle)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(exists ? GCTheme.ink : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(exists ? ReviewStatus.ready.color.opacity(0.07) : Color.black.opacity(0.025))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                Button("서류 관리") { state.destination = .documents }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var auditHistoryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("최근 검수", eyebrow: "HISTORY")
                if let latest = state.history.first {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GCTheme.brand)
                            .frame(width: 30, height: 30)
                            .background(GCTheme.brandSoft)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(latest.note)
                                .font(.system(size: 12, weight: .semibold))
                            Text(latest.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("BLOCKED \(latest.blockedCount) · REVIEW \(latest.reviewCount) · READY \(latest.readyCount)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(GCTheme.secondaryInk)
                        }
                    }
                } else {
                    Text("아직 검수 이력이 없습니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(GCTheme.brand)
            Text("GradCheck는 업로드된 문서의 누락과 불일치를 확인하는 제출 전 QA 도구입니다. 합격 가능성, 공식 발급 여부, 학점 환산, 영어 면제 또는 비자 승인을 판단하지 않습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

private struct StatusMetricCard: View {
    let status: ReviewStatus
    let count: Int

    var body: some View {
        SurfaceCard(padding: 16) {
            HStack(spacing: 13) {
                Image(systemName: status.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 38, height: 38)
                    .background(status.color.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count)")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(GCTheme.ink)
                    Text(status.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(status.color)
                }
                Spacer()
                Text(status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
