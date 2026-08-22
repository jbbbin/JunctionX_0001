import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isPresentingAddApplication = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 290)
        } detail: {
            detail
                .background(Color.awCanvas)
        }
        .sheet(isPresented: $isPresentingAddApplication) {
            AddApplicationView { applicationID in
                isPresentingAddApplication = false
                store.route = .application(applicationID)
            }
            .environmentObject(store)
        }
    }

    private var sidebar: some View {
        List(selection: routeSelection) {
            Section("워크스페이스") {
                Label("지원 현황", systemImage: "rectangle.grid.2x2.fill")
                    .tag(SidebarRoute.dashboard)

                Button {
                    isPresentingAddApplication = true
                } label: {
                    Label("새 공고 추가", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.awAccent)
                }
                .buttonStyle(.plain)
            }

            Section("내 정보") {
                Label("프로필", systemImage: "person.crop.circle")
                    .tag(SidebarRoute.profile)
                Label("내 문서함", systemImage: "folder.fill")
                    .tag(SidebarRoute.documents)
            }

            Section("최근 지원") {
                ForEach(store.applications.prefix(4)) { application in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(application.title)
                            .lineLimit(1)
                        Text(application.dDayText)
                            .font(.caption)
                            .foregroundStyle(application.daysRemaining <= 5 ? .orange : .secondary)
                    }
                    .tag(SidebarRoute.application(application.id))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.awAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Upstage Studio")
                        .font(.caption.weight(.semibold))
                    Text("Firebase 연결 준비")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Application Workspace")
    }

    @ViewBuilder
    private var detail: some View {
        switch store.route {
        case .dashboard:
            DashboardView(onAdd: { isPresentingAddApplication = true })
        case .profile:
            MyProfileView()
        case .documents:
            MyDocumentsView()
        case let .application(id):
            ApplicationWorkspaceView(applicationID: id)
        }
    }

    private var routeSelection: Binding<SidebarRoute?> {
        Binding(
            get: { store.route },
            set: { newValue in
                if let newValue {
                    store.route = newValue
                }
            }
        )
    }
}
