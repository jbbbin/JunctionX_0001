import Foundation
import SwiftUI

enum SidebarRoute: Hashable {
    case dashboard
    case applications
    case profile
    case documents
    case archive
    case urgent
    case needsReview
    case application(UUID)
}

enum ApplicationCategory: String, CaseIterable, Identifiable {
    case employment = "채용"
    case scholarship = "장학금"
    case competition = "공모전·대회"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .employment: "briefcase.fill"
        case .scholarship: "graduationcap.fill"
        case .competition: "trophy.fill"
        }
    }

    var tint: Color {
        switch self {
        case .employment: Color(red: 0.29, green: 0.36, blue: 0.96)
        case .scholarship: Color(red: 0.10, green: 0.62, blue: 0.48)
        case .competition: Color(red: 0.94, green: 0.48, blue: 0.18)
        }
    }
}

enum EligibilityState: String, CaseIterable {
    case eligible = "지원 가능"
    case needsReview = "확인 필요"
    case difficult = "지원 어려움"

    var icon: String {
        switch self {
        case .eligible: "checkmark.circle.fill"
        case .needsReview: "questionmark.circle.fill"
        case .difficult: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .eligible: .green
        case .needsReview: .orange
        case .difficult: .red
        }
    }
}

enum RequirementState: String {
    case satisfied = "충족"
    case needsReview = "확인 필요"
    case unsatisfied = "미충족"

    var icon: String {
        switch self {
        case .satisfied: "checkmark.circle.fill"
        case .needsReview: "questionmark.circle.fill"
        case .unsatisfied: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .satisfied: .green
        case .needsReview: .orange
        case .unsatisfied: .red
        }
    }
}

enum DocumentPreparationType: String {
    case owned = "보유 문서"
    case write = "작성 필요"
    case request = "외부 요청"

    var icon: String {
        switch self {
        case .owned: "doc.badge.checkmark"
        case .write: "square.and.pencil"
        case .request: "person.crop.circle.badge.questionmark"
        }
    }

    var tint: Color {
        switch self {
        case .owned: .blue
        case .write: .purple
        case .request: .orange
        }
    }
}

struct EligibilityRequirement: Identifiable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var state: RequirementState
    var sourcePage: Int

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
        self.sourcePage = sourcePage
    }
}

struct RequiredDocument: Identifiable, Hashable {
    let id: UUID
    var name: String
    var preparationType: DocumentPreparationType
    var isReady: Bool
    var linkedFilename: String?
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        preparationType: DocumentPreparationType,
        isReady: Bool = false,
        linkedFilename: String? = nil,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.preparationType = preparationType
        self.isReady = isReady
        self.linkedFilename = linkedFilename
        self.note = note
    }
}

struct ApplicationItem: Identifiable, Hashable {
    let id: UUID
    var category: ApplicationCategory
    var title: String
    var organization: String
    var deadline: Date
    var eligibility: EligibilityState
    var requirements: [EligibilityRequirement]
    var requiredDocuments: [RequiredDocument]
    var nextAction: String
    var applicationURL: URL?
    var sourceFilename: String
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        category: ApplicationCategory,
        title: String,
        organization: String,
        deadline: Date,
        eligibility: EligibilityState,
        requirements: [EligibilityRequirement],
        requiredDocuments: [RequiredDocument],
        nextAction: String,
        applicationURL: URL?,
        sourceFilename: String,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.organization = organization
        self.deadline = deadline
        self.eligibility = eligibility
        self.requirements = requirements
        self.requiredDocuments = requiredDocuments
        self.nextAction = nextAction
        self.applicationURL = applicationURL
        self.sourceFilename = sourceFilename
        self.isCompleted = isCompleted
    }

    var readyDocumentCount: Int {
        requiredDocuments.filter(\.isReady).count
    }

    var remainingTaskCount: Int {
        requiredDocuments.count - readyDocumentCount
    }

    var progress: Double {
        guard !requiredDocuments.isEmpty else { return 0 }
        return Double(readyDocumentCount) / Double(requiredDocuments.count)
    }

    var progressPercent: Int {
        Int((progress * 100).rounded())
    }

    var daysRemaining: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: deadline)
        ).day ?? 0
    }

    var dDayText: String {
        switch daysRemaining {
        case let value where value > 0: "D-\(value)"
        case 0: "D-Day"
        default: "마감"
        }
    }
}

struct UserProfile: Equatable {
    var school: String
    var enrollmentStatus: String
    var grade: Int
    var gpa: String
    var incomeBracket: String
    var major: String
    var region: String
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
