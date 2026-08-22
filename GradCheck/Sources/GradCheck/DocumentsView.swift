import SwiftUI
import UniformTypeIdentifiers

struct DocumentsView: View {
    @EnvironmentObject private var state: AppViewModel
    @State private var showImporter = false
    @State private var importTarget: DocumentType?
    @State private var isDropTargeted = false

    private let supportedTypes: [UTType] = [.pdf, .plainText, .rtf, .image]

    var body: some View {
        Group {
            switch state.documentsRoute {
            case .list:
                workspaceList
            case .detail:
                documentDetail
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: importTarget == nil || importTarget.map { state.requiredCount(for: $0) > 1 } == true
        ) { result in
            switch result {
            case .success(let urls): state.importDocuments(urls, as: importTarget)
            case .failure(let error): state.errorMessage = error.localizedDescription
            }
        }
    }

    private var workspaceList: some View {
        WorkspaceSelectionView(
            title: "지원 서류",
            eyebrow: "APPLICATIONS",
            subtitle: "지원할 학교와 프로그램을 선택해 모집요강 기반 서류 목록을 확인하세요.",
            actionTitle: "새 지원 목표",
            action: { state.showNewWorkspace = true },
            select: state.showWorkspaceDocuments
        )
        .environmentObject(state)
    }

    private var documentDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button {
                    state.showWorkspaceList()
                } label: {
                    Label("지원 목록", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(GCTheme.brand)

                HStack(alignment: .bottom) {
                    SectionTitle(
                        "지원 서류",
                        eyebrow: "APPLICATION PACKAGE",
                        subtitle: "이 지원서의 공식 모집요강에서 확인한 서류만 구성하고 서로 대조합니다."
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
                    .disabled(state.isImporting || state.requiredDocumentTypes.isEmpty)
                }

                requirementsSourceSummary

                if state.requirements.isEmpty || state.requiredDocumentTypes.isEmpty {
                    SurfaceCard {
                        EmptyStateView(
                            symbol: "building.columns",
                            title: "먼저 모집요강을 확인해 주세요",
                            message: "공식 모집요강을 분석한 뒤 학교·프로그램에 맞는 필요 서류 목록을 만듭니다.",
                            actionTitle: "모집요강으로 이동",
                            action: { state.destination = .requirements }
                        )
                    }
                } else {
                    requiredDocumentsCard
                        .allowsHitTesting(!state.isImporting)
                    extractedChecklistCard
                }
                processingNote
            }
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
            .gcPagePadding()
        }
    }

    private var requiredDocumentsCard: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("모집요강 기반 필요 서류")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(GCTheme.ink)
                        Text("PDF, TXT, RTF 또는 이미지 · 파일별 최대 처리 시간은 네트워크 환경에 따라 달라집니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(state.readyDocumentCount) / \(state.requiredDocumentCount) 준비")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.readyDocumentCount == state.requiredDocumentCount ? ReviewStatus.ready.color : GCTheme.secondaryInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((state.readyDocumentCount == state.requiredDocumentCount ? ReviewStatus.ready.color : Color.secondary).opacity(0.08))
                        .clipShape(Capsule())
                }
                .padding(20)

                Divider()

                VStack(spacing: 0) {
                    ForEach(Array(state.requiredDocumentTypes.enumerated()), id: \.element.id) { index, type in
                        DocumentSlotRow(
                            type: type,
                            documents: state.documents.filter { $0.type == type },
                            expectedCount: state.requiredCount(for: type),
                            replace: {
                                importTarget = type
                                showImporter = true
                            },
                            remove: { state.removeDocument($0) },
                            sampleRevision: type == .sop && state.workspace.isSample
                                ? { state.applyRevisedSampleSOP() }
                                : nil,
                            dropped: { urls in
                                state.importDocuments(urls, as: type)
                            }
                        )
                        if index < state.requiredDocumentTypes.count - 1 { Divider().padding(.leading, 74) }
                    }
                }

                dropZone
                    .padding(18)
            }
        }
    }

    private var requirementsSourceSummary: some View {
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
                    if let document = state.requirementDocuments.first {
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
                    if state.requirementDocuments.count > 1 {
                        Text("외 \(state.requirementDocuments.count - 1)개")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Button("요건 관리") { state.destination = .requirements }
                        .buttonStyle(.bordered)
                }
                .padding(20)
            }
        }
    }

    /// Keeps every Agent-extracted requirement visible beside the upload slots.
    /// Some requirements (for example an online form or an application fee) do
    /// not have a user-uploadable file type, but still belong in the checklist.
    private var extractedChecklistCard: some View {
        let values = state.requirements.filter { $0.effectiveNecessity != .informational }
        return SurfaceCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("모집요강에서 추출한 전체 체크리스트")
                            .font(.system(size: 15, weight: .bold))
                        Text("파일 업로드가 필요 없는 지원서·수수료 등도 함께 확인하세요.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(values.count)개")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GCTheme.brand)
                }
                .padding(20)

                Divider()

                ForEach(Array(values.enumerated()), id: \.element.id) { index, requirement in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: requirement.effectiveNecessity == .conditional ? "exclamationmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(requirement.effectiveNecessity == .conditional ? ReviewStatus.humanReview.color : GCTheme.brand)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(requirement.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(requirement.effectiveNecessity.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(requirement.effectiveNecessity == .conditional ? ReviewStatus.humanReview.color : ReviewStatus.ready.color)
                            }
                            Text(requirement.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(requirement.page.map { "\(requirement.sourceName) · p.\($0)" } ?? requirement.sourceName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(GCTheme.secondaryInk)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    if index < values.count - 1 { Divider().padding(.leading, 48) }
                }
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
                     ? "모집요강은 Upstage Studio Agent가 구조화하고, 지원자 서류는 제출 목록과 대조합니다. API 키는 이 Mac의 Keychain에만 저장됩니다."
                     : "모집요강 Agent를 실행하려면 새 지원 목표 단계에서 up_로 시작하는 Upstage API 키를 입력해 주세요.")
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
    let documents: [DocumentItem]
    let expectedCount: Int
    let replace: () -> Void
    let remove: (DocumentItem) -> Void
    let sampleRevision: (() -> Void)?
    let dropped: ([URL]) -> Void
    @State private var targeted = false

    private var document: DocumentItem? { documents.first }
    private var readyCount: Int { documents.filter { $0.processingStatus == .ready }.count }

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
                        Text(documents.prefix(2).map(\.filename).joined(separator: ", "))
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
                        if expectedCount > 1 {
                            Text("\(readyCount)/\(expectedCount)부")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(readyCount >= expectedCount ? ReviewStatus.ready.color : ReviewStatus.humanReview.color)
                        }
                    }
                } else {
                    Text(expectedCount > 1
                         ? "\(expectedCount)부를 추가하거나 이 행에 놓으세요"
                         : "파일을 추가하거나 이 행에 놓으세요")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if let document {
                processingStatus(readyCount >= expectedCount ? .ready : document.processingStatus)
                Menu {
                    Button(expectedCount > 1 ? "파일 추가" : "파일 교체", action: replace)
                    if let sampleRevision, document.isSample {
                        Button("수정본 샘플 적용", action: sampleRevision)
                    }
                    Divider()
                    ForEach(documents) { value in
                        Button("\(value.filename) 제거", role: .destructive) { remove(value) }
                    }
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
            dropped(expectedCount > 1 ? urls : Array(urls.prefix(1)))
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
