import Foundation

/// The single source of truth for the signed-in demo user's identity.
/// A production app should replace this fixed profile with an editable
/// Keychain-backed profile; never derive the expected value from a document.
struct ApplicantProfile: Sendable, Equatable {
    let displayName: String
    let legalName: String
    let email: String

    static let current = ApplicantProfile(
        displayName: "김민준",
        legalName: "MINJUN KIM",
        email: "minjoon.kim@example.com"
    )
}

/// Kept in memory for the current run only. It intentionally is not part of
/// ApplicationSessionSnapshot because it contains personal information.
struct ApplicantIdentityExtraction: Sendable, Hashable {
    let fullName: String?
    let email: String?
    let namePage: Int?
    let emailPage: Int?
    let nameEvidence: String?
    let emailEvidence: String?

    var isEmpty: Bool {
        (fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && (email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

/// A file-level result from the separate submission-document Agent. This stays
/// in memory only: its fields can include the applicant's name and email, so it
/// must not be written to the persisted application snapshot.
struct SubmissionDocumentValidation: Sendable, Hashable {
    struct Evidence: Sendable, Hashable {
        let factType: String?
        let value: String?
        let page: Int?
        let quote: String?
    }

    let rawDocumentType: String
    let documentSubtype: String?
    let documentTitle: String?
    let classificationConfidence: String?
    let classificationReason: String?
    let applicantName: String?
    let applicantEmail: String?
    let issuingOrganization: String?
    let documentDate: String?
    let expirationDate: String?
    let evidenceItems: [Evidence]

    /// Maps only the Agent's controlled labels to the app's document slots.
    /// `nil` means that the Agent did not identify a slot with enough detail;
    /// the app shows this as a manual-review result instead of guessing from
    /// the filename or text locally.
    var detectedDocumentType: DocumentType? {
        let category = normalized(rawDocumentType)
        let details = normalized([documentSubtype, documentTitle, issuingOrganization]
            .compactMap { $0 }
            .joined(separator: " "))

        switch category {
        case "cv_resume", "cv", "resume":
            return .cv
        case "statement_of_purpose", "statement", "personal_statement", "sop":
            return .sop
        case "recommendation_letter", "recommendation", "reference_letter":
            return .recommendation
        case "portfolio_writing_sample", "portfolio":
            return details.contains("writing") || details.contains("sample") ? .writingSample : .portfolio
        case "writing_sample":
            return .writingSample
        case "test_score", "test", "score_report":
            if containsAny(details, ["toefl", "ielts", "english", "language", "duolingo"]) {
                return .englishScore
            }
            if containsAny(details, ["gre", "gmat", "graduateadmission"]) {
                return .greScore
            }
            return nil
        case "academic_document", "academic_record":
            if containsAny(details, ["transcript", "academicrecord", "grade", "gpa"]) {
                return .transcript
            }
            if containsAny(details, ["degree", "diploma", "graduation", "certificate"]) {
                return .degreeCertificate
            }
            return nil
        case "supporting_document", "supporting":
            if containsAny(details, ["passport", "visa"]) { return .passportVisa }
            if containsAny(details, ["financial", "bank", "sponsor", "funding"]) { return .financialProof }
            if containsAny(details, ["applicationform", "application form", "supplementalform", "supplemental form"]) {
                return .applicationForm
            }
            if containsAny(details, ["photo", "photograph"]) { return .identityPhoto }
            if containsAny(details, ["translation", "translated"]) { return .certifiedTranslation }
            if containsAny(details, ["residence", "eligibility"]) { return .residencyDocument }
            if containsAny(details, ["proposal", "researchplan", "research plan"]) { return .researchProposal }
            return .supportingDocument
        case "other_unknown", "other", "unknown", "not_stated", "":
            return nil
        default:
            return nil
        }
    }

    /// Only an explicit high-confidence classification can automatically
    /// satisfy a required-document slot. Medium, low, or absent confidence
    /// stays in the report as a human-review result.
    var requiresHumanReview: Bool {
        normalized(classificationConfidence ?? "") != "high"
    }

    var primaryEvidence: Evidence? {
        evidenceItems.first { evidence in
            !(evidence.quote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || !(evidence.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    var evidenceExcerpt: String {
        primaryEvidence?.quote?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? primaryEvidence?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? classificationReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? documentTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? rawDocumentType
    }

    var evidencePage: Int? { primaryEvidence?.page }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.contains(normalized($0)) }
    }
}
