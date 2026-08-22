import SwiftUI
import UniformTypeIdentifiers

struct ApplicationWorkspaceView: View {
    @ObservedObject var viewModel: ApplicationWorkspaceViewModel

    let onReturnToApplications: () -> Void

    var body: some View {
        Group {
            if let application = viewModel.application {
                HStack(spacing: 0) {
                    preparationPanel(application)
                        .frame(minWidth: 390, idealWidth: 430, maxWidth: 470)

                    Divider()

                    SourcePreviewView(
                        applicationURL: viewModel.selectedWebURL,
                        sourceFilename: application.sourceFilename,
                        mode: $viewModel.previewMode,
                        evidenceTitle: $viewModel.evidenceTitle,
                        requestedPDFPage: $viewModel.requestedPDFPage,
                        selectedDocumentURL: $viewModel.selectedDocumentURL
                    )
                    .id(application.id)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.white)
            } else {
                missingApplication
            }
        }
        .fileImporter(
            isPresented: $viewModel.isShowingDocumentImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: viewModel.handleDocumentImport
        )
        .alert(
            "안내",
            isPresented: Binding(
                get: { viewModel.message != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.message = nil
                    }
                }
            )
        ) {
            Button("확인") {
                viewModel.message = nil
            }
        } message: {
            Text(viewModel.message ?? "")
        }
    }

    private var missingApplication: some View {
        VStack(spacing: 18) {
            EmptyPlaceholder(
                icon: "exclamationmark.triangle",
                title: "지원 정보를 찾을 수 없어요",
                message: "삭제되었거나 더 이상 불러올 수 없는 지원입니다. 지원 현황에서 다시 선택해 주세요."
            )

            Button {
                onReturnToApplications()
            } label: {
                Label("지원 현황으로 돌아가기", systemImage: "arrow.left")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func preparationPanel(_ application: ApplicationItem) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    applicationHeader(application)

                    Picker("지원 준비 항목", selection: $viewModel.selectedSection) {
                        ForEach(WorkspaceSection.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    switch viewModel.selectedSection {
                    case .overview:
                        eligibilitySection(application)
                        documentsSection(application)
                    case .eligibility:
                        eligibilitySection(application)
                    case .documents:
                        documentsSection(application)
                    }
                }
                .padding(24)
            }

            Divider()
            bottomActions(application)
        }
        .background(Color.white)
    }

    private func applicationHeader(_ application: ApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(application.organization)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                Text(application.title)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                StatusPill(
                    application.eligibility.rawValue,
                    tint: application.eligibility.tint
                )
            }

            HStack {
                if application.deadline == nil {
                    Label("마감 확인 필요", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                } else {
                    Text("마감 \(viewModel.formattedDeadline(application.deadline)) · \(application.dDayText)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("준비도 \(application.progressPercent)%")
                    .monospacedDigit()
                    .fontWeight(.bold)
            }
            .font(.caption)

            ProgressView(value: application.progress)
                .tint(Color.awAccent)
        }
    }

    private func eligibilitySection(_ application: ApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("자격 요건")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.satisfiedRequirementCount(application)) / \(application.requirements.count) 충족")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            }

            ForEach(application.requirements) { requirement in
                HStack(alignment: .center, spacing: 11) {
                    Image(systemName: requirement.state.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(requirement.state.tint)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(requirement.title)
                            .font(.subheadline.weight(.semibold))
                        Text(requirement.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button("원문 보기  ›") {
                        viewModel.connectEvidence(requirement)
                    }
                    .font(.caption2.weight(.bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.awAccent)
                }
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background(Color.awCanvas.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private func documentsSection(_ application: ApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("제출 서류")
                    .font(.headline)
                Spacer()
                Text("\(application.readyDocumentCount) / \(application.requiredDocuments.count) 준비됨")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(application.requiredDocuments) { document in
                HStack(alignment: .center, spacing: 11) {
                    Image(systemName: documentStatusIcon(document))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(documentStatusTint(document))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.name)
                            .font(.subheadline.weight(.semibold))
                        Text(documentSubtitle(document))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    documentAction(document)
                }
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background(Color.awCanvas.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    @ViewBuilder
    private func documentAction(_ document: RequiredDocument) -> some View {
        if document.preparationType == .request, document.requestState == .received {
            Button("완료 취소") {
                viewModel.requestDocument(document)
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } else if document.isReady, document.linkedFileURL != nil {
            Button("열기") {
                viewModel.openDocument(document)
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.awAccent)
        } else if document.isReady {
            Label("준비 완료", systemImage: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
        } else if document.preparationType == .request {
            Button(requestActionTitle(document)) {
                viewModel.requestDocument(document)
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.awAccent)
        } else {
            Button("연결") {
                viewModel.beginLinking(documentID: document.id)
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.awAccent)
        }
    }

    private func bottomActions(_ application: ApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .foregroundStyle(Color.awAccent)
                Text("왼쪽 항목을 클릭해 오른쪽에서 원문 근거를 확인하세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.exportCalendarEvent()
                } label: {
                    Label(
                        viewModel.calendarExported ? "캘린더 열림" : "캘린더에 추가",
                        systemImage: viewModel.calendarExported ? "checkmark" : "calendar.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    viewModel.performPrimaryAction()
                } label: {
                    Label(viewModel.primaryActionTitle, systemImage: primaryActionIcon(application))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(Color.white)
    }

    private func requestActionTitle(_ document: RequiredDocument) -> String {
        switch document.requestState {
        case .notRequested: "요청"
        case .requested: "수령 완료"
        case .received: "열기"
        }
    }

    private func documentStatusIcon(_ document: RequiredDocument) -> String {
        if document.isReady {
            return "checkmark.circle.fill"
        }
        if document.preparationType == .request, document.requestState == .requested {
            return "clock.fill"
        }

        switch document.preparationType {
        case .owned: return "exclamationmark.circle.fill"
        case .write: return "pencil.circle.fill"
        case .request: return "person.crop.circle.badge.questionmark"
        }
    }

    private func documentStatusTint(_ document: RequiredDocument) -> Color {
        if document.isReady {
            return .green
        }
        if document.preparationType == .request, document.requestState == .requested {
            return .orange
        }
        return document.preparationType.tint
    }

    private func documentSubtitle(_ document: RequiredDocument) -> String {
        if let linkedFilename = document.linkedFilename {
            return linkedFilename
        }

        if document.preparationType == .request {
            switch document.requestState {
            case .notRequested: return "발급 또는 요청 필요"
            case .requested: return "요청됨 · 수령 대기"
            case .received: return "수령 완료"
            }
        }

        switch document.preparationType {
        case .owned: return "내 문서함 연결 필요"
        case .write: return "작성한 파일 연결 필요"
        case .request: return "발급 또는 요청 필요"
        }
    }

    private func primaryActionIcon(_ application: ApplicationItem) -> String {
        if application.isReadyToSubmit {
            return application.applicationURL == nil ? "link.badge.plus" : "arrow.up.right.square"
        }
        return application.requirements.contains(where: { $0.state != .satisfied })
            ? "questionmark.circle"
            : "arrow.right"
    }
}
