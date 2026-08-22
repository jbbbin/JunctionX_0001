import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AuditReportView: View {
    @EnvironmentObject private var state: AppViewModel
    @State private var filter: FindingFilter = .all

    private var filteredFindings: [AuditFinding] {
        state.findings.filter { filter.matches($0) }
    }

    var body: some View {
        auditDetail
        .onChange(of: filter) { _, newValue in
            guard let selected = state.selectedFinding, newValue.matches(selected) else {
                state.selectedFindingID = filteredFindings.first?.id
                return
            }
        }
    }

    private var auditDetail: some View {
        VStack(spacing: 0) {
            reportSummary
            Divider().opacity(0.6)
            if state.findings.isEmpty {
                EmptyStateView(
                    symbol: "checkmark.shield",
                    title: "아직 검수 결과가 없어요",
                    message: "지원 서류를 추가한 뒤 지원 패키지 검수를 실행하세요.",
                    actionTitle: "지원 서류로 이동",
                    action: { state.showSelectedWorkspaceDocuments() }
                )
            } else {
                HStack(spacing: 0) {
                    findingList
                        .frame(minWidth: 355, idealWidth: 405, maxWidth: 455)
                    Divider().opacity(0.65)
                    findingDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GCTheme.canvas)
    }

    private var reportSummary: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("제출 준비 리포트")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(GCTheme.ink)
                Text("문제마다 원본 파일과 페이지 근거를 확인하세요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ReportCount(status: .blocked, count: state.blockedCount)
            ReportCount(status: .humanReview, count: state.humanReviewCount)
            ReportCount(status: .ready, count: state.readyCount)
            Divider().frame(height: 28)
            Button {
                exportChecklist()
            } label: {
                Label("체크리스트 내보내기", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
        .background(.regularMaterial)
    }

    private var findingList: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(14)
            Divider().opacity(0.55)
            if filteredFindings.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "이 상태의 항목이 없어요",
                    message: "다른 필터를 선택해 전체 검수 결과를 확인하세요."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(filteredFindings) { finding in
                            FindingListRow(
                                finding: finding,
                                selected: state.selectedFindingID == finding.id
                            ) {
                                state.selectedFindingID = finding.id
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(GCTheme.surface.opacity(0.58))
    }

    private var filterBar: some View {
        HStack(spacing: 5) {
            ForEach(FindingFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(filter == item ? GCTheme.surface : .clear)
                        .foregroundStyle(filter == item ? GCTheme.ink : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .shadow(color: filter == item ? .black.opacity(0.055) : .clear, radius: 4, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var findingDetail: some View {
        if let finding = state.selectedFinding {
            FindingDetailView(finding: finding)
                .environmentObject(state)
                .id(finding.id)
        } else {
            EmptyStateView(
                symbol: "cursorarrow.click.2",
                title: "검수 항목을 선택하세요",
                message: "왼쪽 목록에서 항목을 선택하면 비교 근거와 다음 행동을 볼 수 있어요."
            )
        }
    }

    private func exportChecklist() {
        let panel = NSSavePanel()
        panel.title = "제출 전 체크리스트 내보내기"
        panel.nameFieldStringValue = "GradCheck_\(state.workspace.school)_Checklist.md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.checklistMarkdown().write(to: url, atomically: true, encoding: .utf8)
            state.successMessage = "체크리스트를 저장했어요."
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

private enum FindingFilter: String, CaseIterable, Identifiable {
    case all
    case blocked
    case review
    case ready

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "전체"
        case .blocked: "BLOCKED"
        case .review: "REVIEW"
        case .ready: "READY"
        }
    }

    func matches(_ finding: AuditFinding) -> Bool {
        switch self {
        case .all: true
        case .blocked: finding.status == .blocked
        case .review: finding.status == .humanReview
        case .ready: finding.status == .ready
        }
    }
}

private struct ReportCount: View {
    let status: ReviewStatus
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(GCTheme.ink)
            Text(status.rawValue)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(status.color)
        }
    }
}

private struct FindingListRow: View {
    let finding: AuditFinding
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: finding.status.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(finding.status.color)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(finding.category.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(finding.status.color)
                        if finding.isResolved {
                            Text("해결됨")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(ReviewStatus.ready.color)
                        }
                        Spacer()
                        if let first = finding.evidences.first, let page = first.page {
                            Text("p.\(page)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(finding.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GCTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(finding.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? GCTheme.surface : GCTheme.surface.opacity(0.46))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? finding.status.color.opacity(0.42) : GCTheme.line, lineWidth: 1)
            }
            .shadow(color: selected ? .black.opacity(0.05) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct FindingDetailView: View {
    @EnvironmentObject private var state: AppViewModel
    let finding: AuditFinding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    StatusBadge(status: finding.status)
                    Text(finding.category.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if finding.isResolved {
                        Label("재검수로 해결됨", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ReviewStatus.ready.color)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(finding.title)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(GCTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(GCTheme.secondaryInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(
                        finding.evidences.count > 1 ? "비교한 근거" : "확인한 근거",
                        eyebrow: "EVIDENCE",
                        subtitle: "자동 판단의 근거가 된 원문 위치입니다."
                    )
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(finding.evidences) { evidence in
                            EvidenceCard(evidence: evidence, status: finding.status)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("다음 행동")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(finding.status.color)
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: finding.status == .ready ? "checkmark.circle.fill" : "arrow.turn.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(finding.status.color)
                            .padding(.top, 1)
                        Text(finding.action)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GCTheme.ink)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(17)
                .background(finding.status.color.opacity(0.075))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(finding.status.color.opacity(0.14), lineWidth: 1)
                }

                HStack {
                    Text("원본에서 수정한 뒤 해당 파일을 교체하면 영향받은 항목을 다시 검수합니다.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if finding.status != .ready {
                        Button {
                            state.showSelectedWorkspaceDocuments()
                        } label: {
                            Label("파일 교체", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(GCTheme.brand)
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }
}

private struct EvidenceCard: View {
    let evidence: EvidenceRef
    let status: ReviewStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: evidence.documentType.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GCTheme.brand)
                    .frame(width: 28, height: 28)
                    .background(GCTheme.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(evidence.fieldLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GCTheme.ink)
                    Text(evidence.sourceLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            Text("“\(evidence.excerpt)”")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(GCTheme.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 5) {
                Circle().fill(status.color).frame(width: 5, height: 5)
                Text("문서에 명시된 내용")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(GCTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(GCTheme.line, lineWidth: 1)
        }
    }
}
