import Foundation
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
        deadline: Date = date(year: 2099, month: 1, day: 1),
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
