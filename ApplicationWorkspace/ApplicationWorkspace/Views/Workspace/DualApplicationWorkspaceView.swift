import SwiftUI
import UniformTypeIdentifiers

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case overview = "개요"
    case eligibility = "자격 요건"
    case documents = "제출 서류"

    var id: String { rawValue }
}

struct ApplicationWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedSection: WorkspaceSection = .overview
    @State private var previewMode: SourcePreviewMode = .web
    @State private var evidenceTitle: String?
    @State private var requestedPDFPage = 1
    @State private var pendingDocumentID: UUID?
    @State private var isShowingDocumentImporter = false
    @State private var calendarAdded = false

    let applicationID: UUID

    var body: some View {
        Group {
            if let application = store.application(id: applicationID) {
                HStack(spacing: 0) {
                    preparationPanel(application)
                        .frame(minWidth: 390, idealWidth: 430, maxWidth: 470)

                    Divider()

                    SourcePreviewView(
                        mode: $previewMode,
                        evidenceTitle: $evidenceTitle,
                        requestedPDFPage: $requestedPDFPage,
                        applicationURL: application.applicationURL,
                        sourceFilename: application.sourceFilename
                    )
                    .id(application.id)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.white)
            } else {
                EmptyPlaceholder(
                    icon: "exclamationmark.triangle",
                    title: "지원 정보를 찾을 수 없어요",
                    message: "지원 현황으로 돌아가 다시 선택해 주세요."
                )
            }
        }
        .fileImporter(
            isPresented: $isShowingDocumentImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result,
                  let url = urls.first,
                  let pendingDocumentID
            else { return }

            store.linkDocument(
                applicationID: applicationID,
                documentID: pendingDocumentID,
                filename: url.lastPathComponent
            )
            self.pendingDocumentID = nil
        }
    }

    private func preparationPanel(_ application: ApplicationItem) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    applicationHeader(application)

                    Picker("지원 준비 항목", selection: $selectedSection) {
                        ForEach(WorkspaceSection.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    switch selectedSection {
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
                Text("마감 \(formattedDeadline(application.deadline)) · \(application.dDayText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("준비도 \(application.progressPercent)%")
                    .font(.caption.monospacedDigit().weight(.bold))
            }

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
                Text("\(satisfiedRequirementCount(application)) / \(application.requirements.count) 충족")
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
                        connectEvidence(
                            title: "\(requirement.title) · \(requirement.detail)",
                            page: requirement.sourcePage,
                            application: application
                        )
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
                    Image(systemName: document.isReady ? "checkmark.circle.fill" : statusIcon(for: document.preparationType))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(document.isReady ? .green : document.preparationType.tint)
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

                    documentAction(document, application: application)
                }
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background(Color.awCanvas.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    @ViewBuilder
    private func documentAction(_ document: RequiredDocument, application: ApplicationItem) -> some View {
        if document.isReady {
            Button("열기") {
                previewMode = .pdf
                evidenceTitle = "\(document.name) · \(document.linkedFilename ?? "연결 문서")"
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.awAccent)
        } else if document.preparationType == .request {
            Button("요청") {
                store.toggleDocumentReady(applicationID: application.id, documentID: document.id)
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.awAccent)
        } else {
            Button("연결") {
                pendingDocumentID = document.id
                isShowingDocumentImporter = true
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
                    calendarAdded.toggle()
                } label: {
                    Label(
                        calendarAdded ? "캘린더 추가됨" : "캘린더에 추가",
                        systemImage: calendarAdded ? "checkmark" : "calendar.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    evidenceTitle = nil
                    previewMode = application.applicationURL == nil ? .pdf : .web
                } label: {
                    Label("제출 준비하기", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(Color.white)
    }

    private func connectEvidence(
        title: String,
        page: Int,
        application: ApplicationItem
    ) {
        evidenceTitle = title
        requestedPDFPage = page
        previewMode = application.applicationURL == nil ? .pdf : .web
    }

    private func satisfiedRequirementCount(_ application: ApplicationItem) -> Int {
        application.requirements.filter { $0.state == .satisfied }.count
    }

    private func statusIcon(for type: DocumentPreparationType) -> String {
        switch type {
        case .owned: "exclamationmark.circle.fill"
        case .write: "pencil.circle.fill"
        case .request: "person.crop.circle.badge.questionmark"
        }
    }

    private func documentSubtitle(_ document: RequiredDocument) -> String {
        if let linkedFilename = document.linkedFilename {
            return linkedFilename
        }

        switch document.preparationType {
        case .owned: return "내 문서함 연결 필요"
        case .write: return "작성한 파일 연결 필요"
        case .request: return "발급 또는 요청 필요"
        }
    }

    private func formattedDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일(E) HH:mm"
        return formatter.string(from: date)
    }
}
