import Combine
import Foundation

@MainActor
final class DashboardViewModel: StoreBackedViewModel {
    @Published var searchText = ""
    @Published var statusFilter: DashboardStatusFilter = .all
    @Published var showsAllApplications = false

    private let now: () -> Date
    private let calendar: Calendar

    init(
        store: AppStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.now = now
        self.calendar = calendar
        super.init(store: store)
    }

    var userName: String { store.profile.name }
    var avatarInitial: String { store.profile.avatarInitial }

    var nearestApplication: ApplicationItem? {
        store.applications
            .filter {
                guard let daysRemaining = daysRemaining(for: $0) else { return false }
                return !$0.isCompleted && daysRemaining >= 0
            }
            .min(by: deadlineComesBefore)
    }

    var eligibleCount: Int {
        store.applications.filter { !$0.isCompleted && $0.eligibility == .eligible }.count
    }

    var reviewCount: Int {
        store.applications.filter { !$0.isCompleted && $0.eligibility == .needsReview }.count
    }

    var filteredApplications: [ApplicationItem] {
        store.applications
            .filter { application in
                matchesStatus(application) && matchesSearch(application)
            }
            .sorted(by: deadlineComesBefore)
    }

    var visibleApplications: [ApplicationItem] {
        showsAllApplications ? filteredApplications : Array(filteredApplications.prefix(4))
    }

    var sectionTitle: String {
        switch statusFilter {
        case .all, .preparing: showsAllApplications ? "전체 지원" : "진행 중인 지원"
        case .urgent: "마감 임박 지원"
        case .needsReview: "확인이 필요한 지원"
        case .completed: "완료된 지원"
        }
    }

    func configure(for route: SidebarRoute) {
        switch route {
        case .dashboard:
            statusFilter = .all
            showsAllApplications = false
            searchText = ""
        case .applications:
            statusFilter = .all
            showsAllApplications = true
        case .archive:
            statusFilter = .completed
            showsAllApplications = true
        case .urgent:
            statusFilter = .urgent
            showsAllApplications = true
        case .needsReview:
            statusFilter = .needsReview
            showsAllApplications = true
        case .profile, .documents, .application:
            break
        }
    }

    func showAll() {
        statusFilter = .all
        showsAllApplications = true
        searchText = ""
    }

    func clearSearch() {
        searchText = ""
    }

    func isSupportedImport(_ url: URL) -> Bool {
        [
            "pdf", "png", "jpg", "jpeg", "heic", "bmp", "gif", "webp", "tif", "tiff",
            "docx", "pptx", "xlsx", "hwp", "hwpx",
        ].contains(url.pathExtension.lowercased())
    }

    func compactEligibility(_ state: EligibilityState) -> String {
        switch state {
        case .eligible: "지원 적격"
        case .needsReview: "확인 필요"
        case .difficult: "지원 어려움"
        }
    }

    func formattedShortDate(_ date: Date?) -> String {
        guard let date else { return "확인 필요" }
        return Self.shortDateFormatter.string(from: date)
    }

    func formattedDeadline(_ date: Date?) -> String {
        guard let date else { return "마감 확인 필요" }
        return Self.deadlineFormatter.string(from: date)
    }

    private func matchesStatus(_ application: ApplicationItem) -> Bool {
        switch statusFilter {
        case .all, .preparing:
            return !application.isCompleted
        case .urgent:
            guard let daysRemaining = daysRemaining(for: application) else { return false }
            return !application.isCompleted && (0...7).contains(daysRemaining)
        case .needsReview:
            return !application.isCompleted && application.eligibility == .needsReview
        case .completed:
            return application.isCompleted
        }
    }

    private func matchesSearch(_ application: ApplicationItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty
            || application.title.localizedCaseInsensitiveContains(query)
            || application.organization.localizedCaseInsensitiveContains(query)
            || application.category.rawValue.localizedCaseInsensitiveContains(query)
    }

    private func daysRemaining(for application: ApplicationItem) -> Int? {
        application.daysRemaining(relativeTo: now(), calendar: calendar)
    }

    private func deadlineComesBefore(_ lhs: ApplicationItem, _ rhs: ApplicationItem) -> Bool {
        switch (lhs.deadline, rhs.deadline) {
        case let (lhsDeadline?, rhsDeadline?):
            if lhsDeadline != rhsDeadline { return lhsDeadline < rhsDeadline }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()

    private static let deadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter
    }()
}
