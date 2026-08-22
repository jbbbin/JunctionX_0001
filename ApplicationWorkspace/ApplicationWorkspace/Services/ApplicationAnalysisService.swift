import Foundation

enum ApplicationAnalysisError: LocalizedError {
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "지원 공고 주소나 PDF를 확인해 주세요."
        }
    }
}

@MainActor
protocol ApplicationAnalyzing {
    func analyze(source: ImportedSource) async throws -> ApplicationItem
}

struct MockApplicationAnalysisService: ApplicationAnalyzing {
    var now: () -> Date = Date.init

    func analyze(source: ImportedSource) async throws -> ApplicationItem {
        let category = inferredCategory(from: source.displayName)
        let deadline = Calendar.current.date(byAdding: .day, value: 10, to: now()) ?? now()
        let evidenceLocation: SourceLocation
        let applicationSource: ApplicationSource

        switch source {
        case let .file(url):
            evidenceLocation = .pdf(page: 2)
            applicationSource = ApplicationSource(
                documentURL: url,
                displayName: url.lastPathComponent
            )
        case let .web(url):
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw ApplicationAnalysisError.unsupportedSource
            }
            evidenceLocation = .web(url: url)
            applicationSource = ApplicationSource(
                webURL: url,
                displayName: url.host() ?? url.absoluteString
            )
        }

        return ApplicationItem(
            category: category,
            title: "AI가 분석한 새 지원 공고",
            organization: sourceOrganization(for: source),
            deadline: deadline,
            eligibility: .needsReview,
            requirements: [
                EligibilityRequirement(
                    title: "학력 조건",
                    detail: "대학 재학생 또는 졸업 예정자",
                    state: .satisfied,
                    evidence: EvidenceReference(location: evidenceLocation)
                ),
                EligibilityRequirement(
                    title: "세부 지원 조건",
                    detail: "원문에서 추출한 조건을 한 번 확인해 주세요.",
                    state: .needsReview,
                    evidence: EvidenceReference(location: evidenceLocation)
                )
            ],
            requiredDocuments: [
                RequiredDocument(name: "재학증명서", preparationType: .owned),
                RequiredDocument(name: "지원서", preparationType: .write),
                RequiredDocument(name: "추천서", preparationType: .request)
            ],
            source: applicationSource
        )
    }

    private func inferredCategory(from value: String) -> ApplicationCategory {
        let normalized = value.lowercased()
        if normalized.contains("장학") || normalized.contains("scholar") {
            return .scholarship
        }
        if normalized.contains("공모") || normalized.contains("대회") || normalized.contains("contest") {
            return .competition
        }
        return .employment
    }

    private func sourceOrganization(for source: ImportedSource) -> String {
        switch source {
        case .file:
            "업로드 문서에서 추출"
        case let .web(url):
            url.host() ?? "웹 공고에서 추출"
        }
    }
}
