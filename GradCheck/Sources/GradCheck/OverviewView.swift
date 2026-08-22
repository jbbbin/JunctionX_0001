import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var state: AppViewModel

    private var summaries: [WorkspaceOverviewItem] {
        state.workspaceOverviewItems
    }

    private var priorityFindings: [PortfolioFindingItem] {
        Array(
            state.portfolioFindingItems
                .filter { $0.finding.status != .ready }
                .sorted {
                    if $0.finding.status.rank != $1.finding.status.rank {
                        return $0.finding.status.rank < $1.finding.status.rank
                    }
                    return $0.workspaceTitle < $1.workspaceTitle
                }
                .prefix(4)
        )
    }

    private var missingRequirements: [WorkspaceOverviewItem] {
        summaries.filter { $0.requirementCount == 0 || $0.requiredDocumentCount == 0 }
    }

    private var incompleteDocuments: [WorkspaceOverviewItem] {
        summaries.filter { $0.missingDocumentCount > 0 }
    }

    private var unauditedWorkspaces: [WorkspaceOverviewItem] {
        summaries.filter { !$0.hasCurrentAudit }
    }

    private var missingDocumentCount: Int {
        summaries.reduce(0) { $0 + $1.missingDocumentCount }
    }

    private var auditedWorkspaceCount: Int {
        summaries.filter(\.hasCurrentAudit).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summaryHero

                HStack(spacing: 14) {
                    StatusMetricCard(status: .blocked, count: state.portfolioBlockedCount)
                    StatusMetricCard(status: .humanReview, count: state.portfolioReviewCount)
                    StatusMetricCard(status: .ready, count: state.portfolioReadyFindingCount)
                }

                HStack(alignment: .top, spacing: 18) {
                    priorityCard
                        .frame(maxWidth: .infinity)
                    portfolioReadinessCard
                        .frame(width: 360)
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
                }
                
                Spacer()
                VStack(alignment: .center, spacing: 5) {
                    Text("\(summaries.count)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("전체 지원 항목")
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
        if !missingRequirements.isEmpty { return "REQUIREMENTS FIRST" }
        if missingDocumentCount > 0 { return "DOCUMENTS REQUIRED" }
        if !unauditedWorkspaces.isEmpty { return "AUDITS REQUIRED" }
        if state.portfolioBlockedCount > 0 { return "REVIEW NEEDED" }
        return "PORTFOLIO OVERVIEW"
    }

    private var heroTitle: String {
        if !missingRequirements.isEmpty {
            return "\(missingRequirements.count)개 지원 항목의 모집요강을 확인해 주세요"
        }
        if missingDocumentCount > 0 {
            return "전체 지원 서류 중 \(missingDocumentCount)개가 남았어요"
        }
        if !unauditedWorkspaces.isEmpty {
            return "\(unauditedWorkspaces.count)개 지원 항목의 검수가 필요해요"
        }
        if state.portfolioBlockedCount > 0 {
            return "전체 지원서에서 \(state.portfolioBlockedCount)개 문제를 발견했어요"
        }
        if state.portfolioReviewCount > 0 {
            return "직접 확인할 항목 \(state.portfolioReviewCount)개가 남았어요"
        }
        return "모든 지원 항목이 제출 준비 상태예요"
    }

    private var heroMessage: String {
        if !missingRequirements.isEmpty {
            return "학교와 프로그램별 공식 모집요강을 기준으로 필요한 서류를 구성해야 전체 준비도를 정확히 계산할 수 있어요."
        }
        if missingDocumentCount > 0 {
            return "모든 지원 항목의 필요 서류를 합산했습니다. 누락된 파일이 있는 지원서부터 채워 검수 가능한 상태로 만드세요."
        }
        if !unauditedWorkspaces.isEmpty {
            return "지원서별로 현재 파일을 다시 읽어 누락과 불일치, 페이지 근거를 확인해야 해요."
        }
        if state.portfolioBlockedCount > 0 || state.portfolioReviewCount > 0 {
            return "학교별 검수 결과를 한곳에 모았습니다. 우선순위가 높은 문제를 선택하면 해당 지원서의 근거와 수정 방향으로 이동해요."
        }
        return "등록된 모든 지원 항목의 모집요강, 서류 준비도와 검수 결과를 합산한 현재 상태입니다."
    }

    private var heroActionTitle: String {
        if !missingRequirements.isEmpty { return "모집요강 확인" }
        if missingDocumentCount > 0 { return "필요 서류 채우기" }
        if !unauditedWorkspaces.isEmpty { return "검수할 지원서 보기" }
        if state.portfolioBlockedCount > 0 || state.portfolioReviewCount > 0 { return "문제부터 확인" }
        return "전체 검수 보기"
    }

    private func performHeroAction() {
        if let item = missingRequirements.first {
            state.showWorkspaceRequirements(item.id)
        } else if let item = incompleteDocuments.first {
            state.showWorkspaceDocuments(item.id)
        } else if let item = unauditedWorkspaces.first {
            state.showWorkspaceAudit(item.id)
        } else if let item = priorityFindings.first {
            state.showPortfolioFinding(item)
        } else {
            state.showSelectedWorkspaceAudit()
        }
    }

    private var priorityCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    SectionTitle(
                        "전체 우선 피드백",
                        eyebrow: "PRIORITY",
                        subtitle: "모든 지원서의 보류와 검토를 함께 보여드려요."
                    )
                    Spacer()
                    Button("선택한 검수 보기") {
                        state.showSelectedWorkspaceAudit()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GCTheme.brand)
                }
                .padding(.bottom, 13)

                if priorityFindings.isEmpty {
                    EmptyStateView(
                        symbol: auditedWorkspaceCount == 0 ? "document.badge.plus" : "checkmark.seal.fill",
                        title: auditedWorkspaceCount == 0 ? "아직 검수된 지원서가 없어요" : "우선 확인할 문제가 없어요",
                        message: auditedWorkspaceCount == 0
                            ? "검수할 지원 항목을 선택하면 전체 우선순위가 여기에 모입니다."
                            : "현재 전체 검수 결과에서 수정이 필요한 항목이 없습니다.",
                        actionTitle: auditedWorkspaceCount == 0 ? "새 지원 목표 만들기" : nil,
                        action: auditedWorkspaceCount == 0 ? { state.showNewWorkspace = true } : nil
                    )
                } else {
                    ForEach(Array(priorityFindings.enumerated()), id: \.element.id) { index, item in
                        let finding = item.finding
                        Button {
                            state.showPortfolioFinding(item)
                        } label: {
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: finding.status.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(finding.status.color)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.workspaceTitle)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(GCTheme.brand)
                                        .lineLimit(1)
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

    private var portfolioReadinessCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle("전체 지원 현황", eyebrow: "APPLICATIONS")
                    Spacer()
                    Text("\(state.portfolioReadyDocumentCount) / \(state.portfolioRequiredDocumentCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(GCTheme.brand)
                }

                VStack(spacing: 7) {
                    ForEach(summaries.prefix(5)) { item in
                        let isReady = item.requiredDocumentCount > 0
                            && item.readyDocumentCount >= item.requiredDocumentCount
                        Button {
                            state.showWorkspaceDocuments(item.id)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: isReady ? "checkmark.circle.fill" : "doc.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isReady ? ReviewStatus.ready.color : Color.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.workspace.school)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(GCTheme.ink)
                                        .lineLimit(1)
                                    Text(item.workspace.program)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(item.readyDocumentCount)/\(item.requiredDocumentCount)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(isReady ? ReviewStatus.ready.color : .secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isReady ? ReviewStatus.ready.color.opacity(0.07) : Color.black.opacity(0.025))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if summaries.count > 5 {
                        Text("외 \(summaries.count - 5)개 지원 항목")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Button("선택한 지원서 보기") { state.showSelectedWorkspaceDocuments() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("UpCheck는 업로드된 문서의 누락과 불일치를 확인하는 제출 전 QA 도구입니다. 합격 가능성, 공식 발급 여부, 학점 환산, 영어 면제 또는 비자 승인을 판단하지 않습니다.")
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
