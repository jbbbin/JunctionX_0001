import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MyDocumentsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingImporter = false
    @State private var replacementDocumentID: UUID?
    @State private var documentToDelete: OwnedDocument?
    @State private var previewDocument: OwnedDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                reusableCallout
                documentList
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .navigationTitle("내 문서함")
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                replacementDocumentID = nil
                return
            }

            if let replacementDocumentID {
                store.replaceOwnedDocument(id: replacementDocumentID, with: url)
            } else {
                store.addOwnedDocument(from: url)
            }
            self.replacementDocumentID = nil
        }
        .confirmationDialog(
            "이 문서를 삭제할까요?",
            isPresented: Binding(
                get: { documentToDelete != nil },
                set: { if !$0 { documentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("문서 삭제", role: .destructive) {
                if let documentToDelete {
                    store.deleteOwnedDocument(id: documentToDelete.id)
                }
                documentToDelete = nil
            }
            Button("취소", role: .cancel) {
                documentToDelete = nil
            }
        } message: {
            Text("다른 지원에서 자동 매칭된 연결도 영향을 받을 수 있어요.")
        }
        .sheet(item: $previewDocument) { document in
            DocumentPreviewSheet(document: document)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("내 문서함")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("반복해서 제출하는 문서를 한 번 등록하고 모든 지원에서 재사용하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                replacementDocumentID = nil
                isShowingImporter = true
            } label: {
                Label("문서 추가", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var reusableCallout: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("새 지원에도 자동으로 매칭돼요")
                    .font(.headline)
                Text("파일명과 문서 유형을 바탕으로 Upstage 분석 결과의 제출 항목과 연결합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill("\(store.ownedDocuments.count)개 보유", icon: "doc.on.doc.fill", tint: .green)
        }
        .padding(17)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var documentList: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("등록 문서")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text("PDF 파일")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 14)

                if store.ownedDocuments.isEmpty {
                    EmptyPlaceholder(
                        icon: "folder.badge.plus",
                        title: "등록한 문서가 없어요",
                        message: "재학증명서나 성적증명서를 추가하면 다음 지원부터 자동으로 연결해 드려요."
                    )
                    .frame(height: 260)
                } else {
                    ForEach(store.ownedDocuments) { document in
                        documentRow(document)
                        if document.id != store.ownedDocuments.last?.id {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }

    private func documentRow(_ document: OwnedDocument) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(Color.awAccent)
                .frame(width: 42, height: 42)
                .background(Color.awAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(document.name)
                        .font(.headline)
                    StatusPill(document.type, tint: .blue)
                }
                Text(document.filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(document.addedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("열기") {
                if let url = document.fileURL {
                    NSWorkspace.shared.open(url)
                } else {
                    previewDocument = document
                }
            }
            .buttonStyle(.borderless)

            Menu {
                Button {
                    replacementDocumentID = document.id
                    isShowingImporter = true
                } label: {
                    Label("최신 파일로 교체", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) {
                    documentToDelete = document
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("문서 작업")
        }
        .padding(.vertical, 12)
    }
}

private struct DocumentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let document: OwnedDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                        .font(.headline)
                    Text(document.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.awAccent)
            }
            .padding(18)
            Divider()

            VStack(spacing: 20) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.awAccent)
                Text("프로토타입 문서 미리보기")
                    .font(.title2.weight(.bold))
                Text("실제 Firebase Storage 연결 후에는 Quick Look 또는 PDFKit으로 보유 문서를 표시합니다.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                StatusPill(document.type, icon: "checkmark.circle.fill", tint: .green)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(48)
        }
        .frame(width: 620, height: 480)
        .background(Color.awCanvas)
    }
}
