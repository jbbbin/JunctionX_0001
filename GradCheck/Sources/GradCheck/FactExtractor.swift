import Foundation

struct ObservedFact: Hashable {
    var value: String
    var normalized: String
    var documentName: String
    var documentType: DocumentType
    var page: Int?
    var excerpt: String

    func evidence(label: String, maskedExcerpt: String? = nil) -> EvidenceRef {
        EvidenceRef(
            documentName: documentName,
            documentType: documentType,
            page: page,
            excerpt: maskedExcerpt ?? excerpt,
            fieldLabel: label
        )
    }
}

struct DocumentFacts {
    var document: DocumentItem
    var names: [ObservedFact] = []
    var birthDates: [ObservedFact] = []
    var applicationStatements: [ObservedFact] = []
    var targetDegrees: [ObservedFact] = []
    var graduationDates: [ObservedFact] = []
    var institutions: [ObservedFact] = []
    var majors: [ObservedFact] = []
    var educationDegrees: [ObservedFact] = []
    var gpas: [ObservedFact] = []
    var englishScores: [ObservedFact] = []
    var testDates: [ObservedFact] = []
}

struct FactExtractor {
    func extract(document: DocumentItem, content: ExtractedDocument) -> DocumentFacts {
        var facts = DocumentFacts(document: document)

        for (pageIndex, page) in content.pages.enumerated() {
            let pageNumber = content.sourcePage(at: pageIndex)
            let lines = page
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for (lineIndex, line) in lines.enumerated() {
                if let name = labeledName(in: line) {
                    facts.names.append(observation(name, normalized: normalizeName(name), document: document, page: pageNumber, line: line))
                } else if lineIndex < 5, looksLikeStandaloneName(line, documentType: document.type) {
                    facts.names.append(observation(line, normalized: normalizeName(line), document: document, page: pageNumber, line: line))
                }

                if containsApplicationContext(line) {
                    facts.applicationStatements.append(
                        observation(line, normalized: normalizeText(line), document: document, page: pageNumber, line: line)
                    )
                    if let degree = canonicalDegree(in: line, includeUndergraduate: false) {
                        facts.targetDegrees.append(
                            observation(degree, normalized: degree, document: document, page: pageNumber, line: line)
                        )
                    }
                }

                if let date = labeledBirthDate(in: line) {
                    facts.birthDates.append(
                        observation(date.display, normalized: date.normalized, document: document, page: pageNumber, line: line)
                    )
                }

                if isEducationDateContext(line, documentType: document.type), let date = educationDate(in: line, documentType: document.type) {
                    facts.graduationDates.append(
                        observation(date.display, normalized: date.normalized, document: document, page: pageNumber, line: line)
                    )
                }

                if let institution = institution(in: line) {
                    facts.institutions.append(
                        observation(institution, normalized: normalizeText(institution), document: document, page: pageNumber, line: line)
                    )
                }

                if let major = major(in: line) {
                    facts.majors.append(
                        observation(major, normalized: normalizeAcademicField(major), document: document, page: pageNumber, line: line)
                    )
                }

                if isEducationContext(line), let degree = canonicalDegree(in: line, includeUndergraduate: true), !["PhD", "MS", "MA", "MEng"].contains(degree) || !containsApplicationContext(line) {
                    facts.educationDegrees.append(
                        observation(degree, normalized: degree, document: document, page: pageNumber, line: line)
                    )
                }

                if let gpa = gpa(in: line) {
                    facts.gpas.append(
                        observation(gpa.value, normalized: gpa.normalized, document: document, page: pageNumber, line: line)
                    )
                }

                if document.type == .englishScore || line.range(of: "TOEFL|IELTS", options: [.regularExpression, .caseInsensitive]) != nil {
                    if let score = englishScore(in: line) {
                        facts.englishScores.append(
                            observation(score, normalized: score, document: document, page: pageNumber, line: line)
                        )
                    }
                    if let date = testDate(in: line) {
                        facts.testDates.append(
                            observation(date.display, normalized: date.normalized, document: document, page: pageNumber, line: line)
                        )
                    }
                }
            }
        }

        facts.names = unique(facts.names)
        facts.birthDates = unique(facts.birthDates)
        facts.applicationStatements = unique(facts.applicationStatements)
        facts.targetDegrees = unique(facts.targetDegrees)
        facts.graduationDates = unique(facts.graduationDates)
        facts.institutions = unique(facts.institutions)
        facts.majors = unique(facts.majors)
        facts.educationDegrees = unique(facts.educationDegrees)
        facts.gpas = unique(facts.gpas)
        facts.englishScores = unique(facts.englishScores)
        facts.testDates = unique(facts.testDates)
        return facts
    }

    func normalizeName(_ value: String) -> String {
        value.uppercased().filter(\.isLetter)
    }

    func nameComparison(_ lhs: String, _ rhs: String) -> NameComparison {
        let leftExact = normalizeName(lhs)
        let rightExact = normalizeName(rhs)
        guard !leftExact.isEmpty, !rightExact.isEmpty else { return .different }
        if leftExact == rightExact { return .exact }

        let leftCandidates = nameOrderCandidates(lhs)
        let rightCandidates = nameOrderCandidates(rhs)
        return leftCandidates.isDisjoint(with: rightCandidates) ? .different : .plausible
    }

    func normalizeText(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    func canonicalDegree(in value: String, includeUndergraduate: Bool = true) -> String? {
        let checks: [(String, String)] = [
            (#"(?i)\b(?:ph\.?\s*d\.?|doctor(?:ate|al)?\s+of\s+philosophy|doctoral)\b"#, "PhD"),
            (#"(?i)\b(?:m\.?\s*s\.?|master\s+of\s+science)\b"#, "MS"),
            (#"(?i)\b(?:m\.?\s*a\.?|master\s+of\s+arts)\b"#, "MA"),
            (#"(?i)\b(?:m\.?\s*eng\.?|master\s+of\s+engineering)\b"#, "MEng"),
            (#"(?i)\b(?:b\.?\s*s\.?|bachelor\s+of\s+science)\b"#, "BS"),
            (#"(?i)\b(?:b\.?\s*a\.?|bachelor\s+of\s+arts)\b"#, "BA")
        ]
        for (pattern, canonical) in checks where includeUndergraduate || !["BS", "BA"].contains(canonical) {
            if value.range(of: pattern, options: .regularExpression) != nil { return canonical }
        }
        return nil
    }

    private func observation(
        _ value: String,
        normalized: String,
        document: DocumentItem,
        page: Int?,
        line: String
    ) -> ObservedFact {
        ObservedFact(
            value: value.trimmingCharacters(in: .whitespacesAndNewlines),
            normalized: normalized,
            documentName: document.filename,
            documentType: document.type,
            page: page,
            excerpt: String(line.prefix(280))
        )
    }

    private func unique(_ values: [ObservedFact]) -> [ObservedFact] {
        var seen: Set<String> = []
        return values.filter {
            seen.insert("\($0.documentName)|\($0.page.map(String.init) ?? "unknown")|\($0.normalized)").inserted
        }
    }

    private func labeledName(in line: String) -> String? {
        capture(
            #"(?i)^\s*(?:student\s+name|applicant\s+name|candidate\s+name|student|applicant|name)\s*[:\-]\s*([A-Z][A-Za-z'’.,\- ]{2,55})\s*$"#,
            in: line
        )
    }

    private func looksLikeStandaloneName(_ line: String, documentType: DocumentType) -> Bool {
        guard [.cv, .sop, .transcript, .englishScore].contains(documentType), line.count <= 45 else { return false }
        let rejected = [
            "STATEMENT OF PURPOSE", "PERSONAL STATEMENT", "CURRICULUM VITAE", "RESUME",
            "TRANSCRIPT", "SCORE REPORT", "EDUCATION", "UNIVERSITY", "COLLEGE", "DEPARTMENT"
        ]
        guard !rejected.contains(where: { line.uppercased().contains($0) }) else { return false }
        guard line.range(of: #"^[A-Za-z][A-Za-z'’\-]+(?:[ ,.\-]+[A-Za-z][A-Za-z'’\-]+){1,3}$"#, options: .regularExpression) != nil else {
            return false
        }
        return line == line.uppercased() || documentType == .cv
    }

    private func containsApplicationContext(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let intent = lowered.contains("apply")
            || lowered.contains("application")
            || lowered.contains("admission")
            || lowered.contains("target program")
            || lowered.contains("intended program")
        let target = lowered.contains("program") || lowered.contains("degree") || lowered.contains("phd") || lowered.contains("ph.d") || lowered.contains("master")
        return intent && target
    }

    private func labeledBirthDate(in line: String) -> (display: String, normalized: String)? {
        guard line.range(of: #"(?i)date\s+of\s+birth|birth\s+date|\bdob\b"#, options: .regularExpression) != nil else {
            return nil
        }
        return fullDate(in: line)
    }

    private func isEducationDateContext(_ line: String, documentType: DocumentType) -> Bool {
        let lowered = line.lowercased()
        if lowered.contains("graduat") || lowered.contains("confer") || lowered.contains("degree awarded") || lowered.contains("expected") {
            return true
        }
        return documentType == .cv && canonicalDegree(in: line) != nil
    }

    private func educationDate(in line: String, documentType: DocumentType) -> (display: String, normalized: String)? {
        let lowered = line.lowercased()
        if lowered.contains("confer") || lowered.contains("degree awarded") || lowered.contains("graduat") {
            return fullDate(in: line) ?? lastYearMonth(in: line)
        }
        if documentType == .cv {
            // Education ranges normally place the graduation/expected date last.
            return lastYearMonth(in: line)
        }
        return fullDate(in: line) ?? yearMonth(in: line)
    }

    private func isEducationContext(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("university") || lowered.contains("college") || lowered.contains("degree") || lowered.contains("education") || lowered.contains("major")
    }

    private func institution(in line: String) -> String? {
        capture(#"\b([A-Z][A-Za-z&.'’\- ]{1,60}?(?:University|College|Institute(?: of Technology)?))\b"#, in: line)
    }

    private func major(in line: String) -> String? {
        let patterns = [
            #"(?i)\b(?:major(?:\s+in)?|department\s+of)\s*[:\-]?\s*([A-Za-z][A-Za-z&'’ \-]{1,45})"#,
            #"(?i)\b(?:b\.?\s*s\.?|bachelor\s+of\s+science|m\.?\s*s\.?|master\s+of\s+science)\s+in\s+([A-Za-z][A-Za-z&'’ \-]{1,45})"#
        ]
        for pattern in patterns {
            if var result = capture(pattern, in: line) {
                result = result.components(separatedBy: "·").first ?? result
                result = result.components(separatedBy: ",").first ?? result
                result = result.replacingOccurrences(of: #"(?i)\s+(?:19|20)\d{2}.*$"#, with: "", options: .regularExpression)
                return result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func normalizeAcademicField(_ value: String) -> String {
        normalizeText(
            value.replacingOccurrences(of: #"(?i)\b(?:department|major|of|in|the)\b"#, with: " ", options: .regularExpression)
        )
    }

    private func gpa(in line: String) -> (value: String, normalized: String)? {
        let lowered = line.lowercased()
        if ["major gpa", "term gpa", "semester gpa", "minimum gpa", "required gpa"].contains(where: { lowered.contains($0) }) {
            return nil
        }
        guard let value = capture(#"(?i)\b(?:cumulative\s+)?GPA\s*[:=]?\s*(\d(?:\.\d{1,3})?)"#, in: line) else {
            return nil
        }
        let scale = capture(#"(?i)\b(?:cumulative\s+)?GPA\s*[:=]?\s*\d(?:\.\d{1,3})?\s*(?:/|out\s+of)\s*(\d(?:\.\d{1,2})?)"#, in: line)
        let normalizedValue = normalizeDecimal(value)
        let normalizedScale = scale.map(normalizeDecimal)
        return (
            scale.map { "\(value) / \($0)" } ?? value,
            normalizedScale.map { "\(normalizedValue)/\($0)" } ?? normalizedValue
        )
    }

    private func normalizeDecimal(_ value: String) -> String {
        NSDecimalNumber(string: value, locale: Locale(identifier: "en_US_POSIX")).stringValue
    }

    private func englishScore(in line: String) -> String? {
        let patterns = [
            #"(?i)\b(?:TOEFL(?:\s+iBT)?|IELTS).*?(?:total\s+score|overall\s+band|overall|score)\s*[:=]?\s*(\d{1,3}(?:\.\d)?)\b"#,
            #"(?i)\b(?:total\s+score|overall\s+band|overall)\s*[:=]?\s*(\d{1,3}(?:\.\d)?)\b"#
        ]
        return patterns.lazy.compactMap { capture($0, in: line) }.first
    }

    private func testDate(in line: String) -> (display: String, normalized: String)? {
        guard line.range(of: #"(?i)test\s+date|date\s+of\s+test|exam\s+date"#, options: .regularExpression) != nil else {
            return nil
        }
        return fullDate(in: line) ?? yearMonth(in: line)
    }

    private func yearMonth(in line: String) -> (display: String, normalized: String)? {
        let months = monthMap
        if let match = captures(#"(?i)\b(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.?\s+(?:\d{1,2},?\s+)?((?:19|20)\d{2})\b"#, in: line),
           match.count >= 2,
           let month = months[match[0].prefix(3).uppercased()] {
            return ("\(match[1])-\(String(format: "%02d", month))", "\(match[1])-\(String(format: "%02d", month))")
        }
        if let match = captures(#"\b((?:19|20)\d{2})[./\-](0?[1-9]|1[0-2])(?:[./\-]\d{1,2})?\b"#, in: line), match.count >= 2 {
            let normalized = "\(match[0])-\(String(format: "%02d", Int(match[1]) ?? 0))"
            return (normalized, normalized)
        }
        if let year = capture(#"\b((?:19|20)\d{2})\b"#, in: line) {
            return (year, year)
        }
        return nil
    }

    private func lastYearMonth(in line: String) -> (display: String, normalized: String)? {
        let textualPattern = #"(?i)\b(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.?\s+(?:\d{1,2},?\s+)?((?:19|20)\d{2})\b"#
        let numericPattern = #"\b((?:19|20)\d{2})[./\-](0?[1-9]|1[0-2])(?:[./\-]\d{1,2})?\b"#
        var candidates: [(location: Int, value: (display: String, normalized: String))] = []

        if let regex = try? NSRegularExpression(pattern: textualPattern) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in regex.matches(in: line, range: range) {
                guard let monthRange = Range(match.range(at: 1), in: line),
                      let yearRange = Range(match.range(at: 2), in: line),
                      let month = monthMap[String(line[monthRange]).prefix(3).uppercased()] else { continue }
                let year = String(line[yearRange])
                let normalized = "\(year)-\(String(format: "%02d", month))"
                candidates.append((match.range.location, (normalized, normalized)))
            }
        }

        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in regex.matches(in: line, range: range) {
                guard let yearRange = Range(match.range(at: 1), in: line),
                      let monthRange = Range(match.range(at: 2), in: line) else { continue }
                let year = String(line[yearRange])
                let month = Int(line[monthRange]) ?? 0
                let normalized = "\(year)-\(String(format: "%02d", month))"
                candidates.append((match.range.location, (normalized, normalized)))
            }
        }

        if let last = candidates.max(by: { $0.location < $1.location })?.value { return last }
        if let year = capture(#"\b((?:19|20)\d{2})\b"#, in: line) { return (year, year) }
        return nil
    }

    private func fullDate(in line: String) -> (display: String, normalized: String)? {
        if let match = captures(#"(?i)\b(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.?\s+(\d{1,2}),?\s+((?:19|20)\d{2})\b"#, in: line),
           match.count >= 3,
           let month = monthMap[match[0].prefix(3).uppercased()] {
            let normalized = "\(match[2])-\(String(format: "%02d", month))-\(String(format: "%02d", Int(match[1]) ?? 0))"
            return (normalized, normalized)
        }
        if let match = captures(#"\b((?:19|20)\d{2})[./\-](0?[1-9]|1[0-2])[./\-](0?[1-9]|[12]\d|3[01])\b"#, in: line), match.count >= 3 {
            let normalized = "\(match[0])-\(String(format: "%02d", Int(match[1]) ?? 0))-\(String(format: "%02d", Int(match[2]) ?? 0))"
            return (normalized, normalized)
        }
        return nil
    }

    private var monthMap: [String: Int] {
        ["JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
         "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12]
    }

    private func nameOrderCandidates(_ value: String) -> Set<String> {
        let tokens = value.uppercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        return [tokens.joined(), tokens.reversed().joined()]
    }

    private func capture(_ pattern: String, in value: String) -> String? {
        captures(pattern, in: value)?.first
    }

    private func captures(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) else {
            return nil
        }
        var values: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: value) else { continue }
            values.append(String(value[range]))
        }
        return values.isEmpty ? nil : values
    }
}

enum NameComparison: Equatable {
    case exact
    case plausible
    case different
}
