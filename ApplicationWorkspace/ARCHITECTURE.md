# PassReady macOS Architecture

PassReady는 화면 디자인이 바뀌어도 분석·지원 준비 흐름을 다시 작성하지 않도록
MVVM과 얇은 서비스 경계를 사용한다. 현재 구현은 로컬 프로토타입이며, 같은
경계 뒤에 Firebase와 Upstage 구현을 교체해 넣는 것을 기준으로 한다.

## Dependency direction

```text
ApplicationWorkspaceApp
        │
        ▼
RootViewModel ── AppDependencies
        │              │
        │              ├── ApplicationAnalyzing
        │              ├── ExternalURLOpening
        │              └── CalendarExporting
        │
        ├── DashboardViewModel
        ├── AddApplicationViewModel
        ├── ApplicationWorkspaceViewModel
        ├── DocumentsViewModel
        └── ProfileViewModel
                 │
                 ▼
             AppStore
                 │
                 ▼
       Foundation-only domain models
```

- **View**는 레이아웃, 포커스, 드롭 하이라이트처럼 일시적인 표시 상태만 가진다.
- **ViewModel**은 화면에 보이는 상태, 사용자 액션, 다음 화면 결정을 담당한다.
- **Service**는 분석, 외부 URL 열기, 캘린더 내보내기처럼 교체 가능한 작업을
  프로토콜로 노출한다.
- **AppStore**는 프로토타입 저장소다. View는 AppStore를 직접 참조하지 않는다.
- **Domain model**은 Foundation만 사용한다. 색상과 아이콘은
  `Components/ModelPresentation.swift`에서 표현 계층 확장으로 제공한다.

## State ownership

| State | Owner | Reason |
| --- | --- | --- |
| 현재 라우트와 시트 | `RootViewModel` | 앱 전역 내비게이션을 한 곳에서 관리 |
| 검색·Smart View·전체 보기 | `DashboardViewModel` | 지원 목록 표시 규칙을 단위 테스트 가능하게 유지 |
| 분석 단계·오류·완료 ID | `AddApplicationViewModel` | 중복 생성과 취소 후 유령 지원 방지 |
| 선택 근거·PDF 페이지·연결 문서·다음 행동 | `ApplicationWorkspaceViewModel` | 지원 건별 상태가 서로 섞이지 않게 격리 |
| 웹 탐색 상태·오류·팝업 처리 | `WebBrowserViewModel` | WebKit을 SwiftUI 레이아웃에서 분리 |
| 파일 선택 창·드롭 강조 | 각 View | 저장할 필요가 없는 순수 UI 상태 |

## Source and document rules

- 공고 입력은 `ImportedSource.file(URL)` 또는 `ImportedSource.web(URL)`로 받는다.
- 분석 결과는 `ApplicationSource`에 웹 URL과 문서 URL을 각각 유지한다.
- 근거는 페이지 숫자 하나가 아니라 `EvidenceReference`의 `web` 또는 `pdf`
  위치로 저장한다.
- 연결 문서는 파일명과 실제 URL을 함께 유지한다. Firebase 적용 시 URL 자리는
  Storage 경로 또는 안정적인 document ID로 교체한다.
- 외부 요청 문서는 `요청 전 → 요청됨 → 수령 완료` 상태를 사용하며, 요청 즉시
  준비 완료로 처리하지 않는다.
- 제출 가능 여부는 문서 준비율뿐 아니라 자격 및 개별 조건 충족 여부까지 함께
  계산한다.

## Firebase and Upstage adapters

다음 구현 단계에서는 View와 ViewModel을 바꾸지 않고 의존성 구현만 교체한다.

1. `ApplicationAnalyzing`
   - 현재 앱 실행: `LocalUpstageApplicationAnalysisService`
     - 파일은 Upstage Document Parse 후 Solar Structured Outputs로 변환
     - 웹 URL은 쿠키 없는 ephemeral URLSession으로 먼저 읽고, 403 또는 본문이
       부족하면 fresh non-persistent WKWebView로 공개 JavaScript 본문만 렌더링
     - 로그인·인증 페이지와 기존 브라우저 세션은 공유하지 않고 PDF 등록 안내
     - 로컬 키는 `UPSTAGE_API_KEY` 또는 macOS Keychain에서만 조회하며 환경 변수가
       Keychain보다 우선
   - 프리뷰·단위 테스트: `MockApplicationAnalysisService`
   - 이후: 동일한 최소 `ApplicationAnalysisContext` DTO를 받는 Cloud Functions가
     Upstage를 호출하고 구조화 결과만 반환
2. `AppStore`
   - 현재: 메모리 기반 샘플 데이터
   - 이후: `ApplicationRepository`, `ProfileRepository`, `DocumentRepository`로
     분리하고 Firebase 구현이 Firestore snapshot을 발행
3. 파일 URL
   - 현재: 프로토타입 세션의 로컬 URL
   - 이후: Firebase Storage 경로와 다운로드 URL 또는 로컬 캐시 ID
4. 인증
   - `AppDependencies`에 `SessionProviding`을 추가하고 repository 쿼리를 user ID로
     제한

SDK를 View 또는 ViewModel에서 직접 호출하지 않는다. Firebase/Upstage 타입은
Data/Infrastructure 구현 안에만 두어 프리뷰, 단위 테스트와 오프라인 fixture가
같은 화면 코드를 사용할 수 있게 한다.

`ApplicationAnalysisContext`는 프로필 이름과 로컬 파일명·경로를 제외하고 자격
판단에 필요한 필드와 보유 문서 표시명·유형만 캡처한다. 로컬 어댑터를 서버
어댑터로 바꿀 때도 이 최소 전송 규칙을 유지한다. 앱 번들, UserDefaults,
Info.plist 또는 저장소에는 Upstage API 키를 저장하지 않는다.

## Product decisions intentionally deferred

- 옵시디언 스타일의 탭을 실제 다중 웹 세션으로 만들지 여부
- OAuth·본인 인증 팝업을 내부 탭과 외부 브라우저 중 어디로 보낼지
- 웹 근거를 URL만 저장할지 selector·문장·anchor까지 저장할지
- 제출 완료와 보관됨을 사용자에게 별도 단계로 노출할지
- 캘린더를 `.ics` 내보내기에서 EventKit 동기화로 확장할지

이 항목은 하이파이와 MVP 범위가 확정된 뒤 결정한다. 현재 구현은 새 창 링크를
같은 내부 웹 뷰에서 열고, 실제 제출은 공식 접수처에서 사용자가 직접 수행한다.

## Verification

구조 변경 뒤 최소 검증 명령은 다음과 같다.

```sh
xcodebuild -project ApplicationWorkspace.xcodeproj \
  -scheme ApplicationWorkspace -configuration Debug \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project ApplicationWorkspace.xcodeproj \
  -scheme ApplicationWorkspace -configuration Debug \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test

xcodebuild -project ApplicationWorkspace.xcodeproj \
  -scheme ApplicationWorkspace -configuration Release \
  -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
```

`ApplicationWorkspaceTests`는 날짜/D-Day 경계, 준비도·제출 가능 조건, 검색과
Smart View, 주소 해석, 전체 보기, 문서 요청 상태 전이를 검증한다. 분석
취소·재시도와 PDF·웹 근거 라우팅은 service/repository 구현이 연결될 때 mock을
주입해 추가한다.
