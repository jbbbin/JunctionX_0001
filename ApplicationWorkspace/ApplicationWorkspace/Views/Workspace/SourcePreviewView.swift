import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum SourcePreviewMode: String, CaseIterable, Identifiable {
    case web = "웹페이지"
    case document = "원문"

    var id: String { rawValue }
}

struct SourcePreviewView: View {
    @StateObject private var browser = WebBrowserViewModel()
    @State private var isShowingDocumentImporter = false
    @State private var isDocumentTabVisible = true
    @State private var addressDraft = ""
    @FocusState private var isAddressFieldFocused: Bool

    @Binding var mode: SourcePreviewMode
    @Binding var evidenceTitle: String?
    @Binding var requestedPDFPage: Int

    let applicationURL: URL?
    let sourceFilename: String
    @Binding var selectedDocumentURL: URL?

    init(
        applicationURL: URL?,
        sourceFilename: String,
        mode: Binding<SourcePreviewMode>,
        evidenceTitle: Binding<String?>,
        requestedPDFPage: Binding<Int>,
        selectedDocumentURL: Binding<URL?>
    ) {
        self.applicationURL = applicationURL
        self.sourceFilename = sourceFilename
        _mode = mode
        _evidenceTitle = evidenceTitle
        _requestedPDFPage = requestedPDFPage
        _selectedDocumentURL = selectedDocumentURL
        _isDocumentTabVisible = State(initialValue: selectedDocumentURL.wrappedValue != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            obsidianTabBar
            sourceHeader
            Divider()

            if mode == .web {
                webToolbar
                Divider()
                webContent
            } else {
                documentToolbar
                Divider()
                documentContent
            }
        }
        .background(Color.awCanvas)
        .fileImporter(
            isPresented: $isShowingDocumentImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            selectedDocumentURL = url
            mode = .document
        }
        .onAppear {
            if addressDraft.isEmpty {
                addressDraft = browser.currentAddress.isEmpty
                    ? (applicationURL?.absoluteString ?? "")
                    : browser.currentAddress
            }
        }
        .onChange(of: browser.currentAddress) { _, newAddress in
            if !isAddressFieldFocused {
                addressDraft = newAddress
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .document {
                isDocumentTabVisible = true
            }
        }
        .onChange(of: evidenceTitle) { _, newTitle in
            if newTitle != nil, mode == .web {
                browser.loadSourceIfNeeded(applicationURL, force: true)
            }
        }
    }

    private var obsidianTabBar: some View {
        HStack(alignment: .bottom, spacing: 3) {
            sourceTab(
                .web,
                title: webTabTitle,
                icon: "globe",
                canClose: false
            )

            if isDocumentTabVisible {
                sourceTab(
                    .document,
                    title: selectedDocumentURL?.lastPathComponent ?? sourceFilename,
                    icon: "doc.text",
                    canClose: true
                )
            }

            Spacer(minLength: 8)

            Button {
                isDocumentTabVisible = true
                mode = .document
                if selectedDocumentURL == nil {
                    isShowingDocumentImporter = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            .help("새 원문 탭")
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .frame(height: 43)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.awBorder)
                .frame(height: 1)
        }
    }

    private func sourceTab(
        _ item: SourcePreviewMode,
        title: String,
        icon: String,
        canClose: Bool
    ) -> some View {
        let isActive = mode == item

        return HStack(spacing: 4) {
            Button {
                mode = item
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(isActive ? Color.awAccent : .secondary)
                    Text(title)
                        .font(.caption.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if canClose {
                Button {
                    isDocumentTabVisible = false
                    mode = .web
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(isActive ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 4))
                .help("탭 닫기")
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, canClose ? 7 : 11)
        .frame(width: item == .web ? 190 : 230, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.white : Color.clear)
                .shadow(color: isActive ? .black.opacity(0.045) : .clear, radius: 4, y: -1)
        )
        .overlay(alignment: .top) {
            if isActive {
                Capsule()
                    .fill(Color.awAccent)
                    .frame(height: 2)
                    .padding(.horizontal, 9)
            }
        }
        .zIndex(isActive ? 1 : 0)
    }

    private var sourceHeader: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Circle()
                    .fill(isCurrentSourceConnected ? Color.awAccent : Color.secondary.opacity(0.55))
                    .frame(width: 7, height: 7)
                Text(sourceConnectionLabel)
                    .font(.caption.weight(.bold))
            }

            Text("분석 결과 연결됨")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                if mode == .web {
                    browser.reload()
                } else {
                    isShowingDocumentImporter = true
                }
            } label: {
                Label(mode == .web ? "새로고침" : "원문 변경", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Color.white)
    }

    private var webTabTitle: String {
        browser.currentURL?.host() ?? applicationURL?.host() ?? "웹 공고"
    }

    private var isCurrentSourceConnected: Bool {
        switch mode {
        case .web:
            browser.currentURL != nil || applicationURL != nil
        case .document:
            selectedDocumentURL != nil
        }
    }

    private var sourceConnectionLabel: String {
        switch (mode, isCurrentSourceConnected) {
        case (.web, true): "공고 웹 · 원문 연결됨"
        case (.web, false): "공고 웹 · 주소 입력 필요"
        case (.document, true): selectedDocumentIsImage ? "공고 이미지 · 원문 연결됨" : "공고 PDF · 원문 연결됨"
        case (.document, false): "공고 원문 · 파일 선택 필요"
        }
    }

    private var browserStatusColor: Color {
        if browser.errorMessage != nil { return .red }
        if browser.isLoading { return .orange }
        if browser.currentURL != nil || applicationURL != nil { return .green }
        return .secondary.opacity(0.55)
    }

    private var webToolbar: some View {
        HStack(spacing: 12) {
            Button {
                browser.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!browser.canGoBack)

            Button {
                browser.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!browser.canGoForward)

            Button {
                browser.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            HStack(spacing: 9) {
                Circle()
                    .fill(browserStatusColor)
                    .frame(width: 7, height: 7)

                TextField(
                    "URL 또는 검색어 입력",
                    text: $addressDraft
                )
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($isAddressFieldFocused)
                    .onChange(of: isAddressFieldFocused) { _, isFocused in
                        if !isFocused {
                            addressDraft = browser.currentAddress
                        }
                    }
                    .onSubmit {
                        browser.navigateFromAddressBar(addressDraft)
                        isAddressFieldFocused = false
                    }

                Spacer(minLength: 0)

                if isAddressFieldFocused || addressDraft != browser.currentAddress {
                    Button {
                        browser.navigateFromAddressBar(addressDraft)
                        isAddressFieldFocused = false
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.awAccent)
                    }
                    .buttonStyle(.plain)
                    .help("이 주소로 이동")
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.awBorder, lineWidth: 1)
            )

            Button {
                guard let url = browser.currentURL ?? applicationURL else { return }
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .disabled(browser.currentURL == nil && applicationURL == nil)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color.awSidebar)
    }

    @ViewBuilder
    private var webContent: some View {
        ZStack(alignment: .bottom) {
            WebKitContainer(viewModel: browser, sourceURL: applicationURL)
                .background(Color.white)

            if let errorMessage = browser.errorMessage {
                browserError(errorMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if applicationURL == nil, browser.currentURL == nil, !browser.isLoading {
                browserStartHint
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            evidenceBar
        }
    }

    private var browserStartHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe.desk")
                .font(.system(size: 38))
                .foregroundStyle(Color.awAccent)
            Text("웹 공고를 찾아보세요")
                .font(.headline)
            Text("위 주소창에 URL이나 검색어를 입력하면 이 탭에서 바로 탐색할 수 있어요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fixedSize()
    }

    private func browserError(_ message: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text("페이지를 불러오지 못했어요")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                retryBrowserNavigation()
            } label: {
                Label("다시 시도", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fixedSize()
    }

    private func retryBrowserNavigation() {
        let input = addressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            browser.reload()
        } else {
            browser.navigateFromAddressBar(input)
        }
    }

    private var documentToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(Color.awAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedDocumentURL?.lastPathComponent ?? sourceFilename)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(documentStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let selectedDocumentURL {
                Button {
                    NSWorkspace.shared.open(selectedDocumentURL)
                } label: {
                    Label("별도 창에서 열기", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
            }
            Button("원문 선택") {
                isShowingDocumentImporter = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color.awSidebar)
    }

    @ViewBuilder
    private var documentContent: some View {
        if let selectedDocumentURL {
            ZStack(alignment: .bottom) {
                if selectedDocumentIsImage,
                   let image = NSImage(contentsOf: selectedDocumentURL) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(28)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(Color(nsColor: .underPageBackgroundColor))
                } else {
                    PDFKitContainer(url: selectedDocumentURL, page: requestedPDFPage)
                }
                evidenceBar
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.awAccent)
                Text("모집요강 원문을 연결하세요")
                    .font(.title3.weight(.bold))
                Text("선택한 PDF나 이미지를 이 패널에서 바로 읽고, 왼쪽 항목과 함께 원문 근거를 확인할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                Button {
                    isShowingDocumentImporter = true
                } label: {
                    Label("원문 선택", systemImage: "folder")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.awCanvas)
        }
    }

    private var selectedDocumentIsImage: Bool {
        guard let fileExtension = selectedDocumentURL?.pathExtension.lowercased() else { return false }
        return ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp"].contains(fileExtension)
    }

    private var documentStatusText: String {
        guard selectedDocumentURL != nil else { return "원본 PDF나 이미지를 선택해 주세요" }
        return selectedDocumentIsImage ? "이미지 원문 표시" : "\(requestedPDFPage)페이지 근거 표시"
    }

    @ViewBuilder
    private var evidenceBar: some View {
        if let evidenceTitle {
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(Color.awAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("원문 근거 연결")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.awAccent)
                    Text(evidenceTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                Button("연결 해제") {
                    self.evidenceTitle = nil
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.awAccent)
                    .frame(height: 2)
            }
            .padding(16)
        }
    }
}

private struct WebKitContainer: NSViewRepresentable {
    @ObservedObject var viewModel: WebBrowserViewModel
    let sourceURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        viewModel.loadSourceIfNeeded(sourceURL)
        return viewModel.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        viewModel.loadSourceIfNeeded(sourceURL)
    }
}

private struct PDFKitContainer: NSViewRepresentable {
    let url: URL
    let page: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        load(url: url, page: page, into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        load(url: url, page: page, into: nsView, coordinator: context.coordinator)
    }

    private func load(url: URL, page: Int, into view: PDFView, coordinator: Coordinator) {
        if coordinator.loadedURL != url {
            view.document = PDFDocument(url: url)
            coordinator.loadedURL = url
            coordinator.page = 0
        }

        guard let document = view.document,
              let targetPage = document.page(at: max(0, min(page - 1, document.pageCount - 1)))
        else { return }

        if coordinator.page != page {
            view.go(to: targetPage)
            coordinator.page = page
        }
    }

    final class Coordinator {
        var loadedURL: URL?
        var page = 0
    }
}
