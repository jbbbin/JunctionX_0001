import AppKit
import SwiftUI

enum GCTheme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    static let brand = Color(nsColor: .systemBlue)
    static let brandBright = brand
    static let brandDeep = Color(nsColor: .systemIndigo)
    static let brandSoft = brand.opacity(0.12)
    static let line = Color(nsColor: .separatorColor)
    static let blue = brand
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(GCTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GCTheme.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.025), radius: 12, y: 4)
    }
}

struct StatusBadge: View {
    let status: ReviewStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            Text(status.rawValue)
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 6)
        .background(status.color.opacity(0.105))
        .clipShape(Capsule())
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
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.09))
        .clipShape(Capsule())
    }
}

struct PageSourceChip: View {
    let evidence: EvidenceRef

    var body: some View {
        Label(evidence.sourceLabel, systemImage: "doc.text")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(GCTheme.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(GCTheme.secondaryInk.opacity(0.09))
            .clipShape(Capsule())
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
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(GCTheme.brandBright)
            }
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GCTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
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
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(GCTheme.brand)
                .frame(width: 64, height: 64)
                .background(GCTheme.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GCTheme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(GCTheme.brand)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(30)
    }
}

private struct GCSidebarGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(GCTheme.brand.opacity(0.055)),
                    in: .rect(cornerRadius: 22)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

private struct GCSidebarTabModifier: ViewModifier {
    let selected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if selected {
                content
                    .glassEffect(
                        .regular.tint(GCTheme.brand.opacity(0.18)).interactive(),
                        in: .rect(cornerRadius: 10)
                    )
            } else {
                content
            }
        } else {
            content
                .background(
                    selected ? GCTheme.brand.opacity(0.13) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
    }
}

extension View {
    func gcPagePadding() -> some View {
        padding(.horizontal, 30).padding(.vertical, 26)
    }

    func gcSidebarGlass() -> some View {
        modifier(GCSidebarGlassModifier())
    }

    func gcSidebarTab(selected: Bool) -> some View {
        modifier(GCSidebarTabModifier(selected: selected))
    }
}
