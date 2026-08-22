import SwiftUI

struct NewWorkspaceSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var school = ""
    @State private var program = ""
    @State private var degree = "PhD"
    @State private var intake = "Fall 2027"
    @State private var applicantName = ""
    @State private var pendingAction: PendingWorkspaceAction?
    @State private var showReplaceAlert = false

    private var canCreate: Bool {
        !school.trimmingCharacters(in: .whitespaces).isEmpty &&
        !program.trimmingCharacters(in: .whitespaces).isEmpty &&
        !intake.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("새 지원 목표")
                        .font(.system(size: 23, weight: .bold))
                    Text("학교 + 프로그램 + 학위 과정 하나를 독립적으로 검수합니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(26)

            Divider()

            Form {
                TextField("학교명", text: $school, prompt: Text("예: MIT"))
                TextField("프로그램명", text: $program, prompt: Text("예: Electrical Engineering & Computer Science"))
                Picker("학위 과정", selection: $degree) {
                    Text("PhD").tag("PhD")
                    Text("MS").tag("MS")
                    Text("MA").tag("MA")
                    Text("MEng").tag("MEng")
                }
                TextField("입학 학기", text: $intake, prompt: Text("예: Fall 2027"))
                TextField("지원자 영문 이름 (선택)", text: $applicantName, prompt: Text("여권 기준 영문 이름"))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, 10)

            HStack {
                Button("샘플 지원서 사용") {
                    request(.loadDemo)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(.bordered)
                Button("지원 목표 만들기") {
                    request(.create)
                }
                .buttonStyle(.borderedProminent)
                .tint(GCTheme.brand)
                .disabled(!canCreate)
            }
            .padding(22)
        }
        .frame(width: 560, height: 500)
        .background(GCTheme.canvas)
        .alert("현재 지원 목표를 교체할까요?", isPresented: $showReplaceAlert) {
            Button("취소", role: .cancel) { pendingAction = nil }
            Button("교체", role: .destructive) { performPendingAction() }
        } message: {
            Text("문서 원문은 앱에 저장하지 않으므로 현재 세션의 문서와 검수 결과를 다시 열 수 없습니다. 검수 이력 요약은 유지되지 않고 새 목표로 시작합니다.")
        }
    }

    private func request(_ action: PendingWorkspaceAction) {
        pendingAction = action
        if state.hasUserWorkspaceData {
            showReplaceAlert = true
        } else {
            performPendingAction()
        }
    }

    private func performPendingAction() {
        switch pendingAction {
        case .create:
            state.createWorkspace(
                school: school,
                program: program,
                degree: degree,
                intake: intake,
                applicantName: applicantName
            )
        case .loadDemo:
            state.loadDemo()
        case nil:
            return
        }
        pendingAction = nil
        dismiss()
    }
}

private enum PendingWorkspaceAction {
    case create
    case loadDemo
}
