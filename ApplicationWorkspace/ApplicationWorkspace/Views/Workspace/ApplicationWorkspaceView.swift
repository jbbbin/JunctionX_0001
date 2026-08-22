import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LegacyApplicationWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingNotice = false
    @State private var noticePage = 1
    @State private var isShowingDocumentImporter = false
    @State private var pendingDocumentID: UUID?

    let applicationID: UUID

    var body: some View {
        Group {
            if let application = store.application(id: applicationID) {
                workspace(application)
            } else {
                EmptyPlaceholder(
                    icon: "exclamationmark.triangle",
                    title: "지원 정보를 찾을 수 없어요",
                    message: "지원 현황으로 돌아가 다시 선택해 주세요."
                )
            }
        }
        .fileImporter(
            isPresented: $isShowingDocumentImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result,
                  let url = urls.first,
                  let pendingDocumentID
            else { return }
            store.linkDocument(
                applicationID: applicationID,
                documentID: pendingDocumentID,
                filename: url.lastPathComponent
            )
            self.pendingDocumentID = nil
        }
        .sheet(isPresented: $isShowingNotice) {
            if let application = store.application(id: applicationID) {
                NoticeViewerView(
                    filename: application.sourceFilename,
                    initialPage: noticePage
                )
            }
        }
    }

    private func workspace(_ application: ApplicationItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(application)
                overview(application)
                nextAction(application)

                HStack(alignment: .top, spacing: 18) {
                    eligibility(application)
                    documents(application)
                }
            }
            .padding(28)
        }
        .navigationTitle(application.title)
    }

    private func header(_ application: ApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                store.route = .dashboard
            } label: {
                Label("지원 현황", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        StatusPill(
                            application.category.rawValue,
                            icon: application.category.icon,
                            tint: application.category.tint
                        )
                        StatusPill(
                            application.eligibility.rawValue,
                            icon: application.eligibility.icon,
                            tint: application.eligibility.tint
                        )
                    }

                    Text(application.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(application.organization)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        noticePage = 1
                        isShowingNotice = true
                    } label: {
                        Label("모집요강 원문", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        openApplicationURL(application.applicationURL)
                    } label: {
                        Label("지원 페이지", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(application.applicationURL == nil)

                    Button {
                        store.toggleCompletion(applicationID: application.id)
                    } label: {
                        Label(
                            application.isCompleted ? "준비 중으로 변경" : "지원 완료",
                            systemImage: application.isCompleted ? "arrow.uturn.backward" : "checkmark"
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private func overview(_ application: ApplicationItem) -> some View {
        HStack(spacing: 16) {
            MetricTile(
                title: "마감일 · \(application.deadline.formatted(date: .abbreviated, time: .omitted))",
                value: application.dDayText,
                icon: "calendar.badge.clock",
                tint: application.daysRemaining <= 5 ? .orange : .blue
            )
            MetricTile(
                title: "전체 준비율",
                value: "\(application.progressPercent)%",
                icon: "chart.bar.fill",
                tint: application.category.tint
            )
            MetricTile(
                title: "남은 작업",
                value: "\(application.remainingTaskCount)개",
                icon: "checklist",
                tint: .purple
            )
            MetricTile(
                title: "지원 상태",
                value: application.isCompleted ? "완료" : "준비 중",
                icon: application.isCompleted ? "checkmark.seal.fill" : "clock.fill",
                tint: application.isCompleted ? .green : .awAccent
            )
        }
    }

    private func nextAction(_ application: ApplicationItem) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.awAccent, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("지금 할 일")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.awAccent)
                Text(application.nextAction)
                    .font(.title3.weight(.bold))
            }
            Spacer()
            if application.remainingTaskCount == 0 {
                Button("지원 페이지 열기") {
                    openApplicationURL(application.applicationURL)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .background(Color.awAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.awAccent.opacity(0.18), lineWidth: 1)
        )
    }

    private func eligibility(_ application: ApplicationItem) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    "지원 자격",
                    subtitle: "내 프로필과 모집요강을 비교했어요",
                    icon: "person.text.rectangle"
                )

                ForEach(application.requirements) { requirement in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: requirement.state.icon)
                            .font(.title3)
                            .foregroundStyle(requirement.state.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(requirement.title)
                                    .font(.headline)
                                Spacer()
                                StatusPill(requirement.state.rawValue, tint: requirement.state.tint)
                            }
                            Text(requirement.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button {
                                noticePage = requirement.sourcePage
                                isShowingNotice = true
                            } label: {
                                Label("원문 \(requirement.sourcePage)페이지에서 확인", systemImage: "quote.opening")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.awAccent)
                        }
                    }
                    .padding(.vertical, 5)

                    if requirement.id != application.requirements.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(minWidth: 350, maxWidth: .infinity, alignment: .top)
    }

    private func documents(_ application: ApplicationItem) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    sectionHeader(
                        "필요 서류",
                        subtitle: "\(application.readyDocumentCount)/\(application.requiredDocuments.count)개 준비됨",
                        icon: "folder.badge.gearshape"
                    )
                    Spacer()
                    Text("\(application.progressPercent)%")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(application.category.tint)
                }

                ProgressView(value: application.progress)
                    .tint(application.category.tint)

                ForEach(application.requiredDocuments) { document in
                    documentRow(document, application: application)
                    if document.id != application.requiredDocuments.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(minWidth: 410, maxWidth: .infinity, alignment: .top)
    }

    private func documentRow(_ document: RequiredDocument, application: ApplicationItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.isReady ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(document.isReady ? .green : .secondary)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(document.name)
                        .font(.headline)
                    StatusPill(
                        document.preparationType.rawValue,
                        icon: document.preparationType.icon,
                        tint: document.preparationType.tint
                    )
                }
                if let filename = document.linkedFilename {
                    Label(filename, systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(document.note.isEmpty ? actionHint(for: document.preparationType) : document.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if document.isReady {
                Button("완료 취소") {
                    store.toggleDocumentReady(applicationID: application.id, documentID: document.id)
                }
                .buttonStyle(.borderless)
            } else if document.preparationType == .request {
                Button("요청 완료") {
                    store.toggleDocumentReady(applicationID: application.id, documentID: document.id)
                }
                .buttonStyle(.bordered)
            } else {
                Button(document.preparationType == .owned ? "파일 연결" : "작성본 연결") {
                    pendingDocumentID = document.id
                    isShowingDocumentImporter = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionHeader(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(Color.awAccent)
                .frame(width: 34, height: 34)
                .background(Color.awAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionHint(for type: DocumentPreparationType) -> String {
        switch type {
        case .owned: "내 문서함에서 자동 매칭되지 않았어요"
        case .write: "작성한 파일을 연결하면 완료돼요"
        case .request: "외부 요청 후 완료로 표시하세요"
        }
    }

    private func openApplicationURL(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
