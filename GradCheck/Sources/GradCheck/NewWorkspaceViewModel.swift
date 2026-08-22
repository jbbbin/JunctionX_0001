import Foundation

@MainActor
final class NewWorkspaceViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case target
        case requirements
        case review

        var title: String {
            switch self {
            case .target: "지원 목표"
            case .requirements: "모집요강"
            case .review: "필요 서류"
            }
        }
    }

    @Published var step: Step = .target
    @Published var school = ""
    @Published var program = ""
    @Published var degree = "PhD"
    @Published var intake = "Fall 2027"
    @Published var applicantName = ""
    @Published private(set) var requirementURLs: [URL] = []
    @Published private(set) var analysis: RequirementAnalysisResult?
    @Published private(set) var isAnalyzing = false
    @Published var errorMessage: String?

    private let app: AppViewModel
    private var analysisTask: Task<Void, Never>?

    init(app: AppViewModel) {
        self.app = app
    }

    var canContinueTarget: Bool {
        let draft = draft.normalized
        return !draft.school.isEmpty && !draft.program.isEmpty && !draft.intake.isEmpty
    }

    var canAnalyze: Bool { !requirementURLs.isEmpty && !isAnalyzing }
    var canCreate: Bool { analysis?.requiredDocumentTypes.isEmpty == false && !isAnalyzing }
    var providerLabel: String { app.providerLabel }
    var isUpstageConnected: Bool { app.isUpstageConnected }

    var draft: WorkspaceDraft {
        WorkspaceDraft(
            school: school,
            program: program,
            degree: degree,
            intake: intake,
            applicantName: applicantName
        )
    }

    func continueFromTarget() {
        guard canContinueTarget else {
            errorMessage = WorkspaceFlowError.targetMissing.localizedDescription
            return
        }
        step = .requirements
    }

    func setRequirementURLs(_ urls: [URL]) {
        var seen = Set<String>()
        requirementURLs = urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
        analysis = nil
    }

    func removeRequirementURL(_ url: URL) {
        requirementURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        analysis = nil
    }

    func analyze() {
        guard canAnalyze else { return }
        analysisTask?.cancel()
        errorMessage = nil
        isAnalyzing = true
        let urls = requirementURLs
        analysisTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isAnalyzing = false
                self.analysisTask = nil
            }
            do {
                self.analysis = try await self.app.analyzeRequirements(urls)
                self.step = .review
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func createWorkspace() {
        guard let analysis, canCreate else {
            errorMessage = WorkspaceFlowError.noApplicantDocuments.localizedDescription
            return
        }
        app.addWorkspace(draft: draft, analysis: analysis)
    }

    func loadDemo() {
        app.loadDemo()
    }
}
