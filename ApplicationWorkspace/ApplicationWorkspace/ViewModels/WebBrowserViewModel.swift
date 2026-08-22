import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class WebBrowserViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentAddress = ""
    @Published var currentURL: URL?
    @Published var errorMessage: String?

    let webView: WKWebView

    private let addressResolver: BrowserAddressResolver
    private var sourceURL: URL?
    private var requestedURL: URL?

    init(addressResolver: BrowserAddressResolver = BrowserAddressResolver()) {
        self.addressResolver = addressResolver
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
    }

    func loadSourceIfNeeded(_ url: URL?, force: Bool = false) {
        guard let url, force || sourceURL != url else { return }
        sourceURL = url
        requestedURL = url
        errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    func navigateFromAddressBar(_ value: String) {
        guard let url = addressResolver.resolve(value) else {
            errorMessage = "올바른 웹 주소나 검색어를 입력해 주세요."
            return
        }
        requestedURL = url
        currentAddress = url.absoluteString
        errorMessage = nil
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
        errorMessage = nil
        if webView.url != nil {
            webView.reload()
        } else if let requestedURL {
            webView.load(URLRequest(url: requestedURL))
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame == nil {
            requestedURL = navigationAction.request.url
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame?.isMainFrame == true {
            requestedURL = navigationAction.request.url
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        requestedURL = navigationAction.request.url
        webView.load(navigationAction.request)
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = makeAlert(title: frame.request.url?.host() ?? "웹페이지 알림", message: message)
        alert.addButton(withTitle: "확인")
        present(alert, in: webView) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = makeAlert(title: frame.request.url?.host() ?? "웹페이지 확인", message: message)
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        present(alert, in: webView) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let alert = makeAlert(title: frame.request.url?.host() ?? "웹페이지 입력", message: prompt)
        alert.accessoryView = input
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        present(alert, in: webView) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        updateState(from: webView, loading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState(from: webView, loading: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateFailure(error, from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        updateFailure(error, from: webView)
    }

    private func updateFailure(_ error: Error, from webView: WKWebView) {
        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled {
            errorMessage = error.localizedDescription
        }
        updateState(from: webView, loading: false)
    }

    private func updateState(from webView: WKWebView, loading: Bool) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = loading
        currentURL = webView.url
        let displayedURL = loading ? (requestedURL ?? webView.url) : (webView.url ?? requestedURL)
        currentAddress = displayedURL?.absoluteString ?? ""
    }

    private func makeAlert(title: String, message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        return alert
    }

    private func present(
        _ alert: NSAlert,
        in webView: WKWebView,
        completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
