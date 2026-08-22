import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum SourcePreviewMode: String, CaseIterable, Identifiable {
    case web = "웹페이지"
    case pdf = "PDF"

    var id: String { rawValue }
}

struct SourcePreviewView: View {
    @StateObject private var browser = BrowserController()
    @State private var selectedPDFURL: URL?
    @State private var isShowingPDFImporter = false
    @State private var isPDFTabVisible = true

    @Binding var mode: SourcePreviewMode
    @Binding var evidenceTitle: String?
    @Binding var requestedPDFPage: Int

    let applicationURL: URL?
    let sourceFilename: String

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
                pdfToolbar
                Divider()
                pdfContent
            }
        }
        .background(Color.awCanvas)
        .fileImporter(
            isPresented: $isShowingPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            selectedPDFURL = url
            mode = .pdf
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

            if isPDFTabVisible {
                sourceTab(
                    .pdf,
                    title: selectedPDFURL?.lastPathComponent ?? sourceFilename,
                    icon: "doc.text",
                    canClose: true
                )
            }

            Spacer(minLength: 8)

            Button {
                isPDFTabVisible = true
                mode = .pdf
                isShowingPDFImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            .help("새 PDF 탭")
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
                    isPDFTabVisible = false
                    selectedPDFURL = nil
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
                    .fill(Color.awAccent)
                    .frame(width: 7, height: 7)
                Text(mode == .web ? "공고 웹 · 원문 연결됨" : "공고 PDF · 원문 연결됨")
                    .font(.caption.weight(.bold))
            }

            Text("마지막 분석 14:02")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                if mode == .web {
                    browser.reload()
                } else {
                    isShowingPDFImporter = true
                }
            } label: {
                Label(mode == .web ? "다시 가져오기" : "PDF 변경", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Color.white)
    }

    private var webTabTitle: String {
        applicationURL?.host() ?? "웹 공고"
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
                    .fill(browser.isLoading ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(browser.currentAddress.isEmpty ? (applicationURL?.absoluteString ?? "연결할 웹 주소가 없습니다") : browser.currentAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
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
        if let applicationURL {
            ZStack(alignment: .bottom) {
                WebKitContainer(controller: browser, url: applicationURL)
                    .background(Color.white)
                evidenceBar
            }
        } else {
            EmptyPlaceholder(
                icon: "network.slash",
                title: "연결된 웹 공고가 없어요",
                message: "PDF 탭에서 모집요강을 선택해 원문을 확인할 수 있습니다."
            )
        }
    }

    private var pdfToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(Color.awAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedPDFURL?.lastPathComponent ?? sourceFilename)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(selectedPDFURL == nil ? "원본 PDF를 선택해 주세요" : "\(requestedPDFPage)페이지 근거 표시")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let selectedPDFURL {
                Button {
                    NSWorkspace.shared.open(selectedPDFURL)
                } label: {
                    Label("별도 창에서 열기", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
            }
            Button("PDF 선택") {
                isShowingPDFImporter = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color.awSidebar)
    }

    @ViewBuilder
    private var pdfContent: some View {
        if let selectedPDFURL {
            ZStack(alignment: .bottom) {
                PDFKitContainer(url: selectedPDFURL, page: requestedPDFPage)
                evidenceBar
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.awAccent)
                Text("모집요강 PDF를 연결하세요")
                    .font(.title3.weight(.bold))
                Text("선택한 PDF를 이 패널에서 바로 읽고, 왼쪽의 원문 근거 버튼으로 해당 페이지를 이동할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                Button {
                    isShowingPDFImporter = true
                } label: {
                    Label("PDF 선택", systemImage: "folder")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.awCanvas)
        }
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

@MainActor
private final class BrowserController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentAddress = ""
    @Published var currentURL: URL?

    let webView: WKWebView
    private var requestedURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsMagnification = true
    }

    func loadIfNeeded(_ url: URL) {
        guard requestedURL != url else { return }
        requestedURL = url
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func reload() {
        if webView.url != nil {
            webView.reload()
        } else if let requestedURL {
            webView.load(URLRequest(url: requestedURL))
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateState(from: webView, loading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState(from: webView, loading: false)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        updateState(from: webView, loading: false)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        updateState(from: webView, loading: false)
    }

    private func updateState(from webView: WKWebView, loading: Bool) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = loading
        currentURL = webView.url
        currentAddress = webView.url?.absoluteString ?? requestedURL?.absoluteString ?? ""
    }
}

private struct WebKitContainer: NSViewRepresentable {
    @ObservedObject var controller: BrowserController
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        controller.loadIfNeeded(url)
        return controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        controller.loadIfNeeded(url)
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
