import Foundation
import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable {
    case overview = "개요"
    case documents = "지원 서류"
    case audit = "검수 리포트"
    case requirements = "모집 요건"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .documents: "doc.on.doc"
        case .audit: "checkmark.shield"
        case .requirements: "list.clipboard"
        }
    }
}

enum ReviewStatus: String, Codable, CaseIterable, Identifiable {
    case blocked = "BLOCKED"
    case humanReview = "HUMAN REVIEW"
    case ready = "READY"

    var id: Self { self }

    var label: String {
        switch self {
        case .blocked: "수정 필요"
        case .humanReview: "직접 확인"
        case .ready: "확인 완료"
        }
    }

    var symbol: String {
        switch self {
        case .blocked: "xmark.octagon.fill"
        case .humanReview: "exclamationmark.triangle.fill"
        case .ready: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .blocked: Color(nsColor: .systemRed)
        case .humanReview: Color(nsColor: .systemOrange)
        case .ready: Color(nsColor: .systemGreen)
        }
    }

    var rank: Int {
        switch self {
        case .blocked: 0
        case .humanReview: 1
        case .ready: 2
        }
    }
}

enum WorkspaceStatus: String, Codable {
    case preparing
    case needsReview
    case ready

    var label: String {
        switch self {
        case .preparing: "준비 중"
        case .needsReview: "검수 필요"
        case .ready: "제출 준비 완료"
        }
    }

    var color: Color {
        switch self {
        case .preparing: .secondary
        case .needsReview: ReviewStatus.blocked.color
        case .ready: ReviewStatus.ready.color
        }
    }
}

enum DocumentType: String, Codable, CaseIterable, Identifiable {
    case cv
    case sop
    case transcript
    case englishScore
    case requirements
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .cv: "CV / Resume"
        case .sop: "SOP / Personal Statement"
        case .transcript: "성적표"
        case .englishScore: "공인영어성적"
        case .requirements: "공식 모집요강"
        case .other: "기타 문서"
        }
    }

    var shortTitle: String {
        switch self {
        case .cv: "CV"
        case .sop: "SOP"
        case .transcript: "성적표"
        case .englishScore: "영어성적"
        case .requirements: "모집요강"
        case .other: "기타"
        }
    }

    var symbol: String {
        switch self {
        case .cv: "person.text.rectangle"
        case .sop: "text.document"
        case .transcript: "graduationcap"
        case .englishScore: "character.book.closed"
        case .requirements: "building.columns"
        case .other: "doc"
        }
    }

    var isCore: Bool {
        [.cv, .sop, .transcript, .englishScore].contains(self)
    }

    static func infer(from filename: String) -> DocumentType {
        let value = filename.lowercased()
        if value.contains("resume") || value.contains("cv") { return .cv }
        if value.contains("sop") || value.contains("statement") || value.contains("personal") { return .sop }
        if value.contains("transcript") || value.contains("성적") { return .transcript }
        if value.contains("toefl") || value.contains("ielts") || value.contains("english") { return .englishScore }
        if value.contains("requirement") || value.contains("admission") || value.contains("모집") { return .requirements }
        return .other
    }

    static func infer(from filename: String, content: String) -> DocumentType {
        let filenameType = infer(from: filename)
        if filenameType == .requirements { return .requirements }
        let contentType = infer(fromContent: content)
        return contentType == .other ? filenameType : contentType
    }

    static func infer(fromContent content: String) -> DocumentType {
        let value = content.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let requirementSignals = [
            "application requirements", "admission requirements", "required application materials",
            "graduate admissions", "application deadline", "letters of recommendation", "지원 자격", "모집 요강"
        ].filter { value.contains($0) }.count
        let mentionedCoreTypes = [
            value.contains("statement of purpose") || value.contains("personal statement"),
            value.contains("curriculum vitae") || value.contains("resume"),
            value.contains("transcript") || value.contains("academic record"),
            value.contains("toefl") || value.contains("ielts")
        ].filter { $0 }.count
        if requirementSignals >= 1 && mentionedCoreTypes >= 2 { return .requirements }
        if value.contains("application requirements") || value.contains("admission requirements") || value.contains("모집 요강") {
            return .requirements
        }

        if value.contains("toefl ibt score report")
            || value.contains("ielts test report form")
            || ((value.contains("toefl") || value.contains("ielts"))
                && (value.contains("total score") || value.contains("overall band") || value.contains("test date"))) {
            return .englishScore
        }

        if value.contains("official transcript")
            || value.contains("academic transcript")
            || (value.contains("cumulative gpa") && (value.contains("course") || value.contains("credit") || value.contains("degree conferred"))) {
            return .transcript
        }

        if value.contains("statement of purpose")
            || value.contains("personal statement")
            || value.contains("statement of objectives")
            || (value.contains("i am applying") && (value.contains("program") || value.contains("degree"))) {
            return .sop
        }

        let cvSignals = [
            "curriculum vitae", "research experience", "work experience", "professional experience",
            "publications", "selected projects", "education"
        ].filter { value.contains($0) }.count
        if value.contains("curriculum vitae") || value.contains("resume") || cvSignals >= 2 { return .cv }

        return .other
    }
}

enum DocumentProcessingStatus: String, Codable {
    case queued
    case parsing
    case ready
    case failed

    var label: String {
        switch self {
        case .queued: "대기 중"
        case .parsing: "문서 분석 중"
        case .ready: "분석 완료"
        case .failed: "확인 필요"
        }
    }
}

struct DocumentItem: Identifiable, Codable, Hashable {
    let id: UUID
    var type: DocumentType
    var filename: String
    var pageCount: Int?
    var sizeInBytes: Int64
    var uploadedAt: Date
    var processingStatus: DocumentProcessingStatus
    var isSample: Bool

    init(
        id: UUID = UUID(),
        type: DocumentType,
        filename: String,
        pageCount: Int? = nil,
        sizeInBytes: Int64 = 0,
        uploadedAt: Date = .now,
        processingStatus: DocumentProcessingStatus = .ready,
        isSample: Bool = false
    ) {
        self.id = id
        self.type = type
        self.filename = filename
        self.pageCount = pageCount
        self.sizeInBytes = sizeInBytes
        self.uploadedAt = uploadedAt
        self.processingStatus = processingStatus
        self.isSample = isSample
    }

    var metadata: String {
        var parts: [String] = []
        if let pageCount { parts.append("\(pageCount)페이지") }
        if sizeInBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

enum AuditCategory: String, Codable, CaseIterable {
    case target = "지원 방향"
    case identity = "개인정보"
    case education = "학력 이력"
    case score = "시험 성적"
    case completeness = "필수 서류"
    case format = "형식 요건"
}

struct EvidenceRef: Identifiable, Codable, Hashable {
    let id: UUID
    var documentName: String
    var documentType: DocumentType
    var page: Int?
    var excerpt: String
    var fieldLabel: String

    init(
        id: UUID = UUID(),
        documentName: String,
        documentType: DocumentType,
        page: Int? = nil,
        excerpt: String,
        fieldLabel: String
    ) {
        self.id = id
        self.documentName = documentName
        self.documentType = documentType
        self.page = page
        self.excerpt = excerpt
        self.fieldLabel = fieldLabel
    }

    var sourceLabel: String {
        if let page { return "\(documentName) · p.\(page)" }
        return documentName
    }
}

struct AuditFinding: Identifiable, Codable, Hashable {
    let id: UUID
    var status: ReviewStatus
    var category: AuditCategory
    var title: String
    var summary: String
    var action: String
    var evidences: [EvidenceRef]
    var isResolved: Bool

    init(
        id: UUID = UUID(),
        status: ReviewStatus,
        category: AuditCategory,
        title: String,
        summary: String,
        action: String,
        evidences: [EvidenceRef],
        isResolved: Bool = false
    ) {
        self.id = id
        self.status = status
        self.category = category
        self.title = title
        self.summary = summary
        self.action = action
        self.evidences = evidences
        self.isResolved = isResolved
    }
}

enum RequirementScope: String, Codable {
    case university = "학교 공통"
    case program = "프로그램 고유"
}

struct RequirementItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var scope: RequirementScope
    var status: ReviewStatus
    var sourceName: String
    var page: Int?
    var relatedDocumentType: DocumentType?
    var maximumPages: Int?
    var maximumWords: Int?
    var requiredFileExtension: String?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        scope: RequirementScope,
        status: ReviewStatus,
        sourceName: String,
        page: Int? = nil,
        relatedDocumentType: DocumentType? = nil,
        maximumPages: Int? = nil,
        maximumWords: Int? = nil,
        requiredFileExtension: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.scope = scope
        self.status = status
        self.sourceName = sourceName
        self.page = page
        self.relatedDocumentType = relatedDocumentType
        self.maximumPages = maximumPages
        self.maximumWords = maximumWords
        self.requiredFileExtension = requiredFileExtension
    }
}

struct ApplicationWorkspace: Identifiable, Codable, Hashable {
    let id: UUID
    var school: String
    var program: String
    var degree: String
    var intake: String
    var applicantName: String
    var status: WorkspaceStatus
    var createdAt: Date
    var lastAuditedAt: Date?
    var isSample: Bool

    init(
        id: UUID = UUID(),
        school: String,
        program: String,
        degree: String,
        intake: String,
        applicantName: String = "",
        status: WorkspaceStatus = .preparing,
        createdAt: Date = .now,
        lastAuditedAt: Date? = nil,
        isSample: Bool = false
    ) {
        self.id = id
        self.school = school
        self.program = program
        self.degree = degree
        self.intake = intake
        self.applicantName = applicantName
        self.status = status
        self.createdAt = createdAt
        self.lastAuditedAt = lastAuditedAt
        self.isSample = isSample
    }

    var compactTitle: String { "\(school) · \(program)" }
    var subtitle: String { "\(degree) · \(intake)" }
}

enum AuditPhase: Int, CaseIterable, Identifiable {
    case reading
    case classifying
    case comparing
    case reporting

    var id: Self { self }

    var title: String {
        switch self {
        case .reading: "문서 읽기"
        case .classifying: "핵심 정보 추출"
        case .comparing: "문서 간 사실 대조"
        case .reporting: "근거 리포트 생성"
        }
    }

    var symbol: String {
        switch self {
        case .reading: "doc.text.magnifyingglass"
        case .classifying: "square.stack.3d.up"
        case .comparing: "arrow.left.arrow.right"
        case .reporting: "checkmark.shield"
        }
    }
}

struct AuditHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var blockedCount: Int
    var reviewCount: Int
    var readyCount: Int
    var note: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        blockedCount: Int,
        reviewCount: Int,
        readyCount: Int,
        note: String
    ) {
        self.id = id
        self.date = date
        self.blockedCount = blockedCount
        self.reviewCount = reviewCount
        self.readyCount = readyCount
        self.note = note
    }
}
