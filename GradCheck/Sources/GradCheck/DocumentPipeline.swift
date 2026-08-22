import AppKit
import CoreFoundation
import Foundation
import PDFKit
import UniformTypeIdentifiers

struct ExtractedDocument: Sendable {
    var pages: [String]
    var provider: String
    var sourcePageNumbers: [Int?]

    init(pages: [String], provider: String, sourcePageNumbers: [Int?]? = nil) {
        self.pages = pages
        self.provider = provider
        self.sourcePageNumbers = sourcePageNumbers ?? pages.indices.map { $0 + 1 }
    }

    var text: String { pages.joined(separator: "\n\n") }
    var pageCount: Int { max(pages.count, 1) }

    func sourcePage(at index: Int) -> Int? {
        guard sourcePageNumbers.indices.contains(index) else { return nil }
        return sourcePageNumbers[index]
    }
}

enum DocumentPipelineError: LocalizedError {
    case unreadableFile
    case unsupportedFileType
    case missingParsedContent
    case fileTooLarge
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "파일을 읽을 수 없습니다. 접근 권한을 확인해 주세요."
        case .unsupportedFileType:
            "이 파일 형식은 로컬 분석을 지원하지 않습니다. PDF 또는 텍스트 파일을 사용해 주세요."
        case .missingParsedContent:
            "문서에서 읽을 수 있는 텍스트를 찾지 못했습니다."
        case .fileTooLarge:
            "파일이 25MB를 초과합니다. 문서를 나누거나 용량을 줄인 뒤 다시 시도해 주세요."
        case .serviceError(let message):
            "문서 분석 서비스 오류: \(message)"
        }
    }
}

protocol DocumentAnalyzing: Sendable {
    var providerLabel: String { get }
    var isUpstageConnected: Bool { get }
    func extract(from url: URL) async throws -> ExtractedDocument
}

protocol DocumentModelService: Sendable {
    var providerName: String { get }
    func supports(contentType: UTType?, fileExtension: String) -> Bool
    func parse(url: URL) async throws -> ExtractedDocument
}

struct UpstageModelConfiguration: Sendable {
    var model: String
    var endpoint: URL
    var timeout: TimeInterval

    static let documentParse = UpstageModelConfiguration(
        model: "document-parse",
        endpoint: URL(string: "https://api.upstage.ai/v1/document-digitization")!,
        timeout: 90
    )
}

struct DocumentPipeline: DocumentAnalyzing {
    private let modelServices: [any DocumentModelService]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let key = environment["UPSTAGE_API_KEY"], !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let defaultConfiguration = UpstageModelConfiguration.documentParse
            let configuration = UpstageModelConfiguration(
                model: environment["UPSTAGE_DOCUMENT_MODEL"] ?? defaultConfiguration.model,
                endpoint: environment["UPSTAGE_DOCUMENT_ENDPOINT"].flatMap(URL.init(string:)) ?? defaultConfiguration.endpoint,
                timeout: environment["UPSTAGE_DOCUMENT_TIMEOUT"].flatMap(TimeInterval.init) ?? defaultConfiguration.timeout
            )
            modelServices = [UpstageDocumentService(apiKey: key, configuration: configuration)]
        } else {
            modelServices = []
        }
    }

    init(modelServices: [any DocumentModelService]) {
        self.modelServices = modelServices
    }

    var providerLabel: String {
        modelServices.first.map { "\($0.providerName) 연결됨" } ?? "온디바이스 분석"
    }

    var isUpstageConnected: Bool {
        modelServices.contains { $0.providerName.localizedCaseInsensitiveContains("Upstage") }
    }

    func extract(from url: URL) async throws -> ExtractedDocument {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let contentType = values?.contentType
        if let size = values?.fileSize, size > 25 * 1_024 * 1_024 {
            throw DocumentPipelineError.fileTooLarge
        }

        let fileExtension = url.pathExtension.lowercased()
        var modelError: Error?
        for service in modelServices where service.supports(contentType: contentType, fileExtension: fileExtension) {
            do {
                return try await service.parse(url: url)
            } catch {
                modelError = error
            }
        }

        if contentType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else {
                if let modelError { throw modelError }
                throw DocumentPipelineError.unreadableFile
            }
            let pages = (0..<document.pageCount).map { index in
                document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            guard pages.contains(where: { !$0.isEmpty }) else {
                if let modelError { throw modelError }
                throw DocumentPipelineError.missingParsedContent
            }
            return ExtractedDocument(pages: pages, provider: "PDFKit · 온디바이스")
        }

        if contentType?.conforms(to: .plainText) == true || ["txt", "md", "csv"].contains(url.pathExtension.lowercased()) {
            guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
                throw DocumentPipelineError.unreadableFile
            }
            return ExtractedDocument(pages: [text], provider: "텍스트 · 온디바이스")
        }

        if contentType?.conforms(to: .rtf) == true || url.pathExtension.lowercased() == "rtf" {
            let value = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ).string
            guard !value.isEmpty else { throw DocumentPipelineError.missingParsedContent }
            return ExtractedDocument(pages: [value], provider: "RTF · 온디바이스")
        }

        if let modelError { throw modelError }
        throw DocumentPipelineError.unsupportedFileType
    }
}

struct UpstageDocumentService: DocumentModelService {
    let apiKey: String
    let configuration: UpstageModelConfiguration

    init(apiKey: String, configuration: UpstageModelConfiguration = .documentParse) {
        self.apiKey = apiKey
        self.configuration = configuration
    }

    var providerName: String { "Upstage \(configuration.model)" }

    func supports(contentType: UTType?, fileExtension: String) -> Bool {
        contentType?.conforms(to: .pdf) == true
            || contentType?.conforms(to: .image) == true
            || fileExtension == "pdf"
            || ["png", "jpg", "jpeg", "heic", "tiff"].contains(fileExtension)
    }

    func parse(url: URL) async throws -> ExtractedDocument {
        let boundary = "GradCheck-\(UUID().uuidString)"
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw DocumentPipelineError.unreadableFile
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = configuration.timeout

        var body = Data()
        body.appendFormField(name: "model", value: configuration.model, boundary: boundary)
        body.appendFormField(name: "ocr", value: "auto", boundary: boundary)
        body.appendFormField(name: "output_formats", value: #"["text", "markdown"]"#, boundary: boundary)
        body.appendFile(
            name: "document",
            filename: url.lastPathComponent,
            mimeType: mimeType(for: url),
            contents: fileData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DocumentPipelineError.serviceError("응답을 확인할 수 없습니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(in: data) ?? "HTTP \(http.statusCode)"
            throw DocumentPipelineError.serviceError(message)
        }

        return try Self.extractedDocument(from: data)
    }

    private func mimeType(for url: URL) -> String {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let preferred = type.preferredMIMEType {
            return preferred
        }
        return "application/octet-stream"
    }

    static func extractedDocument(from data: Data) throws -> ExtractedDocument {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DocumentPipelineError.missingParsedContent
        }

        if let elementPages = elementPages(in: json) {
            return ExtractedDocument(
                pages: elementPages.pages,
                provider: "Upstage Document Parse",
                sourcePageNumbers: elementPages.sourcePageNumbers
            )
        }

        guard let parsed = preferredContent(in: json["content"])
            ?? preferredContent(in: json),
            !parsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentPipelineError.missingParsedContent
        }

        let usagePages = usagePageCount(in: json)
        let split = explicitlySplitPages(in: parsed)
        let pages = split?.pages ?? [parsed.trimmingCharacters(in: .whitespacesAndNewlines)]
        let sourcePageNumbers: [Int?]

        if let split,
                  let usagePages,
                  usagePages == split.pages.count,
                  trustworthy(split.sourcePageNumbers, expectedCount: split.pages.count) {
            sourcePageNumbers = split.sourcePageNumbers
        } else if split == nil, pages.count == 1, usagePages == 1 {
            sourcePageNumbers = [1]
        } else {
            sourcePageNumbers = Array(repeating: nil, count: pages.count)
        }

        return ExtractedDocument(
            pages: pages,
            provider: "Upstage Document Parse",
            sourcePageNumbers: sourcePageNumbers
        )
    }

    private static func elementPages(in json: [String: Any]) -> (pages: [String], sourcePageNumbers: [Int?])? {
        guard let elements = json["elements"] as? [Any] else { return nil }

        var knownPageParts: [Int: [String]] = [:]
        var unknownPageParts: [String] = []

        for case let element as [String: Any] in elements {
            guard let content = preferredContent(in: element["content"]) else { continue }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let page = positiveInteger(element["page"]) {
                knownPageParts[page, default: []].append(trimmed)
            } else {
                unknownPageParts.append(trimmed)
            }
        }

        guard !knownPageParts.isEmpty || !unknownPageParts.isEmpty else { return nil }

        let orderedPageNumbers = knownPageParts.keys.sorted()
        var pages = orderedPageNumbers.map { page in
            knownPageParts[page, default: []].joined(separator: "\n\n")
        }
        var sourcePageNumbers = orderedPageNumbers.map(Optional.some)

        if !unknownPageParts.isEmpty {
            pages.append(unknownPageParts.joined(separator: "\n\n"))
            sourcePageNumbers.append(nil)
        }

        return (pages, sourcePageNumbers)
    }

    private static func preferredContent(in value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        for key in ["text", "markdown", "html"] {
            if let string = dictionary[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func usagePageCount(in json: [String: Any]) -> Int? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        return positiveInteger(usage["pages"])
    }

    private static func positiveInteger(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            guard double.isFinite, double.rounded() == double, double > 0 else { return nil }
            return Int(exactly: double)
        }
        if let string = value as? String,
           let integer = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           integer > 0 {
            return integer
        }
        return nil
    }

    private static func trustworthy(_ values: [Int?], expectedCount: Int) -> Bool {
        let pageNumbers = values.compactMap { $0 }
        guard pageNumbers.count == expectedCount else { return false }
        return zip(pageNumbers, pageNumbers.dropFirst()).allSatisfy { $0.0 < $0.1 }
    }

    private static func explicitlySplitPages(
        in text: String
    ) -> (pages: [String], sourcePageNumbers: [Int?])? {
        if let numbered = splitOnNumberedPageMarkers(text) { return numbered }

        let horizontalRule = try? NSRegularExpression(pattern: #"(?i)<hr\s*/?>"#)
        guard let horizontalRule else { return nil }
        let matches = horizontalRule.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        guard !matches.isEmpty else { return nil }

        let pages = text
            .components(separatedBy: horizontalRule)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (pages, pages.indices.map { $0 + 1 })
    }

    private static func splitOnNumberedPageMarkers(
        _ text: String
    ) -> (pages: [String], sourcePageNumbers: [Int?])? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?im)^[ \t]*---[ \t]*page[ \t]+(\d+)[ \t]*---[ \t]*$"#
        ) else { return nil }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else { return nil }

        var pages: [String] = []
        var sourcePageNumbers: [Int?] = []
        let firstMatch = matches[0]
        let prefixRange = NSRange(location: fullRange.location, length: firstMatch.range.location - fullRange.location)
        if let range = Range(prefixRange, in: text) {
            let prefix = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                pages.append(prefix)
                let firstPage = positiveInteger(capturedString(in: text, match: firstMatch, group: 1))
                sourcePageNumbers.append(firstPage == 2 ? 1 : nil)
            }
        }

        for (index, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count
                ? matches[index + 1].range.location
                : fullRange.location + fullRange.length
            guard let range = Range(NSRange(location: start, length: end - start), in: text) else { continue }
            pages.append(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines))
            sourcePageNumbers.append(positiveInteger(capturedString(in: text, match: match, group: 1)))
        }

        return pages.isEmpty ? nil : (pages, sourcePageNumbers)
    }

    private static func capturedString(
        in text: String,
        match: NSTextCheckingResult,
        group: Int
    ) -> String? {
        guard group < match.numberOfRanges,
              match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = json["message"] as? String { return message }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return nil
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(string.data(using: .utf8) ?? Data())
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendFile(
        name: String,
        filename: String,
        mimeType: String,
        contents: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(contents)
        append("\r\n")
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..<endIndex, in: self)
        var result: [String] = []
        var lastLocation = range.location
        for match in regex.matches(in: self, range: range) {
            let length = match.range.location - lastLocation
            if let swiftRange = Range(NSRange(location: lastLocation, length: length), in: self) {
                result.append(String(self[swiftRange]))
            }
            lastLocation = match.range.location + match.range.length
        }
        if let swiftRange = Range(NSRange(location: lastLocation, length: range.location + range.length - lastLocation), in: self) {
            result.append(String(self[swiftRange]))
        }
        return result
    }
}
