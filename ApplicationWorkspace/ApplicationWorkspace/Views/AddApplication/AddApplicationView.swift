import SwiftUI
import UniformTypeIdentifiers

struct AddApplicationView: View {
    private typealias AnalysisPhase = AddApplicationViewModel.AnalysisPhase

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AddApplicationViewModel

    let onCompleted: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 24) {
                if let sourceDisplayName = viewModel.sourceDisplayName {
                    analysisContent(sourceDisplayName: sourceDisplayName)
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
            isPresented: $viewModel.isShowingImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false,
            onCompletion: viewModel.handleFileImport
        )
        .onAppear {
            viewModel.startIfNeeded()
        }
        .onDisappear {
            viewModel.cancel()
        }
        .onChange(of: viewModel.completedApplicationID) { _, applicationID in
            guard let applicationID else { return }
            onCompleted(applicationID)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("새 공고 추가")
                    .font(.title2.weight(.bold))
                Text("파일이나 공고 주소 하나만 입력하면 자동으로 정리해 드려요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.cancel()
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
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Color.awAccentSoft)
                    .frame(width: 92, height: 92)
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Color.awAccent)
            }

            VStack(spacing: 7) {
                Text(viewModel.phase.title)
                    .font(.title3.weight(.bold))
                Text(viewModel.phase.subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.isShowingImporter = true
            } label: {
                Label("모집요강 파일 선택", systemImage: "folder")
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.awBorder)
                    .frame(height: 1)
                Text("또는 공고 URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle()
                    .fill(Color.awBorder)
                    .frame(height: 1)
            }
            .frame(maxWidth: 460)

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://example.com/recruit", text: $viewModel.urlDraft)
                        .textFieldStyle(.plain)
                        .onSubmit(viewModel.analyzeURL)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.awBorder, lineWidth: 1)
                )

                Button("분석하기", action: viewModel.analyzeURL)
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(viewModel.urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 460)

            if let errorMessage = viewModel.errorMessage {
                errorCallout(errorMessage) {
                    viewModel.analyzeURL()
                }
            }

            HStack(spacing: 18) {
                Label("채용", systemImage: ApplicationCategory.employment.icon)
                Label("장학금", systemImage: ApplicationCategory.scholarship.icon)
                Label("공모전·대회", systemImage: ApplicationCategory.competition.icon)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func analysisContent(sourceDisplayName: String) -> some View {
        VStack(spacing: 24) {
            SectionCard {
                HStack(spacing: 14) {
                    Image(systemName: sourceIcon)
                        .font(.title2)
                        .foregroundStyle(Color.awAccent)
                        .frame(width: 44, height: 44)
                        .background(Color.awAccent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sourceDisplayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(sourceKindTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.phase != .completed {
                        Button("변경") {
                            changeSource()
                        }
                        .buttonStyle(.borderless)
                        Button {
                            viewModel.removeSource()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("선택한 원본 제거")
                    }
                }
            }

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: viewModel.phase.progress)
                        .stroke(Color.awAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.35), value: viewModel.phase.progress)
                    Image(systemName: phaseIcon)
                        .font(.title.weight(.bold))
                        .foregroundStyle(phaseTint)
                }
                .frame(width: 94, height: 94)

                Text(viewModel.phase.title)
                    .font(.title3.weight(.bold))
                Text(viewModel.phase.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            progressSteps

            if let errorMessage = viewModel.errorMessage {
                errorCallout(errorMessage) {
                    viewModel.beginAnalysis()
                }
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
        let isReached = viewModel.phase.rawValue >= threshold.rawValue && viewModel.phase != .failed
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
            .fill(
                viewModel.phase.rawValue >= threshold.rawValue && viewModel.phase != .failed
                    ? Color.awAccent
                    : Color.primary.opacity(0.10)
            )
            .frame(height: 2)
            .offset(y: -9)
    }

    private func errorCallout(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("다시 시도", action: retry)
                .buttonStyle(.borderless)
                .foregroundStyle(Color.awAccent)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: 460, minHeight: 42)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var sourceIcon: String {
        switch viewModel.source {
        case .some(.file): "doc.richtext.fill"
        case .some(.web): "globe"
        case .none: "doc.badge.plus"
        }
    }

    private var sourceKindTitle: String {
        switch viewModel.source {
        case .some(.file): "모집요강 파일"
        case .some(.web): "공고 웹페이지"
        case .none: "공고 원본"
        }
    }

    private var phaseIcon: String {
        switch viewModel.phase {
        case .completed: "checkmark"
        case .failed: "exclamationmark"
        case .waiting, .uploading, .classifying, .extracting, .matching: "sparkles"
        }
    }

    private var phaseTint: Color {
        switch viewModel.phase {
        case .completed: .green
        case .failed: .orange
        case .waiting, .uploading, .classifying, .extracting, .matching: .awAccent
        }
    }

    private func changeSource() {
        switch viewModel.source {
        case .some(.file):
            viewModel.isShowingImporter = true
        case .some(.web), .none:
            viewModel.removeSource()
        }
    }
}
