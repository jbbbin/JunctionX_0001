import SwiftUI
import UniformTypeIdentifiers

struct DocumentsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showImporter = false
    @State private var importTarget: DocumentType?
    @State private var isDropTargeted = false

    private let supportedTypes: [UTType] = [.pdf, .plainText, .rtf, .image]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    SectionTitle(
                        "지원 서류",
                        eyebrow: "APPLICATION PACKAGE",
                        subtitle: "핵심 문서 4종을 함께 읽고 이름, 학력, 날짜, 목표 프로그램을 대조합니다."
                    )
                    Spacer()
                    Button {
                        importTarget = nil
                        showImporter = true
                    } label: {
                        Label("파일 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GCTheme.brand)
                    .disabled(state.isImporting)
                }

                coreDocumentsCard
                    .allowsHitTesting(!state.isImporting)
                requirementsDocumentCard
                    .allowsHitTesting(!state.isImporting)
                processingNote
            }
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
            .gcPagePadding()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: importTarget == nil
        ) { result in
            switch result {
            case .success(let urls): state.importDocuments(urls, as: importTarget)
            case .failure(let error): state.errorMessage = error.localizedDescription
            }
        }
    }

    private var coreDocumentsCard: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("핵심 검수 서류")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(GCTheme.ink)
                        Text("PDF, TXT, RTF 또는 이미지 · 파일별 최대 처리 시간은 네트워크 환경에 따라 달라집니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(state.coreDocumentCount) / 4 준비")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.coreDocumentCount == 4 ? ReviewStatus.ready.color : GCTheme.secondaryInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((state.coreDocumentCount == 4 ? ReviewStatus.ready.color : Color.secondary).opacity(0.08))
                        .clipShape(Capsule())
                }
                .padding(20)

                Divider()

                VStack(spacing: 0) {
                    ForEach(Array([DocumentType.cv, .sop, .transcript, .englishScore].enumerated()), id: \.element.id) { index, type in
                        DocumentSlotRow(
                            type: type,
                            document: state.documents.first(where: { $0.type == type }),
                            replace: {
                                importTarget = type
                                showImporter = true
                            },
                            remove: {
                                if let document = state.documents.first(where: { $0.type == type }) {
                                    state.removeDocument(document)
                                }
                            },
                            sampleRevision: type == .sop && state.workspace.isSample
                                ? { state.applyRevisedSampleSOP() }
                                : nil,
                            dropped: { urls in
                                state.importDocuments(urls, as: type)
                            }
                        )
                        if index < 3 { Divider().padding(.leading, 74) }
                    }
                }

                dropZone
                    .padding(18)
            }
        }
    }

    private var requirementsDocumentCard: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(GCTheme.blue.opacity(0.09))
                        Image(systemName: DocumentType.requirements.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(GCTheme.blue)
                    }
                    .frame(width: 45, height: 45)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("공식 모집요강")
                                .font(.system(size: 14, weight: .bold))
                            Text("P1")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(GCTheme.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(GCTheme.blue.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        Text("학교 공통 안내와 프로그램 고유 요건을 분리해 출처 페이지와 함께 정리합니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let document = state.documents.first(where: { $0.type == .requirements }) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Label(document.filename, systemImage: document.processingStatus == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(document.processingStatus == .ready ? ReviewStatus.ready.color : ReviewStatus.humanReview.color)
                                .lineLimit(1)
                            Text(document.metadata)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 250, alignment: .trailing)
                    }
                    Button(state.documents.contains(where: { $0.type == .requirements }) ? "교체" : "추가") {
                        importTarget = .requirements
                        showImporter = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
            }
        }
    }

    private var dropZone: some View {
        HStack(spacing: 11) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isDropTargeted ? .white : GCTheme.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text("여기에 여러 파일을 놓아도 돼요")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDropTargeted ? .white : GCTheme.ink)
                Text("파일명과 내용을 기준으로 문서 유형을 분류합니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(isDropTargeted ? .white.opacity(0.75) : .secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(isDropTargeted ? GCTheme.brand : GCTheme.brandSoft.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GCTheme.brand.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.importDocuments(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var processingNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.isUpstageConnected ? "network.badge.shield.half.filled" : "lock.macwindow")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(GCTheme.brand)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.providerLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GCTheme.ink)
                Text(state.isUpstageConnected
                     ? "가져온 PDF와 이미지는 Upstage Document Parse로 구조화합니다. API 키와 원문 텍스트는 앱 상태에 저장하지 않습니다."
                     : "텍스트 레이어가 있는 PDF와 텍스트 문서는 이 Mac에서 읽습니다. 스캔 이미지 분석은 UPSTAGE_API_KEY를 설정하면 활성화됩니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

private struct DocumentSlotRow: View {
    let type: DocumentType
    let document: DocumentItem?
    let replace: () -> Void
    let remove: () -> Void
    let sampleRevision: (() -> Void)?
    let dropped: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(document == nil ? Color.black.opacity(0.04) : GCTheme.brandSoft)
                Image(systemName: type.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(document == nil ? Color.secondary : GCTheme.brand)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(type.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GCTheme.ink)
                if let document {
                    HStack(spacing: 7) {
                        Text(document.filename)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(GCTheme.secondaryInk)
                            .lineLimit(1)
                        if !document.metadata.isEmpty {
                            Text(document.metadata)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if document.isSample {
                            Text("샘플")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(GCTheme.blue)
                        }
                    }
                } else {
                    Text("파일을 추가하거나 이 행에 놓으세요")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if let document {
                processingStatus(document.processingStatus)
                Menu {
                    Button("파일 교체", action: replace)
                    if let sampleRevision, document.isSample {
                        Button("수정본 샘플 적용", action: sampleRevision)
                    }
                    Button("목록에서 제거", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            } else {
                Button("파일 선택", action: replace)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(targeted ? GCTheme.brandSoft.opacity(0.75) : .clear)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            dropped(Array(urls.prefix(1)))
            return !urls.isEmpty
        } isTargeted: { targeted = $0 }
    }

    @ViewBuilder
    private func processingStatus(_ status: DocumentProcessingStatus) -> some View {
        switch status {
        case .queued, .parsing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(status.label)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(GCTheme.blue)
        case .ready:
            Label(status.label, systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ReviewStatus.ready.color)
        case .failed:
            Label(status.label, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ReviewStatus.humanReview.color)
        }
    }
}
