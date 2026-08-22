import Combine
import Foundation

@MainActor
final class AddApplicationViewModel: ObservableObject {
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
            case .uploading: "원문을 안전하게 준비하는 중"
            case .classifying: "지원 분야를 분류하는 중"
            case .extracting: "조건과 제출 서류를 읽는 중"
            case .matching: "내 프로필·문서와 대조하는 중"
            case .completed: "워크스페이스 준비 완료"
            case .failed: "분석을 완료하지 못했어요"
            }
        }

        var subtitle: String {
            switch self {
            case .waiting: "파일 또는 공고 URL 한 번이면 나머지는 자동으로 진행돼요."
            case .uploading: "Firebase Storage 연동 전까지 원본 참조를 세션에 안전하게 유지해요."
            case .classifying: "채용·장학금·공모전 중 알맞은 분야를 찾고 있어요."
            case .extracting: "Upstage Studio 연결 지점에서 마감일과 요구사항을 구조화해요."
            case .matching: "이미 가진 문서와 새로 준비할 항목을 나누고 있어요."
            case .completed: "결과 화면으로 바로 이동할게요."
            case .failed: "원본을 확인한 뒤 다시 시도해 주세요."
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

    @Published var source: ImportedSource?
    @Published var urlDraft = ""
    @Published var phase: AnalysisPhase = .waiting
    @Published var errorMessage: String?
    @Published var isShowingImporter = false
    @Published private(set) var completedApplicationID: UUID?

    private let store: AppStore
    private let analyzer: any ApplicationAnalyzing
    private let addressResolver: BrowserAddressResolver
    private var analysisTask: Task<Void, Never>?

    init(
        source: ImportedSource? = nil,
        store: AppStore,
        analyzer: any ApplicationAnalyzing,
        addressResolver: BrowserAddressResolver = BrowserAddressResolver()
    ) {
        self.source = source
        self.store = store
        self.analyzer = analyzer
        self.addressResolver = addressResolver
        phase = source == nil ? .waiting : .uploading
    }

    var sourceDisplayName: String? { source?.displayName }
    var isAnalyzing: Bool { ![.waiting, .completed, .failed].contains(phase) }

    func startIfNeeded() {
        guard source != nil, analysisTask == nil, completedApplicationID == nil else { return }
        beginAnalysis()
    }

    func selectFile(_ url: URL) {
        source = .file(url)
        beginAnalysis()
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            selectFile(url)
        case let .failure(error):
            let nsError = error as NSError
            guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) else {
                return
            }
            errorMessage = "파일을 불러오지 못했어요. 다시 선택해 주세요."
            phase = .failed
        }
    }

    func analyzeURL() {
        guard let url = addressResolver.resolveWebAddress(urlDraft),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            errorMessage = "올바른 http 또는 https 공고 주소를 입력해 주세요."
            phase = .failed
            return
        }

        source = .web(url)
        urlDraft = url.absoluteString
        beginAnalysis()
    }

    func beginAnalysis() {
        guard let source else { return }
        analysisTask?.cancel()
        errorMessage = nil
        completedApplicationID = nil
        phase = .uploading

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                for (nextPhase, delay) in Self.phaseSequence {
                    try await Task.sleep(nanoseconds: delay)
                    try Task.checkCancellation()
                    phase = nextPhase
                }

                let application = try await analyzer.analyze(source: source)
                try Task.checkCancellation()
                phase = .completed
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                completedApplicationID = store.addApplication(application)
                analysisTask = nil
            } catch is CancellationError {
                analysisTask = nil
            } catch {
                errorMessage = error.localizedDescription
                phase = .failed
                analysisTask = nil
            }
        }
    }

    func removeSource() {
        cancel()
        source = nil
        urlDraft = ""
        errorMessage = nil
        completedApplicationID = nil
        phase = .waiting
    }

    func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    private static let phaseSequence: [(AnalysisPhase, UInt64)] = [
        (.classifying, 350_000_000),
        (.extracting, 420_000_000),
        (.matching, 480_000_000)
    ]
}
