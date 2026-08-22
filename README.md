# Application Workspace

모집요강 PDF 한 번으로 지원 조건, 마감일, 필요 서류와 현재 준비 상태를
한 화면에 만드는 AI 지원 준비 워크스페이스입니다.

제품 정의는 [`description.md`](description.md), 화면별 기능 기준은
[`feature_list.md`](feature_list.md)를 확인하세요. 구현 계층과 Firebase·Upstage
교체 지점은 [`ApplicationWorkspace/ARCHITECTURE.md`](ApplicationWorkspace/ARCHITECTURE.md)에
정리되어 있습니다.

## macOS Prototype

`ApplicationWorkspace/`에는 SwiftUI 기반 macOS 프로토타입이 있습니다.
Firebase와 Upstage Studio를 연결하기 전에도 핵심 사용자 흐름과 필수 버튼을
샘플 데이터로 확인할 수 있습니다.

### 포함된 화면

- 지원 현황 Dashboard 및 상태·분야 필터
- PDF·이미지·공고 URL 등록과 자동 분석 진행 상태
- 지원 가능 상태, D-Day, 준비율과 다음 행동을 모은 Workspace
- 필요 서류 파일 연결, 외부 요청 완료와 지원 완료 처리
- 모집요강 원문·판정 근거 보기
- PDF와 웹 공고를 나란히 확인하는 듀얼 워크스페이스
- 반복 사용하는 내 프로필과 내 문서함

### 실행

1. `ApplicationWorkspace/ApplicationWorkspace.xcodeproj`를 Xcode에서 엽니다.
2. `ApplicationWorkspace` scheme과 `My Mac`을 선택합니다.
3. Run 버튼을 누릅니다.

단위 테스트는 Xcode의 Test 액션 또는 다음 명령으로 실행할 수 있습니다.

```sh
xcodebuild -project ApplicationWorkspace/ApplicationWorkspace.xcodeproj \
  -scheme ApplicationWorkspace -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
```

현재 분석과 데이터 저장은 프로토타입용 로컬 샘플 상태입니다. Firebase Auth,
Storage, Firestore, Cloud Functions와 Upstage Studio 연결은 다음 구현 단계입니다.
