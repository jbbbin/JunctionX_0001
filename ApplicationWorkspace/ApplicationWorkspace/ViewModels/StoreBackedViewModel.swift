import Combine
import Foundation

@MainActor
class StoreBackedViewModel: ObservableObject {
    let store: AppStore
    var cancellables = Set<AnyCancellable>()

    init(store: AppStore) {
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
