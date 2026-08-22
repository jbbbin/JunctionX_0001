# Application Workspace

모집요강 PDF 한 번으로 지원 조건, 마감일, 필요 서류와 현재 준비 상태를
한 화면에 만드는 AI 지원 준비 워크스페이스입니다.

제품 정의는 [`description.md`](description.md), 화면별 기능 기준은
[`feature_list.md`](feature_list.md)를 확인하세요. 구현 계층과 Firebase·Upstage
교체 지점은 [`ApplicationWorkspace/ARCHITECTURE.md`](ApplicationWorkspace/ARCHITECTURE.md)에
정리되어 있습니다.

## macOS Prototype

`ApplicationWorkspace/`에는 SwiftUI 기반 macOS 프로토타입이 있습니다.
현재 새 공고 분석은 로컬 Upstage API 어댑터로 실제 동작하며, 저장소와 나머지
화면 상태는 Firebase를 연결하기 전까지 메모리 기반 프로토타입을 사용합니다.

### 포함된 화면

- 지원 현황 Dashboard 및 상태·분야 필터
- PDF·이미지·Office·HWP·공고 URL 등록과 자동 분석 진행 상태
- 지원 가능 상태, D-Day, 준비율과 다음 행동을 모은 Workspace
- 필요 서류 파일 연결, 외부 요청 완료와 지원 완료 처리
- 모집요강 원문·판정 근거 보기
- PDF와 웹 공고를 나란히 확인하는 듀얼 워크스페이스
- 반복 사용하는 내 프로필과 내 문서함

### 실행

1. `ApplicationWorkspace/ApplicationWorkspace.xcodeproj`를 Xcode에서 엽니다.
2. `ApplicationWorkspace` scheme과 `My Mac`을 선택합니다.
3. Run 버튼을 누릅니다.

### 로컬 Upstage 연결

1. [Upstage Console](https://console.upstage.ai/api-keys)에서 API 키를 발급합니다.
2. 앱에서 `새 지원`을 누르고 API 키를 한 번 입력합니다.
3. 앱에서 직접 입력한 키는 macOS Keychain에만 저장되며, 이후 PDF·이미지·
   Office·HWP 파일이나 공고 URL을 넣으면 실제 Document Parse와 Solar 분석이
   실행됩니다.

환경 변수로 주입하려면 Xcode Scheme의 Run 환경에 `UPSTAGE_API_KEY`를 사용할 수
있으며, 설정된 환경 변수 값이 Keychain보다 우선합니다. 모델 alias를 시험할
때만 `UPSTAGE_SOLAR_MODEL` 또는
`UPSTAGE_DOCUMENT_MODEL`을 지정하며, 기본값은 각각 `solar-pro4`,
`document-parse`입니다. 키를 소스, Info.plist, `.env`, 공유 scheme에 커밋하지
마세요.

분석 시 사용자가 선택한 원문과 이름을 제외한 자격 판단 정보(학교·재학 상태·
학년·학점·소득분위·전공·지역), 보유 문서의 표시명·유형이 Upstage API로
전송됩니다. 보유 파일 경로와 파일명은 전송하지 않으며, Upstage 프롬프트의 URL
식별자에서도 사용자 정보, query와 fragment를 제거합니다. 공개 JavaScript 공고는
쿠키·자격 증명을 공유하지 않는 비영구 WebKit 폴백으로 본문을 가져옵니다.
로그인·인증 또는 기존 브라우저 세션이 필요한 페이지는 PDF로 저장한 뒤
추가하세요.

단위 테스트는 Xcode의 Test 액션 또는 다음 명령으로 실행할 수 있습니다.

```sh
xcodebuild -project ApplicationWorkspace/ApplicationWorkspace.xcodeproj \
  -scheme ApplicationWorkspace -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
```

현재 직접 API 호출은 로컬 개발용입니다. 배포 단계에서는 팀 공용 키를 앱에
포함하지 않고 `ApplicationAnalyzing` 구현만 Firebase Cloud Functions 어댑터로
교체해 Upstage 호출을 서버로 옮깁니다. Firebase Auth, Storage, Firestore 연동도
같은 단계에서 추가합니다.
