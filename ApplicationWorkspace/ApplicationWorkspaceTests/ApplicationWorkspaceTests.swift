import Foundation
import CoreFoundation
import XCTest
@testable import ApplicationWorkspace

final class BrowserAddressResolverTests: XCTestCase {
    private let resolver = BrowserAddressResolver()

    func testResolvesHTTPSAddress() {
        let result = resolver.resolve("  https://careers.example.com/jobs?id=7  ")

        XCTAssertEqual(result?.absoluteString, "https://careers.example.com/jobs?id=7")
    }

    func testResolvesBareDomainWithHTTPS() {
        let result = resolver.resolve("careers.example.com/jobs")

        XCTAssertEqual(result?.absoluteString, "https://careers.example.com/jobs")
    }

    func testResolvesLocalhostWithHTTP() {
        let result = resolver.resolve("localhost:8080/preview")

        XCTAssertEqual(result?.absoluteString, "http://localhost:8080/preview")
    }

    func testTurnsKoreanTextIntoGoogleSearch() throws {
        let result = try XCTUnwrap(resolver.resolve("한국 장학금 모집 요강"))
        let components = try XCTUnwrap(URLComponents(url: result, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.path, "/search")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "한국 장학금 모집 요강")
    }

    func testRejectsBlankInput() {
        XCTAssertNil(resolver.resolve("  \n\t  "))
        XCTAssertNil(resolver.resolveWebAddress("  \n\t  "))
    }

    func testBlocksUnsafeSchemes() {
        for input in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,hello"] {
            XCTAssertNil(resolver.resolve(input), "Expected \(input) to be blocked")
            XCTAssertNil(resolver.resolveWebAddress(input), "Expected \(input) to be blocked for add flow")
        }
    }

    func testAddFlowRejectsGeneralSearchText() {
        XCTAssertNil(resolver.resolveWebAddress("장학금 지원 공고"))
    }
}

final class ApplicationItemTests: XCTestCase {
    func testDaysRemainingUsesFixedDateAndCalendarDayBoundaries() {
        let calendar = TestFixtures.seoulCalendar()
        let now = TestFixtures.date(year: 2026, month: 8, day: 22, hour: 23, calendar: calendar)

        let dDay = TestFixtures.application(
            title: "D-Day",
            deadline: TestFixtures.date(year: 2026, month: 8, day: 22, hour: 1, calendar: calendar)
        )
        let future = TestFixtures.application(
            title: "D-7",
            deadline: TestFixtures.date(year: 2026, month: 8, day: 29, hour: 9, calendar: calendar)
        )
        let expired = TestFixtures.application(
            title: "Expired",
            deadline: TestFixtures.date(year: 2026, month: 8, day: 21, hour: 23, calendar: calendar)
        )

        XCTAssertEqual(dDay.daysRemaining(relativeTo: now, calendar: calendar), 0)
        XCTAssertEqual(future.daysRemaining(relativeTo: now, calendar: calendar), 7)
        XCTAssertEqual(expired.daysRemaining(relativeTo: now, calendar: calendar), -1)
    }

    func testMissingDeadlineHasExplicitReviewState() {
        let application = TestFixtures.application(title: "마감 미정", deadline: nil)

        XCTAssertNil(application.daysRemaining())
        XCTAssertEqual(application.dDayText, "마감 확인 필요")
    }

    func testProgressCountsReadyDocumentsAndTreatsNoDocumentsAsComplete() {
        let documents = [
            TestFixtures.document(name: "A", isReady: true),
            TestFixtures.document(name: "B", isReady: true),
            TestFixtures.document(name: "C", isReady: false),
        ]
        let application = TestFixtures.application(documents: documents)
        let noDocuments = TestFixtures.application(documents: [])

        XCTAssertEqual(application.readyDocumentCount, 2)
        XCTAssertEqual(application.remainingTaskCount, 1)
        XCTAssertEqual(application.progress, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(application.progressPercent, 67)
        XCTAssertEqual(noDocuments.progress, 1)
        XCTAssertEqual(noDocuments.progressPercent, 100)
    }

    func testReadyToSubmitRequiresEligibilitySatisfiedRequirementsAndReadyDocuments() {
        var application = TestFixtures.application(
            eligibility: .eligible,
            requirements: [TestFixtures.requirement(title: "학력", state: .satisfied)],
            documents: [TestFixtures.document(name: "지원서", isReady: true)]
        )

        XCTAssertTrue(application.isReadyToSubmit)

        let knownDeadline = application.deadline
        application.deadline = nil
        XCTAssertFalse(application.isReadyToSubmit)
        XCTAssertEqual(application.nextAction, "마감일을 확인해 주세요")
        application.deadline = knownDeadline

        application.eligibility = .needsReview
        XCTAssertFalse(application.isReadyToSubmit)

        application.eligibility = .eligible
        application.requirements[0].state = .needsReview
        XCTAssertFalse(application.isReadyToSubmit)

        application.requirements[0].state = .satisfied
        application.requiredDocuments[0].isReady = false
        XCTAssertFalse(application.isReadyToSubmit)
    }

    func testNextActionPrioritizesBlockingRequirementThenReviewThenDocument() {
        var application = TestFixtures.application(
            requirements: [
                TestFixtures.requirement(title: "필수 학력", state: .unsatisfied),
                TestFixtures.requirement(title: "영어 성적", state: .needsReview),
            ],
            documents: [TestFixtures.document(name: "포트폴리오", preparationType: .write)]
        )

        XCTAssertEqual(application.nextAction, "필수 학력 조건을 다시 확인해 주세요")

        application.requirements[0].state = .satisfied
        XCTAssertEqual(application.nextAction, "영어 성적 조건을 확인해 주세요")

        application.requirements[1].state = .satisfied
        XCTAssertEqual(application.nextAction, "포트폴리오를 작성해 주세요")
    }

    func testNextActionDistinguishesRequestingFromWaitingForDocument() {
        var application = TestFixtures.application(
            documents: [
                TestFixtures.document(
                    name: "추천서",
                    preparationType: .request,
                    requestState: .notRequested
                ),
            ]
        )

        XCTAssertEqual(application.nextAction, "추천서를 요청해 주세요")

        application.requiredDocuments[0].requestState = .requested
        XCTAssertEqual(application.nextAction, "추천서 수령을 기다리고 있어요")
    }
}

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testSearchMatchesTitleOrganizationAndCategory() {
        let applications = [
            TestFixtures.application(title: "iOS Developer", organization: "Acme", category: .employment),
            TestFixtures.application(title: "미래 인재", organization: "한국장학재단", category: .scholarship),
            TestFixtures.application(title: "서울 해커톤", organization: "Junction", category: .competition),
        ]
        let viewModel = DashboardViewModel(store: TestFixtures.store(applications: applications))
        viewModel.showsAllApplications = true

        viewModel.searchText = "developer"
        XCTAssertEqual(viewModel.visibleApplications.map(\.title), ["iOS Developer"])

        viewModel.searchText = "장학재단"
        XCTAssertEqual(viewModel.visibleApplications.map(\.title), ["미래 인재"])

        viewModel.searchText = "공모전"
        XCTAssertEqual(viewModel.visibleApplications.map(\.title), ["서울 해커톤"])
    }

    func testUrgentFilterIncludesDayZeroAndSevenOnly() {
        let calendar = TestFixtures.seoulCalendar()
        let fixedNow = TestFixtures.date(year: 2026, month: 8, day: 22, hour: 12, calendar: calendar)
        let referenceDay = calendar.startOfDay(for: fixedNow)
        let applications = [
            TestFixtures.application(title: "Expired", deadline: calendar.date(byAdding: .day, value: -1, to: referenceDay)!),
            TestFixtures.application(title: "D-Day", deadline: referenceDay),
            TestFixtures.application(title: "D-7", deadline: calendar.date(byAdding: .day, value: 7, to: referenceDay)!),
            TestFixtures.application(title: "D-8", deadline: calendar.date(byAdding: .day, value: 8, to: referenceDay)!),
            TestFixtures.application(title: "Unknown", deadline: nil),
            TestFixtures.application(
                title: "Submitted D-3",
                deadline: calendar.date(byAdding: .day, value: 3, to: referenceDay)!,
                status: .submitted
            ),
        ]
        let viewModel = DashboardViewModel(
            store: TestFixtures.store(applications: applications),
            now: { fixedNow },
            calendar: calendar
        )

        viewModel.configure(for: .urgent)

        XCTAssertEqual(Set(viewModel.visibleApplications.map(\.title)), Set(["D-Day", "D-7"]))
    }

    func testMissingDeadlineSortsLastAndIsNotNearest() throws {
        let calendar = TestFixtures.seoulCalendar()
        let fixedNow = TestFixtures.date(year: 2026, month: 8, day: 22, calendar: calendar)
        let dated = TestFixtures.application(
            title: "날짜 있음",
            deadline: calendar.date(byAdding: .day, value: 3, to: fixedNow)
        )
        let undated = TestFixtures.application(title: "날짜 없음", deadline: nil)
        let viewModel = DashboardViewModel(
            store: TestFixtures.store(applications: [undated, dated]),
            now: { fixedNow },
            calendar: calendar
        )
        viewModel.showAll()

        XCTAssertEqual(viewModel.filteredApplications.map(\.title), ["날짜 있음", "날짜 없음"])
        XCTAssertEqual(viewModel.nearestApplication?.id, dated.id)
        XCTAssertEqual(viewModel.formattedShortDate(nil), "확인 필요")
    }

    func testDashboardLimitsRowsToFourAndShowAllRevealsEveryApplication() {
        let calendar = TestFixtures.seoulCalendar()
        let applications = (1...6).map { index in
            TestFixtures.application(
                title: "지원 \(index)",
                deadline: TestFixtures.date(year: 2099, month: 1, day: index, calendar: calendar)
            )
        }
        let viewModel = DashboardViewModel(store: TestFixtures.store(applications: applications))

        viewModel.configure(for: .dashboard)
        XCTAssertEqual(viewModel.filteredApplications.count, 6)
        XCTAssertEqual(viewModel.visibleApplications.count, 4)

        viewModel.showAll()
        XCTAssertEqual(viewModel.visibleApplications.count, 6)
        XCTAssertEqual(viewModel.sectionTitle, "전체 지원")
    }
}

@MainActor
final class AppStoreTests: XCTestCase {
    func testDocumentRequestTransitionsFromRequestedToReceivedAndBackToNotRequested() throws {
        let applicationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let documentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let application = TestFixtures.application(
            id: applicationID,
            documents: [
                TestFixtures.document(
                    id: documentID,
                    name: "추천서",
                    preparationType: .request,
                    requestState: .notRequested
                ),
            ]
        )
        let store = TestFixtures.store(applications: [application])

        store.markDocumentRequested(applicationID: applicationID, documentID: documentID)
        var document = try XCTUnwrap(store.application(id: applicationID)?.requiredDocuments.first)
        XCTAssertEqual(document.requestState, .requested)
        XCTAssertFalse(document.isReady)
        XCTAssertEqual(store.application(id: applicationID)?.nextAction, "추천서 수령을 기다리고 있어요")

        store.markDocumentReceived(applicationID: applicationID, documentID: documentID)
        document = try XCTUnwrap(store.application(id: applicationID)?.requiredDocuments.first)
        XCTAssertEqual(document.requestState, .received)
        XCTAssertTrue(document.isReady)
        XCTAssertTrue(try XCTUnwrap(store.application(id: applicationID)).isReadyToSubmit)

        store.resetDocumentRequest(applicationID: applicationID, documentID: documentID)
        document = try XCTUnwrap(store.application(id: applicationID)?.requiredDocuments.first)
        XCTAssertEqual(document.requestState, .notRequested)
        XCTAssertFalse(document.isReady)
        XCTAssertEqual(store.application(id: applicationID)?.nextAction, "추천서를 요청해 주세요")
    }

    func testOwnedDocumentNeedsLinkedFileBeforeRequiredDocumentBecomesReady() throws {
        let store = TestFixtures.store(applications: [])
        store.ownedDocuments = [
            OwnedDocument(name: "성적증명서", type: "성적", filename: "transcript.pdf")
        ]
        let metadataOnly = TestFixtures.application(
            title: "파일 없는 보유 기록",
            documents: [TestFixtures.document(name: "성적증명서")]
        )
        let metadataOnlyID = store.addApplication(metadataOnly)

        var required = try XCTUnwrap(store.application(id: metadataOnlyID)?.requiredDocuments.first)
        XCTAssertFalse(required.isReady)
        XCTAssertNil(required.linkedFileURL)

        let linkedURL = URL(fileURLWithPath: "/tmp/transcript.pdf")
        store.ownedDocuments = [
            OwnedDocument(
                name: "성적증명서",
                type: "성적",
                filename: "transcript.pdf",
                fileURL: linkedURL
            )
        ]
        let linked = TestFixtures.application(
            title: "파일 연결된 보유 기록",
            documents: [TestFixtures.document(name: "성적증명서")]
        )
        let linkedID = store.addApplication(linked)

        required = try XCTUnwrap(store.application(id: linkedID)?.requiredDocuments.first)
        XCTAssertTrue(required.isReady)
        XCTAssertEqual(required.linkedFileURL, linkedURL)
    }
}

@MainActor
final class CalendarExportTests: XCTestCase {
    func testMissingDeadlineReturnsActionableErrorBeforeOpeningCalendar() {
        let application = TestFixtures.application(title: "마감 미정", deadline: nil)

        XCTAssertThrowsError(try ICSCalendarExportService().openCalendarEvent(for: application)) { error in
            guard case CalendarExportError.missingDeadline = error else {
                return XCTFail("Expected missingDeadline, got \(error)")
            }
            XCTAssertEqual(error.localizedDescription, "마감일을 확인한 뒤 캘린더에 추가해 주세요.")
        }
    }
}

final class ApplicationAnalysisContextTests: XCTestCase {
    func testContextEncodesOnlyEligibilityFieldsAndDocumentSummaries() throws {
        let profile = UserProfile(
            name: "전송하면 안 되는 이름",
            school: "포항공과대학교",
            enrollmentStatus: "재학",
            grade: 4,
            gpa: "3.82",
            incomeBracket: "6분위",
            major: "컴퓨터공학과",
            region: "경상북도"
        )
        let document = OwnedDocument(
            name: "성적증명서",
            type: "성적",
            filename: "private-transcript.pdf",
            fileURL: URL(fileURLWithPath: "/Users/example/private-transcript.pdf")
        )

        let context = ApplicationAnalysisContext(
            profile: profile,
            ownedDocuments: [document]
        )
        let data = try JSONEncoder().encode(context)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let encodedProfile = try XCTUnwrap(root["profile"] as? [String: Any])
        let encodedDocuments = try XCTUnwrap(root["ownedDocuments"] as? [[String: Any]])
        let encodedDocument = try XCTUnwrap(encodedDocuments.first)

        XCTAssertEqual(
            Set(encodedProfile.keys),
            Set(["school", "enrollmentStatus", "grade", "gpa", "incomeBracket", "major", "region"])
        )
        XCTAssertEqual(Set(encodedDocument.keys), Set(["name", "type"]))
        XCTAssertNil(encodedProfile["name"])
        XCTAssertNil(encodedDocument["filename"])
        XCTAssertNil(encodedDocument["fileURL"])
    }
}

@MainActor
final class AddApplicationViewModelAnalysisTests: XCTestCase {
    func testMissingKeyDoesNotCallAnalyzerAndSavingKeyStartsAnalysis() async throws {
        let store = TestFixtures.store(applications: [])
        let application = TestFixtures.application(title: "키 저장 후 분석")
        let analyzer = RecordingApplicationAnalyzer(results: [.success(application)])
        let credentialStore = InMemoryUpstageAPIKeyStore()
        let source = ImportedSource.web(URL(string: "https://example.com/recruit")!)
        let viewModel = AddApplicationViewModel(
            source: source,
            store: store,
            analyzer: analyzer,
            credentialStore: credentialStore
        )

        viewModel.startIfNeeded()
        await Task.yield()

        XCTAssertEqual(viewModel.phase, .setupRequired)
        XCTAssertTrue(viewModel.requiresAPIKeySetup)
        XCTAssertEqual(analyzer.callCount, 0)
        XCTAssertTrue(store.applications.isEmpty)

        viewModel.apiKeyDraft = "  up_test_local_key  "
        viewModel.saveAPIKey()

        try await waitUntil { viewModel.completedApplicationID == application.id }

        XCTAssertEqual(credentialStore.savedValues, ["up_test_local_key"])
        XCTAssertEqual(analyzer.callCount, 1)
        XCTAssertEqual(store.applications.map(\.id), [application.id])
    }

    func testRetryBuildsContextFromLatestProfileAndDocuments() async throws {
        let store = TestFixtures.store(applications: [])
        store.profile.school = "첫 번째 학교"
        store.ownedDocuments = [
            OwnedDocument(name: "재학증명서", type: "학적", filename: "enrollment.pdf")
        ]
        let completedApplication = TestFixtures.application(title: "재시도 성공")
        let analyzer = RecordingApplicationAnalyzer(
            results: [
                .failure(TestAnalysisError.expectedFailure),
                .success(completedApplication),
            ]
        )
        let viewModel = AddApplicationViewModel(
            source: .file(URL(fileURLWithPath: "/tmp/recruit.pdf")),
            store: store,
            analyzer: analyzer
        )

        viewModel.startIfNeeded()
        try await waitUntil { viewModel.phase == .failed }

        store.profile.school = "변경된 학교"
        store.ownedDocuments = [
            OwnedDocument(name: "성적증명서", type: "성적", filename: "transcript.pdf")
        ]
        viewModel.beginAnalysis()

        try await waitUntil { viewModel.completedApplicationID == completedApplication.id }

        XCTAssertEqual(analyzer.contexts.count, 2)
        XCTAssertEqual(analyzer.contexts[0].profile.school, "첫 번째 학교")
        XCTAssertEqual(analyzer.contexts[0].ownedDocuments.map(\.name), ["재학증명서"])
        XCTAssertEqual(analyzer.contexts[1].profile.school, "변경된 학교")
        XCTAssertEqual(analyzer.contexts[1].ownedDocuments.map(\.name), ["성적증명서"])
    }

    func testRepeatedStartAddsSuccessfulAnalysisOnlyOnce() async throws {
        let store = TestFixtures.store(applications: [])
        let application = TestFixtures.application(title: "한 번만 추가")
        let analyzer = RecordingApplicationAnalyzer(results: [.success(application)])
        let viewModel = AddApplicationViewModel(
            source: .web(URL(string: "https://example.com/competition")!),
            store: store,
            analyzer: analyzer
        )

        viewModel.startIfNeeded()
        viewModel.startIfNeeded()
        try await waitUntil { viewModel.completedApplicationID == application.id }

        viewModel.startIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(analyzer.callCount, 1)
        XCTAssertEqual(store.applications.map(\.id), [application.id])
    }

    func testRapidSourceReplacementOnlyAddsNewestAnalysis() async throws {
        let store = TestFixtures.store(applications: [])
        let analyzer = ControllableApplicationAnalyzer()
        let viewModel = AddApplicationViewModel(
            source: .web(URL(string: "https://example.com/first")!),
            store: store,
            analyzer: analyzer
        )
        let first = TestFixtures.application(title: "첫 번째")
        let second = TestFixtures.application(title: "두 번째")
        let third = TestFixtures.application(title: "세 번째")

        viewModel.startIfNeeded()
        try await waitUntil { analyzer.callCount == 1 }
        viewModel.source = .web(URL(string: "https://example.com/second")!)
        viewModel.beginAnalysis()
        try await waitUntil { analyzer.callCount == 2 }

        analyzer.resume(call: 0, with: .success(first))
        try await Task.sleep(nanoseconds: 50_000_000)
        viewModel.source = .web(URL(string: "https://example.com/third")!)
        viewModel.beginAnalysis()
        try await waitUntil { analyzer.callCount == 3 }

        analyzer.resume(call: 1, with: .success(second))
        analyzer.resume(call: 2, with: .success(third))
        try await waitUntil { viewModel.completedApplicationID == third.id }

        XCTAssertEqual(store.applications.map(\.id), [third.id])
        XCTAssertEqual(viewModel.phase, .completed)
    }

    func testCancelPreventsLateFailureFromMutatingState() async throws {
        let store = TestFixtures.store(applications: [])
        let analyzer = ControllableApplicationAnalyzer()
        let viewModel = AddApplicationViewModel(
            source: .web(URL(string: "https://example.com/cancel")!),
            store: store,
            analyzer: analyzer
        )

        viewModel.startIfNeeded()
        try await waitUntil { analyzer.callCount == 1 }
        let phaseAtCancellation = viewModel.phase
        viewModel.cancel()
        analyzer.resume(call: 0, with: .failure(TestAnalysisError.expectedFailure))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.phase, phaseAtCancellation)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.completedApplicationID)
        XCTAssertTrue(store.applications.isEmpty)
    }
}

@MainActor
final class UpstageAPIClientTests: XCTestCase {
    func testDocumentParseRequestUsesOfficialContractAndPrefersPageElements() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: [
            "content": ["markdown": "aggregate content without page markers"],
            "elements": [
                ["page": 1, "content": ["markdown": "첫 페이지 자격 조건"]],
                ["page": 2, "content": ["markdown": "둘째 페이지 제출 서류"]],
            ],
        ])
        let transport = RecordingUpstageTransport(
            responses: [.init(statusCode: 200, data: responseData)]
        )
        let keyStore = InMemoryUpstageAPIKeyStore(apiKey: "up_test_key")
        let client = UpstageAPIClient(
            apiKeyStore: keyStore,
            configuration: UpstageAPIConfiguration(
                baseURL: URL(string: "https://api.upstage.ai/v1")!,
                documentModel: "document-parse",
                solarModel: "solar-pro4"
            ),
            transport: transport
        )

        let result = try await client.parseDocument(
            UpstageDocumentInput(
                data: Data("document-payload".utf8),
                filename: "application-source.pdf",
                mimeType: "application/pdf",
                ocrMode: .auto
            )
        )

        XCTAssertEqual(
            result.content,
            "[PAGE 1]\n첫 페이지 자격 조건\n\n[PAGE 2]\n둘째 페이지 제출 서류"
        )
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.upstage.ai/v1/document-digitization")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer up_test_key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ndocument-parse"))
        XCTAssertTrue(body.contains("name=\"mode\"\r\n\r\nauto"))
        XCTAssertTrue(body.contains("name=\"ocr\"\r\n\r\nauto"))
        XCTAssertTrue(body.contains("name=\"document\"; filename=\"application-source.pdf\""))
        XCTAssertTrue(body.contains("document-payload"))
    }

    func testChatRequestUsesStructuredOutputAndRequiresStopFinishReason() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [
                [
                    "finish_reason": "stop",
                    "message": ["content": "{\"result\":\"ok\"}"],
                ],
            ],
        ])
        let transport = RecordingUpstageTransport(
            responses: [.init(statusCode: 200, data: responseData)]
        )
        let client = UpstageAPIClient(
            apiKeyStore: InMemoryUpstageAPIKeyStore(apiKey: "up_chat_key"),
            transport: transport
        )
        let schema = UpstageStructuredOutputSchema(
            name: "test_schema",
            root: .object(
                properties: ["result": .string(enumValues: ["ok"])],
                required: ["result"]
            )
        )

        let result = try await client.createStructuredCompletion(
            systemPrompt: "system",
            userPrompt: "user",
            schema: schema
        )

        XCTAssertEqual(result, "{\"result\":\"ok\"}")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.upstage.ai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer up_chat_key")
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, "solar-pro4")
        XCTAssertEqual(body["reasoning_effort"] as? String, "minimal")
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "test_schema")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        XCTAssertNotNil(jsonSchema["schema"] as? [String: Any])
    }

    func testUnauthorizedResponseMapsToInvalidAPIKey() async throws {
        let transport = RecordingUpstageTransport(
            responses: [.init(statusCode: 401, data: Data())]
        )
        let client = UpstageAPIClient(
            apiKeyStore: InMemoryUpstageAPIKeyStore(apiKey: "up_invalid"),
            transport: transport
        )

        do {
            _ = try await client.createStructuredCompletion(
                systemPrompt: "system",
                userPrompt: "user",
                schema: UpstageStructuredOutputSchema(
                    name: "unauthorized",
                    root: .object(properties: ["value": .string()], required: ["value"])
                )
            )
            XCTFail("401 response should throw")
        } catch let error as UpstageAPIError {
            guard case .invalidAPIKey = error else {
                return XCTFail("Expected invalidAPIKey, got \(error)")
            }
        }
    }
}

@MainActor
final class URLSessionUpstageWebSourceLoaderTests: XCTestCase {
    func testKeepsUsefulStaticHTMLWithoutInvokingRenderer() async throws {
        let url = URL(string: "https://careers.example.com/jobs/ios")!
        let body = String(repeating: "공개 채용 공고 자격 조건과 제출 서류 안내 ", count: 8)
        let html = "<html><body><h1>iOS 개발자</h1><p>\(body)</p></body></html>"
        let transport = RecordingUpstageTransport(
            responses: [.init(
                statusCode: 200,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                data: Data(html.utf8)
            )]
        )
        let renderer = StubRenderedWebContentLoader(
            content: Self.renderedContent(url: url)
        )
        let loader = URLSessionUpstageWebSourceLoader(
            transport: transport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        let payload = try await loader.load(url)

        XCTAssertEqual(payload.data, Data(html.utf8))
        XCTAssertEqual(renderer.loadedURLs, [])
    }

    func testUsesDeclaredEUCKREncodingForKoreanStaticPage() async throws {
        let url = URL(string: "https://careers.example.com/jobs/legacy")!
        let html = "<html><body>" + String(
            repeating: "채용 공고 지원 자격 제출 서류 마감 일정 ",
            count: 10
        ) + "</body></html>"
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding("euc-kr" as CFString)
        XCTAssertNotEqual(cfEncoding, kCFStringEncodingInvalidId)
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        )
        let encodedHTML = try XCTUnwrap(html.data(using: encoding))
        let transport = RecordingUpstageTransport(
            responses: [.init(
                statusCode: 200,
                headers: ["Content-Type": "text/html; charset=euc-kr"],
                data: encodedHTML
            )]
        )
        let renderer = StubRenderedWebContentLoader(content: Self.renderedContent(url: url))
        let loader = URLSessionUpstageWebSourceLoader(
            transport: transport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        let payload = try await loader.load(url)
        let decoded = try XCTUnwrap(
            WebSourceTextSanitizer.decodedText(
                from: payload.data,
                textEncodingName: payload.textEncodingName
            )
        )

        XCTAssertTrue(decoded.contains("채용 공고 지원 자격"))
        XCTAssertEqual(payload.textEncodingName?.lowercased(), "euc-kr")
        XCTAssertTrue(renderer.loadedURLs.isEmpty)
    }

    func testInvalidDeclaredTextEncodingFallsBackToRenderer() async throws {
        let url = URL(string: "https://careers.example.com/jobs/broken-encoding")!
        let transport = RecordingUpstageTransport(
            responses: [.init(
                statusCode: 200,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                data: Data([0xFF, 0xFE, 0xFF, 0xFE])
            )]
        )
        let renderer = StubRenderedWebContentLoader(content: Self.renderedContent(url: url))
        let loader = URLSessionUpstageWebSourceLoader(
            transport: transport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        let payload = try await loader.load(url)

        XCTAssertEqual(renderer.loadedURLs, [url])
        XCTAssertEqual(payload.textEncodingName, "utf-8")
    }

    func testFallsBackToRenderedTextWhenStaticHTMLHasNoUsefulBody() async throws {
        let url = URL(string: "https://careers.example.com/jobs/spa?token=secret#private")!
        let transport = RecordingUpstageTransport(
            responses: [.init(
                statusCode: 200,
                headers: ["Content-Type": "text/html"],
                data: Data("<html><body><div id='app'></div><script>render()</script></body></html>".utf8)
            )]
        )
        let rendered = Self.renderedContent(url: url)
        let renderer = StubRenderedWebContentLoader(content: rendered)
        let loader = URLSessionUpstageWebSourceLoader(
            transport: transport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        let payload = try await loader.load(url)
        let text = try XCTUnwrap(String(data: payload.data, encoding: .utf8))

        XCTAssertEqual(renderer.loadedURLs, [url])
        XCTAssertTrue(payload.mimeType.hasPrefix("text/plain"))
        XCTAssertTrue(text.contains("Page title: 공개 공고"))
        XCTAssertTrue(text.contains("Final URL: https://careers.example.com"))
        XCTAssertFalse(text.contains("/jobs/spa"))
        XCTAssertTrue(text.contains(rendered.innerText))
        XCTAssertFalse(text.contains("token=secret"))
        XCTAssertFalse(text.contains("#private"))
    }

    func testFallsBackToRendererForForbiddenStaticRequest() async throws {
        let url = URL(string: "https://careers.example.com/jobs/browser-only")!
        let transport = RecordingUpstageTransport(
            responses: [.init(statusCode: 403, data: Data())]
        )
        let renderer = StubRenderedWebContentLoader(content: Self.renderedContent(url: url))
        let loader = URLSessionUpstageWebSourceLoader(
            transport: transport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        _ = try await loader.load(url)

        XCTAssertEqual(renderer.loadedURLs, [url])
    }

    func testCancellationPropagatesIntoRenderedFallback() async throws {
        let url = URL(string: "https://careers.example.com/jobs/slow")!
        let transport = RecordingUpstageTransport(
            responses: [.init(statusCode: 403, data: Data())]
        )
        let renderer = StubRenderedWebContentLoader(
            content: Self.renderedContent(url: url),
            delayNanoseconds: 5_000_000_000
        )
        let loader = URLSessionUpstageWebSourceLoader(
            transport: transport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )
        let task = Task { try await loader.load(url) }
        try await waitUntil { renderer.loadedURLs == [url] }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled rendered fallback should throw")
        } catch is CancellationError {
            // Expected: the child task is not allowed to outlive AddApplication.
        }
    }

    func testRenderedLoginPageIsRejectedBeforeItCanReachAnalysisPrompt() async throws {
        let url = URL(string: "https://careers.example.com/login")!
        let transport = RecordingUpstageTransport(
            responses: [.init(statusCode: 403, data: Data())]
        )
        let renderer = StubRenderedWebContentLoader(
            content: RenderedWebContent(
                title: "로그인",
                finalURL: url,
                innerText: "로그인 계정 비밀번호 Password Sign in"
            )
        )
        let loader = URLSessionUpstageWebSourceLoader(
            transport: transport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        do {
            _ = try await loader.load(url)
            XCTFail("Authentication pages must not be returned for Upstage analysis")
        } catch let error as LocalUpstageAnalysisError {
            guard case .webPageUnavailable = error else {
                return XCTFail("Expected webPageUnavailable, got \(error)")
            }
        }
    }

    func testPublicURLPolicyRejectsCredentialsAndNonPublicDestinations() {
        let policy = PublicWebURLPolicy { host in
            host == "rebind.example" ? ["127.0.0.1"] : ["93.184.216.34"]
        }
        let blockedValues = [
            "https://user:password@jobs.example.com/opening",
            "http://localhost:8080/private",
            "https://service.local/private",
            "https://127.0.0.1/private",
            "https://10.0.0.1/private",
            "https://169.254.169.254/latest/meta-data",
            "https://224.0.0.1/private",
            "https://0.0.0.0/private",
            "https://[::1]/private",
            "https://[fc00::1]/private",
            "https://[fe80::1]/private",
            "https://[ff02::1]/private",
            "https://[::]/private",
            "https://rebind.example/private",
        ]

        for value in blockedValues {
            XCTAssertFalse(policy.allows(URL(string: value)!), value)
        }
        XCTAssertTrue(policy.allows(URL(string: "https://jobs.example.com/opening")!))
        XCTAssertTrue(policy.allows(URL(string: "https://8.8.8.8/opening")!))
        XCTAssertTrue(policy.allows(URL(string: "https://[2606:4700:4700::1111]/opening")!))
    }

    func testRejectsUnsafeInitialAndFinalURLsBeforeAnalysis() async throws {
        let publicURL = URL(string: "https://careers.example.com/jobs/public")!
        let privateURL = URL(string: "https://127.0.0.1/internal")!
        let initialTransport = RecordingUpstageTransport(
            responses: [.init(statusCode: 200, data: Data("private".utf8))]
        )
        let renderer = StubRenderedWebContentLoader(content: Self.renderedContent(url: publicURL))
        let initialLoader = URLSessionUpstageWebSourceLoader(
            transport: initialTransport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        do {
            _ = try await initialLoader.load(privateURL)
            XCTFail("Private initial URLs must be rejected")
        } catch is ApplicationAnalysisError {
            XCTAssertEqual(initialTransport.requests.count, 0)
        }

        let redirectedTransport = RecordingUpstageTransport(
            responses: [.init(
                statusCode: 200,
                data: Data("private".utf8),
                responseURL: privateURL
            )]
        )
        let redirectedLoader = URLSessionUpstageWebSourceLoader(
            transport: redirectedTransport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        do {
            _ = try await redirectedLoader.load(publicURL)
            XCTFail("Redirected private URLs must be rejected")
        } catch let error as LocalUpstageAnalysisError {
            guard case .webPageUnavailable = error else {
                return XCTFail("Expected webPageUnavailable, got \(error)")
            }
        }
    }

    func testRemoteDocumentUsesMIMEBasedPrivateFilename() async throws {
        let url = URL(string: "https://careers.example.com/private/token/applicant-name.pdf")!
        let pdf = Data("%PDF-private-document".utf8)
        let transport = RecordingUpstageTransport(
            responses: [.init(
                statusCode: 200,
                headers: [
                    "Content-Type": "application/pdf",
                    "Content-Disposition": "attachment; filename=applicant-name.pdf",
                ],
                data: pdf
            )]
        )
        let renderer = StubRenderedWebContentLoader(content: Self.renderedContent(url: url))
        let loader = URLSessionUpstageWebSourceLoader(
            transport: transport,
            renderedContentLoader: renderer,
            urlPolicy: Self.publicURLPolicy
        )

        let payload = try await loader.load(url)

        XCTAssertEqual(payload.privateUploadFilename, "application-source.pdf")
        XCTAssertFalse(payload.privateUploadFilename.contains("applicant-name"))
    }

    func testHeadAndTailLimitPreservesDeadlineAtDocumentEnd() {
        let source = String(repeating: "A", count: 200_000) + "마감일 2026-09-18"

        let result = WebSourceTextSanitizer.headAndTail(source, maximumCharacters: 180_000)

        XCTAssertEqual(result.count, 180_000)
        XCTAssertTrue(result.hasPrefix(String(repeating: "A", count: 100)))
        XCTAssertTrue(result.hasSuffix("마감일 2026-09-18"))
        XCTAssertTrue(result.contains("[중간 본문 생략]"))
    }

    func testWebReferenceKeepsOnlyOrigin() {
        let source = URL(
            string: "https://user:password@careers.example.com:8443/jobs/7?token=secret#private"
        )!

        let result = WebSourceTextSanitizer.redactedReference(for: source)

        XCTAssertEqual(result, "https://careers.example.com:8443")
        XCTAssertFalse(result.contains("/jobs/7"))
        XCTAssertFalse(result.contains("user"))
        XCTAssertFalse(result.contains("password"))
        XCTAssertFalse(result.contains("secret"))
        XCTAssertFalse(result.contains("private"))
    }

    private static func renderedContent(url: URL) -> RenderedWebContent {
        RenderedWebContent(
            title: "공개 공고",
            finalURL: url,
            innerText: String(repeating: "지원 자격 제출 서류 마감 일정 ", count: 10)
        )
    }

    private static let publicURLPolicy = PublicWebURLPolicy { _ in
        ["93.184.216.34"]
    }
}

@MainActor
final class LocalUpstageApplicationAnalysisServiceTests: XCTestCase {
    func testWebAnalysisRetriesInvalidJSONMapsResultAndSendsMinimalContext() async throws {
        let webURL = URL(
            string: "https://scholarship.example.org/notices/2026?token=secret#private"
        )!
        let visibleSource = """
        <html><body><h1>2026 미래인재 장학금</h1>
        <p>컴퓨터공학 전공 재학생을 대상으로 하며 2026년 9월 18일까지 지원합니다.</p>
        <p>성적증명서와 추천서를 제출해야 합니다. 세부 소득 기준은 모집 요강을 확인하세요.</p>
        </body></html>
        """
        let loader = StubUpstageWebSourceLoader(
            payload: UpstageWebSourcePayload(
                data: Data(visibleSource.utf8),
                mimeType: "text/html"
            )
        )
        let validResult = """
        {
          "category": "scholarship",
          "title": "2026 미래인재 장학금",
          "organization": "미래재단",
          "deadline": "2026-09-18T23:59:59+09:00",
          "eligibility": "eligible",
          "requirements": [
            {
              "title": "전공",
              "detail": "컴퓨터공학 전공 재학생",
              "state": "satisfied",
              "evidence_excerpt": "컴퓨터공학 전공 재학생을 대상",
              "source_page": null
            }
          ],
          "required_documents": [
            {"name": "성적증명서", "preparation_type": "write"},
            {"name": "추천서", "preparation_type": "request"}
          ],
          "official_url": "https://different.example.org/ignored"
        }
        """
        let client = StubUpstageAPIClient(
            completionResults: [.success("not-json"), .success(validResult)]
        )
        let service = LocalUpstageApplicationAnalysisService(
            client: client,
            webSourceLoader: loader
        )
        let profile = UserProfile(
            name: "프롬프트에 없어야 하는 이름",
            school: "포항공과대학교",
            enrollmentStatus: "재학",
            grade: 4,
            gpa: "3.82",
            incomeBracket: "6분위",
            major: "컴퓨터공학과",
            region: "경상북도"
        )
        let ownedDocument = OwnedDocument(
            name: "성적증명서",
            type: "성적",
            filename: "secret-transcript.pdf",
            fileURL: URL(fileURLWithPath: "/private/secret-transcript.pdf")
        )

        let application = try await service.analyze(
            source: .web(webURL),
            context: ApplicationAnalysisContext(
                profile: profile,
                ownedDocuments: [ownedDocument]
            )
        )

        XCTAssertEqual(loader.loadedURLs, [webURL])
        XCTAssertEqual(client.completionPrompts.count, 2)
        XCTAssertTrue(client.completionPrompts[1].user.contains("이전 응답 검증 오류"))
        XCTAssertEqual(application.category, .scholarship)
        XCTAssertEqual(application.title, "2026 미래인재 장학금")
        XCTAssertEqual(application.organization, "미래재단")
        XCTAssertEqual(application.eligibility, .eligible)
        XCTAssertEqual(application.source.webURL, webURL)
        XCTAssertNil(application.source.documentURL)
        XCTAssertEqual(application.requiredDocuments.map(\.preparationType), [.owned, .request])
        XCTAssertEqual(application.requiredDocuments.map(\.isReady), [false, false])

        let requirement = try XCTUnwrap(application.requirements.first)
        guard case let .web(evidenceURL, _) = requirement.evidence.location else {
            return XCTFail("Expected web evidence")
        }
        XCTAssertEqual(evidenceURL, webURL)

        let prompt = try XCTUnwrap(client.completionPrompts.first?.user)
        XCTAssertTrue(prompt.contains("포항공과대학교"))
        XCTAssertTrue(prompt.contains("성적증명서"))
        XCTAssertTrue(prompt.contains("컴퓨터공학 전공 재학생"))
        XCTAssertFalse(prompt.contains("프롬프트에 없어야 하는 이름"))
        XCTAssertFalse(prompt.contains("secret-transcript.pdf"))
        XCTAssertFalse(prompt.contains("/private/secret-transcript.pdf"))
        XCTAssertFalse(prompt.contains("token=secret"))
        XCTAssertFalse(prompt.contains("#private"))
        XCTAssertTrue(prompt.contains("source_reference: https://scholarship.example.org"))
        XCTAssertFalse(prompt.contains("/notices/2026"))
        XCTAssertFalse(prompt.contains("<script"))
        XCTAssertEqual(client.parsedInputs.count, 0)
    }

    func testMissingDeadlineIsAcceptedAsReviewableApplication() async throws {
        let webURL = URL(string: "https://competition.example.org/open-ended")!
        let sourceText = String(
            repeating: "공모전 참가 자격과 제출 서류 안내이며 마감일은 추후 공지됩니다. ",
            count: 8
        )
        let loader = StubUpstageWebSourceLoader(
            payload: UpstageWebSourcePayload(
                data: Data(sourceText.utf8),
                mimeType: "text/plain",
                textEncodingName: "utf-8"
            )
        )
        let result = """
        {
          "category": "competition",
          "title": "상시 아이디어 공모전",
          "organization": "테스트 재단",
          "deadline": null,
          "eligibility": "needs_review",
          "requirements": [
            {
              "title": "참가 자격",
              "detail": "세부 자격 확인 필요",
              "state": "needs_review",
              "evidence_excerpt": "참가 자격",
              "source_page": null
            }
          ],
          "required_documents": [],
          "official_url": null
        }
        """
        let client = StubUpstageAPIClient(completionResults: [.success(result)])
        let service = LocalUpstageApplicationAnalysisService(
            client: client,
            webSourceLoader: loader
        )
        let store = TestFixtures.store(applications: [])

        let application = try await service.analyze(
            source: .web(webURL),
            context: ApplicationAnalysisContext(
                profile: store.profile,
                ownedDocuments: store.ownedDocuments
            )
        )

        XCTAssertNil(application.deadline)
        XCTAssertEqual(application.dDayText, "마감 확인 필요")
        XCTAssertEqual(application.eligibility, .needsReview)
        XCTAssertEqual(client.completionPrompts.count, 1)
    }
}

@MainActor
private final class RecordingUpstageTransport: UpstageRequestPerforming {
    struct StubResponse {
        var statusCode: Int
        var headers: [String: String]
        var data: Data
        var responseURL: URL?

        init(
            statusCode: Int,
            headers: [String: String] = [:],
            data: Data,
            responseURL: URL? = nil
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.data = data
            self.responseURL = responseURL
        }
    }

    private var responses: [StubResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [StubResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw TestAnalysisError.unexpectedInvocation
        }
        let response = responses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: response.responseURL ?? request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        return (response.data, httpResponse)
    }
}

@MainActor
private final class StubUpstageAPIClient: UpstageAPIClienting {
    struct CompletionPrompt {
        var system: String
        var user: String
        var schema: UpstageStructuredOutputSchema
    }

    private var completionResults: [Result<String, Error>]
    private(set) var parsedInputs: [UpstageDocumentInput] = []
    private(set) var completionPrompts: [CompletionPrompt] = []

    init(completionResults: [Result<String, Error>]) {
        self.completionResults = completionResults
    }

    func parseDocument(_ input: UpstageDocumentInput) async throws -> UpstageParsedDocument {
        parsedInputs.append(input)
        return UpstageParsedDocument(content: "parsed")
    }

    func createStructuredCompletion(
        systemPrompt: String,
        userPrompt: String,
        schema: UpstageStructuredOutputSchema
    ) async throws -> String {
        completionPrompts.append(
            CompletionPrompt(system: systemPrompt, user: userPrompt, schema: schema)
        )
        guard !completionResults.isEmpty else {
            throw TestAnalysisError.unexpectedInvocation
        }
        return try completionResults.removeFirst().get()
    }
}

@MainActor
private final class StubUpstageWebSourceLoader: UpstageWebSourceLoading {
    private let payload: UpstageWebSourcePayload
    private(set) var loadedURLs: [URL] = []

    init(payload: UpstageWebSourcePayload) {
        self.payload = payload
    }

    func load(_ url: URL) async throws -> UpstageWebSourcePayload {
        loadedURLs.append(url)
        return payload
    }
}

@MainActor
private final class StubRenderedWebContentLoader: RenderedWebContentLoading {
    private let content: RenderedWebContent
    private let delayNanoseconds: UInt64
    private(set) var loadedURLs: [URL] = []

    init(content: RenderedWebContent, delayNanoseconds: UInt64 = 0) {
        self.content = content
        self.delayNanoseconds = delayNanoseconds
    }

    func render(_ url: URL) async throws -> RenderedWebContent {
        loadedURLs.append(url)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return content
    }
}

private enum TestAnalysisError: LocalizedError {
    case expectedFailure
    case unexpectedInvocation

    var errorDescription: String? {
        switch self {
        case .expectedFailure: "의도한 분석 실패"
        case .unexpectedInvocation: "예상보다 분석기가 더 많이 호출됨"
        }
    }
}

@MainActor
private final class RecordingApplicationAnalyzer: ApplicationAnalyzing {
    private var results: [Result<ApplicationItem, Error>]

    private(set) var sources: [ImportedSource] = []
    private(set) var contexts: [ApplicationAnalysisContext] = []

    init(results: [Result<ApplicationItem, Error>]) {
        self.results = results
    }

    var callCount: Int { contexts.count }

    func analyze(
        source: ImportedSource,
        context: ApplicationAnalysisContext
    ) async throws -> ApplicationItem {
        sources.append(source)
        contexts.append(context)

        guard !results.isEmpty else {
            throw TestAnalysisError.unexpectedInvocation
        }
        return try results.removeFirst().get()
    }
}

@MainActor
private final class ControllableApplicationAnalyzer: ApplicationAnalyzing {
    private var continuations: [CheckedContinuation<ApplicationItem, Error>?] = []
    private(set) var sources: [ImportedSource] = []

    var callCount: Int { sources.count }

    func analyze(
        source: ImportedSource,
        context: ApplicationAnalysisContext
    ) async throws -> ApplicationItem {
        sources.append(source)
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resume(call index: Int, with result: Result<ApplicationItem, Error>) {
        precondition(continuations.indices.contains(index), "Unknown analysis call")
        guard let continuation = continuations[index] else {
            preconditionFailure("Analysis call already resumed")
        }
        continuations[index] = nil
        continuation.resume(with: result)
    }
}

@MainActor
private final class InMemoryUpstageAPIKeyStore: UpstageAPIKeyStoring {
    private var apiKey: String?

    private(set) var savedValues: [String] = []

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    var hasAPIKey: Bool { apiKey != nil }
    var activeSource: UpstageAPIKeySource? { apiKey == nil ? nil : .keychain }

    func loadAPIKey() throws -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
        savedValues.append(apiKey)
    }

    func deleteAPIKey() throws {
        apiKey = nil
    }
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 3,
    condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else {
            throw TestAnalysisError.expectedFailure
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

private enum TestFixtures {
    static func seoulCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        calendar: Calendar = seoulCalendar()
    ) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )
        return calendar.date(from: components)!
    }

    static func requirement(
        title: String = "자격",
        state: RequirementState = .satisfied
    ) -> EligibilityRequirement {
        EligibilityRequirement(title: title, detail: "테스트 조건", state: state, sourcePage: 1)
    }

    static func document(
        id: UUID = UUID(),
        name: String,
        preparationType: DocumentPreparationType = .owned,
        isReady: Bool = false,
        requestState: DocumentRequestState = .notRequested
    ) -> RequiredDocument {
        RequiredDocument(
            id: id,
            name: name,
            preparationType: preparationType,
            isReady: isReady,
            requestState: requestState
        )
    }

    static func application(
        id: UUID = UUID(),
        title: String = "테스트 지원",
        organization: String = "테스트 기관",
        category: ApplicationCategory = .employment,
        deadline: Date? = date(year: 2099, month: 1, day: 1),
        eligibility: EligibilityState = .eligible,
        requirements: [EligibilityRequirement] = [requirement()],
        documents: [RequiredDocument] = [document(name: "지원서", preparationType: .write, isReady: true)],
        status: ApplicationStatus = .preparing
    ) -> ApplicationItem {
        ApplicationItem(
            id: id,
            category: category,
            title: title,
            organization: organization,
            deadline: deadline,
            eligibility: eligibility,
            requirements: requirements,
            requiredDocuments: documents,
            source: ApplicationSource(displayName: "test.pdf"),
            status: status
        )
    }

    @MainActor
    static func store(applications: [ApplicationItem]) -> AppStore {
        let store = AppStore()
        store.applications = applications
        store.ownedDocuments = []
        return store
    }
}
