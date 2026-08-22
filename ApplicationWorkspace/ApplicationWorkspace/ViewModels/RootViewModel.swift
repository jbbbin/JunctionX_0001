import Combine
import Foundation

enum SidebarRoute: Hashable {
    case dashboard
    case applications
    case profile
    case documents
    case archive
    case urgent
    case needsReview
    case application(UUID)
}

@MainActor
final class RootViewModel: StoreBackedViewModel {
    @Published private(set) var route: SidebarRoute = .dashboard
    @Published var isPresentingAddApplication = false
    @Published private(set) var addApplicationViewModel: AddApplicationViewModel?

    let dashboardViewModel: DashboardViewModel
    let documentsViewModel: DocumentsViewModel
    let profileViewModel: ProfileViewModel

    private let dependencies: AppDependencies
    private var workspaceViewModels: [UUID: ApplicationWorkspaceViewModel] = [:]

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        dashboardViewModel = DashboardViewModel(store: dependencies.store)
        documentsViewModel = DocumentsViewModel(
            store: dependencies.store,
            externalURLOpener: dependencies.externalURLOpener
        )
        profileViewModel = ProfileViewModel(store: dependencies.store)
        super.init(store: dependencies.store)
    }

    var selectedApplication: ApplicationItem? {
        guard case let .application(id) = route else { return nil }
        return store.application(id: id)
    }

    var routeTitle: String {
        switch route {
        case .dashboard, .applications: "지원 현황"
        case .documents: "문서 보관함"
        case .profile: "내 프로필"
        case .archive: "완료된 지원"
        case .urgent: "마감 임박"
        case .needsReview: "확인 필요"
        case let .application(id): store.application(id: id)?.title ?? "지원 상세"
        }
    }

    var activeApplications: [ApplicationItem] {
        store.applications.filter { !$0.isCompleted }
    }

    var completedApplications: [ApplicationItem] {
        store.applications.filter(\.isCompleted)
    }

    func navigate(to route: SidebarRoute) {
        self.route = route
        dashboardViewModel.configure(for: route)
    }

    func showAllApplications() {
        dashboardViewModel.showAll()
        route = .applications
    }

    func presentAddApplication(source: ImportedSource? = nil) {
        addApplicationViewModel?.cancel()
        addApplicationViewModel = AddApplicationViewModel(
            source: source,
            store: store,
            analyzer: dependencies.applicationAnalyzer,
            credentialStore: dependencies.localAnalysisCredentialStore
        )
        isPresentingAddApplication = true
    }

    func dismissAddApplication() {
        addApplicationViewModel?.cancel()
        addApplicationViewModel = nil
        isPresentingAddApplication = false
    }

    func completeAddApplication(_ applicationID: UUID) {
        addApplicationViewModel = nil
        isPresentingAddApplication = false
        navigate(to: .application(applicationID))
    }

    func workspaceViewModel(for applicationID: UUID) -> ApplicationWorkspaceViewModel {
        if let cached = workspaceViewModels[applicationID] {
            return cached
        }

        let viewModel = ApplicationWorkspaceViewModel(
            applicationID: applicationID,
            store: store,
            externalURLOpener: dependencies.externalURLOpener,
            calendarExporter: dependencies.calendarExporter
        )
        workspaceViewModels[applicationID] = viewModel
        return viewModel
    }

    func toggleCompletion(of application: ApplicationItem) {
        store.toggleCompletion(applicationID: application.id)
    }

    func openExternalSource(of application: ApplicationItem) {
        guard let url = application.applicationURL else { return }
        _ = dependencies.externalURLOpener.open(url)
    }
}
