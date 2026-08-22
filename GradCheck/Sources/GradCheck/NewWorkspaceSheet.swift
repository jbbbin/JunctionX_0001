import SwiftUI
import UniformTypeIdentifiers

struct NewWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: NewWorkspaceViewModel
    @State private var showImporter = false

    init(appViewModel: AppViewModel) {
        _model = StateObject(wrappedValue: NewWorkspaceViewModel(app: appViewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepIndicator
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 720, height: 650)
        .background(GCTheme.canvas)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf, .plainText, .rtf, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): model.setRequirementURLs(urls)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .alert(
            "확인해 주세요",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("새 지원서 추가")
                    .font(.system(size: 23, weight: .bold))
                Text("학교마다 다른 모집요강을 먼저 읽고, 필요한 제출 서류를 지원서별로 구성합니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(26)
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(NewWorkspaceViewModel.Step.allCases.enumerated()), id: \.element.rawValue) { index, step in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(step.rawValue <= model.step.rawValue ? .white : .secondary)
                        .frame(width: 22, height: 22)
                        .background(step.rawValue <= model.step.rawValue ? GCTheme.brand : Color.black.opacity(0.06))
                        .clipShape(Circle())
                    Text(step.title)
                        .font(.system(size: 12, weight: model.step == step ? .bold : .medium))
                        .foregroundStyle(model.step == step ? GCTheme.ink : .secondary)
                }
                if index < NewWorkspaceViewModel.Step.allCases.count - 1 {
                    Rectangle()
                        .fill(step.rawValue < model.step.rawValue ? GCTheme.brand.opacity(0.5) : Color.black.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .target:
            targetStep
        case .requirements:
            requirementsStep
        case .review:
            reviewStep
        }
    }

    private var targetStep: some View {
        Form {
            Section("지원 대상") {
                TextField("학교명", text: $model.school, prompt: Text("예: MIT"))
                TextField("프로그램명", text: $model.program, prompt: Text("예: Electrical Engineering & Computer Science"))
                Picker("학위 과정", selection: $model.degree) {
                    ForEach(["PhD", "MS", "MA", "MEng", "MBA"], id: \.self) { Text($0).tag($0) }
                }
                TextField("입학 학기", text: $model.intake, prompt: Text("예: Fall 2027"))
            }
            Section("지원자") {
                TextField("지원자 영문 이름 (선택)", text: $model.applicantName, prompt: Text("여권 기준 영문 이름"))
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }

    private var requirementsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(GCTheme.brand)
                    .frame(width: 46, height: 46)
                    .background(GCTheme.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text("공식 모집요강을 추가하세요")
                        .font(.system(size: 16, weight: .bold))
                    Text("대학원 공통 안내와 학과·프로그램 안내를 함께 넣을 수 있습니다. 각 파일의 출처와 페이지를 유지해 요건을 구조화합니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Label("파일 선택", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(GCTheme.brand)
                .disabled(model.isAnalyzing)
            }

            SurfaceCard(padding: 0) {
                if model.requirementURLs.isEmpty {
                    EmptyStateView(
                        symbol: "doc.text.magnifyingglass",
                        title: "아직 모집요강이 없어요",
                        message: "PDF, 이미지, TXT, RTF 파일을 여러 개 선택할 수 있습니다.",
                        actionTitle: "모집요강 선택",
                        action: { showImporter = true }
                    )
                    .padding(24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.requirementURLs.enumerated()), id: \.element) { index, url in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(GCTheme.brand)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(index == 0 ? "공식 출처 문서" : "추가 공식 출처")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    model.removeRequirementURL(url)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            if index < model.requirementURLs.count - 1 { Divider().padding(.leading, 48) }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: model.isUpstageConnected ? "network.badge.shield.half.filled" : "lock.macwindow")
                    .foregroundStyle(GCTheme.brand)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.providerLabel)
                        .font(.system(size: 11, weight: .semibold))
                    Text(model.isUpstageConnected
                         ? "Upstage 모델로 문서 구조를 분석합니다. 모델명과 엔드포인트는 환경 설정으로 교체할 수 있습니다."
                         : "현재는 이 Mac의 텍스트 추출을 사용합니다. UPSTAGE_API_KEY를 설정하면 이미지·PDF 분석이 확장됩니다.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(28)
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let analysis = model.analysis {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("모집요강 분석 완료")
                                .font(.system(size: 16, weight: .bold))
                            Text("아래 서류 구성을 새 지원서에 적용합니다. 조건부 항목은 이후 검수에서 직접 확인으로 남습니다.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(analysis.requiredDocumentTypes.count)개 유형")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GCTheme.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(GCTheme.brandSoft)
                            .clipShape(Capsule())
                    }

                    SurfaceCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(analysis.requiredDocumentTypes.enumerated()), id: \.element) { index, type in
                                let related = analysis.requirements.filter {
                                    $0.relatedDocumentType == type && $0.effectiveNecessity != .informational
                                }
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: type.symbol)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(GCTheme.brand)
                                        .frame(width: 36, height: 36)
                                        .background(GCTheme.brandSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 8) {
                                            Text(type.title)
                                                .font(.system(size: 12, weight: .semibold))
                                            if let count = related.compactMap(\.requiredCount).max(), count > 1 {
                                                Text("\(count)부")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(GCTheme.brand)
                                            }
                                        }
                                        Text(related.map(\.detail).joined(separator: " · "))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        Text(related.first.map { requirement in
                                            requirement.page.map { "\(requirement.sourceName) · p.\($0)" }
                                                ?? requirement.sourceName
                                        } ?? "공식 모집요강")
                                            .font(.system(size: 9))
                                            .foregroundStyle(GCTheme.secondaryInk)
                                    }
                                    Spacer()
                                    let needsReview = related.contains { $0.effectiveNecessity == .conditional }
                                    Text(needsReview ? "조건부" : "필수")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(needsReview ? ReviewStatus.humanReview.color : ReviewStatus.ready.color)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                if index < analysis.requiredDocumentTypes.count - 1 { Divider().padding(.leading, 66) }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var footer: some View {
        HStack {
            Button("샘플 지원서 사용") {
                model.loadDemo()
                dismiss()
            }
            .buttonStyle(.bordered)
            Spacer()
            if model.step != .target {
                Button("이전") {
                    if model.step == .review { model.step = .requirements }
                    else { model.step = .target }
                }
                .buttonStyle(.bordered)
                .disabled(model.isAnalyzing)
            }
            Button("취소") { dismiss() }
                .buttonStyle(.bordered)
                .disabled(model.isAnalyzing)
            primaryAction
        }
        .padding(22)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.step {
        case .target:
            Button("모집요강 추가") { model.continueFromTarget() }
                .buttonStyle(.borderedProminent)
                .tint(GCTheme.brand)
                .disabled(!model.canContinueTarget)
        case .requirements:
            Button {
                model.analyze()
            } label: {
                if model.isAnalyzing {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("모집요강 분석 중")
                    }
                } else {
                    Label("필요 서류 확인", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(GCTheme.brand)
            .disabled(!model.canAnalyze)
        case .review:
            Button("지원서 만들기") {
                model.createWorkspace()
            }
            .buttonStyle(.borderedProminent)
            .tint(GCTheme.brand)
            .disabled(!model.canCreate)
        }
    }
}
