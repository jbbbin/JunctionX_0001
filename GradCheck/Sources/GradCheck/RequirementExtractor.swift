import Foundation

struct RequirementExtractor {
    func extract(from document: ExtractedDocument, sourceName: String) -> [RequirementItem] {
        var items: [RequirementItem] = []
        var activeRequirementIndex: Int?

        for (pageIndex, page) in document.pages.enumerated() {
            let pageNumber = document.sourcePage(at: pageIndex)
            let lines = page
                .components(separatedBy: .newlines)
                .flatMap { $0.components(separatedBy: ". ") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for line in lines {
                let lowered = line.lowercased()
                let type = relatedType(in: lowered)
                let isNamedRequirement = type != nil
                    || lowered.contains("recommendation")
                    || lowered.contains("deadline")
                    || lowered.contains("gre")
                    || lowered.contains("portfolio")
                let constraints = constraints(in: line)

                if isNamedRequirement {
                    let item = RequirementItem(
                        title: requirementTitle(for: type, line: line),
                        detail: String(line.prefix(300)),
                        scope: requirementScope(in: lowered),
                        status: containsConditionalLanguage(lowered) ? .humanReview : .ready,
                        sourceName: sourceName,
                        page: pageNumber,
                        relatedDocumentType: type,
                        maximumPages: constraints.maximumPages,
                        maximumWords: constraints.maximumWords,
                        requiredFileExtension: constraints.requiredFileExtension
                    )
                    activeRequirementIndex = merge(item, into: &items)
                    continue
                }

                guard let activeRequirementIndex,
                      items.indices.contains(activeRequirementIndex),
                      isConstraintContinuation(lowered, constraints: constraints) else {
                    continue
                }

                let active = items[activeRequirementIndex]
                let continuation = RequirementItem(
                    title: active.title,
                    detail: String(line.prefix(300)),
                    scope: active.scope,
                    status: containsConditionalLanguage(lowered) ? .humanReview : .ready,
                    sourceName: sourceName,
                    page: pageNumber,
                    relatedDocumentType: active.relatedDocumentType,
                    maximumPages: constraints.maximumPages,
                    maximumWords: constraints.maximumWords,
                    requiredFileExtension: constraints.requiredFileExtension
                )
                items[activeRequirementIndex] = merged(items[activeRequirementIndex], with: continuation)
            }
        }

        if !items.isEmpty { return items }

        return [
            RequirementItem(
                title: "공식 요건 직접 확인",
                detail: "문서 텍스트는 읽었지만 필수·조건부 요건을 확실하게 구조화하지 못했습니다.",
                scope: .program,
                status: .humanReview,
                sourceName: sourceName,
                page: 1
            )
        ]
    }

    private func relatedType(in value: String) -> DocumentType? {
        if value.contains("statement of purpose") || value.contains("statement of objectives") || value.contains("personal statement") || value.contains(" sop ") {
            return .sop
        }
        if value.contains("curriculum vitae") || value.contains("resume") || value.contains("résumé") || value.hasPrefix("cv ") {
            return .cv
        }
        if value.contains("transcript") || value.contains("academic record") { return .transcript }
        if value.contains("toefl") || value.contains("ielts") || value.contains("english proficiency") || value.contains("english score") {
            return .englishScore
        }
        return nil
    }

    private func requirementTitle(for type: DocumentType?, line: String) -> String {
        if let type { return type.title }
        let lowered = line.lowercased()
        if lowered.contains("recommendation") { return "추천서" }
        if lowered.contains("deadline") { return "지원 마감일" }
        if lowered.contains("gre") { return "GRE" }
        if lowered.contains("portfolio") { return "포트폴리오" }
        return "기타 공식 요건"
    }

    private func containsConditionalLanguage(_ value: String) -> Bool {
        ["unless", "optional", "may ", "if ", "waiver", "exemption", "verify", "recommended"].contains {
            value.contains($0)
        }
    }

    private func requirementScope(in value: String) -> RequirementScope {
        value.contains("university") || value.contains("graduate admissions") ? .university : .program
    }

    private func constraints(in line: String) -> RequirementConstraints {
        RequirementConstraints(
            maximumPages: integerCapture(
                #"(?i)(?:maximum|max\.?|at\s+most|no\s+more\s+than|not\s+exceed(?:ing)?)\s*(\d{1,3})\s*pages?"#,
                in: line
            ),
            maximumWords: integerCapture(
                #"(?i)(?:maximum|max\.?|at\s+most|no\s+more\s+than|not\s+exceed(?:ing)?)\s*([\d,]{2,6})\s*words?"#,
                in: line
            ),
            requiredFileExtension: requiredExtension(in: line.lowercased())
        )
    }

    private func isConstraintContinuation(_ value: String, constraints: RequirementConstraints) -> Bool {
        if constraints.hasValue { return true }
        guard containsConditionalLanguage(value) || containsRequiredLanguage(value) else { return false }
        return value.contains("page")
            || value.contains("word")
            || value.contains("format")
            || value.contains("file")
            || value.contains("required")
            || value.contains("must")
            || value.contains("shall")
            || value.contains("optional")
            || value.contains("unless")
            || value.contains("waiver")
            || value.contains("exemption")
    }

    private func containsRequiredLanguage(_ value: String) -> Bool {
        value.contains("required") || value.contains("must ") || value.contains("shall ")
    }

    @discardableResult
    private func merge(_ item: RequirementItem, into items: inout [RequirementItem]) -> Int {
        if let index = items.firstIndex(where: { mergeKey(for: $0) == mergeKey(for: item) }) {
            items[index] = merged(items[index], with: item)
            return index
        }
        items.append(item)
        return items.index(before: items.endIndex)
    }

    private func mergeKey(for item: RequirementItem) -> String {
        item.relatedDocumentType?.rawValue ?? item.title.lowercased()
    }

    private func merged(_ existing: RequirementItem, with incoming: RequirementItem) -> RequirementItem {
        var result = existing
        if !detailParts(in: result.detail).contains(incoming.detail) {
            result.detail = (detailParts(in: result.detail) + [incoming.detail]).joined(separator: " · ")
        }

        let existingHadConstraint = result.maximumPages != nil
            || result.maximumWords != nil
            || result.requiredFileExtension != nil
        let incomingHasConstraint = incoming.maximumPages != nil
            || incoming.maximumWords != nil
            || incoming.requiredFileExtension != nil
        if !existingHadConstraint, incomingHasConstraint {
            result.page = incoming.page
        }

        result.maximumPages = result.maximumPages ?? incoming.maximumPages
        result.maximumWords = result.maximumWords ?? incoming.maximumWords
        result.requiredFileExtension = result.requiredFileExtension ?? incoming.requiredFileExtension

        if result.status == .humanReview || incoming.status == .humanReview
            || hasConflictingConstraint(result.maximumPages, incoming.maximumPages)
            || hasConflictingConstraint(result.maximumWords, incoming.maximumWords)
            || hasConflictingConstraint(result.requiredFileExtension, incoming.requiredFileExtension) {
            result.status = .humanReview
        }
        return result
    }

    private func detailParts(in detail: String) -> [String] {
        detail.components(separatedBy: " · ")
    }

    private func hasConflictingConstraint<T: Equatable>(_ existing: T?, _ incoming: T?) -> Bool {
        guard let existing, let incoming else { return false }
        return existing != incoming
    }

    private func requiredExtension(in value: String) -> String? {
        if value.range(of: #"\bpdf\b"#, options: .regularExpression) != nil { return "pdf" }
        if value.range(of: #"\bdocx?\b"#, options: .regularExpression) != nil { return "docx" }
        return nil
    }

    private func integerCapture(_ pattern: String, in value: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Int(value[range].replacingOccurrences(of: ",", with: ""))
    }
}

private struct RequirementConstraints {
    var maximumPages: Int?
    var maximumWords: Int?
    var requiredFileExtension: String?

    var hasValue: Bool {
        maximumPages != nil || maximumWords != nil || requiredFileExtension != nil
    }
}
