import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var searchText: String
    @State private var isShowingImporter = false
    @State private var isDropTargeted = false

    let statusFilter: DashboardStatusFilter
    let onImport: (URL) -> Void
    let onShowAll: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                greeting
                overview
                uploadSection
                applicationsSection
            }
            .padding(.horizontal, 40)
            .padding(.top, 38)
            .padding(.bottom, 44)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.awCanvas)
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            onImport(url)
        }
    }

    private var greeting: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("안녕하세요, 홍길동님")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("이번 주, 놓치지 말아야 할 지원")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("공고를 추가하면 자격·서류·마감일을 한 번에 정리합니다.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("B")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color.awAccent, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 9, y: 6)
        }
    }

    private var overview: some View {
        HStack(spacing: 18) {
            if let nearestApplication {
                Button {
                    store.route = .application(nearestApplication.id)
                } label: {
                    HStack(spacing: 22) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("가장 가까운 마감")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                            Text(nearestApplication.title)
                                .font(.system(size: 23, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(formattedDeadline(nearestApplication.deadline)) · \(nearestApplication.dDayText)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.90))
                        }
                        Spacer()
                        Text("준비도 \(nearestApplication.progressPercent)%")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.awAccent)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 9)
                            .background(.white, in: Capsule())
                    }
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, minHeight: 154)
                    .background(Color.awAccent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                EmptyPlaceholder(
                    icon: "calendar.badge.plus",
                    title: "가까운 마감이 없어요",
                    message: "새 공고를 추가해 지원 준비를 시작하세요."
                )
                .frame(maxWidth: .infinity, minHeight: 154)
                .background(Color.awAccentSoft, in: RoundedRectangle(cornerRadius: 20))
            }

            VStack(spacing: 12) {
                summaryCard(
                    count: eligibleCount,
                    title: "지원 가능",
                    subtitle: "바로 준비를 시작할 수 있어요",
                    tint: .awAccent
                )
                summaryCard(
                    count: reviewCount,
                    title: "조건 확인 필요",
                    subtitle: "원문 근거를 한 번 더 보세요",
                    tint: .orange
                )
            }
            .frame(width: 300)
        }
    }

    private func summaryCard(
        count: Int,
        title: String,
        subtitle: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 17) {
            Text("\(count)")
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 71)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.awBorder.opacity(0.55), lineWidth: 1)
        )
    }

    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("공고를 추가하세요")
                    .font(.system(size: 21, weight: .bold))
                Spacer()
                Text("PDF · 이미지 · 공고 URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.awAccent)
                Text("모집요강을 여기에 놓으세요")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.awAccent)
                Text("또는 파일을 선택하세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("파일 선택") {
                    isShowingImporter = true
                }
                .font(.caption.weight(.bold))
                .buttonStyle(SecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                (isDropTargeted ? Color.awAccent.opacity(0.13) : Color.awAccent.opacity(0.055)),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(
                        Color.awAccent.opacity(isDropTargeted ? 0.8 : 0.30),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                    )
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, isSupportedImport(url) else { return false }
                onImport(url)
                return true
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.15)) {
                    isDropTargeted = targeted
                }
            }
        }
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(sectionTitle)
                    .font(.system(size: 21, weight: .bold))
                Spacer()
                Button("전체 보기  ›", action: onShowAll)
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.awAccent)
            }

            if displayedApplications.isEmpty {
                SectionCard {
                    EmptyPlaceholder(
                        icon: "tray",
                        title: "조건에 맞는 지원이 없어요",
                        message: "검색어를 지우거나 다른 Smart View를 선택해 보세요."
                    )
                    .frame(height: 180)
                }
            } else {
                VStack(spacing: 0) {
                    tableHeader
                    Divider().padding(.horizontal, 18)
                    ForEach(Array(displayedApplications.prefix(4).enumerated()), id: \.element.id) { index, application in
                        applicationRow(application, isHighlighted: index == 0)
                        if application.id != displayedApplications.prefix(4).last?.id {
                            Divider().padding(.horizontal, 18)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.awBorder.opacity(0.55), lineWidth: 1)
                )
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 14) {
            Text("지원")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("마감")
                .frame(width: 94, alignment: .leading)
            Text("자격")
                .frame(width: 112, alignment: .leading)
            Text("준비도")
                .frame(width: 124, alignment: .leading)
            Text("다음 행동")
                .frame(width: 142, alignment: .leading)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 26)
        .frame(height: 38)
    }

    private func applicationRow(_ application: ApplicationItem, isHighlighted: Bool) -> some View {
        Button {
            store.route = .application(application.id)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(application.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(application.organization) · \(application.category.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(formattedShortDate(application.deadline))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 94, alignment: .leading)

                StatusPill(
                    compactEligibility(application.eligibility),
                    tint: application.eligibility.tint
                )
                .frame(width: 112, alignment: .leading)

                Text("\(application.readyDocumentCount)/\(application.requiredDocuments.count) · \(application.progressPercent)%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(application.progress >= 1 ? .green : Color(red: 0.10, green: 0.56, blue: 0.26))
                    .frame(width: 124, alignment: .leading)

                Text(application.progress >= 1 ? "패키지 생성  ›" : "준비 계속  ›")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.awAccent)
                    .frame(width: 142, alignment: .leading)
            }
            .padding(.horizontal, 26)
            .frame(height: 66)
            .background(
                isHighlighted ? Color.awAccentSoft.opacity(0.78) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }

    private var nearestApplication: ApplicationItem? {
        store.applications
            .filter { !$0.isCompleted && $0.daysRemaining >= 0 }
            .min { $0.deadline < $1.deadline }
    }

    private var eligibleCount: Int {
        store.applications.filter { !$0.isCompleted && $0.eligibility == .eligible }.count
    }

    private var reviewCount: Int {
        store.applications.filter { !$0.isCompleted && $0.eligibility == .needsReview }.count
    }

    private var displayedApplications: [ApplicationItem] {
        store.applications
            .filter { application in
                let matchesStatus: Bool
                switch statusFilter {
                case .all, .preparing:
                    matchesStatus = !application.isCompleted
                case .urgent:
                    matchesStatus = !application.isCompleted && (0...7).contains(application.daysRemaining)
                case .needsReview:
                    matchesStatus = !application.isCompleted && application.eligibility == .needsReview
                case .completed:
                    matchesStatus = application.isCompleted
                }

                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesSearch = query.isEmpty
                    || application.title.localizedCaseInsensitiveContains(query)
                    || application.organization.localizedCaseInsensitiveContains(query)
                    || application.category.rawValue.localizedCaseInsensitiveContains(query)

                return matchesStatus && matchesSearch
            }
            .sorted { $0.deadline < $1.deadline }
    }

    private var sectionTitle: String {
        switch statusFilter {
        case .all, .preparing: "진행 중인 지원"
        case .urgent: "마감 임박 지원"
        case .needsReview: "확인이 필요한 지원"
        case .completed: "보관된 지원"
        }
    }

    private func compactEligibility(_ state: EligibilityState) -> String {
        switch state {
        case .eligible: "지원 적격"
        case .needsReview: "확인 필요"
        case .difficult: "지원 어려움"
        }
    }

    private func formattedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    private func formattedDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter.string(from: date)
    }

    private func isSupportedImport(_ url: URL) -> Bool {
        ["pdf", "png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased())
    }
}
