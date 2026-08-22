import AppKit
import SwiftUI

// Keep every product color inside the macOS semantic system. This makes light
// mode, dark mode, and increased-contrast settings behave like a native app.
enum GCTheme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let content = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let ink = Color(nsColor: .labelColor)
    static let secondaryInk = Color(nsColor: .secondaryLabelColor)
    static let tertiaryInk = Color(nsColor: .tertiaryLabelColor)
    static let brand = Color(nsColor: .systemBlue)
    static let brandBright = brand
    static let brandSoft = brand.opacity(0.12)
    static let line = Color(nsColor: .separatorColor)
    static let selected = Color(nsColor: .selectedContentBackgroundColor)
    static let blue = brand
}

/// Use an inset group only for genuinely grouped information; the rows inside
/// should provide hierarchy through dividers, not another layer of cards.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(GCTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StatusBadge: View {
    let status: ReviewStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            Text(status.label)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(status.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("\(status.rawValue), \(status.label)")
    }
}

struct WorkspaceBadge: View {
    let status: WorkspaceStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            Text(status.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(status.color)
    }
}

struct PageSourceChip: View {
    let evidence: EvidenceRef

    var body: some View {
        Label(evidence.sourceLabel, systemImage: "doc.text")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(GCTheme.secondaryInk)
            .lineLimit(1)
    }
}

struct SectionTitle: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GCTheme.secondaryInk)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GCTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(GCTheme.secondaryInk)
            }
        }
    }
}

/// Reserved for the title of a whole destination. Inset groups should use
/// `SectionTitle` so the page hierarchy is never flattened by oversized text.
struct PageTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(GCTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(GCTheme.secondaryInk)
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(GCTheme.brand)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GCTheme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(GCTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(GCTheme.brand)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .padding(28)
    }
}

extension View {
    func gcPagePadding() -> some View {
        padding(.horizontal, 28).padding(.vertical, 24)
    }

}
