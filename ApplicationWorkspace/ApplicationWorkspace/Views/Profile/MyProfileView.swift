import SwiftUI

struct MyProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel

    let onOpenDocuments: () -> Void

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
            Button(action: viewModel.editOrSave) {
                Label(
                    viewModel.isEditing ? "저장" : "프로필 수정",
                    systemImage: viewModel.isEditing ? "checkmark" : "pencil"
                )
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
                    Text(viewModel.profile.avatarInitial)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.profile.name)
                        .font(.title3.weight(.bold))
                    Text("\(viewModel.profile.school) · \(viewModel.profile.major)")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        StatusPill(
                            viewModel.profile.enrollmentStatus,
                            icon: "graduationcap.fill",
                            tint: .blue
                        )
                        StatusPill("프로필 자동 재사용", icon: "arrow.triangle.2.circlepath", tint: .green)
                    }
                }
                Spacer()

                if viewModel.didSave {
                    Label("저장됨", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                Button(action: onOpenDocuments) {
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
                    if viewModel.isEditing {
                        Button("취소", action: viewModel.cancelEditing)
                        .buttonStyle(.borderless)
                    }
                }

                if let validationMessage = viewModel.validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
                    GridRow {
                        fieldLabel("이름", icon: "person")
                        TextField("이름", text: $viewModel.draft.name)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!viewModel.isEditing)

                        fieldLabel("지역", icon: "mappin.and.ellipse")
                        TextField("거주 지역", text: $viewModel.draft.region)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!viewModel.isEditing)
                    }

                    GridRow {
                        fieldLabel("학교", icon: "building.columns")
                        TextField("학교명", text: $viewModel.draft.school)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!viewModel.isEditing)

                        fieldLabel("전공", icon: "books.vertical")
                        TextField("전공", text: $viewModel.draft.major)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!viewModel.isEditing)
                    }

                    GridRow {
                        fieldLabel("재학 상태", icon: "person.text.rectangle")
                        Picker("재학 상태", selection: $viewModel.draft.enrollmentStatus) {
                            Text("재학").tag("재학")
                            Text("휴학").tag("휴학")
                            Text("졸업 예정").tag("졸업 예정")
                            Text("졸업").tag("졸업")
                        }
                        .labelsHidden()
                        .disabled(!viewModel.isEditing)

                        fieldLabel("학년", icon: "number.circle")
                        Picker("학년", selection: $viewModel.draft.grade) {
                            ForEach(1...6, id: \.self) { grade in
                                Text("\(grade)학년").tag(grade)
                            }
                        }
                        .labelsHidden()
                        .disabled(!viewModel.isEditing)
                    }

                    GridRow {
                        fieldLabel("학점", icon: "chart.line.uptrend.xyaxis")
                        TextField("예: 3.82", text: $viewModel.draft.gpa)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!viewModel.isEditing)

                        fieldLabel("소득분위", icon: "chart.pie")
                        Picker("소득분위", selection: $viewModel.draft.incomeBracket) {
                            Text("미입력").tag("미입력")
                            ForEach(1...10, id: \.self) { bracket in
                                Text("\(bracket)분위").tag("\(bracket)분위")
                            }
                        }
                        .labelsHidden()
                        .disabled(!viewModel.isEditing)
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
