import Combine
import Foundation

@MainActor
final class AddApplicationViewModel: ObservableObject {
    enum AnalysisPhase: Int, CaseIterable {
        case waiting
        case setupRequired
        case uploading
        case classifying
        case extracting
        case matching
        case completed
        case failed

        var title: String {
            switch self {
            case .waiting: "모집요강을 선택해 주세요"
            case .setupRequired: "Upstage API 연결이 필요해요"
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
            case .setupRequired: "API 키를 이 Mac에 한 번만 저장하면 바로 분석을 시작할 수 있어요."
            case .uploading: "선택한 원문을 Upstage 분석에 맞게 준비하고 있어요."
            case .classifying: "채용·장학금·공모전 중 알맞은 분야를 찾고 있어요."
            case .extracting: "Upstage가 마감일·자격 조건·제출 서류를 구조화하고 있어요."
            case .matching: "이미 가진 문서와 새로 준비할 항목을 나누고 있어요."
            case .completed: "결과 화면으로 바로 이동할게요."
            case .failed: "원본을 확인한 뒤 다시 시도해 주세요."
            }
        }

        var progress: Double {
            switch self {
            case .waiting, .setupRequired: 0
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
    @Published var apiKeyDraft = ""
    @Published var isEditingAPIKey = false
    @Published private(set) var isAPIKeyConfigured: Bool
    @Published private(set) var apiKeyMessage: String?
    @Published private(set) var completedApplicationID: UUID?

    private let store: AppStore
    private let analyzer: any ApplicationAnalyzing
    private let addressResolver: BrowserAddressResolver
    private let credentialStore: (any UpstageAPIKeyStoring)?
    private var analysisTask: Task<Void, Never>?
    private var analysisGeneration: UUID?

    init(
        source: ImportedSource? = nil,
        store: AppStore,
        analyzer: any ApplicationAnalyzing,
        credentialStore: (any UpstageAPIKeyStoring)? = nil,
        addressResolver: BrowserAddressResolver = BrowserAddressResolver()
    ) {
        self.source = source
        self.store = store
        self.analyzer = analyzer
        self.credentialStore = credentialStore
        self.addressResolver = addressResolver
        let isConfigured = credentialStore?.hasAPIKey ?? true
        isAPIKeyConfigured = isConfigured
        isEditingAPIKey = credentialStore != nil && !isConfigured
        phase = isConfigured ? (source == nil ? .waiting : .uploading) : .setupRequired
    }

    var sourceDisplayName: String? { source?.displayName }
    var isAnalyzing: Bool { ![.waiting, .setupRequired, .completed, .failed].contains(phase) }
    var showsLocalAPIKeySettings: Bool { credentialStore != nil }
    var requiresAPIKeySetup: Bool { showsLocalAPIKeySettings && !isAPIKeyConfigured }
    var isAPIKeyManagedByEnvironment: Bool {
        guard let credentialStore else { return false }
        if case .environment = credentialStore.activeSource { return true }
        return false
    }

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
        analysisTask = nil
        analysisGeneration = nil
        errorMessage = nil
        completedApplicationID = nil

        guard credentialStore?.hasAPIKey ?? true else {
            isAPIKeyConfigured = false
            isEditingAPIKey = true
            phase = .setupRequired
            return
        }

        isAPIKeyConfigured = true
        phase = .uploading
        let generation = UUID()
        analysisGeneration = generation

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                for (nextPhase, delay) in Self.phaseSequence {
                    try await Task.sleep(nanoseconds: delay)
                    try Task.checkCancellation()
                    guard analysisGeneration == generation else { return }
                    phase = nextPhase
                }

                let context = ApplicationAnalysisContext(
                    profile: store.profile,
                    ownedDocuments: store.ownedDocuments
                )
                let application = try await analyzer.analyze(
                    source: source,
                    context: context
                )
                try Task.checkCancellation()
                guard analysisGeneration == generation else { return }
                phase = .matching
                try await Task.sleep(nanoseconds: 160_000_000)
                try Task.checkCancellation()
                guard analysisGeneration == generation else { return }
                let applicationID = store.addApplication(application)
                phase = .completed
                completedApplicationID = applicationID
                analysisTask = nil
                analysisGeneration = nil
            } catch is CancellationError {
                guard analysisGeneration == generation else { return }
                analysisTask = nil
                analysisGeneration = nil
            } catch {
                guard analysisGeneration == generation else { return }
                errorMessage = error.localizedDescription
                if isCredentialError(error) {
                    let isEnvironmentManaged = isAPIKeyManagedByEnvironment
                    isAPIKeyConfigured = isEnvironmentManaged
                    isEditingAPIKey = !isEnvironmentManaged
                    apiKeyMessage = isEnvironmentManaged
                        ? "Xcode Scheme의 UPSTAGE_API_KEY 값을 교체한 뒤 앱을 다시 실행해 주세요."
                        : nil
                    phase = .setupRequired
                } else {
                    phase = .failed
                }
                analysisTask = nil
                analysisGeneration = nil
            }
        }
    }

    func removeSource() {
        cancel()
        source = nil
        urlDraft = ""
        errorMessage = nil
        completedApplicationID = nil
        phase = requiresAPIKeySetup ? .setupRequired : .waiting
    }

    func editAPIKey() {
        apiKeyMessage = nil
        isEditingAPIKey = true
    }

    func cancelAPIKeyEditing() {
        apiKeyDraft = ""
        apiKeyMessage = nil
        isEditingAPIKey = !isAPIKeyConfigured
    }

    func saveAPIKey() {
        guard let credentialStore else { return }
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            apiKeyMessage = "API 키를 입력해 주세요."
            return
        }

        do {
            try credentialStore.saveAPIKey(key)
            apiKeyDraft = ""
            apiKeyMessage = nil
            isAPIKeyConfigured = credentialStore.hasAPIKey
            isEditingAPIKey = !isAPIKeyConfigured

            if source != nil {
                beginAnalysis()
            } else {
                phase = .waiting
            }
        } catch {
            apiKeyMessage = error.localizedDescription
        }
    }

    func cancel() {
        analysisGeneration = nil
        analysisTask?.cancel()
        analysisTask = nil
    }

    private func isCredentialError(_ error: Error) -> Bool {
        guard let error = error as? UpstageAPIError else { return false }
        return switch error {
        case .missingAPIKey, .invalidAPIKey: true
        default: false
        }
    }

    private static let phaseSequence: [(AnalysisPhase, UInt64)] = [
        (.classifying, 120_000_000),
        (.extracting, 100_000_000)
    ]
}
