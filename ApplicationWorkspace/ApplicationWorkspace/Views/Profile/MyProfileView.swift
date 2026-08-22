import SwiftUI

struct MyProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = UserProfile(
        school: "",
        enrollmentStatus: "재학",
        grade: 1,
        gpa: "",
        incomeBracket: "미입력",
        major: "",
        region: ""
    )
    @State private var isEditing = false
    @State private var didSave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                profileSummary
                fields
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .navigationTitle("내 프로필")
        .onAppear { draft = store.profile }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("내 프로필")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("한 번 입력하면 모든 지원 자격 판단에 자동으로 재사용돼요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if isEditing {
                    store.updateProfile(draft)
                    didSave = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        didSave = false
                    }
                } else {
                    draft = store.profile
                }
                isEditing.toggle()
            } label: {
                Label(isEditing ? "저장" : "프로필 수정", systemImage: isEditing ? "checkmark" : "pencil")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var profileSummary: some View {
        SectionCard {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.awAccent, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("현")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text("지원자 프로필")
                        .font(.title3.weight(.bold))
                    Text("\(store.profile.school) · \(store.profile.major)")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        StatusPill(store.profile.enrollmentStatus, icon: "graduationcap.fill", tint: .blue)
                        StatusPill("프로필 자동 재사용", icon: "arrow.triangle.2.circlepath", tint: .green)
                    }
                }
                Spacer()

                if didSave {
                    Label("저장됨", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                Button {
                    store.route = .documents
                } label: {
                    Label("내 문서함 열기", systemImage: "folder")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var fields: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("자격 판단 정보")
                            .font(.title3.weight(.bold))
                        Text("새 공고에서 필요한 정보가 생기면 그 항목만 추가로 물어볼게요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isEditing {
                        Button("취소") {
                            draft = store.profile
                            isEditing = false
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
                    GridRow {
                        fieldLabel("학교", icon: "building.columns")
                        TextField("학교명", text: $draft.school)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!isEditing)

                        fieldLabel("전공", icon: "books.vertical")
                        TextField("전공", text: $draft.major)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!isEditing)
                    }

                    GridRow {
                        fieldLabel("재학 상태", icon: "person.text.rectangle")
                        Picker("재학 상태", selection: $draft.enrollmentStatus) {
                            Text("재학").tag("재학")
                            Text("휴학").tag("휴학")
                            Text("졸업 예정").tag("졸업 예정")
                            Text("졸업").tag("졸업")
                        }
                        .labelsHidden()
                        .disabled(!isEditing)

                        fieldLabel("학년", icon: "number.circle")
                        Picker("학년", selection: $draft.grade) {
                            ForEach(1...6, id: \.self) { grade in
                                Text("\(grade)학년").tag(grade)
                            }
                        }
                        .labelsHidden()
                        .disabled(!isEditing)
                    }

                    GridRow {
                        fieldLabel("학점", icon: "chart.line.uptrend.xyaxis")
                        TextField("예: 3.82", text: $draft.gpa)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!isEditing)

                        fieldLabel("소득분위", icon: "chart.pie")
                        Picker("소득분위", selection: $draft.incomeBracket) {
                            Text("미입력").tag("미입력")
                            ForEach(1...10, id: \.self) { bracket in
                                Text("\(bracket)분위").tag("\(bracket)분위")
                            }
                        }
                        .labelsHidden()
                        .disabled(!isEditing)
                    }

                    GridRow {
                        fieldLabel("지역", icon: "mappin.and.ellipse")
                        TextField("거주 지역", text: $draft.region)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!isEditing)
                        Color.clear
                        Color.clear
                    }
                }
            }
        }
    }

    private func fieldLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 88, alignment: .leading)
    }
}
