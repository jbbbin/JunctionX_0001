import SwiftUI

extension ApplicationCategory {
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

extension EligibilityState {
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

extension RequirementState {
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

extension DocumentPreparationType {
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
