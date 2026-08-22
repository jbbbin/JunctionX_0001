import SwiftUI
import UniformTypeIdentifiers

struct AddApplicationView: View {
    enum AnalysisPhase: Int, CaseIterable {
        case waiting
        case uploading
        case classifying
        case extracting
        case matching
        case completed
        case failed

        var title: String {
            switch self {
            case .waiting: "모집요강을 선택해 주세요"
            case .uploading: "문서를 안전하게 업로드 중"
            case .classifying: "지원 분야를 분류하는 중"
            case .extracting: "조건과 제출 서류를 읽는 중"
            case .matching: "내 프로필·문서와 대조하는 중"
            case .completed: "워크스페이스 준비 완료"
            case .failed: "분석을 완료하지 못했어요"
            }
        }

        var subtitle: String {
            switch self {
            case .waiting: "모집요강 한 번만 올리면 나머지는 자동으로 진행돼요."
            case .uploading: "Firebase Storage에 원본을 저장하고 있어요."
            case .classifying: "채용·장학금·공모전 중 알맞은 분야를 찾고 있어요."
            case .extracting: "Upstage Studio가 마감일과 요구사항을 구조화하고 있어요."
            case .matching: "이미 가진 문서와 새로 준비할 항목을 나누고 있어요."
            case .completed: "결과 화면으로 바로 이동할게요."
            case .failed: "파일을 확인한 뒤 한 번만 다시 시도해 주세요."
            }
        }

        var progress: Double {
            switch self {
            case .waiting: 0
            case .uploading: 0.18
            case .classifying: 0.38
            case .extracting: 0.66
            case .matching: 0.86
            case .completed: 1
            case .failed: 0
            }
        }
    }

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingImporter = false
    @State private var selectedFilename: String?
    @State private var phase: AnalysisPhase = .waiting
    @State private var analysisTask: Task<Void, Never>?

    let onCompleted: (UUID) -> Void

    init(
        initialFilename: String? = nil,
        onCompleted: @escaping (UUID) -> Void
    ) {
        _selectedFilename = State(initialValue: initialFilename)
        _phase = State(initialValue: initialFilename == nil ? .waiting : .uploading)
        self.onCompleted = onCompleted
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 24) {
                if let selectedFilename {
                    analysisContent(filename: selectedFilename)
                } else {
                    uploadContent
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 590)
        .background(Color.awCanvas)
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            selectedFilename = url.lastPathComponent
            beginAnalysis()
        }
        .onAppear {
            if selectedFilename != nil, phase == .uploading, analysisTask == nil {
                beginAnalysis()
            }
        }
        .onDisappear {
            analysisTask?.cancel()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("새 공고 추가")
                    .font(.title2.weight(.bold))
                Text("복잡한 설정 없이 모집요강만 선택하세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.06), in: Circle())
        }
        .padding(22)
    }

    private var uploadContent: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.awAccentSoft)
                    .frame(width: 108, height: 108)
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.awAccent)
            }

            VStack(spacing: 8) {
                Text(phase.title)
                    .font(.title3.weight(.bold))
                Text(phase.subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                isShowingImporter = true
            } label: {
                Label("모집요강 파일 선택", systemImage: "folder")
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 18) {
                Label("채용", systemImage: ApplicationCategory.employment.icon)
                Label("장학금", systemImage: ApplicationCategory.scholarship.icon)
                Label("공모전·대회", systemImage: ApplicationCategory.competition.icon)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func analysisContent(filename: String) -> some View {
        VStack(spacing: 24) {
            SectionCard {
                HStack(spacing: 14) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.title2)
                        .foregroundStyle(Color.awAccent)
                        .frame(width: 44, height: 44)
                        .background(Color.awAccent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(filename)
                            .font(.headline)
                            .lineLimit(1)
                        Text("모집요강 파일")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if phase != .completed {
                        Button("변경") {
                            isShowingImporter = true
                        }
                        .buttonStyle(.borderless)
                        Button {
                            removeFile()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("선택한 파일 제거")
                    }
                }
            }

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: phase.progress)
                        .stroke(Color.awAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.35), value: phase.progress)
                    Image(systemName: phase == .completed ? "checkmark" : "sparkles")
                        .font(.title.weight(.bold))
                        .foregroundStyle(phase == .completed ? .green : Color.awAccent)
                }
                .frame(width: 94, height: 94)

                Text(phase.title)
                    .font(.title3.weight(.bold))
                Text(phase.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            progressSteps

            if phase == .failed {
                Button("다시 시도") {
                    beginAnalysis()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private var progressSteps: some View {
        HStack(spacing: 0) {
            phaseStep("업로드", threshold: .uploading)
            connector(threshold: .classifying)
            phaseStep("분류", threshold: .classifying)
            connector(threshold: .extracting)
            phaseStep("정보 추출", threshold: .extracting)
            connector(threshold: .matching)
            phaseStep("문서 매칭", threshold: .matching)
        }
        .frame(maxWidth: 470)
    }

    private func phaseStep(_ title: String, threshold: AnalysisPhase) -> some View {
        let isReached = phase.rawValue >= threshold.rawValue && phase != .failed
        return VStack(spacing: 7) {
            Image(systemName: isReached ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReached ? Color.awAccent : Color.secondary.opacity(0.45))
            Text(title)
                .font(.caption2)
                .foregroundStyle(isReached ? .primary : .secondary)
        }
    }

    private func connector(threshold: AnalysisPhase) -> some View {
        Rectangle()
            .fill(phase.rawValue >= threshold.rawValue ? Color.awAccent : Color.primary.opacity(0.10))
            .frame(height: 2)
            .offset(y: -9)
    }

    private func beginAnalysis() {
        analysisTask?.cancel()
        phase = .uploading
        analysisTask = Task { @MainActor in
            let sequence: [(AnalysisPhase, UInt64)] = [
                (.classifying, 650_000_000),
                (.extracting, 720_000_000),
                (.matching, 800_000_000),
                (.completed, 760_000_000)
            ]

            for (nextPhase, delay) in sequence {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                phase = nextPhase
            }

            guard let selectedFilename, !Task.isCancelled else { return }
            let applicationID = store.addImportedApplication(filename: selectedFilename)
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            onCompleted(applicationID)
        }
    }

    private func removeFile() {
        analysisTask?.cancel()
        analysisTask = nil
        selectedFilename = nil
        phase = .waiting
    }
}
