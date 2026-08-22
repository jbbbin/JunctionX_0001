import Foundation

struct AuditEngine {
    private let legacyCoreTypes: [DocumentType] = [.cv, .sop, .transcript, .englishScore]
    private let extractor = FactExtractor()

    func findings(
        for workspace: ApplicationWorkspace,
        documents: [DocumentItem],
        extracted: [UUID: ExtractedDocument],
        requirements: [RequirementItem] = [],
        identityExtractions: [UUID: ApplicantIdentityExtraction] = [:]
    ) -> [AuditFinding] {
        let facts = documents.compactMap { document -> DocumentFacts? in
            guard let content = extracted[document.id] else { return nil }
            return extractor.extract(document: document, content: content)
        }

        var results = completenessFindings(documents: documents, requirements: requirements)
        results.append(contentsOf: targetFindings(workspace: workspace, facts: facts))
        results.append(contentsOf: identityFindings(
            workspace: workspace,
            facts: facts,
            documents: documents,
            identityExtractions: identityExtractions
        ))
        results.append(contentsOf: educationFindings(facts: facts))
        results.append(contentsOf: scoreFindings(facts: facts))
        results.append(contentsOf: requirementConstraintFindings(requirements: requirements, documents: documents, extracted: extracted))
        results.append(contentsOf: verifiabilityFindings(documents: documents, extracted: extracted))

        return results.sorted { lhs, rhs in
            if lhs.status.rank == rhs.status.rank { return lhs.title < rhs.title }
            return lhs.status.rank < rhs.status.rank
        }
    }

    private func completenessFindings(
        documents: [DocumentItem],
        requirements: [RequirementItem]
    ) -> [AuditFinding] {
        let derivedTypes = RequirementAnalysisResult.requiredTypes(from: requirements)
        let types = derivedTypes.isEmpty ? legacyCoreTypes : derivedTypes
        return types.map { type in
            let expectedCount = max(
                RequirementAnalysisResult.requiredCount(for: type, in: requirements),
                1
            )
            let readyDocuments = documents.filter {
                $0.type == type && $0.processingStatus == .ready
            }
            let requirement = requirements.first {
                $0.relatedDocumentType == type && $0.effectiveNecessity != .informational
            }
            let requirementEvidence = requirement.map {
                EvidenceRef(
                    documentName: $0.sourceName,
                    documentType: .requirements,
                    page: $0.page,
                    excerpt: $0.detail,
                    fieldLabel: "공식 요건"
                )
            }

            if readyDocuments.count >= expectedCount, let document = readyDocuments.first {
                var evidences = [
                    EvidenceRef(
                        documentName: document.filename,
                        documentType: type,
                        page: 1,
                        excerpt: expectedCount > 1
                            ? "\(readyDocuments.count)부 업로드 및 분석 완료"
                            : (document.metadata.isEmpty ? "업로드 및 분석 완료" : document.metadata),
                        fieldLabel: "업로드 상태"
                    )
                ]
                if let requirementEvidence { evidences.append(requirementEvidence) }
                return AuditFinding(
                    status: .ready,
                    category: .completeness,
                    title: expectedCount > 1
                        ? "\(type.title) \(expectedCount)부를 확인했어요"
                        : "\(type.title) 파일을 확인했어요",
                    summary: "공식 모집요강에서 확인한 제출 수량만큼 분석 가능한 문서가 등록되어 있습니다.",
                    action: "세부 사실 대조 결과를 확인하세요.",
                    evidences: evidences
                )
            }
            let isConditional = requirement?.effectiveNecessity == .conditional
            var evidences = [
                EvidenceRef(
                    documentName: "지원 서류 묶음",
                    documentType: type,
                    excerpt: "\(readyDocuments.count)/\(expectedCount)부 · 분석 가능한 파일 부족",
                    fieldLabel: "업로드 상태"
                )
            ]
            if let requirementEvidence { evidences.append(requirementEvidence) }
            return AuditFinding(
                status: isConditional ? .humanReview : .blocked,
                category: .completeness,
                title: expectedCount > 1
                    ? "\(type.title) \(expectedCount)부가 필요해요"
                    : "\(type.title) 파일이 필요해요",
                summary: isConditional
                    ? "조건부 제출 또는 면제 여부를 먼저 확인해야 합니다. 현재 \(readyDocuments.count)/\(expectedCount)부가 준비되었습니다."
                    : "공식 모집요강 기준 \(expectedCount)부 중 \(readyDocuments.count)부만 분석할 수 있습니다.",
                action: isConditional
                    ? "공식 조건을 직접 확인하고 해당되면 파일을 추가하세요."
                    : "\(type.title) 파일을 추가한 뒤 다시 검수하세요.",
                evidences: evidences
            )
        }
    }

    private func targetFindings(workspace: ApplicationWorkspace, facts: [DocumentFacts]) -> [AuditFinding] {
        let targetFacts = facts.filter { $0.document.type == .sop || $0.document.type == .cv }
        let statements = targetFacts.flatMap(\.applicationStatements)
        var findings: [AuditFinding] = []

        if statements.isEmpty {
            if targetFacts.contains(where: { $0.document.type == .sop }) {
                findings.append(
                    AuditFinding(
                        status: .humanReview,
                        category: .target,
                        title: "목표 학교와 프로그램명을 직접 확인해 주세요",
                        summary: "SOP에서 지원 대상을 명시한 문장을 확실하게 찾지 못했습니다.",
                        action: "SOP 원문에서 현재 지원 학교, 프로그램, 학위 과정이 정확한지 확인하세요.",
                        evidences: targetFacts.filter { $0.document.type == .sop }.map {
                            EvidenceRef(
                                documentName: $0.document.filename,
                                documentType: .sop,
                                page: 1,
                                excerpt: "not_stated · 지원 문맥 자동 확인 불가",
                                fieldLabel: "목표 프로그램"
                            )
                        }
                    )
                )
            }
        } else {
            let schoolAliases = aliases(for: workspace.school)
            let programAliases = aliases(for: workspace.program)
            let matchingStatement = statements.first { statement in
                containsAny(statement, aliases: schoolAliases)
                    && containsAny(statement, aliases: programAliases)
            }
            let conflictingStatement = statements.first { statement in
                let schoolMatches = containsAny(statement, aliases: schoolAliases)
                let programMatches = containsAny(statement, aliases: programAliases)
                return !(schoolMatches && programMatches) && containsSpecificTargetReference(statement.value)
            }

            if let conflictingStatement {
                var evidences = [conflictingStatement.evidence(label: "다른 지원 대상 흔적")]
                if let matchingStatement { evidences.insert(matchingStatement.evidence(label: "현재 지원 대상"), at: 0) }
                findings.append(
                    AuditFinding(
                        status: .blocked,
                        category: .target,
                        title: "지원 문서에 다른 학교 또는 프로그램 흔적이 남아 있어요",
                        summary: "현재 목표와 다른 구체적인 지원 대상 문장이 함께 발견되었습니다.",
                        action: "표시된 문장을 원본에서 확인하고 이전 지원 학교·프로그램명을 제거한 뒤 다시 검수하세요.",
                        evidences: evidences
                    )
                )
            } else if let matchingStatement {
                findings.append(
                    AuditFinding(
                        status: .ready,
                        category: .target,
                        title: "목표 학교와 프로그램명이 일치해요",
                        summary: "지원 문맥에서 \(workspace.school) · \(workspace.program) 표기를 확인했습니다.",
                        action: "자동 확인 결과와 함께 원문의 공식 명칭을 최종 점검하세요.",
                        evidences: [matchingStatement.evidence(label: "지원 문서의 목표")]
                    )
                )
            } else {
                let observed = statements[0]
                let schoolMatched = statements.contains { containsAny($0, aliases: schoolAliases) }
                let programMatched = statements.contains { containsAny($0, aliases: programAliases) }
                let missingPart = schoolMatched ? "프로그램" : (programMatched ? "학교" : "학교와 프로그램")
                findings.append(
                    AuditFinding(
                        status: containsSpecificTargetReference(observed.value) ? .blocked : .humanReview,
                        category: .target,
                        title: containsSpecificTargetReference(observed.value)
                            ? "지원 문서의 목표 학교 또는 프로그램이 달라요"
                            : "목표 학교와 프로그램명을 직접 확인해 주세요",
                        summary: "현재 목표는 \(workspace.school) · \(workspace.program)이지만 지원 문맥에서 \(missingPart)을 확정하지 못했습니다.",
                        action: "해당 문장을 원본에서 확인하고 정확한 학교·프로그램명이 명시되어 있는지 점검하세요.",
                        evidences: [observed.evidence(label: "감지된 지원 문맥")]
                    )
                )
            }
        }

        let degreeFacts = targetFacts.flatMap(\.targetDegrees)
        if !degreeFacts.isEmpty {
            let expected = extractor.canonicalDegree(in: workspace.degree) ?? workspace.degree
            if let conflicting = degreeFacts.first(where: { $0.normalized != expected }) {
                findings.append(
                    AuditFinding(
                        status: .blocked,
                        category: .target,
                        title: "지원 학위 과정이 현재 목표와 달라요",
                        summary: "워크스페이스는 \(expected)이지만 지원 문서에서는 \(conflicting.value) 표기를 확인했습니다.",
                        action: "지원하려는 학위 과정과 SOP의 표현을 일치시키세요.",
                        evidences: [conflicting.evidence(label: "문서의 학위 과정")]
                    )
                )
            } else if let confirmed = degreeFacts.first {
                findings.append(
                    AuditFinding(
                        status: .ready,
                        category: .target,
                        title: "지원 학위 과정이 일치해요",
                        summary: "워크스페이스와 지원 문서에서 모두 \(expected) 과정으로 확인했습니다.",
                        action: "추가 조치가 필요하지 않습니다.",
                        evidences: [confirmed.evidence(label: "문서의 학위 과정")]
                    )
                )
            }
        } else if targetFacts.contains(where: { $0.document.type == .sop }) {
            findings.append(
                AuditFinding(
                    status: .humanReview,
                    category: .target,
                    title: "지원 학위 과정을 문서에서 확인하지 못했어요",
                    summary: "SOP의 지원 문맥에서 \(workspace.degree) 표기를 확실하게 추출하지 못했습니다.",
                    action: "학교·프로그램명뿐 아니라 학위 과정도 정확히 적혀 있는지 직접 확인하세요.",
                    evidences: targetFacts.filter { $0.document.type == .sop }.map {
                        EvidenceRef(
                            documentName: $0.document.filename,
                            documentType: .sop,
                            page: 1,
                            excerpt: "not_stated · 학위 과정 자동 확인 불가",
                            fieldLabel: "학위 과정"
                        )
                    }
                )
            )
        }
        return findings
    }

    private func identityFindings(
        workspace: ApplicationWorkspace,
        facts: [DocumentFacts],
        documents: [DocumentItem],
        identityExtractions: [UUID: ApplicantIdentityExtraction]
    ) -> [AuditFinding] {
        let identityTypes: Set<DocumentType> = [
            .cv, .sop, .transcript, .englishScore, .degreeCertificate, .passportVisa
        ]
        let coreFacts = facts.filter { identityTypes.contains($0.document.type) }
        let agentNames = agentIdentityFacts(
            documents: documents,
            extractions: identityExtractions,
            value: \.fullName,
            page: \.namePage,
            evidence: \.nameEvidence,
            label: "Agent 추출 이름"
        )
        let agentDocumentIDsWithName = Set(agentNames.map(\.documentName))
        let names = agentNames + coreFacts
            .filter { !agentDocumentIDsWithName.contains($0.document.filename) }
            .compactMap { $0.names.first }
        var findings: [AuditFinding] = []
        let expectedName = workspace.isSample && !workspace.applicantName.isEmpty
            ? workspace.applicantName
            : ApplicantProfile.current.legalName
        let profileNameEvidence = profileEvidence(value: expectedName, label: "앱 사용자 기준 이름")

        if !names.isEmpty {
            let comparisons = names.map { extractor.nameComparison(expectedName, $0.value) }
            if comparisons.contains(where: { $0 == .different }) {
                findings.append(
                    AuditFinding(
                        status: .blocked,
                        category: .identity,
                        title: "문서의 영문 이름이 앱 사용자 정보와 달라요",
                        summary: "앱 기준 이름(\(expectedName))과 다른 이름 표기가 발견되었습니다.",
                        action: "여권 영문 이름을 기준으로 원서와 모든 지원 서류의 이름을 수정하세요.",
                        evidences: [profileNameEvidence] + names.map { $0.evidence(label: "\($0.documentType.shortTitle) 이름") }
                    )
                )
            } else if comparisons.contains(where: { $0 == .plausible }) {
                findings.append(
                    AuditFinding(
                        status: .humanReview,
                        category: .identity,
                        title: "영문 이름의 순서와 띄어쓰기를 확인해 주세요",
                        summary: "앱 기준 이름과 같은 사람일 가능성은 있지만 성·이름 순서 또는 음절 띄어쓰기가 다릅니다.",
                        action: "여권 표기와 각 지원 서류의 이름이 허용되는 형식인지 직접 확인하세요.",
                        evidences: [profileNameEvidence] + names.map { $0.evidence(label: "\($0.documentType.shortTitle) 이름") }
                    )
                )
            } else {
                findings.append(
                    AuditFinding(
                        status: .ready,
                        category: .identity,
                        title: "영문 이름이 앱 사용자 정보와 일치해요",
                        summary: "업로드된 문서에서 앱 기준 영문 이름을 확인했습니다.",
                        action: "여권 원본과도 최종 대조하세요.",
                        evidences: [profileNameEvidence] + names.map { $0.evidence(label: "\($0.documentType.shortTitle) 이름") }
                    )
                )
            }
        } else if coreFacts.count >= 2 {
            findings.append(
                AuditFinding(
                    status: .humanReview,
                    category: .identity,
                    title: "영문 이름을 충분히 대조하지 못했어요",
                    summary: "두 개 이상의 문서에서 이름 필드를 확실하게 추출하지 못했습니다.",
                    action: "여권 기준 이름을 각 문서에서 직접 확인하세요.",
                    evidences: coreFacts.map {
                        EvidenceRef(
                            documentName: $0.document.filename,
                            documentType: $0.document.type,
                            excerpt: "not_stated · 이름 자동 추출 불가",
                            fieldLabel: "영문 이름"
                        )
                    }
                )
            )
        }

        if names.count >= 2 {
            let missingNameSources = coreFacts.filter { $0.names.isEmpty }
            if !missingNameSources.isEmpty {
                findings.append(
                    AuditFinding(
                        status: .humanReview,
                        category: .identity,
                        title: "일부 문서에서 영문 이름을 확인하지 못했어요",
                        summary: "이름이 확인된 문서끼리는 대조했지만 모든 핵심 문서의 이름 표기를 검증하지는 못했습니다.",
                        action: "여권 표기를 기준으로 이름이 추출되지 않은 문서를 직접 확인하세요.",
                        evidences: missingNameSources.map {
                            EvidenceRef(
                                documentName: $0.document.filename,
                                documentType: $0.document.type,
                                excerpt: "not_stated · 이름 자동 추출 불가",
                                fieldLabel: "영문 이름"
                            )
                        }
                    )
                )
            }
        }

        if !workspace.isSample {
            let emails = agentIdentityFacts(
                documents: documents,
                extractions: identityExtractions,
                value: \.email,
                page: \.emailPage,
                evidence: \.emailEvidence,
                label: "Agent 추출 이메일"
            )
            if !emails.isEmpty {
                let expectedEmail = ApplicantProfile.current.email
                let isMismatch = emails.contains {
                    normalizedEmail($0.value) != normalizedEmail(expectedEmail)
                }
                findings.append(
                    AuditFinding(
                        status: isMismatch ? .blocked : .ready,
                        category: .identity,
                        title: isMismatch
                            ? "문서의 이메일이 앱 사용자 정보와 달라요"
                            : "이메일이 앱 사용자 정보와 일치해요",
                        summary: isMismatch
                            ? "앱 기준 이메일(\(expectedEmail))과 다른 이메일 표기가 발견되었습니다."
                            : "업로드된 문서에서 앱 기준 이메일을 확인했습니다.",
                        action: isMismatch
                            ? "원서와 제출 서류의 이메일을 앱 사용자 정보 기준으로 수정하세요."
                            : "추가 조치가 필요하지 않습니다.",
                        evidences: [profileEvidence(value: expectedEmail, label: "앱 사용자 기준 이메일")]
                            + emails.map { $0.evidence(label: "\($0.documentType.shortTitle) 이메일") }
                    )
                )
            }
        }

        let birthDates = facts.flatMap(\.birthDates)
        if birthDates.count >= 2 {
            let uniqueDates = Set(birthDates.map(\.normalized))
            let status: ReviewStatus = uniqueDates.count == 1 ? .ready : .blocked
            findings.append(
                AuditFinding(
                    status: status,
                    category: .identity,
                    title: status == .ready ? "생년월일이 문서에서 일치해요" : "생년월일이 문서마다 달라요",
                    summary: status == .ready ? "민감값을 마스킹한 상태로 일치 여부만 확인했습니다." : "서로 다른 생년월일 표기가 발견되어 제출 전 수정이 필요합니다.",
                    action: status == .ready ? "여권 원본과도 최종 대조하세요." : "여권의 생년월일을 기준으로 잘못된 문서를 수정하세요.",
                    evidences: birthDates.map {
                        $0.evidence(label: "생년월일", maskedExcerpt: maskDate($0.normalized))
                    }
                )
            )
        } else if coreFacts.count >= 2 {
            findings.append(
                AuditFinding(
                    status: .humanReview,
                    category: .identity,
                    title: "생년월일을 문서 간 대조하지 못했어요",
                    summary: birthDates.isEmpty
                        ? "핵심 문서에서 생년월일 필드를 확실하게 추출하지 못했습니다."
                        : "생년월일은 한 문서에서만 확인되어 교차 검증할 수 없습니다.",
                    action: "생년월일이 기재된 제출 서류를 여권 원본과 직접 대조하세요.",
                    evidences: birthDates.isEmpty
                        ? coreFacts.prefix(2).map {
                            EvidenceRef(
                                documentName: $0.document.filename,
                                documentType: $0.document.type,
                                excerpt: "not_stated · 생년월일 자동 추출 불가",
                                fieldLabel: "생년월일"
                            )
                        }
                        : birthDates.map { $0.evidence(label: "생년월일", maskedExcerpt: maskDate($0.normalized)) }
                )
            )
        }
        return findings
    }

    private func agentIdentityFacts(
        documents: [DocumentItem],
        extractions: [UUID: ApplicantIdentityExtraction],
        value: KeyPath<ApplicantIdentityExtraction, String?>,
        page: KeyPath<ApplicantIdentityExtraction, Int?>,
        evidence: KeyPath<ApplicantIdentityExtraction, String?>,
        label: String
    ) -> [ObservedFact] {
        let supportedTypes: Set<DocumentType> = [.cv, .sop, .transcript, .englishScore, .degreeCertificate, .passportVisa]
        return documents.compactMap { document in
            guard supportedTypes.contains(document.type),
                  let extraction = extractions[document.id],
                  let rawValue = extraction[keyPath: value]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawValue.isEmpty
            else { return nil }
            return ObservedFact(
                value: rawValue,
                normalized: label.contains("이메일") ? normalizedEmail(rawValue) : extractor.normalizeName(rawValue),
                documentName: document.filename,
                documentType: document.type,
                page: extraction[keyPath: page],
                excerpt: extraction[keyPath: evidence] ?? rawValue
            )
        }
    }

    private func profileEvidence(value: String, label: String) -> EvidenceRef {
        EvidenceRef(
            documentName: "앱 사용자 프로필",
            documentType: .other,
            excerpt: value,
            fieldLabel: label
        )
    }

    private func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func educationFindings(facts: [DocumentFacts]) -> [AuditFinding] {
        let cv = facts.first { $0.document.type == .cv }
        let transcript = facts.first { $0.document.type == .transcript }
        guard cv != nil || transcript != nil else { return [] }
        var findings: [AuditFinding] = []

        if let cvDate = cv?.graduationDates.first, let transcriptDate = transcript?.graduationDates.first {
            if cvDate.normalized == transcriptDate.normalized {
                findings.append(readyComparison(
                    category: .education,
                    title: "졸업일이 두 문서에서 일치해요",
                    summary: "CV와 성적표에서 \(cvDate.value)로 확인했습니다.",
                    evidences: [cvDate.evidence(label: "CV 졸업일"), transcriptDate.evidence(label: "성적표 학위 수여일")]
                ))
            } else if datePrecisionOnlyDifference(cvDate.normalized, transcriptDate.normalized) {
                findings.append(
                    AuditFinding(
                        status: .humanReview,
                        category: .education,
                        title: "졸업일의 상세 표기를 확인해 주세요",
                        summary: "연도는 같지만 한 문서에는 월 또는 일이 명시되지 않았습니다.",
                        action: "공식 학위 수여일을 기준으로 원서와 CV를 확인하세요.",
                        evidences: [cvDate.evidence(label: "CV 졸업일"), transcriptDate.evidence(label: "성적표 학위 수여일")]
                    )
                )
            } else {
                findings.append(
                    AuditFinding(
                        status: .blocked,
                        category: .education,
                        title: "졸업 시기가 두 문서에서 달라요",
                        summary: "CV: \(cvDate.value) · 성적표: \(transcriptDate.value). 두 표기가 일치하지 않습니다.",
                        action: "실제 학위 수여일을 확인하고 CV와 원서 입력값을 동일하게 맞추세요.",
                        evidences: [cvDate.evidence(label: "CV 졸업일"), transcriptDate.evidence(label: "성적표 학위 수여일")]
                    )
                )
            }
        } else if cv != nil, transcript != nil {
            findings.append(
                AuditFinding(
                    status: .humanReview,
                    category: .education,
                    title: "졸업일을 두 문서에서 모두 확인하지 못했어요",
                    summary: "CV와 성적표 중 적어도 한 문서에서 졸업일 또는 학위 수여일을 찾지 못했습니다.",
                    action: "공식 학위 수여일을 기준으로 CV와 원서 입력값을 직접 대조하세요.",
                    evidences: missingEvidence(for: [cv, transcript], label: "졸업일")
                )
            )
        }

        if cv != nil, transcript != nil {
            findings.append(academicComparison(
                title: "학교명이 학력 문서에서 일치해요",
                mismatchTitle: "학교명이 학력 문서에서 달라요",
                label: "학교명",
                values: [cv?.institutions.first, transcript?.institutions.first],
                sources: [cv, transcript]
            ))

            findings.append(academicComparison(
                title: "전공명이 학력 문서에서 일치해요",
                mismatchTitle: "전공명이 학력 문서에서 달라요",
                label: "전공명",
                values: [cv?.majors.first, transcript?.majors.first],
                sources: [cv, transcript]
            ))

            findings.append(academicComparison(
                title: "이전 학위명이 문서에서 일치해요",
                mismatchTitle: "이전 학위명이 문서에서 달라요",
                label: "이전 학위",
                values: [cv?.educationDegrees.first, transcript?.educationDegrees.first],
                sources: [cv, transcript]
            ))
        }
        return findings
    }

    private func scoreFindings(facts: [DocumentFacts]) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        let gpas = facts.flatMap(\.gpas)
        let academicSources = facts.filter { $0.document.type == .cv || $0.document.type == .transcript }
        if !gpas.isEmpty {
            let scoreValues = Set(gpas.map { gpaParts($0.normalized).score })
            let statedScales = gpas.compactMap { gpaParts($0.normalized).scale }
            let scaleValues = Set(statedScales)
            if scoreValues.count > 1 {
                findings.append(
                    AuditFinding(
                        status: .blocked,
                        category: .score,
                        title: "GPA가 문서마다 달라요",
                        summary: "서로 다른 누적 GPA 값이 발견되었습니다.",
                        action: "공식 성적표 값을 기준으로 CV와 원서 입력값을 수정하세요. 임의 환산은 하지 마세요.",
                        evidences: gpas.map { $0.evidence(label: "GPA") }
                    )
                )
            } else if scaleValues.count > 1 {
                findings.append(
                    AuditFinding(
                        status: .blocked,
                        category: .score,
                        title: "GPA 만점 기준이 문서마다 달라요",
                        summary: "같은 GPA 숫자에 서로 다른 만점 척도가 표기되어 있습니다.",
                        action: "공식 성적표의 GPA와 만점 척도를 기준으로 CV와 원서 입력값을 확인하세요. 임의 환산은 하지 마세요.",
                        evidences: gpas.map { $0.evidence(label: "GPA / 만점") }
                    )
                )
            } else {
                findings.append(readyComparison(
                    category: .score,
                    title: "GPA 값을 확인했어요",
                    summary: "업로드된 문서에서 누적 GPA \(gpas[0].value)를 확인했습니다.",
                    evidences: gpas.map { $0.evidence(label: "GPA") }
                ))
            }
            if statedScales.count < gpas.count {
                findings.append(
                    AuditFinding(
                        status: .humanReview,
                        category: .score,
                        title: "GPA 기준 척도가 명시되지 않았어요",
                        summary: "GPA 값은 확인했지만 만점 기준을 자동으로 확인하지 못했습니다.",
                        action: "공식 grading scale을 확인하세요. UpCheck는 학점을 임의 환산하지 않습니다.",
                        evidences: [gpas[0].evidence(label: "누적 GPA")]
                    )
                )
            }

            if academicSources.count >= 2 {
                let missingSources = academicSources.filter { $0.gpas.isEmpty }
                if !missingSources.isEmpty {
                    findings.append(
                        AuditFinding(
                            status: .humanReview,
                            category: .score,
                            title: "GPA를 모든 학력 문서에서 대조하지 못했어요",
                            summary: "GPA 값은 확인했지만 CV와 성적표 중 일부에서는 확실하게 추출하지 못했습니다.",
                            action: "공식 성적표의 누적 GPA와 만점 척도를 기준으로 CV와 원서 값을 직접 확인하세요.",
                            evidences: missingSources.map {
                                EvidenceRef(
                                    documentName: $0.document.filename,
                                    documentType: $0.document.type,
                                    excerpt: "not_stated · 누적 GPA 자동 추출 불가",
                                    fieldLabel: "GPA"
                                )
                            }
                        )
                    )
                }
            }
        } else if academicSources.count >= 2 {
            findings.append(
                AuditFinding(
                    status: .humanReview,
                    category: .score,
                    title: "누적 GPA를 자동 확인하지 못했어요",
                    summary: "CV와 성적표에서 비교할 수 있는 누적 GPA 값을 확실하게 추출하지 못했습니다.",
                    action: "공식 성적표의 누적 GPA와 만점 척도를 직접 확인하세요. 임의 환산은 하지 마세요.",
                    evidences: academicSources.map {
                        EvidenceRef(
                            documentName: $0.document.filename,
                            documentType: $0.document.type,
                            excerpt: "not_stated · 누적 GPA 자동 추출 불가",
                            fieldLabel: "GPA"
                        )
                    }
                )
            )
        }

        if let english = facts.first(where: { $0.document.type == .englishScore }) {
            if let score = english.englishScores.first {
                if let date = english.testDates.first {
                    findings.append(readyComparison(
                        category: .score,
                        title: "영어 점수와 시험일을 확인했어요",
                        summary: "공인영어성적표에서 점수 \(score.value) · 시험일 \(date.value)를 확인했습니다.",
                        evidences: [score.evidence(label: "영어 시험 점수"), date.evidence(label: "시험일")]
                    ))
                } else {
                    findings.append(
                        AuditFinding(
                            status: .humanReview,
                            category: .score,
                            title: "영어 점수는 확인했지만 시험일을 찾지 못했어요",
                            summary: "점수 \(score.value)는 확인했지만 시험일과 유효기간을 자동으로 검증할 수 없습니다.",
                            action: "성적표 원문에서 시험일을 확인하고 지원 마감일 기준 유효기간을 직접 점검하세요.",
                            evidences: [score.evidence(label: "영어 시험 점수")]
                        )
                    )
                }
            } else {
                findings.append(
                    AuditFinding(
                        status: .humanReview,
                        category: .score,
                        title: "영어 시험 점수를 자동 확인하지 못했어요",
                        summary: "성적표 파일은 읽었지만 TOEFL 또는 IELTS 총점을 확실하게 추출하지 못했습니다.",
                        action: "점수와 시험일, 지원 마감일 기준 유효기간을 직접 확인하세요.",
                        evidences: [
                            EvidenceRef(
                                documentName: english.document.filename,
                                documentType: .englishScore,
                                page: 1,
                                excerpt: "not_stated · 점수 자동 추출 불가",
                                fieldLabel: "영어 시험"
                            )
                        ]
                    )
                )
            }
        }
        return findings
    }

    private func requirementConstraintFindings(
        requirements: [RequirementItem],
        documents: [DocumentItem],
        extracted: [UUID: ExtractedDocument]
    ) -> [AuditFinding] {
        var findings: [AuditFinding] = []

        for requirement in requirements {
            let requirementEvidence = EvidenceRef(
                documentName: requirement.sourceName,
                documentType: .requirements,
                page: requirement.page,
                excerpt: requirement.detail,
                fieldLabel: "공식 요건"
            )

            guard let type = requirement.relatedDocumentType else {
                if let keywords = supplementaryKeywords(for: requirement.title) {
                    let supplied = documents.contains { document in
                        guard document.processingStatus == .ready, document.type != .requirements else { return false }
                        let filename = document.filename.lowercased()
                        let content = extracted[document.id]?.text.lowercased() ?? ""
                        return keywords.contains {
                            containsRequirementKeyword($0, in: filename) || containsRequirementKeyword($0, in: content)
                        }
                    }
                    if !supplied || requirement.status == .humanReview {
                        let status: ReviewStatus = !supplied && requirement.status == .ready ? .blocked : .humanReview
                        findings.append(
                            AuditFinding(
                                status: status,
                                category: .completeness,
                                title: !supplied ? "\(requirement.title) 제출 여부를 확인해 주세요" : "\(requirement.title) 조건을 직접 확인해 주세요",
                                summary: !supplied
                                    ? "공식 모집요강에는 해당 항목이 있지만 대응하는 업로드 문서를 확인하지 못했습니다."
                                    : "대응 문서는 찾았지만 조건부·면제 여부를 자동으로 확정하지 않았습니다.",
                                action: "공식 모집요강과 지원 시스템에서 필수 여부와 제출 상태를 직접 확인하세요.",
                                evidences: [requirementEvidence]
                            )
                        )
                    }
                } else if requirement.status == .humanReview {
                    findings.append(requirementReviewFinding(requirement, evidence: requirementEvidence))
                }
                continue
            }

            guard let document = documents.first(where: { $0.type == type && $0.processingStatus == .ready }) else {
                // Requirement-derived completeness findings already report missing
                // files and quantities once per document type.
                continue
            }

            if requirement.status == .humanReview {
                findings.append(requirementReviewFinding(requirement, evidence: requirementEvidence))
            }

            var violations: [String] = []
            if let maximumPages = requirement.maximumPages, let pageCount = document.pageCount, pageCount > maximumPages {
                violations.append("\(pageCount)페이지 / 최대 \(maximumPages)페이지")
            }
            if let maximumWords = requirement.maximumWords, let content = extracted[document.id] {
                let count = content.text.split(whereSeparator: { $0.isWhitespace }).count
                if count > maximumWords { violations.append("\(count)단어 / 최대 \(maximumWords)단어") }
            }
            if let extensionName = requirement.requiredFileExtension {
                let currentExtension = document.filename.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
                if currentExtension != extensionName.lowercased() {
                    violations.append("파일 형식 .\(currentExtension.isEmpty ? "-" : currentExtension) / 요구 .\(extensionName)")
                }
            }
            guard !violations.isEmpty else { continue }
            findings.append(
                AuditFinding(
                    status: .blocked,
                    category: .format,
                    title: "\(type.shortTitle)이 공식 형식 요건을 벗어났어요",
                    summary: violations.joined(separator: " · "),
                    action: "공식 모집요강의 분량과 파일 형식에 맞게 수정한 뒤 교체하세요.",
                    evidences: [
                        EvidenceRef(
                            documentName: document.filename,
                            documentType: type,
                            excerpt: document.metadata.isEmpty ? "업로드 및 분석 완료" : document.metadata,
                            fieldLabel: "현재 파일"
                        ),
                        requirementEvidence
                    ]
                )
            )
        }
        return findings
    }

    private func verifiabilityFindings(documents: [DocumentItem], extracted: [UUID: ExtractedDocument]) -> [AuditFinding] {
        documents.compactMap { document in
            guard document.type.isApplicantDocument,
                  document.processingStatus != .parsing,
                  extracted[document.id] == nil,
                  !document.isSample else { return nil }
            return AuditFinding(
                status: .humanReview,
                category: .format,
                title: "\(document.type.shortTitle)의 텍스트를 직접 확인해 주세요",
                summary: "파일 메타데이터는 있지만 현재 세션에서 문서 사실을 읽을 수 없습니다.",
                action: "텍스트 레이어가 있는 PDF로 다시 추가하거나 원문을 직접 확인하세요.",
                evidences: [
                    EvidenceRef(
                        documentName: document.filename,
                        documentType: document.type,
                        excerpt: "not_stated · 자동 추출 불가",
                        fieldLabel: "추출 상태"
                    )
                ]
            )
        }
    }

    private func aliases(for value: String) -> Set<String> {
        let normalized = extractor.normalizeText(value)
        let words = value.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let stopwords = Set(["of", "the", "and", "at", "for"])
        let acronym = words
            .filter { !stopwords.contains($0.lowercased()) }
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        var values: Set<String> = [normalized]
        if acronym.count >= 2 { values.insert(acronym) }
        if normalized == "MASSACHUSETTSINSTITUTEOFTECHNOLOGY" { values.insert("MIT") }
        return Set(values.filter { $0.count >= 2 })
    }

    private func containsAny(_ fact: ObservedFact, aliases: Set<String>) -> Bool {
        aliases.contains { alias in
            if alias.count <= 4 {
                let escaped = NSRegularExpression.escapedPattern(for: alias)
                return fact.value.range(
                    of: "(?i)(?<![A-Z0-9])\(escaped)(?![A-Z0-9])",
                    options: .regularExpression
                ) != nil
            }
            return fact.normalized.contains(alias)
        }
    }

    private func containsSpecificTargetReference(_ value: String) -> Bool {
        if value.range(of: #"(?i)\b(?:university|college|institute(?:\s+of\s+technology)?|school\s+of)\b"#, options: .regularExpression) != nil {
            return true
        }

        let patterns = [
            #"(?i)(?:apply(?:ing)?|application|admission)\s+to\s+(?:the\s+)?(.{1,120}?)\s+(?:program|degree)\b"#,
            #"(?i)(?:target|intended)\s+program\s*[:\-]\s*(.{1,120})$"#
        ]
        let generic = Set([
            "a", "an", "the", "this", "that", "your", "our", "graduate", "graduates",
            "doctoral", "doctorate", "phd", "ph", "d", "master", "masters", "ms", "ma", "meng",
            "degree", "program", "programs", "several", "multiple"
        ])

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
                  let range = Range(match.range(at: 1), in: value) else { continue }
            let tokens = value[range]
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !generic.contains($0) }
            if !tokens.isEmpty { return true }
        }
        return false
    }

    private func datePrecisionOnlyDifference(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: "-")
        let right = rhs.split(separator: "-")
        let sharedCount = min(left.count, right.count)
        return left.count != right.count
            && sharedCount > 0
            && Array(left.prefix(sharedCount)) == Array(right.prefix(sharedCount))
    }

    private func academicComparison(
        title: String,
        mismatchTitle: String,
        label: String,
        values: [ObservedFact?],
        sources: [DocumentFacts?]
    ) -> AuditFinding {
        let present = values.compactMap { $0 }
        guard present.count == 2 else {
            let evidences = values.enumerated().compactMap { index, value -> EvidenceRef? in
                if let value { return value.evidence(label: label) }
                guard sources.indices.contains(index), let source = sources[index] else { return nil }
                return EvidenceRef(
                    documentName: source.document.filename,
                    documentType: source.document.type,
                    excerpt: "not_stated · \(label) 자동 추출 불가",
                    fieldLabel: label
                )
            }
            return AuditFinding(
                status: .humanReview,
                category: .education,
                title: "\(label)을 두 문서에서 모두 확인하지 못했어요",
                summary: "CV와 성적표 중 적어도 한 문서에서 \(label)을 확실하게 추출하지 못했습니다.",
                action: "공식 성적표를 기준으로 CV와 원서 입력값을 직접 대조하세요.",
                evidences: evidences
            )
        }

        let comparison = valuesComparison(present[0].normalized, present[1].normalized)
        return AuditFinding(
            status: comparison,
            category: .education,
            title: comparison == .ready ? title : (comparison == .blocked ? mismatchTitle : "\(label)의 상세 표기를 확인해 주세요"),
            summary: comparison == .ready
                ? "CV와 성적표에서 \(present[0].value)로 동일하게 확인했습니다."
                : (comparison == .blocked
                    ? "CV의 ‘\(present[0].value)’와 성적표의 ‘\(present[1].value)’가 일치하지 않습니다."
                    : "한 값이 다른 값에 포함되지만 동일한 사실이라고 자동 확정하지 않았습니다."),
            action: comparison == .ready ? "추가 조치가 필요하지 않습니다." : "공식 성적표를 기준으로 CV와 원서 입력값을 확인하세요.",
            evidences: present.map { $0.evidence(label: label) }
        )
    }

    private func valuesComparison(_ lhs: String, _ rhs: String) -> ReviewStatus {
        if lhs == rhs { return .ready }
        if min(lhs.count, rhs.count) >= 5, lhs.contains(rhs) || rhs.contains(lhs) { return .humanReview }
        return .blocked
    }

    private func gpaParts(_ normalized: String) -> (score: String, scale: String?) {
        let parts = normalized.split(separator: "/", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1] : nil)
    }

    private func supplementaryKeywords(for title: String) -> [String]? {
        let lowered = title.lowercased()
        if lowered.contains("추천") || lowered.contains("recommendation") { return ["recommendation", "reference", "추천"] }
        if lowered.contains("portfolio") || lowered.contains("포트폴리오") { return ["portfolio", "포트폴리오"] }
        if lowered.contains("gre") { return ["gre", "graduate record examination"] }
        return nil
    }

    private func containsRequirementKeyword(_ keyword: String, in value: String) -> Bool {
        if keyword.count <= 4, keyword.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            let escaped = NSRegularExpression.escapedPattern(for: keyword)
            return value.range(
                of: "(?i)(?<![A-Z0-9])\(escaped)(?![A-Z0-9])",
                options: .regularExpression
            ) != nil
        }
        return value.localizedCaseInsensitiveContains(keyword)
    }

    private func requirementReviewFinding(_ requirement: RequirementItem, evidence: EvidenceRef) -> AuditFinding {
        AuditFinding(
            status: .humanReview,
            category: .format,
            title: "\(requirement.title) 조건을 직접 확인해 주세요",
            summary: "모집요강의 조건부 표현이나 면제 여부를 문서 사실만으로 확정하지 않았습니다.",
            action: "공식 모집요강과 지원 시스템에서 본인에게 적용되는 조건을 확인하세요.",
            evidences: [evidence]
        )
    }

    private func missingEvidence(for facts: [DocumentFacts?], label: String) -> [EvidenceRef] {
        facts.compactMap { $0 }.map {
            EvidenceRef(
                documentName: $0.document.filename,
                documentType: $0.document.type,
                page: 1,
                excerpt: "not_stated · \(label) 자동 추출 불가",
                fieldLabel: label
            )
        }
    }

    private func readyComparison(
        category: AuditCategory,
        title: String,
        summary: String,
        evidences: [EvidenceRef]
    ) -> AuditFinding {
        AuditFinding(
            status: .ready,
            category: category,
            title: title,
            summary: summary,
            action: "추가 조치가 필요하지 않습니다.",
            evidences: evidences
        )
    }

    private func maskDate(_ date: String) -> String {
        let suffix = date.split(separator: "-").last.map(String.init) ?? "••"
        return "••••-••-\(suffix)"
    }
}
