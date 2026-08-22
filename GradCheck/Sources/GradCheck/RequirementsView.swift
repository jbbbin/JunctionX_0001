import SwiftUI
import UniformTypeIdentifiers

struct RequirementsView: View {
    @EnvironmentObject private var state: AppViewModel
    @State private var showImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    SectionTitle(
                        "공식 모집 요건",
                        eyebrow: "REQUIREMENTS AGENT · P1",
                        subtitle: "학교 공통 규정과 프로그램 고유 규정을 분리하고, 모든 항목에 출처 페이지를 남깁니다."
                    )
                    Spacer()
                    Button {
                        showImporter = true
                    } label: {
                        Label("모집요강 추가", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GCTheme.brand)
                    .disabled(state.isImporting)
                }

                sourceCard

                if state.requirements.isEmpty {
                    SurfaceCard {
                        EmptyStateView(
                            symbol: "building.columns",
                            title: "등록된 공식 모집요강이 없어요",
                            message: "학교 또는 프로그램의 공식 PDF를 추가하면 요건을 구조화하고 지원 서류와 대조할 수 있어요.",
                            actionTitle: "PDF 추가",
                            action: { showImporter = true }
                        )
                    }
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        requirementGroup(.university)
                        requirementGroup(.program)
                    }
                }

                provenanceNote
            }
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
            .gcPagePadding()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): state.importDocuments(urls, as: .requirements)
            case .failure(let error): state.errorMessage = error.localizedDescription
            }
        }
    }

    private var sourceCard: some View {
        SurfaceCard(padding: 0) {
            if state.requirementDocuments.isEmpty {
                HStack(spacing: 15) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 49, height: 49)
                        .background(Color.black.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("공식 출처 문서가 필요합니다")
                            .font(.system(size: 14, weight: .bold))
                        Text("대학원 또는 학과가 제공한 공식 PDF를 등록하세요.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.requirementDocuments.enumerated()), id: \.element.id) { index, document in
                        HStack(spacing: 15) {
                            Image(systemName: document.processingStatus == .ready ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(document.processingStatus == .ready ? GCTheme.brand : ReviewStatus.humanReview.color)
                                .frame(width: 42, height: 42)
                                .background(GCTheme.brandSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.filename)
                                    .font(.system(size: 12, weight: .semibold))
                                Text([document.metadata, document.isSample ? "합성 데모 출처" : state.providerLabel]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(document.processingStatus.label, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ReviewStatus.ready.color)
                            Button {
                                state.removeDocument(document)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(state.isImporting)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        if index < state.requirementDocuments.count - 1 { Divider().padding(.leading, 74) }
                    }
                }
            }
        }
    }

    private func requirementGroup(_ scope: RequirementScope) -> some View {
        let values = state.requirements.filter { $0.scope == scope }
        return SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(scope.rawValue)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(GCTheme.ink)
                        Text(scope == .university ? "대학원 전체에 적용되는 안내" : "선택한 프로그램에만 적용되는 안내")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(values.count)개")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GCTheme.brand)
                }
                .padding(18)

                Divider()

                ForEach(Array(values.enumerated()), id: \.element.id) { index, requirement in
                    RequirementRow(requirement: requirement)
                    if index < values.count - 1 { Divider().padding(.leading, 50) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var provenanceNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.bubble.fill")
                .foregroundStyle(GCTheme.brand)
            VStack(alignment: .leading, spacing: 4) {
                Text("추정하지 않는 요건 정리")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GCTheme.ink)
                Text("문서에 명시되지 않았거나 학교 안내와 프로그램 안내가 충돌하면 확정 요건으로 만들지 않고 HUMAN REVIEW로 남깁니다. 공식성, 면제 여부, 학점 환산은 기관의 최종 판단입니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct RequirementRow: View {
    let requirement: RequirementItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: requirement.status.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(requirement.status.color)
                .frame(width: 28, height: 28)
                .background(requirement.status.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(requirement.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GCTheme.ink)
                    Spacer()
                    Text(requirement.status == .humanReview ? "직접 확인" : "출처 확인")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(requirement.status.color)
                }
                Text(requirement.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(
                    requirement.page.map { "\(requirement.sourceName) · p.\($0)" } ?? requirement.sourceName,
                    systemImage: "doc.text"
                )
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GCTheme.secondaryInk)
                .lineLimit(1)
            }
        }
        .padding(16)
    }
}
