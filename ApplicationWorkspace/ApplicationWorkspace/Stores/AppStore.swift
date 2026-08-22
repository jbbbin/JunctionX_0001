import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
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
        reconcileOwnedDocuments()
    }

    func application(id: UUID) -> ApplicationItem? {
        applications.first { $0.id == id }
    }

    @discardableResult
    func addApplication(_ application: ApplicationItem) -> UUID {
        applications.insert(application, at: 0)
        reconcileOwnedDocuments()
        return application.id
    }

    func toggleCompletion(applicationID: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        applications[index].status = applications[index].isCompleted ? .preparing : .submitted
    }

    func toggleDocumentReady(applicationID: UUID, documentID: UUID) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }),
              let documentIndex = applications[applicationIndex].requiredDocuments.firstIndex(where: { $0.id == documentID })
        else { return }

        applications[applicationIndex].requiredDocuments[documentIndex].isReady.toggle()
    }

    func linkDocument(
        applicationID: UUID,
        documentID: UUID,
        url: URL
    ) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }),
              let documentIndex = applications[applicationIndex].requiredDocuments.firstIndex(where: { $0.id == documentID })
        else { return }

        let filename = url.lastPathComponent
        applications[applicationIndex].requiredDocuments[documentIndex].linkedFilename = filename
        applications[applicationIndex].requiredDocuments[documentIndex].linkedFileURL = url
        applications[applicationIndex].requiredDocuments[documentIndex].isReady = true

        if !ownedDocuments.contains(where: { $0.fileURL == url || $0.filename == filename }) {
            let name = url.deletingPathExtension().lastPathComponent
            ownedDocuments.insert(
                OwnedDocument(
                    name: name,
                    type: inferredDocumentType(from: name),
                    filename: filename,
                    fileURL: url
                ),
                at: 0
            )
        }
    }

    func markDocumentRequested(applicationID: UUID, documentID: UUID) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }),
              let documentIndex = applications[applicationIndex].requiredDocuments.firstIndex(where: { $0.id == documentID })
        else { return }

        applications[applicationIndex].requiredDocuments[documentIndex].requestState = .requested
        applications[applicationIndex].requiredDocuments[documentIndex].isReady = false
    }

    func markDocumentReceived(applicationID: UUID, documentID: UUID) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }),
              let documentIndex = applications[applicationIndex].requiredDocuments.firstIndex(where: { $0.id == documentID })
        else { return }

        applications[applicationIndex].requiredDocuments[documentIndex].requestState = .received
        applications[applicationIndex].requiredDocuments[documentIndex].isReady = true
    }

    func resetDocumentRequest(applicationID: UUID, documentID: UUID) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }),
              let documentIndex = applications[applicationIndex].requiredDocuments.firstIndex(where: { $0.id == documentID })
        else { return }

        applications[applicationIndex].requiredDocuments[documentIndex].requestState = .notRequested
        applications[applicationIndex].requiredDocuments[documentIndex].isReady = false
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
        reconcileOwnedDocuments()
    }

    func replaceOwnedDocument(id: UUID, with url: URL) {
        guard let index = ownedDocuments.firstIndex(where: { $0.id == id }) else { return }
        let previousFilename = ownedDocuments[index].filename
        ownedDocuments[index].filename = url.lastPathComponent
        ownedDocuments[index].fileURL = url
        ownedDocuments[index].addedAt = Date()

        for applicationIndex in applications.indices {
            for documentIndex in applications[applicationIndex].requiredDocuments.indices
            where applications[applicationIndex].requiredDocuments[documentIndex].linkedFilename == previousFilename {
                applications[applicationIndex].requiredDocuments[documentIndex].linkedFilename = url.lastPathComponent
                applications[applicationIndex].requiredDocuments[documentIndex].linkedFileURL = url
            }
        }
    }

    func deleteOwnedDocument(id: UUID) {
        guard let document = ownedDocuments.first(where: { $0.id == id }) else { return }
        ownedDocuments.removeAll { $0.id == id }

        for applicationIndex in applications.indices {
            for documentIndex in applications[applicationIndex].requiredDocuments.indices
            where applications[applicationIndex].requiredDocuments[documentIndex].linkedFilename == document.filename {
                applications[applicationIndex].requiredDocuments[documentIndex].linkedFilename = nil
                applications[applicationIndex].requiredDocuments[documentIndex].linkedFileURL = nil
                applications[applicationIndex].requiredDocuments[documentIndex].isReady = false
            }
        }
    }

    @discardableResult
    func addImportedApplication(source importedSource: ImportedSource) -> UUID {
        let source: ApplicationSource
        switch importedSource {
        case let .file(url):
            source = ApplicationSource(
                documentURL: url,
                displayName: url.lastPathComponent
            )
        case let .web(url):
            source = ApplicationSource(
                webURL: url,
                displayName: url.host() ?? url.absoluteString
            )
        }

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
            source: source
        )
        return addApplication(application)
    }

    private func reconcileOwnedDocuments() {
        for applicationIndex in applications.indices {
            for documentIndex in applications[applicationIndex].requiredDocuments.indices {
                let required = applications[applicationIndex].requiredDocuments[documentIndex]
                guard !required.isReady,
                      required.preparationType == .owned,
                      let owned = ownedDocuments.first(where: {
                          $0.fileURL != nil
                              && normalizedDocumentName($0.name) == normalizedDocumentName(required.name)
                      }),
                      let ownedURL = owned.fileURL
                else { continue }

                applications[applicationIndex].requiredDocuments[documentIndex].linkedFilename = owned.filename
                applications[applicationIndex].requiredDocuments[documentIndex].linkedFileURL = ownedURL
                applications[applicationIndex].requiredDocuments[documentIndex].isReady = true
            }
        }
    }

    private func normalizedDocumentName(_ name: String) -> String {
        name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
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

    private static func webEvidence(_ address: String) -> EvidenceReference {
        EvidenceReference(location: .web(url: URL(string: address)))
    }

    private static let sampleApplications: [ApplicationItem] = [
        ApplicationItem(
            category: .employment,
            title: "2026 SKT 신입 개발자 채용",
            organization: "SK텔레콤",
            deadline: date(daysFromNow: 4),
            eligibility: .eligible,
            requirements: [
                EligibilityRequirement(title: "학력", detail: "2027년 2월 이전 졸업 예정자", state: .satisfied, evidence: webEvidence("https://www.skcareers.com")),
                EligibilityRequirement(title: "전공", detail: "전공 무관", state: .satisfied, evidence: webEvidence("https://www.skcareers.com")),
                EligibilityRequirement(title: "근무 가능 시점", detail: "2026년 11월부터 근무 가능", state: .needsReview, evidence: webEvidence("https://www.skcareers.com"))
            ],
            requiredDocuments: [
                RequiredDocument(name: "지원서", preparationType: .write, isReady: true, linkedFilename: "SKT_지원서_v2.pdf"),
                RequiredDocument(name: "재학증명서", preparationType: .owned, isReady: true, linkedFilename: "재학증명서_2026.pdf"),
                RequiredDocument(name: "성적증명서", preparationType: .owned, isReady: true, linkedFilename: "성적증명서_2026.pdf"),
                RequiredDocument(name: "포트폴리오", preparationType: .write),
                RequiredDocument(name: "추천서", preparationType: .request)
            ],
            source: ApplicationSource(
                webURL: URL(string: "https://www.skcareers.com"),
                displayName: "SKT_2026_신입채용.pdf"
            )
        ),
        ApplicationItem(
            category: .scholarship,
            title: "2026 미래인재 장학금",
            organization: "한국미래재단",
            deadline: date(daysFromNow: 7),
            eligibility: .needsReview,
            requirements: [
                EligibilityRequirement(title: "재학 상태", detail: "국내 대학 정규학기 재학생", state: .satisfied, evidence: webEvidence("https://example.com/scholarship")),
                EligibilityRequirement(title: "성적", detail: "직전 학기 3.5 / 4.5 이상", state: .satisfied, evidence: webEvidence("https://example.com/scholarship")),
                EligibilityRequirement(title: "소득분위", detail: "7분위 이하", state: .needsReview, evidence: webEvidence("https://example.com/scholarship"))
            ],
            requiredDocuments: [
                RequiredDocument(name: "주민등록등본", preparationType: .owned, isReady: true, linkedFilename: "주민등록등본.pdf"),
                RequiredDocument(name: "재학증명서", preparationType: .owned, isReady: true, linkedFilename: "재학증명서_2026.pdf"),
                RequiredDocument(name: "성적증명서", preparationType: .owned, isReady: true, linkedFilename: "성적증명서_2026.pdf"),
                RequiredDocument(name: "자기소개서", preparationType: .write),
                RequiredDocument(name: "추천서", preparationType: .request)
            ],
            source: ApplicationSource(
                webURL: URL(string: "https://example.com/scholarship"),
                displayName: "미래인재_장학금_모집요강.pdf"
            )
        ),
        ApplicationItem(
            category: .competition,
            title: "JunctionX Seoul 2026",
            organization: "Junction Asia",
            deadline: date(daysFromNow: 12),
            eligibility: .eligible,
            requirements: [
                EligibilityRequirement(title: "참가 형태", detail: "개인 지원 후 현장 팀 빌딩 가능", state: .satisfied, evidence: webEvidence("https://www.junction.com")),
                EligibilityRequirement(title: "연령", detail: "만 18세 이상", state: .satisfied, evidence: webEvidence("https://www.junction.com"))
            ],
            requiredDocuments: [
                RequiredDocument(name: "참가 신청서", preparationType: .write, isReady: true, linkedFilename: "JunctionX_신청서.pdf"),
                RequiredDocument(name: "GitHub 프로필", preparationType: .write, isReady: true, linkedFilename: "github.com/hyeonpaper"),
                RequiredDocument(name: "아이디어 소개", preparationType: .write)
            ],
            source: ApplicationSource(
                webURL: URL(string: "https://www.junction.com"),
                displayName: "JunctionX_Seoul_2026.pdf"
            )
        )
    ]
}
