import AppKit
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
            topBarTrailing
        }
        .padding(.leading, 146)
        .padding(.trailing, 28)
        .frame(height: 72)
        .background(Color.white)
    }

    @ViewBuilder
    private var topBarTrailing: some View {
        if let application = selectedApplication {
            StatusPill("웹 공고 연결됨", icon: "link", tint: .awAccent)

            Button {
                guard let url = application.applicationURL else { return }
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "arrow.up.right")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(application.applicationURL == nil)

            Menu {
                Button {
                    store.toggleCompletion(applicationID: application.id)
                } label: {
                    Label(
                        application.isCompleted ? "준비 중으로 변경" : "지원 완료로 표시",
                        systemImage: application.isCompleted ? "arrow.uturn.backward" : "checkmark"
                    )
                }
                Button {
                    store.route = .applications
                } label: {
                    Label("지원 현황으로 이동", systemImage: "rectangle.stack")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 34)
        } else {
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
    }

    @ViewBuilder
    private var sidebar: some View {
        if let selectedApplication {
            applicationSidebar(selectedApplication)
        } else {
            primarySidebar
        }
    }

    private var primarySidebar: some View {
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

    private func applicationSidebar(_ selectedApplication: ApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PassReady")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    store.route = .applications
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 20)

            VStack(spacing: 4) {
                sidebarButton("지원 현황", icon: "tray", route: .applications)
                sidebarButton("내 프로필", icon: "person", route: .profile)
                sidebarButton("문서 보관함", icon: "folder", route: .documents)
            }
            .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("진행 중")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)

                    ForEach(store.applications.filter { !$0.isCompleted }) { application in
                        applicationSidebarRow(application, isSelected: application.id == selectedApplication.id)
                    }

                    Text("보관됨")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)

                    if store.applications.allSatisfy({ !$0.isCompleted }) {
                        Text("보관된 지원이 없습니다")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(store.applications.filter(\.isCompleted)) { application in
                            applicationSidebarRow(application, isSelected: application.id == selectedApplication.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            Button {
                presentAddApplication()
            } label: {
                Label("새 지원", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(14)
        }
        .background(Color.awSidebar)
    }

    private func applicationSidebarRow(_ application: ApplicationItem, isSelected: Bool) -> some View {
        Button {
            store.route = .application(application.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(isSelected ? Color.awAccent : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(application.title)
                        .font(.caption.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(application.dDayText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.white : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.awBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    private var selectedApplication: ApplicationItem? {
        guard case let .application(id) = store.route else { return nil }
        return store.application(id: id)
    }
}
