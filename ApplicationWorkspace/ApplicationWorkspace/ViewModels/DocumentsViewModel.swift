import Combine
import Foundation

@MainActor
final class DocumentsViewModel: StoreBackedViewModel {
    @Published var isShowingImporter = false
    @Published var replacementDocumentID: UUID?
    @Published var documentToDelete: OwnedDocument?
    @Published var previewDocument: OwnedDocument?
    @Published var message: String?

    private let externalURLOpener: any ExternalURLOpening

    init(store: AppStore, externalURLOpener: any ExternalURLOpening) {
        self.externalURLOpener = externalURLOpener
        super.init(store: store)
    }

    var documents: [OwnedDocument] { store.ownedDocuments }

    func beginAdding() {
        replacementDocumentID = nil
        isShowingImporter = true
    }

    func beginReplacing(_ document: OwnedDocument) {
        replacementDocumentID = document.id
        isShowingImporter = true
    }

    func handleImport(_ result: Result<[URL], Error>) {
        defer { replacementDocumentID = nil }
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result {
                let nsError = error as NSError
                if !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) {
                    message = "파일을 불러오지 못했어요. 다시 선택해 주세요."
                }
            }
            return
        }

        if let replacementDocumentID {
            store.replaceOwnedDocument(id: replacementDocumentID, with: url)
        } else {
            store.addOwnedDocument(from: url)
        }
    }

    func open(_ document: OwnedDocument) {
        if let url = document.fileURL {
            _ = externalURLOpener.open(url)
        } else {
            previewDocument = document
        }
    }

    func confirmDelete() {
        guard let documentToDelete else { return }
        store.deleteOwnedDocument(id: documentToDelete.id)
        self.documentToDelete = nil
    }
}
