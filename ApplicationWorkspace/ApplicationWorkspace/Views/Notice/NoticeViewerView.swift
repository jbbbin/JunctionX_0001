import SwiftUI

struct NoticeViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int
    @State private var zoom: Double = 1

    let filename: String
    private let totalPages = 5

    init(filename: String, initialPage: Int = 1) {
        self.filename = filename
        _page = State(initialValue: min(max(initialPage, 1), 5))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HStack(spacing: 0) {
                thumbnailRail
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    mockPage
                        .scaleEffect(zoom, anchor: .top)
                        .padding(42)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
        .frame(minWidth: 900, minHeight: 680)
        .background(Color.awCanvas)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("모집요강 원문")
                    .font(.headline)
                Text(filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                page = max(1, page - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(page == 1)

            Text("\(page) / \(totalPages)")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 55)

            Button {
                page = min(totalPages, page + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(page == totalPages)

            Divider().frame(height: 20)

            Button {
                zoom = max(0.7, zoom - 0.1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 42)
            Button {
                zoom = min(1.5, zoom + 0.1)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }

            Button("닫기") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Color.awAccent)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var thumbnailRail: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(1...totalPages, id: \.self) { number in
                    Button {
                        page = number
                    } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white)
                                .frame(width: 72, height: 94)
                                .overlay(
                                    VStack(alignment: .leading, spacing: 5) {
                                        ForEach(0..<5, id: \.self) { index in
                                            Capsule()
                                                .fill(Color.gray.opacity(index == 0 ? 0.45 : 0.20))
                                                .frame(width: index == 0 ? 42 : 52, height: 3)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(page == number ? Color.awAccent : Color.black.opacity(0.12), lineWidth: page == number ? 2 : 1)
                                )
                            Text("\(number)")
                                .font(.caption2)
                                .foregroundStyle(page == number ? Color.awAccent : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .frame(width: 112)
        .background(Color.primary.opacity(0.025))
    }

    private var mockPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(pageTitle)
                .font(.system(size: 22, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)

            Text("모집 기관  |  Application Workspace Prototype")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            Text("\(page). \(sectionTitle)")
                .font(.headline)

            Text(sectionBody)
                .font(.body)
                .lineSpacing(7)

            if page == 2 || page == 3 {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI 판정 근거", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.awAccent)
                    Text(page == 2 ? "지원 대상 및 학력 조건" : "필수 제출 서류와 확인이 필요한 조건")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                )
            }

            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 7) {
                    Text("• 세부 안내 항목 \(index + 1)")
                        .fontWeight(.semibold)
                    Text("제출 전 공식 접수 페이지에서 최신 내용과 유의사항을 반드시 확인해 주세요.")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Text("- \(page) -")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(54)
        .frame(width: 620, height: 820, alignment: .topLeading)
        .background(.white)
        .foregroundStyle(.black)
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var pageTitle: String {
        "2026 지원 모집요강"
    }

    private var sectionTitle: String {
        switch page {
        case 1: "모집 개요"
        case 2: "지원 자격"
        case 3: "제출 서류"
        case 4: "전형 일정"
        default: "접수 방법 및 유의사항"
        }
    }

    private var sectionBody: String {
        switch page {
        case 1: "본 모집은 새로운 가능성을 발견하고 성장할 지원자를 선발하기 위한 프로그램입니다. 아래 일정과 지원 요건을 확인하여 기간 내에 접수해 주세요."
        case 2: "국내 대학 재학생 및 졸업 예정자를 대상으로 하며, 분야별 세부 조건은 공고에 명시된 기준을 따릅니다. 일부 조건은 사용자 프로필 정보와 대조하여 확인이 필요할 수 있습니다."
        case 3: "지원서, 재학증명서, 성적증명서와 분야별 추가 서류를 제출해야 합니다. 추천서 등 외부 발급 문서는 마감 전에 충분한 시간을 두고 요청해 주세요."
        case 4: "접수, 서류 심사, 인터뷰 및 최종 발표 일정은 기관 사정에 따라 변경될 수 있습니다. 변경 사항은 공식 접수 페이지를 기준으로 합니다."
        default: "모든 서류를 확인한 뒤 공식 접수 페이지에서 지원자가 직접 인증하고 제출해야 합니다. Application Workspace는 자동 제출을 수행하지 않습니다."
        }
    }
}
