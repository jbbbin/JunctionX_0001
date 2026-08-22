import Foundation

enum ApplicationCategory: String, CaseIterable, Identifiable {
    case employment = "채용"
    case scholarship = "장학금"
    case competition = "공모전·대회"

    var id: String { rawValue }
}

enum EligibilityState: String, CaseIterable {
    case eligible = "지원 가능"
    case needsReview = "확인 필요"
    case difficult = "지원 어려움"
}

enum RequirementState: String {
    case satisfied = "충족"
    case needsReview = "확인 필요"
    case unsatisfied = "미충족"
}

enum DocumentPreparationType: String {
    case owned = "보유 문서"
    case write = "작성 필요"
    case request = "외부 요청"
}

enum DocumentRequestState: String, Hashable {
    case notRequested = "요청 전"
    case requested = "요청됨"
    case received = "수령 완료"
}

enum ApplicationStatus: String, Hashable {
    case preparing = "준비 중"
    case submitted = "제출 완료"
    case archived = "보관됨"
}

enum SourceLocation: Hashable {
    case web(url: URL?, anchor: String? = nil)
    case pdf(page: Int)
}

struct EvidenceReference: Hashable {
    var location: SourceLocation
    var excerpt: String?

    init(location: SourceLocation, excerpt: String? = nil) {
        self.location = location
        self.excerpt = excerpt
    }
}

struct ApplicationSource: Hashable {
    var webURL: URL?
    var documentURL: URL?
    var displayName: String

    init(webURL: URL? = nil, documentURL: URL? = nil, displayName: String) {
        self.webURL = webURL
        self.documentURL = documentURL
        self.displayName = displayName
    }
}

enum ImportedSource: Hashable {
    case file(URL)
    case web(URL)

    var displayName: String {
        switch self {
        case let .file(url): url.lastPathComponent
        case let .web(url): url.host() ?? url.absoluteString
        }
    }
}

struct EligibilityRequirement: Identifiable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var state: RequirementState
    var evidence: EvidenceReference

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        state: RequirementState,
        sourcePage: Int
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        evidence = EvidenceReference(location: .pdf(page: max(1, sourcePage)))
    }

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        state: RequirementState,
        evidence: EvidenceReference
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.evidence = evidence
    }
}

struct RequiredDocument: Identifiable, Hashable {
    let id: UUID
    var name: String
    var preparationType: DocumentPreparationType
    var isReady: Bool
    var linkedFilename: String?
    var linkedFileURL: URL?
    var requestState: DocumentRequestState
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        preparationType: DocumentPreparationType,
        isReady: Bool = false,
        linkedFilename: String? = nil,
        linkedFileURL: URL? = nil,
        requestState: DocumentRequestState = .notRequested,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.preparationType = preparationType
        self.isReady = isReady
        self.linkedFilename = linkedFilename
        self.linkedFileURL = linkedFileURL
        self.requestState = requestState
        self.note = note
    }
}

struct ApplicationItem: Identifiable, Hashable {
    let id: UUID
    var category: ApplicationCategory
    var title: String
    var organization: String
    var deadline: Date?
    var eligibility: EligibilityState
    var requirements: [EligibilityRequirement]
    var requiredDocuments: [RequiredDocument]
    var source: ApplicationSource
    var status: ApplicationStatus

    init(
        id: UUID = UUID(),
        category: ApplicationCategory,
        title: String,
        organization: String,
        deadline: Date?,
        eligibility: EligibilityState,
        requirements: [EligibilityRequirement],
        requiredDocuments: [RequiredDocument],
        source: ApplicationSource,
        status: ApplicationStatus = .preparing
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.organization = organization
        self.deadline = deadline
        self.eligibility = eligibility
        self.requirements = requirements
        self.requiredDocuments = requiredDocuments
        self.source = source
        self.status = status
    }

    var applicationURL: URL? { source.webURL }
    var sourceFilename: String { source.displayName }
    var isCompleted: Bool { status == .submitted || status == .archived }

    var readyDocumentCount: Int {
        requiredDocuments.filter(\.isReady).count
    }

    var remainingTaskCount: Int {
        requiredDocuments.count - readyDocumentCount
    }

    var progress: Double {
        guard !requiredDocuments.isEmpty else { return 1 }
        return Double(readyDocumentCount) / Double(requiredDocuments.count)
    }

    var progressPercent: Int {
        Int((progress * 100).rounded())
    }

    var isReadyToSubmit: Bool {
        deadline != nil
            && eligibility == .eligible
            && requirements.allSatisfy { $0.state == .satisfied }
            && requiredDocuments.allSatisfy(\.isReady)
    }

    var nextAction: String {
        if let requirement = requirements.first(where: { $0.state == .unsatisfied }) {
            return "\(requirement.title) 조건을 다시 확인해 주세요"
        }

        if let requirement = requirements.first(where: { $0.state == .needsReview }) {
            return "\(requirement.title) 조건을 확인해 주세요"
        }

        if deadline == nil {
            return "마감일을 확인해 주세요"
        }

        if let document = requiredDocuments.first(where: { !$0.isReady }) {
            if document.preparationType == .request, document.requestState == .requested {
                return "\(document.name) 수령을 기다리고 있어요"
            }

            switch document.preparationType {
            case .owned: return "\(document.name) 파일을 연결해 주세요"
            case .write: return "\(document.name)\(document.name.koreanObjectParticle) 작성해 주세요"
            case .request: return "\(document.name)\(document.name.koreanObjectParticle) 요청해 주세요"
            }
        }

        return isReadyToSubmit ? "공식 접수처에서 제출해 주세요" : "자격 조건을 확인해 주세요"
    }

    func daysRemaining(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let deadline else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: deadline)
        ).day ?? 0
    }

    var daysRemaining: Int? { daysRemaining() }

    var dDayText: String {
        guard let daysRemaining else { return "마감 확인 필요" }
        return switch daysRemaining {
        case let value where value > 0: "D-\(value)"
        case 0: "D-Day"
        default: "마감"
        }
    }
}

private extension String {
    var koreanObjectParticle: String {
        guard let scalar = unicodeScalars.last?.value,
              (0xAC00...0xD7A3).contains(scalar)
        else { return "을" }

        return (scalar - 0xAC00) % 28 == 0 ? "를" : "을"
    }
}

struct UserProfile: Equatable {
    var name: String = "홍길동"
    var school: String
    var enrollmentStatus: String
    var grade: Int
    var gpa: String
    var incomeBracket: String
    var major: String
    var region: String

    var avatarInitial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
    }
}

struct OwnedDocument: Identifiable, Hashable {
    let id: UUID
    var name: String
    var type: String
    var filename: String
    var addedAt: Date
    var fileURL: URL?

    init(
        id: UUID = UUID(),
        name: String,
        type: String,
        filename: String,
        addedAt: Date = Date(),
        fileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.filename = filename
        self.addedAt = addedAt
        self.fileURL = fileURL
    }
}

enum DashboardStatusFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case preparing = "준비 중"
    case urgent = "마감 임박"
    case needsReview = "확인 필요"
    case completed = "완료"

    var id: String { rawValue }
}
