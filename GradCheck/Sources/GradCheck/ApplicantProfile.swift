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
        email: "minjan.kim@example.com"
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
