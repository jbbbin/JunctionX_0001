import Combine
import Foundation

@MainActor
final class ProfileViewModel: StoreBackedViewModel {
    @Published var draft: UserProfile
    @Published var isEditing = false
    @Published var didSave = false
    @Published var validationMessage: String?

    private var feedbackTask: Task<Void, Never>?

    override init(store: AppStore) {
        draft = store.profile
        super.init(store: store)
    }

    var profile: UserProfile { store.profile }

    func editOrSave() {
        if !isEditing {
            draft = store.profile
            validationMessage = nil
            isEditing = true
            return
        }

        guard validate() else { return }
        store.updateProfile(draft)
        isEditing = false
        didSave = true
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.didSave = false
        }
    }

    func cancelEditing() {
        draft = store.profile
        validationMessage = nil
        isEditing = false
    }

    private func validate() -> Bool {
        let requiredValues = [draft.name, draft.school, draft.major]
        guard requiredValues.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            validationMessage = "이름·학교·전공을 모두 입력해 주세요."
            return false
        }

        if !draft.gpa.isEmpty {
            guard let gpa = Double(draft.gpa), (0...4.5).contains(gpa) else {
                validationMessage = "학점은 0부터 4.5 사이의 숫자로 입력해 주세요."
                return false
            }
        }

        validationMessage = nil
        return true
    }
}
