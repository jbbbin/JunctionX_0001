import Combine
import Foundation

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case overview = "개요"
    case eligibility = "자격 요건"
    case documents = "제출 서류"

    var id: String { rawValue }
}

@MainActor
final class ApplicationWorkspaceViewModel: StoreBackedViewModel {
    @Published var selectedSection: WorkspaceSection = .overview
    @Published var previewMode: SourcePreviewMode
    @Published var evidenceTitle: String?
    @Published var requestedPDFPage = 1
    @Published var selectedWebURL: URL?
    @Published var selectedDocumentURL: URL?
    @Published var pendingDocumentID: UUID?
    @Published var isShowingDocumentImporter = false
    @Published var calendarExported = false
    @Published var message: String?

    let applicationID: UUID
    private let externalURLOpener: any ExternalURLOpening
    private let calendarExporter: any CalendarExporting

    init(
        applicationID: UUID,
        store: AppStore,
        externalURLOpener: any ExternalURLOpening,
        calendarExporter: any CalendarExporting
    ) {
        self.applicationID = applicationID
        self.externalURLOpener = externalURLOpener
        self.calendarExporter = calendarExporter
        let application = store.application(id: applicationID)
        previewMode = application?.applicationURL == nil ? .document : .web
        selectedWebURL = application?.applicationURL
        selectedDocumentURL = application?.source.documentURL
        super.init(store: store)
    }

    var application: ApplicationItem? { store.application(id: applicationID) }

    var primaryActionTitle: String {
        guard let application else { return "지원 현황으로 돌아가기" }
        if application.isReadyToSubmit {
            return application.applicationURL == nil ? "접수 URL 확인" : "공식 접수처 열기"
        }
        if application.requirements.contains(where: { $0.state != .satisfied }) {
            return "확인할 자격 보기"
        }
        return "다음 준비 항목 보기"
    }

    func satisfiedRequirementCount(_ application: ApplicationItem) -> Int {
        application.requirements.filter { $0.state == .satisfied }.count
    }

    func connectEvidence(_ requirement: EligibilityRequirement) {
        guard let application else { return }
        evidenceTitle = "\(requirement.title) · \(requirement.detail)"

        switch requirement.evidence.location {
        case let .pdf(page):
            requestedPDFPage = max(1, page)
            if let documentURL = application.source.documentURL {
                selectedDocumentURL = documentURL
                previewMode = .document
            } else if application.applicationURL != nil {
                previewMode = .web
                message = "PDF 원본이 없어 연결된 웹 공고를 표시했어요."
            } else {
                previewMode = .document
            }
        case let .web(url, _):
            selectedWebURL = url ?? application.applicationURL
            previewMode = .web
        }
    }

    func openDocument(_ document: RequiredDocument) {
        guard document.isReady else { return }
        if let url = document.linkedFileURL {
            selectedDocumentURL = url
            previewMode = .document
            evidenceTitle = "\(document.name) · \(document.linkedFilename ?? url.lastPathComponent)"
        } else {
            message = "이 문서는 파일명만 연결돼 있어요. 최신 파일을 다시 연결해 주세요."
            selectedSection = .documents
        }
    }

    func beginLinking(documentID: UUID) {
        pendingDocumentID = documentID
        isShowingDocumentImporter = true
    }

    func handleDocumentImport(_ result: Result<[URL], Error>) {
        defer { pendingDocumentID = nil }
        guard case let .success(urls) = result,
              let url = urls.first,
              let pendingDocumentID
        else {
            if case let .failure(error) = result {
                let nsError = error as NSError
                if !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) {
                    message = "문서를 불러오지 못했어요. 다시 연결해 주세요."
                }
            }
            return
        }

        store.linkDocument(
            applicationID: applicationID,
            documentID: pendingDocumentID,
            url: url
        )
        selectedDocumentURL = url
        previewMode = .document
    }

    func requestDocument(_ document: RequiredDocument) {
        switch document.requestState {
        case .notRequested:
            store.markDocumentRequested(applicationID: applicationID, documentID: document.id)
            message = "요청 상태로 표시했어요. 실제 발급 요청 연동은 다음 단계에서 연결합니다."
        case .requested:
            store.markDocumentReceived(applicationID: applicationID, documentID: document.id)
        case .received:
            store.resetDocumentRequest(applicationID: applicationID, documentID: document.id)
        }
    }

    func performPrimaryAction() {
        guard let application else { return }

        if application.isReadyToSubmit, let url = application.applicationURL {
            _ = externalURLOpener.open(url)
            return
        }

        if application.isReadyToSubmit {
            previewMode = .web
            message = "공식 접수 URL이 아직 없어요. 오른쪽 주소창에서 접수처를 확인해 주세요."
            return
        }

        if let requirement = application.requirements.first(where: { $0.state != .satisfied }) {
            selectedSection = .eligibility
            connectEvidence(requirement)
            return
        }

        selectedSection = .documents
        evidenceTitle = application.nextAction
    }

    func exportCalendarEvent() {
        guard let application else { return }
        do {
            try calendarExporter.openCalendarEvent(for: application)
            calendarExported = true
        } catch {
            message = error.localizedDescription
        }
    }

    func formattedDeadline(_ date: Date?) -> String {
        guard let date else { return "마감 확인 필요" }
        return Self.deadlineFormatter.string(from: date)
    }

    private static let deadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일(E) HH:mm"
        return formatter
    }()
}
