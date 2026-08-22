import Foundation
import CoreFoundation
import Darwin
import WebKit

struct PublicWebURLPolicy: Sendable {
    typealias HostResolver = @Sendable (String) -> [String]?

    private let hostResolver: HostResolver

    init(
        hostResolver: @escaping HostResolver = {
            PublicWebURLPolicy.resolveUsingSystemDNS($0)
        }
    ) {
        self.hostResolver = hostResolver
    }

    func allows(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.user == nil,
              components.password == nil,
              var host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return false
        }

        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        guard !host.isEmpty,
              !host.contains("%"),
              host != "localhost",
              !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local")
        else {
            return false
        }

        if Self.isIPAddress(host) {
            return Self.isPublicIPAddress(host)
        }

        guard let resolvedAddresses = hostResolver(host),
              !resolvedAddresses.isEmpty
        else {
            return false
        }
        return resolvedAddresses.allSatisfy(Self.isPublicIPAddress)
    }

    func allowsResolvedAddress(_ address: String) -> Bool {
        Self.isPublicIPAddress(address)
    }

    private static func resolveUsingSystemDNS(_ host: String) -> [String]? {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else {
            return nil
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let current = cursor {
            let info = current.pointee
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                info.ai_addr,
                info.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let bytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
                addresses.append(String(decoding: bytes, as: UTF8.self))
            }
            cursor = info.ai_next
        }
        return addresses.isEmpty ? nil : addresses
    }

    private static func isIPAddress(_ value: String) -> Bool {
        ipv4Bytes(value) != nil || ipv6Bytes(value) != nil
    }

    private static func isPublicIPAddress(_ value: String) -> Bool {
        if let bytes = ipv4Bytes(value) {
            return isPublicIPv4(bytes)
        }
        guard let bytes = ipv6Bytes(value) else { return false }

        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            return isPublicIPv4(Array(bytes.suffix(4)))
        }

        let isUnspecified = bytes.allSatisfy { $0 == 0 }
        let isLoopback = bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] == 1
        let isIPv4Compatible = bytes.prefix(12).allSatisfy { $0 == 0 }
        let isUniqueLocal = bytes[0] & 0xfe == 0xfc
        let isLinkLocal = bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80
        let isMulticast = bytes[0] == 0xff
        let isDocumentation = bytes[0] == 0x20
            && bytes[1] == 0x01
            && bytes[2] == 0x0d
            && bytes[3] == 0xb8

        return !isUnspecified
            && !isLoopback
            && !isIPv4Compatible
            && !isUniqueLocal
            && !isLinkLocal
            && !isMulticast
            && !isDocumentation
    }

    private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let first = bytes[0]
        let second = bytes[1]
        let third = bytes[2]

        let isSharedAddressSpace = first == 100 && (64...127).contains(second)
        let isPrivate = first == 10
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
        let isDocumentation = (first == 192 && second == 0 && third == 2)
            || (first == 198 && second == 51 && third == 100)
            || (first == 203 && second == 0 && third == 113)
        let isBenchmarking = first == 198 && (18...19).contains(second)

        return first != 0
            && first != 127
            && !(first == 169 && second == 254)
            && !isPrivate
            && !isSharedAddressSpace
            && !isDocumentation
            && !isBenchmarking
            && first < 224
    }

    private static func ipv4Bytes(_ value: String) -> [UInt8]? {
        var address = in_addr()
        guard inet_pton(AF_INET, value, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func ipv6Bytes(_ value: String) -> [UInt8]? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, value, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }
}

enum PublicWebContentLimits {
    static let maximumWebPageBytes = 5 * 1_024 * 1_024
    static let maximumDocumentBytes = 50 * 1_024 * 1_024

    static func isDocument(mimeType: String, url: URL?, data: Data? = nil) -> Bool {
        let mimeType = mimeType.lowercased().split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        if documentMIMETypes.contains(mimeType) || mimeType.hasPrefix("image/") {
            return true
        }
        if data?.starts(with: Data("%PDF".utf8)) == true {
            return true
        }
        return url?.pathExtension.lowercased() == "pdf"
    }

    static func byteLimit(mimeType: String, url: URL?, data: Data? = nil) -> Int {
        isDocument(mimeType: mimeType, url: url, data: data)
            ? maximumDocumentBytes
            : maximumWebPageBytes
    }

    private static let documentMIMETypes: Set<String> = [
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/x-hwp",
        "application/vnd.hancom.hwpx",
    ]
}

struct RenderedWebContent: Equatable, Sendable {
    let title: String
    let finalURL: URL
    let innerText: String
}

enum RenderedWebContentError: LocalizedError {
    case navigationFailed
    case timedOut
    case emptyContent
    case sourceTooLarge

    var errorDescription: String? {
        switch self {
        case .navigationFailed:
            "브라우저에서 공고 페이지를 불러오지 못했어요."
        case .timedOut:
            "공고 페이지를 불러오는 데 시간이 너무 오래 걸려 중단했어요."
        case .emptyContent:
            "브라우저에서 분석할 공고 본문을 찾지 못했어요."
        case .sourceTooLarge:
            "렌더링된 공고 본문이 로컬 분석 허용 크기를 넘었어요."
        }
    }
}

@MainActor
protocol RenderedWebContentLoading: AnyObject {
    func render(_ url: URL) async throws -> RenderedWebContent
}

/// Loads JavaScript-rendered public pages without reading form values, cookies,
/// local storage, or iframe documents. Each default render uses a fresh,
/// non-persistent data store and cannot inherit Safari or in-app browser login.
@MainActor
final class WKWebViewRenderedContentLoader: RenderedWebContentLoading {
    private let providedDataStore: WKWebsiteDataStore?
    private let timeoutNanoseconds: UInt64
    private let stabilizationNanoseconds: UInt64
    private let urlPolicy: PublicWebURLPolicy
    private var sessions: [UUID: RenderSession] = [:]

    init(
        dataStore: WKWebsiteDataStore? = nil,
        timeout: TimeInterval = 20,
        stabilizationDelay: TimeInterval = 0.7,
        urlPolicy: PublicWebURLPolicy = PublicWebURLPolicy()
    ) {
        providedDataStore = dataStore
        timeoutNanoseconds = Self.nanoseconds(from: timeout)
        stabilizationNanoseconds = Self.nanoseconds(from: stabilizationDelay)
        self.urlPolicy = urlPolicy
    }

    func render(_ url: URL) async throws -> RenderedWebContent {
        let urlPolicy = self.urlPolicy
        let initialURLAllowed = try await AnalysisBackgroundWorker.run {
            urlPolicy.allows(url)
        }
        guard initialURLAllowed else {
            throw ApplicationAnalysisError.unsupportedSource
        }

        let id = UUID()
        let session = RenderSession(
            // A fresh non-persistent store prevents Safari, SourcePreview, and
            // earlier render jobs from contributing authentication cookies.
            dataStore: providedDataStore ?? .nonPersistent(),
            timeoutNanoseconds: timeoutNanoseconds,
            stabilizationNanoseconds: stabilizationNanoseconds,
            urlPolicy: urlPolicy
        )
        sessions[id] = session
        defer { sessions[id] = nil }
        return try await session.render(url)
    }

    private static func nanoseconds(from interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }
}

/// Cookie-free transport for the first, non-rendered attempt. This is separate
/// from the authenticated Upstage API transport so source sites cannot inherit
/// cookies or credentials from another request path.
@MainActor
final class PublicWebURLSessionTransport: UpstageRequestPerforming {
    private let urlPolicy: PublicWebURLPolicy

    init(urlPolicy: PublicWebURLPolicy = PublicWebURLPolicy()) {
        self.urlPolicy = urlPolicy
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw ApplicationAnalysisError.unsupportedSource
        }
        let urlPolicy = self.urlPolicy
        let initialURLAllowed = try await AnalysisBackgroundWorker.run {
            urlPolicy.allows(url)
        }
        guard initialURLAllowed else {
            throw ApplicationAnalysisError.unsupportedSource
        }
        return try await BoundedPublicWebRequest(urlPolicy: urlPolicy).perform(request)
    }
}

private final class BoundedPublicWebRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let urlPolicy: PublicWebURLPolicy
    private let lock = NSLock()

    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: URLResponse?
    private var receivedData = Data()
    private var byteLimit = PublicWebContentLimits.maximumWebPageBytes
    private var pendingError: Error?
    private var isCancelled = false
    private var isCompleted = false

    init(urlPolicy: PublicWebURLPolicy) {
        self.urlPolicy = urlPolicy
    }

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(request, continuation: continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(
        _ request: URLRequest,
        continuation: CheckedContinuation<(Data, URLResponse), Error>
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForResource = 30

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        let task = session.dataTask(with: request)

        lock.lock()
        self.continuation = continuation
        self.session = session
        self.task = task
        let shouldCancel = isCancelled
        if shouldCancel {
            isCompleted = true
            self.continuation = nil
            self.session = nil
            self.task = nil
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
            session.invalidateAndCancel()
            continuation.resume(throwing: CancellationError())
        } else {
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, urlPolicy.allows(url) else {
            setPendingError(ApplicationAnalysisError.unsupportedSource)
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let responseURL = response.url, urlPolicy.allows(responseURL) else {
            setPendingError(ApplicationAnalysisError.unsupportedSource)
            completionHandler(.cancel)
            return
        }

        let mimeType = response.mimeType?.lowercased() ?? ""
        let limit = PublicWebContentLimits.byteLimit(mimeType: mimeType, url: responseURL)
        if response.expectedContentLength > Int64(limit) {
            setPendingError(LocalUpstageAnalysisError.sourceTooLarge)
            completionHandler(.cancel)
            return
        }

        lock.lock()
        self.response = response
        byteLimit = limit
        if response.expectedContentLength > 0 {
            receivedData.reserveCapacity(min(Int(response.expectedContentLength), limit))
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        let exceedsLimit = data.count > byteLimit || receivedData.count > byteLimit - data.count
        if exceedsLimit {
            pendingError = LocalUpstageAnalysisError.sourceTooLarge
        } else if pendingError == nil {
            receivedData.append(data)
        }
        lock.unlock()

        if exceedsLimit {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let unsafeAddress = metrics.transactionMetrics.contains { metric in
            guard !metric.isProxyConnection, let address = metric.remoteAddress else {
                return false
            }
            return !urlPolicy.allowsResolvedAddress(address)
        }
        if unsafeAddress {
            setPendingError(ApplicationAnalysisError.unsupportedSource)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        let continuation = self.continuation
        self.continuation = nil
        let response = self.response
        let data = receivedData
        let pendingError = self.pendingError
        let wasCancelled = isCancelled
        self.task = nil
        self.session = nil
        lock.unlock()

        session.finishTasksAndInvalidate()

        if let pendingError {
            continuation?.resume(throwing: pendingError)
        } else if wasCancelled || (error as? URLError)?.code == .cancelled {
            continuation?.resume(throwing: CancellationError())
        } else if let error {
            continuation?.resume(throwing: error)
        } else if let response {
            continuation?.resume(returning: (data, response))
        } else {
            continuation?.resume(throwing: LocalUpstageAnalysisError.webPageUnavailable)
        }
    }

    private func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    private func setPendingError(_ error: Error) {
        lock.lock()
        if pendingError == nil {
            pendingError = error
        }
        lock.unlock()
    }
}

@MainActor
private final class RenderSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let maximumRenderedCharacters = 180_000
    private static let maximumRenderedBytes = 5 * 1_024 * 1_024
    private static let minimumUsefulCharacters = 80
    private static let maximumStabilizationChecks = 8
    private static let subsequentCheckDelayNanoseconds: UInt64 = 250_000_000

    private let webView: WKWebView
    private let timeoutNanoseconds: UInt64
    private let stabilizationNanoseconds: UInt64
    private let urlPolicy: PublicWebURLPolicy

    private var activeNavigation: WKNavigation?
    private var continuation: CheckedContinuation<RenderedWebContent, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var extractionTask: Task<Void, Never>?
    private var hasFinished = false

    init(
        dataStore: WKWebsiteDataStore,
        timeoutNanoseconds: UInt64,
        stabilizationNanoseconds: UInt64,
        urlPolicy: PublicWebURLPolicy
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1_280, height: 900),
            configuration: configuration
        )
        self.timeoutNanoseconds = timeoutNanoseconds
        self.stabilizationNanoseconds = stabilizationNanoseconds
        self.urlPolicy = urlPolicy
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func render(_ url: URL) async throws -> RenderedWebContent {
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                self.continuation = continuation
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                activeNavigation = webView.load(request)
                startTimeout()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame != nil else {
            // Hidden rendering must never create or redirect into popup windows.
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                finish(.failure(RenderedWebContentError.navigationFailed))
                return
            }
            let urlPolicy = urlPolicy
            Task { @MainActor [weak self] in
                let isAllowed = (try? await AnalysisBackgroundWorker.run {
                    urlPolicy.allows(url)
                }) ?? false
                guard let self, !self.hasFinished else {
                    decisionHandler(.cancel)
                    return
                }
                if isAllowed {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.cancel)
                    self.finish(.failure(RenderedWebContentError.navigationFailed))
                }
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        extractionTask?.cancel()
        extractionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: stabilizationNanoseconds)
                try Task.checkCancellation()
                await extractWhenStable(remainingChecks: Self.maximumStabilizationChecks)
            } catch {
                if error is CancellationError, !hasFinished { return }
                finish(.failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        finishNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard navigation === activeNavigation else { return }
        finishNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        completionHandler(false)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        completionHandler(nil)
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                try Task.checkCancellation()
                finish(.failure(RenderedWebContentError.timedOut))
            } catch {
                // A completed or cancelled render owns cleanup through finish(_:).
            }
        }
    }

    private func extractWhenStable(remainingChecks: Int) async {
        guard !hasFinished, !Task.isCancelled else { return }

        do {
            let content = try await extractVisibleContent()
            if content.innerText.count >= Self.minimumUsefulCharacters {
                finish(.success(content))
                return
            }

            guard remainingChecks > 0 else {
                finish(.failure(RenderedWebContentError.emptyContent))
                return
            }
            try await Task.sleep(nanoseconds: Self.subsequentCheckDelayNanoseconds)
            try Task.checkCancellation()
            await extractWhenStable(remainingChecks: remainingChecks - 1)
        } catch is CancellationError {
            // finish(_:) is invoked by the caller's cancellation handler.
        } catch {
            finish(.failure(error))
        }
    }

    private func extractVisibleContent() async throws -> RenderedWebContent {
        // body.innerText only reflects rendered text. No form values, cookie,
        // localStorage, sessionStorage, or iframe document is accessed here.
        // Head/tail limiting happens inside WebKit so the full body is never
        // bridged into the app process.
        let script = """
        (() => {
          const maximumCharacters = (Self.maximumRenderedCharacters);
          const marker = ' … [중간 본문 생략] … ';
          const text = String((document.body && document.body.innerText) ||
                              (document.documentElement && document.documentElement.innerText) || '');
          let limitedText = text;
          if (text.length > maximumCharacters) {
            const availableCharacters = Math.max(0, maximumCharacters - marker.length);
            const headCount = Math.floor(availableCharacters * 2 / 3);
            const tailCount = availableCharacters - headCount;
            limitedText = text.slice(0, headCount) + marker + text.slice(-tailCount);
          }
          return {
            title: String(document.title || '').slice(0, 500),
            url: String(window.location.href || ''),
            innerText: limitedText
          };
        })()
        """
        let value = try await webView.evaluateJavaScript(script)
        guard let object = value as? [String: Any],
              let rawURL = object["url"] as? String,
              let finalURL = URL(string: rawURL)
        else {
            throw RenderedWebContentError.navigationFailed
        }

        let rawTitle = object["title"] as? String ?? ""
        let rawInnerText = object["innerText"] as? String ?? ""
        let maximumRenderedCharacters = Self.maximumRenderedCharacters
        let maximumRenderedBytes = Self.maximumRenderedBytes
        let urlPolicy = urlPolicy
        return try await AnalysisBackgroundWorker.run {
            try Task.checkCancellation()
            guard urlPolicy.allows(finalURL) else {
                throw RenderedWebContentError.navigationFailed
            }
            let title = String(WebSourceTextSanitizer.normalize(rawTitle).prefix(500))
            try Task.checkCancellation()
            let innerText = WebSourceTextSanitizer.normalize(rawInnerText)
            try Task.checkCancellation()
            let limitedText = WebSourceTextSanitizer.headAndTail(
                innerText,
                maximumCharacters: maximumRenderedCharacters
            )
            guard let encoded = limitedText.data(using: .utf8),
                  encoded.count <= maximumRenderedBytes
            else {
                throw RenderedWebContentError.sourceTooLarge
            }
            try Task.checkCancellation()
            return RenderedWebContent(
                title: title,
                finalURL: finalURL,
                innerText: limitedText
            )
        }
    }

    private func finishNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(RenderedWebContentError.navigationFailed))
        }
    }

    private func finish(_ result: Result<RenderedWebContent, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        extractionTask?.cancel()
        extractionTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        activeNavigation = nil

        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}

enum WebSourceTextSanitizer {
    static func visibleText(
        fromHTMLData data: Data,
        textEncodingName: String? = nil
    ) -> String? {
        try? visibleText(
            fromHTMLData: data,
            textEncodingName: textEncodingName,
            cancellationCheck: {}
        )
    }

    static func cancellableVisibleText(
        fromHTMLData data: Data,
        textEncodingName: String? = nil
    ) throws -> String? {
        try visibleText(
            fromHTMLData: data,
            textEncodingName: textEncodingName,
            cancellationCheck: Task.checkCancellation
        )
    }

    private static func visibleText(
        fromHTMLData data: Data,
        textEncodingName: String?,
        cancellationCheck: () throws -> Void
    ) throws -> String? {
        try cancellationCheck()
        guard let html = try decodedText(
            from: data,
            textEncodingName: textEncodingName,
            cancellationCheck: cancellationCheck
        ) else {
            return nil
        }
        var value = html
        let replacements = [
            (#"(?is)<(script|style|noscript|svg|canvas)[^>]*>.*?</\1>"#, " "),
            (#"(?is)<!--.*?-->"#, " "),
            (#"(?is)<[^>]+>"#, " "),
            (#"&nbsp;|&#160;"#, " "),
            (#"&(?:amp|#38);"#, "&"),
            (#"&(?:lt|#60);"#, "<"),
            (#"&(?:gt|#62);"#, ">"),
            (#"&(?:quot|#34);"#, "\""),
        ]
        for (pattern, replacement) in replacements {
            try cancellationCheck()
            value = replacing(pattern, in: value, with: replacement)
        }
        try cancellationCheck()
        return normalize(value)
    }

    static func normalize(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func headAndTail(_ value: String, maximumCharacters: Int) -> String {
        guard maximumCharacters > 0, value.count > maximumCharacters else {
            return maximumCharacters > 0 ? value : ""
        }

        let marker = " … [중간 본문 생략] … "
        let availableCharacters = max(0, maximumCharacters - marker.count)
        let headCount = availableCharacters * 2 / 3
        let tailCount = availableCharacters - headCount
        return String(value.prefix(headCount)) + marker + String(value.suffix(tailCount))
    }

    static func isLikelyAuthenticationPage(url: URL, title: String = "", text: String) -> Bool {
        let urlValue = url.absoluteString.lowercased()
        let authenticationURLMarkers = [
            "/login", "/log-in", "/signin", "/sign-in", "/auth/", "/oauth/", "/sso/"
        ]
        if authenticationURLMarkers.contains(where: urlValue.contains) {
            return true
        }

        guard text.count < 4_000 else { return false }
        let content = "\(title) \(text)".lowercased()
        let authenticationTextMarkers = [
            "로그인", "sign in", "log in", "single sign-on", "비밀번호", "password"
        ]
        return authenticationTextMarkers.filter(content.contains).count >= 2
    }

    static func redactedReference(for url: URL) -> String {
        guard let source = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = source.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = source.host,
              !host.isEmpty
        else {
            return "web-source"
        }

        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = source.port
        return origin.url?.absoluteString ?? "web-source"
    }

    static func decodedText(from data: Data, textEncodingName: String? = nil) -> String? {
        try? decodedText(
            from: data,
            textEncodingName: textEncodingName,
            cancellationCheck: {}
        )
    }

    static func cancellableDecodedText(
        from data: Data,
        textEncodingName: String? = nil
    ) throws -> String? {
        try decodedText(
            from: data,
            textEncodingName: textEncodingName,
            cancellationCheck: Task.checkCancellation
        )
    }

    private static func decodedText(
        from data: Data,
        textEncodingName: String?,
        cancellationCheck: () throws -> Void
    ) throws -> String? {
        var encodings: [String.Encoding] = []
        if let textEncodingName,
           let declaredEncoding = encoding(named: textEncodingName) {
            encodings.append(declaredEncoding)
        }
        encodings.append(contentsOf: [.utf8, .utf16])

        var attempted: Set<UInt> = []
        for encoding in encodings {
            try cancellationCheck()
            guard attempted.insert(encoding.rawValue).inserted else { continue }
            guard let value = String(data: data, encoding: encoding),
                  !isLikelyCorrupted(value)
            else { continue }
            return value
        }
        try cancellationCheck()
        return nil
    }

    private static func encoding(named name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(
            name.trimmingCharacters(in: .whitespacesAndNewlines) as CFString
        )
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        )
    }

    private static func isLikelyCorrupted(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let invalidCount = value.unicodeScalars.reduce(into: 0) { count, scalar in
            if scalar.value == 0xFFFD
                || ((0x00...0x1F).contains(scalar.value)
                    && scalar.value != 0x09
                    && scalar.value != 0x0A
                    && scalar.value != 0x0D)
                || (0x7F...0x9F).contains(scalar.value) {
                count += 1
            }
        }
        return invalidCount > 0 && invalidCount * 100 >= value.unicodeScalars.count
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}
