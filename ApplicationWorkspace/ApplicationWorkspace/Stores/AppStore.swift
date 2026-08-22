import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var route: SidebarRoute = .dashboard
    @Published var applications: [ApplicationItem]
    @Published var profile: UserProfile
    @Published var ownedDocuments: [OwnedDocument]

    init() {
        applications = Self.sampleApplications
        profile = UserProfile(
            school: "포항공과대학교",
            enrollmentStatus: "재학",
            grade: 4,
            gpa: "3.82",
            incomeBracket: "6분위",
            major: "컴퓨터공학과",
            region: "경상북도"
        )
        ownedDocuments = [
            OwnedDocument(name: "재학증명서", type: "학적", filename: "재학증명서_2026.pdf"),
            OwnedDocument(name: "성적증명서", type: "성적", filename: "성적증명서_2026.pdf"),
            OwnedDocument(name: "주민등록등본", type: "신원", filename: "주민등록등본.pdf")
        ]
    }

    func application(id: UUID) -> ApplicationItem? {
        applications.first { $0.id == id }
    }

    func toggleCompletion(applicationID: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        applications[index].isCompleted.toggle()
    }

    func toggleDocumentReady(applicationID: UUID, documentID: UUID) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }),
              let documentIndex = applications[applicationIndex].requiredDocuments.firstIndex(where: { $0.id == documentID })
        else { return }

        applications[applicationIndex].requiredDocuments[documentIndex].isReady.toggle()
        updateNextAction(for: applicationIndex)
    }

    func linkDocument(
        applicationID: UUID,
        documentID: UUID,
        filename: String
    ) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }),
              let documentIndex = applications[applicationIndex].requiredDocuments.firstIndex(where: { $0.id == documentID })
        else { return }

        applications[applicationIndex].requiredDocuments[documentIndex].linkedFilename = filename
        applications[applicationIndex].requiredDocuments[documentIndex].isReady = true
        updateNextAction(for: applicationIndex)
    }

    func updateProfile(_ newProfile: UserProfile) {
        profile = newProfile
    }

    func addOwnedDocument(from url: URL) {
        let filename = url.lastPathComponent
        let displayName = url.deletingPathExtension().lastPathComponent
        ownedDocuments.insert(
            OwnedDocument(
                name: displayName,
                type: inferredDocumentType(from: displayName),
                filename: filename,
                fileURL: url
            ),
            at: 0
        )
    }

    func replaceOwnedDocument(id: UUID, with url: URL) {
        guard let index = ownedDocuments.firstIndex(where: { $0.id == id }) else { return }
        ownedDocuments[index].filename = url.lastPathComponent
        ownedDocuments[index].fileURL = url
        ownedDocuments[index].addedAt = Date()
    }

    func deleteOwnedDocument(id: UUID) {
        ownedDocuments.removeAll { $0.id == id }
    }

    @discardableResult
    func addImportedApplication(filename: String) -> UUID {
        let application = ApplicationItem(
            category: .employment,
            title: "AI가 분석한 새 지원 공고",
            organization: "업로드 문서에서 추출",
            deadline: Self.date(daysFromNow: 10),
            eligibility: .needsReview,
            requirements: [
                EligibilityRequirement(
                    title: "학력 조건",
                    detail: "대학 재학생 또는 졸업 예정자",
                    state: .satisfied,
                    sourcePage: 2
                ),
                EligibilityRequirement(
                    title: "경력 조건",
                    detail: "세부 조건을 한 번 확인해 주세요.",
                    state: .needsReview,
                    sourcePage: 3
                )
            ],
            requiredDocuments: [
                RequiredDocument(
                    name: "재학증명서",
                    preparationType: .owned,
                    isReady: true,
                    linkedFilename: "재학증명서_2026.pdf"
                ),
                RequiredDocument(name: "지원서", preparationType: .write),
                RequiredDocument(name: "추천서", preparationType: .request)
            ],
            nextAction: "경력 조건을 확인해 주세요",
            applicationURL: URL(string: "https://example.com/apply"),
            sourceFilename: filename
        )
        applications.insert(application, at: 0)
        return application.id
    }

    private func updateNextAction(for applicationIndex: Int) {
        if let next = applications[applicationIndex].requiredDocuments.first(where: { !$0.isReady }) {
            switch next.preparationType {
            case .owned:
                applications[applicationIndex].nextAction = "\(next.name) 파일을 연결해 주세요"
            case .write:
                applications[applicationIndex].nextAction = "\(next.name)을 작성해 주세요"
            case .request:
                applications[applicationIndex].nextAction = "\(next.name)을 요청해 주세요"
            }
        } else {
            applications[applicationIndex].nextAction = "공식 접수처에서 제출해 주세요"
        }
    }

    private func inferredDocumentType(from name: String) -> String {
        if name.contains("성적") { return "성적" }
        if name.contains("재학") || name.contains("졸업") { return "학적" }
        if name.contains("등본") { return "신원" }
        return "기타"
    }

    private static func date(daysFromNow days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }

    private static let sampleApplications: [ApplicationItem] = [
        ApplicationItem(
            category: .employment,
            title: "2026 SKT 신입 개발자 채용",
            organization: "SK텔레콤",
            deadline: date(daysFromNow: 4),
            eligibility: .eligible,
            requirements: [
                EligibilityRequirement(title: "학력", detail: "2027년 2월 이전 졸업 예정자", state: .satisfied, sourcePage: 2),
                EligibilityRequirement(title: "전공", detail: "전공 무관", state: .satisfied, sourcePage: 2),
                EligibilityRequirement(title: "근무 가능 시점", detail: "2026년 11월부터 근무 가능", state: .needsReview, sourcePage: 4)
            ],
            requiredDocuments: [
                RequiredDocument(name: "지원서", preparationType: .write, isReady: true, linkedFilename: "SKT_지원서_v2.pdf"),
                RequiredDocument(name: "재학증명서", preparationType: .owned, isReady: true, linkedFilename: "재학증명서_2026.pdf"),
                RequiredDocument(name: "성적증명서", preparationType: .owned, isReady: true, linkedFilename: "성적증명서_2026.pdf"),
                RequiredDocument(name: "포트폴리오", preparationType: .write),
                RequiredDocument(name: "추천서", preparationType: .request)
            ],
            nextAction: "포트폴리오를 연결해 주세요",
            applicationURL: URL(string: "https://www.skcareers.com"),
            sourceFilename: "SKT_2026_신입채용.pdf"
        ),
        ApplicationItem(
            category: .scholarship,
            title: "2026 미래인재 장학금",
            organization: "한국미래재단",
            deadline: date(daysFromNow: 7),
            eligibility: .needsReview,
            requirements: [
                EligibilityRequirement(title: "재학 상태", detail: "국내 대학 정규학기 재학생", state: .satisfied, sourcePage: 1),
                EligibilityRequirement(title: "성적", detail: "직전 학기 3.5 / 4.5 이상", state: .satisfied, sourcePage: 2),
                EligibilityRequirement(title: "소득분위", detail: "7분위 이하", state: .needsReview, sourcePage: 2)
            ],
            requiredDocuments: [
                RequiredDocument(name: "주민등록등본", preparationType: .owned, isReady: true, linkedFilename: "주민등록등본.pdf"),
                RequiredDocument(name: "재학증명서", preparationType: .owned, isReady: true, linkedFilename: "재학증명서_2026.pdf"),
                RequiredDocument(name: "성적증명서", preparationType: .owned, isReady: true, linkedFilename: "성적증명서_2026.pdf"),
                RequiredDocument(name: "자기소개서", preparationType: .write),
                RequiredDocument(name: "추천서", preparationType: .request)
            ],
            nextAction: "소득분위 정보를 확인해 주세요",
            applicationURL: URL(string: "https://example.com/scholarship"),
            sourceFilename: "미래인재_장학금_모집요강.pdf"
        ),
        ApplicationItem(
            category: .competition,
            title: "JunctionX Seoul 2026",
            organization: "Junction Asia",
            deadline: date(daysFromNow: 12),
            eligibility: .eligible,
            requirements: [
                EligibilityRequirement(title: "참가 형태", detail: "개인 지원 후 현장 팀 빌딩 가능", state: .satisfied, sourcePage: 1),
                EligibilityRequirement(title: "연령", detail: "만 18세 이상", state: .satisfied, sourcePage: 1)
            ],
            requiredDocuments: [
                RequiredDocument(name: "참가 신청서", preparationType: .write, isReady: true, linkedFilename: "JunctionX_신청서.pdf"),
                RequiredDocument(name: "GitHub 프로필", preparationType: .write, isReady: true, linkedFilename: "github.com/hyeonpaper"),
                RequiredDocument(name: "아이디어 소개", preparationType: .write)
            ],
            nextAction: "아이디어 소개를 작성해 주세요",
            applicationURL: URL(string: "https://www.junction.com"),
            sourceFilename: "JunctionX_Seoul_2026.pdf"
        )
    ]
}
