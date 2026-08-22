import Foundation

enum DemoData {
    static let referenceDate = Date(timeIntervalSince1970: 1_787_392_800)

    static let workspace = ApplicationWorkspace(
        school: "MIT",
        program: "Electrical Engineering & Computer Science",
        degree: "PhD",
        intake: "Fall 2027",
        applicantName: "Jiyoon Kim",
        status: .needsReview,
        createdAt: referenceDate.addingTimeInterval(-86400 * 12),
        lastAuditedAt: referenceDate.addingTimeInterval(-60 * 18),
        isSample: true
    )

    static let documents: [DocumentItem] = [
        DocumentItem(
            type: .cv,
            filename: "JiyoonKim_CV.pdf",
            pageCount: 2,
            sizeInBytes: 428_300,
            uploadedAt: referenceDate.addingTimeInterval(-3600),
            isSample: true
        ),
        DocumentItem(
            type: .sop,
            filename: "JiyoonKim_SOP.pdf",
            pageCount: 2,
            sizeInBytes: 312_840,
            uploadedAt: referenceDate.addingTimeInterval(-3500),
            isSample: true
        ),
        DocumentItem(
            type: .transcript,
            filename: "KoreaUniversity_Transcript.pdf",
            pageCount: 3,
            sizeInBytes: 1_206_442,
            uploadedAt: referenceDate.addingTimeInterval(-3400),
            isSample: true
        ),
        DocumentItem(
            type: .englishScore,
            filename: "TOEFL_Score_Report.pdf",
            pageCount: 1,
            sizeInBytes: 584_210,
            uploadedAt: referenceDate.addingTimeInterval(-3300),
            isSample: true
        ),
        DocumentItem(
            type: .requirements,
            filename: "MIT_EECS_Admissions_2027.pdf",
            pageCount: 8,
            sizeInBytes: 842_104,
            uploadedAt: referenceDate.addingTimeInterval(-3200),
            isSample: true
        )
    ]

    static func revisedSOPDocument() -> DocumentItem {
        DocumentItem(
            type: .sop,
            filename: "JiyoonKim_SOP_revised.pdf",
            pageCount: 1,
            sizeInBytes: 1_248,
            processingStatus: .ready,
            isSample: true
        )
    }

    static let findings: [AuditFinding] = [
        AuditFinding(
            status: .blocked,
            category: .target,
            title: "SOP에 이전 지원 프로그램명이 남아 있어요",
            summary: "현재 지원 목표는 MIT EECS이지만 SOP 첫 문단에는 Stanford Computer Science가 언급되어 있습니다.",
            action: "SOP의 목표 학교와 프로그램명을 수정한 뒤 파일을 교체하고 다시 검수하세요.",
            evidences: [
                EvidenceRef(
                    documentName: "JiyoonKim_SOP.pdf",
                    documentType: .sop,
                    page: 1,
                    excerpt: "I am applying to the Stanford Computer Science PhD program to pursue research in…",
                    fieldLabel: "SOP에 적힌 목표"
                ),
                EvidenceRef(
                    documentName: "MIT_EECS_Admissions_2027.pdf",
                    documentType: .requirements,
                    page: 1,
                    excerpt: "Graduate application for the MIT EECS doctoral program, Fall 2027 entry",
                    fieldLabel: "현재 지원 목표"
                )
            ]
        ),
        AuditFinding(
            status: .blocked,
            category: .education,
            title: "졸업 시기가 두 문서에서 달라요",
            summary: "CV에는 2025년 2월 졸업으로, 성적표에는 2025년 8월 학위 수여로 표시되어 있습니다.",
            action: "실제 학위 수여일을 확인하고 CV의 Education 항목과 원서 입력값을 동일하게 맞추세요.",
            evidences: [
                EvidenceRef(
                    documentName: "JiyoonKim_CV.pdf",
                    documentType: .cv,
                    page: 1,
                    excerpt: "B.S. in Computer Science · Korea University · Feb 2025",
                    fieldLabel: "CV 졸업일"
                ),
                EvidenceRef(
                    documentName: "KoreaUniversity_Transcript.pdf",
                    documentType: .transcript,
                    page: 1,
                    excerpt: "Degree conferred: Bachelor of Science · August 22, 2025",
                    fieldLabel: "성적표 학위 수여일"
                )
            ]
        ),
        AuditFinding(
            status: .humanReview,
            category: .identity,
            title: "영문 이름 표기를 직접 확인해 주세요",
            summary: "CV의 ‘Jiyoon Kim’과 성적표의 ‘KIM, JI YOON’이 같은 사람인지 자동으로 확정하지 않았습니다.",
            action: "여권의 영문 이름을 기준으로 원서와 모든 지원 서류의 표기를 확인하세요.",
            evidences: [
                EvidenceRef(
                    documentName: "JiyoonKim_CV.pdf",
                    documentType: .cv,
                    page: 1,
                    excerpt: "JIYOON KIM",
                    fieldLabel: "CV 이름"
                ),
                EvidenceRef(
                    documentName: "KoreaUniversity_Transcript.pdf",
                    documentType: .transcript,
                    page: 1,
                    excerpt: "Student: KIM, JI YOON",
                    fieldLabel: "성적표 이름"
                )
            ]
        ),
        AuditFinding(
            status: .humanReview,
            category: .score,
            title: "GPA 기준 척도가 명시되지 않았어요",
            summary: "성적표에서 누적 GPA 3.82는 확인했지만 만점 기준을 읽을 수 없어 자동 비교에서 제외했습니다.",
            action: "공식 성적표의 grading scale 페이지 또는 학교 설명을 확인하세요. 임의 환산은 하지 마세요.",
            evidences: [
                EvidenceRef(
                    documentName: "KoreaUniversity_Transcript.pdf",
                    documentType: .transcript,
                    page: 3,
                    excerpt: "Cumulative GPA: 3.82 · Grading scale: not stated",
                    fieldLabel: "누적 GPA"
                )
            ]
        ),
        AuditFinding(
            status: .ready,
            category: .completeness,
            title: "기본 대조 서류 4종이 준비됐어요",
            summary: "CV, SOP, 성적표, 공인영어성적 파일을 확인했습니다. 조건부 제출 항목은 별도로 확인해야 합니다.",
            action: "각 문서의 세부 검수 결과를 이어서 확인하세요.",
            evidences: [
                EvidenceRef(
                    documentName: "지원 서류 묶음",
                    documentType: .other,
                    excerpt: "CV 1 · SOP 1 · Transcript 1 · English score 1",
                    fieldLabel: "업로드 현황"
                )
            ]
        ),
        AuditFinding(
            status: .ready,
            category: .score,
            title: "TOEFL 점수와 시험일을 확인했어요",
            summary: "총점 108점, 시험일 2026년 10월 12일이 영어성적표에서 확인됩니다.",
            action: "지원 마감일 기준 유효기간은 공식 프로그램 안내에서 최종 확인하세요.",
            evidences: [
                EvidenceRef(
                    documentName: "TOEFL_Score_Report.pdf",
                    documentType: .englishScore,
                    page: 1,
                    excerpt: "Total Score 108 · Test Date October 12, 2026",
                    fieldLabel: "영어 시험"
                )
            ]
        ),
        AuditFinding(
            status: .ready,
            category: .target,
            title: "지원 학위 과정이 일치해요",
            summary: "워크스페이스와 공식 모집 안내에서 모두 PhD 과정으로 확인했습니다.",
            action: "추가 조치가 필요하지 않습니다.",
            evidences: [
                EvidenceRef(
                    documentName: "MIT_EECS_Admissions_2027.pdf",
                    documentType: .requirements,
                    page: 1,
                    excerpt: "Doctor of Philosophy (PhD) admissions",
                    fieldLabel: "모집 과정"
                )
            ]
        ),
        AuditFinding(
            status: .ready,
            category: .education,
            title: "학부 학교명과 전공명이 일치해요",
            summary: "CV와 성적표에서 Korea University, Computer Science를 동일하게 확인했습니다.",
            action: "추가 조치가 필요하지 않습니다.",
            evidences: [
                EvidenceRef(
                    documentName: "JiyoonKim_CV.pdf",
                    documentType: .cv,
                    page: 1,
                    excerpt: "Korea University · Computer Science",
                    fieldLabel: "CV 학력"
                ),
                EvidenceRef(
                    documentName: "KoreaUniversity_Transcript.pdf",
                    documentType: .transcript,
                    page: 1,
                    excerpt: "College of Informatics · Department of Computer Science",
                    fieldLabel: "성적표 학력"
                )
            ]
        )
    ]

    static let requirements: [RequirementItem] = [
        RequirementItem(
            title: "온라인 지원서",
            detail: "MIT Graduate Admissions 온라인 지원서를 마감 전 제출",
            scope: .university,
            status: .ready,
            sourceName: "MIT_EECS_Admissions_2027.pdf",
            page: 2
        ),
        RequirementItem(
            title: "CV / Resume",
            detail: "학력과 연구 경험을 포함한 최신 영문 CV 1부",
            scope: .program,
            status: .ready,
            sourceName: "MIT_EECS_Admissions_2027.pdf",
            page: 4,
            relatedDocumentType: .cv,
            requiredFileExtension: "pdf"
        ),
        RequirementItem(
            title: "Statement of Objectives",
            detail: "연구 관심사와 지원 동기를 포함한 영문 에세이 1부",
            scope: .program,
            status: .ready,
            sourceName: "MIT_EECS_Admissions_2027.pdf",
            page: 4,
            relatedDocumentType: .sop,
            maximumPages: 2,
            maximumWords: 1_000,
            requiredFileExtension: "pdf"
        ),
        RequirementItem(
            title: "추천서 3부",
            detail: "추천인이 시스템을 통해 직접 제출",
            scope: .program,
            status: .humanReview,
            sourceName: "MIT_EECS_Admissions_2027.pdf",
            page: 5,
            relatedDocumentType: .recommendation,
            necessity: .conditional,
            requiredCount: 3
        ),
        RequirementItem(
            title: "공식 성적표",
            detail: "지원 시 스캔본 허용, 합격 후 공식본 요청 가능",
            scope: .university,
            status: .ready,
            sourceName: "MIT_EECS_Admissions_2027.pdf",
            page: 3,
            relatedDocumentType: .transcript,
            requiredFileExtension: "pdf"
        ),
        RequirementItem(
            title: "영어 능력 증빙",
            detail: "TOEFL 또는 IELTS. 면제 조건은 별도 확인 필요",
            scope: .university,
            status: .humanReview,
            sourceName: "MIT_EECS_Admissions_2027.pdf",
            page: 6,
            relatedDocumentType: .englishScore,
            requiredFileExtension: "pdf",
            necessity: .conditional
        ),
        RequirementItem(
            title: "GRE",
            detail: "2027 입학 주기의 제출 정책이 안내 문서 간 명확하지 않음",
            scope: .program,
            status: .humanReview,
            sourceName: "MIT_EECS_Admissions_2027.pdf",
            page: 7,
            relatedDocumentType: .greScore,
            necessity: .conditional
        )
    ]

    static func extractions(for documents: [DocumentItem]) -> [UUID: ExtractedDocument] {
        var result: [UUID: ExtractedDocument] = [:]
        for document in documents where document.isSample {
            let pages: [String]
            switch document.type {
            case .cv:
                pages = [
                    """
                    JIYOON KIM
                    EDUCATION
                    B.S. in Computer Science · Korea University · Feb 2025
                    Cumulative GPA: 3.82
                    RESEARCH EXPERIENCE
                    Systems Research Lab · 2023–2025
                    """,
                    "Selected publications and projects"
                ]
            case .sop:
                if document.filename == "JiyoonKim_SOP_revised.pdf" {
                    pages = [
                        """
                        JIYOON KIM
                        STATEMENT OF PURPOSE · REVISED SAMPLE
                        I am applying to the MIT Electrical Engineering & Computer Science PhD program to pursue research in dependable systems.
                        My undergraduate research at Korea University focused on distributed storage.
                        """
                    ]
                } else {
                    pages = [
                        """
                        JIYOON KIM
                        STATEMENT OF PURPOSE
                        I am applying to the Stanford Computer Science PhD program to pursue research in dependable systems.
                        My undergraduate research at Korea University focused on distributed storage.
                        """,
                        "Research interests and proposed directions"
                    ]
                }
            case .transcript:
                pages = [
                    """
                    KOREA UNIVERSITY OFFICIAL TRANSCRIPT
                    Student: KIM, JI YOON
                    Institution: Korea University
                    Degree conferred: Bachelor of Science · August 22, 2025
                    Major: Computer Science
                    """,
                    "Course history",
                    "Cumulative GPA: 3.82 · Grading scale: not stated"
                ]
            case .englishScore:
                pages = [
                    """
                    TOEFL iBT SCORE REPORT
                    Name: JIYOON KIM
                    TOEFL iBT Total Score: 108
                    Test Date: October 12, 2026
                    """
                ]
            case .requirements:
                pages = [
                    "MIT EECS doctoral admissions · Fall 2027",
                    "Online application is required.",
                    "Upload a transcript in PDF format.",
                    "Statement of Objectives: PDF, maximum 2 pages and 1,000 words.",
                    "Three letters of recommendation are required.",
                    "TOEFL or IELTS score report is required unless an official exemption applies.",
                    "GRE policy: verify the current program guidance.",
                    "Application deadline and final notes."
                ]
            case .recommendation, .greScore, .writingSample, .portfolio,
                 .researchProposal, .degreeCertificate, .passportVisa, .other:
                pages = []
            }
            if !pages.isEmpty {
                result[document.id] = ExtractedDocument(pages: pages, provider: "합성 데모 데이터")
            }
        }
        return result
    }
}
