import SwiftUI
import UniformTypeIdentifiers

/// Finder-like evidence inventory. It uses the existing document pipeline and
/// only changes how the active application's files are presented.
struct EvidenceVaultView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedDocumentID: UUID?
    @State private var showImporter = false
    @State private var importTarget: DocumentType?
    @State private var isDropTargeted = false

    private let supportedTypes: [UTType] = [.pdf, .plainText, .rtf, .image]

    private var selectedDocument: DocumentItem? {
        if let selectedDocumentID,
           let document = state.documents.first(where: { $0.id == selectedDocumentID }) {
            return document
        }
        return state.documents.first
    }

    private var sortedDocuments: [DocumentItem] {
        state.documents.sorted { lhs, rhs in
            documentSortOrder(lhs.type) < documentSortOrder(rhs.type)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                vaultHeader
                Divider()

                if sortedDocuments.isEmpty {
                    EmptyStateView(
                        symbol: "doc.badge.plus",
                        title: "아직 등록된 제출 서류가 없어요",
                        message: "PDF, 텍스트 또는 이미지 파일을 추가하면 문서 종류와 핵심 사실을 정리합니다.",
                        actionTitle: "파일 추가",
                        action: { showImporter = true }
                    )
                } else {
                    documentTable
                }

                Divider()
                dropTarget
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }

            Divider()

            VaultInspector(
                document: selectedDocument,
                findings: state.findings,
                replace: {
                    guard let type = selectedDocument?.type else { return }
                    importTarget = type
                    showImporter = true
                },
                remove: {
                    guard let document = selectedDocument else { return }
                    state.removeDocument(document)
                    selectedDocumentID = state.documents.first?.id
                }
            )
            .frame(width: 320)
            .background(GCTheme.canvas)
        }
        .background(GCTheme.canvas)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: importTarget == nil
        ) { result in
            switch result {
            case .success(let urls):
                state.importDocuments(urls, as: importTarget)
            case .failure(let error):
                state.errorMessage = error.localizedDescription
            }
        }
        .onAppear {
            if selectedDocumentID == nil {
                selectedDocumentID = state.documents.first?.id
            }
        }
        .onChange(of: state.documents) { _, documents in
            guard let selectedDocumentID,
                  documents.contains(where: { $0.id == selectedDocumentID }) else {
                self.selectedDocumentID = documents.first?.id
                return
            }
        }
    }

    private var vaultHeader: some View {
        HStack(alignment: .bottom) {
            PageTitle(
                "Evidence Vault",
                subtitle: "현재 지원에 사용할 증빙을 정리하고, 검수에 사용한 파일을 확인합니다."
            )
            Spacer()
            Button {
                importTarget = nil
                showImporter = true
            } label: {
                Label("문서 추가", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(state.isImporting)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private var documentTable: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                VaultTableHeader()
                Divider()
                ForEach(Array(sortedDocuments.enumerated()), id: \.element.id) { index, document in
                    VaultTableRow(
                        document: document,
                        selected: selectedDocument?.id == document.id
                    ) {
                        selectedDocumentID = document.id
                    }
                    if index < sortedDocuments.count - 1 {
                        Divider().padding(.leading, 28)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    private var dropTarget: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isDropTargeted ? .white : GCTheme.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text("파일을 이곳으로 드래그해 추가")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDropTargeted ? .white : GCTheme.ink)
                Text("PDF, TXT, RTF 또는 이미지를 문서 유형별로 자동 분류합니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(isDropTargeted ? .white.opacity(0.8) : GCTheme.secondaryInk)
            }
            Spacer()
            if state.isImporting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(isDropTargeted ? GCTheme.brand : GCTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isDropTargeted ? GCTheme.brand : GCTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.importDocuments(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }

    private func documentSortOrder(_ type: DocumentType) -> Int {
        switch type {
        case .cv: 0
        case .sop: 1
        case .transcript: 2
        case .englishScore: 3
        case .requirements: 4
        case .other: 5
        }
    }
}

private struct VaultTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("유형")
                .frame(width: 124, alignment: .leading)
            Text("파일")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("추가일")
                .frame(width: 104, alignment: .leading)
            Text("상태")
                .frame(width: 104, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(GCTheme.secondaryInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct VaultTableRow: View {
    let document: DocumentItem
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: document.type.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? GCTheme.brand : GCTheme.secondaryInk)
                        .frame(width: 24, height: 24)
                    Text(document.type.shortTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(GCTheme.ink)
                        .lineLimit(1)
                }
                .frame(width: 124, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(document.filename)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GCTheme.ink)
                        .lineLimit(1)
                    Text(document.metadata.isEmpty ? "파일 정보 없음" : document.metadata)
                        .font(.system(size: 11))
                        .foregroundStyle(GCTheme.secondaryInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(document.uploadedAt.formatted(.dateTime.year().month().day()))
                    .font(.system(size: 11))
                    .foregroundStyle(GCTheme.secondaryInk)
                    .monospacedDigit()
                    .frame(width: 104, alignment: .leading)

                DocumentProcessingLabel(status: document.processingStatus)
                    .frame(width: 104, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(selected ? GCTheme.brandSoft : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct DocumentProcessingLabel: View {
    let status: DocumentProcessingStatus

    var body: some View {
        switch status {
        case .queued, .parsing:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(status.label)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(GCTheme.brand)
        case .ready:
            Label(status.label, systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ReviewStatus.ready.color)
        case .failed:
            Label(status.label, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ReviewStatus.humanReview.color)
        }
    }
}

private struct VaultInspector: View {
    let document: DocumentItem?
    let findings: [AuditFinding]
    let replace: () -> Void
    let remove: () -> Void

    private var relatedFindings: [AuditFinding] {
        guard let document else { return [] }
        return findings.filter { finding in
            finding.evidences.contains { $0.documentName == document.filename }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let document {
                    inspectorContent(document)
                } else {
                    EmptyStateView(
                        symbol: "doc.text.magnifyingglass",
                        title: "문서를 선택하세요",
                        message: "문서의 파일 정보와 검수에서 사용한 근거를 이곳에서 확인할 수 있어요."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func inspectorContent(_ document: DocumentItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("선택한 문서", subtitle: document.type.title)

            HStack(spacing: 11) {
                Image(systemName: document.type.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(GCTheme.brand)
                    .frame(width: 42, height: 42)
                    .background(GCTheme.brandSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.filename)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GCTheme.ink)
                        .lineLimit(2)
                    Text(document.metadata.isEmpty ? "파일 정보 없음" : document.metadata)
                        .font(.system(size: 11))
                        .foregroundStyle(GCTheme.secondaryInk)
                }
            }
        }
        .padding(18)

        Divider()

        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("검수에 사용한 근거", subtitle: relatedFindings.isEmpty ? "이 문서를 인용한 검수 항목이 아직 없습니다." : "\(relatedFindings.count)개 항목이 이 파일을 참조합니다.")
            if relatedFindings.isEmpty {
                Text("문서를 추가한 뒤 제출 점검을 실행하면 결과와 함께 근거가 연결됩니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(GCTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(relatedFindings.prefix(3)) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(finding.status.color).frame(width: 6, height: 6).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(GCTheme.ink)
                                .lineLimit(2)
                            Text(finding.status.label)
                                .font(.system(size: 11))
                                .foregroundStyle(finding.status.color)
                        }
                    }
                }
            }
        }
        .padding(18)

        Divider()

        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("파일 관리")
            Button("파일 교체", action: replace)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("목록에서 제거", role: .destructive, action: remove)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(18)
    }
}
