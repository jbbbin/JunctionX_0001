import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isPresentingAddApplication = false
    @State private var pendingImportFilename: String?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 246)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.awCanvas)
            }
        }
        .background(Color.awCanvas)
        .sheet(isPresented: $isPresentingAddApplication) {
            AddApplicationView(initialFilename: pendingImportFilename) { applicationID in
                pendingImportFilename = nil
                isPresentingAddApplication = false
                store.route = .application(applicationID)
            }
            .environmentObject(store)
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Text(routeTitle)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("지원 검색", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .onSubmit {
                        store.route = .applications
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(width: 220, height: 38)
            .background(Color.awCanvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.awBorder.opacity(0.65), lineWidth: 1)
            )

            Button {
                presentAddApplication()
            } label: {
                Label("새 지원", systemImage: "plus")
                    .frame(minWidth: 126)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.leading, 146)
        .padding(.trailing, 28)
        .frame(height: 72)
        .background(Color.white)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PassReady")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("지원 준비 워크스페이스")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 38)
            .padding(.bottom, 32)

            VStack(spacing: 6) {
                sidebarButton("대시보드", icon: "square.grid.2x2.fill", route: .dashboard)
                sidebarButton("지원 현황", icon: "rectangle.stack", route: .applications)
                sidebarButton("문서 보관함", icon: "folder", route: .documents)
                sidebarButton("내 프로필", icon: "person", route: .profile)
                sidebarButton("보관됨", icon: "archivebox", route: .archive)
            }
            .padding(.horizontal, 14)

            Text("SMART VIEW")
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.top, 34)
                .padding(.bottom, 10)

            VStack(spacing: 6) {
                sidebarButton("마감 임박", icon: "clock", route: .urgent)
                sidebarButton("확인 필요", icon: "questionmark.circle", route: .needsReview)
            }
            .padding(.horizontal, 14)

            Spacer()
        }
        .background(Color.awSidebar)
    }

    private func sidebarButton(_ title: String, icon: String, route: SidebarRoute) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                store.route = route
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 15, weight: store.route == route ? .bold : .medium))
                Spacer()
            }
            .foregroundStyle(store.route == route ? Color.awAccent : Color.primary.opacity(0.80))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                store.route == route ? Color.awAccentSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch store.route {
        case .dashboard, .applications, .archive, .urgent, .needsReview:
            DashboardView(
                searchText: $searchText,
                statusFilter: dashboardFilter,
                onImport: { url in
                    presentAddApplication(filename: url.lastPathComponent)
                },
                onShowAll: {
                    searchText = ""
                    store.route = .applications
                }
            )
        case .profile:
            MyProfileView()
        case .documents:
            MyDocumentsView()
        case let .application(id):
            ApplicationWorkspaceView(applicationID: id)
        }
    }

    private var dashboardFilter: DashboardStatusFilter {
        switch store.route {
        case .archive:
            .completed
        case .urgent:
            .urgent
        case .needsReview:
            .needsReview
        case .dashboard, .applications, .profile, .documents, .application:
            .all
        }
    }

    private var routeTitle: String {
        switch store.route {
        case .dashboard, .applications:
            "지원 현황"
        case .documents:
            "문서 보관함"
        case .profile:
            "내 프로필"
        case .archive:
            "보관됨"
        case .urgent:
            "마감 임박"
        case .needsReview:
            "확인 필요"
        case let .application(id):
            store.application(id: id)?.title ?? "지원 상세"
        }
    }

    private func presentAddApplication(filename: String? = nil) {
        pendingImportFilename = filename
        isPresentingAddApplication = true
    }
}
