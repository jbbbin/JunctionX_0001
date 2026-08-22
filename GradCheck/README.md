# UpCheck

UpCheck는 해외 대학원 지원을 준비하는 사용자를 위한 네이티브 macOS 문서 QA 워크스페이스입니다. 여러 학교·프로그램의 지원서를 독립적으로 관리하고, 각 지원서의 공식 모집요강에서 추출한 필요 서류와 실제 파일을 대조해 누락·오탈자·문서 간 불일치를 페이지 근거와 함께 보여줍니다.

새 지원서는 `지원 목표 → 공식 모집요강 분석 → 필요 서류 검토 → 지원 파일 업로드` 순서로 만듭니다. CV, SOP, 성적표에 고정되지 않고 추천서 수량, GRE/GMAT, Writing Sample, 포트폴리오, 연구계획서, 학위증명, 여권·비자 서류 등 모집요강에서 확인된 항목으로 체크리스트가 동적으로 구성됩니다.

저장소에는 실제 개인정보가 없는 결정론적 샘플 워크스페이스와 오프라인 우선 문서 흐름이 포함되어 있습니다. 모집요강 PDF는 Upstage Studio의 **미국 대학원 모집요강 Agent**가 `Parse → Classify → Extract`하여 학교 공통/프로그램별 요건과 필수·조건부 서류를 구조화합니다. 지원자 서류의 내용 대조는 로컬 문서 분석 흐름을 유지합니다.

실제 문서를 읽은 뒤에는 파일명만으로 판단하지 않습니다. 원문에서 찾은 영문 이름, 지원 학교·프로그램·학위, 졸업일, 학교·전공·학위명, GPA, TOEFL/IELTS 점수와 시험일을 문서 및 페이지 근거와 함께 대조합니다. 기대값을 실제 원문에서 확인하지 못한 경우 `READY`로 추정하지 않고 `HUMAN REVIEW`로 남깁니다.

## 실행

1. Xcode 26 이상에서 `GradCheck.xcodeproj`를 엽니다.
2. `GradCheck` 실행 스킴과 **My Mac**을 선택해 실행합니다.

공유 Scheme에는 macOS 앱 타깃과 `GradCheckTests` 테스트 타깃이 포함되어 있습니다. `Package.swift`도 CLI와 CI 호환성을 위해 함께 유지합니다.

터미널에서는 다음 명령으로 Xcode 프로젝트를 검증할 수 있습니다.

```sh
xcodebuild -project GradCheck.xcodeproj -scheme GradCheck -destination 'platform=macOS' test
```

Swift Package 명령도 계속 사용할 수 있습니다.

```sh
swift build
swift test
swift run GradCheck
```

첫 실행에는 MIT EECS PhD 합성 샘플이 열리므로, 개인정보를 올리지 않고도 전체 검수 흐름을 시연할 수 있습니다.

## Upstage Studio Agent 연결

앱에서 **새 지원 목표 → 모집요강** 단계로 이동해 `up_`로 시작하는 Upstage API 키를 입력하세요. 분석을 시작할 때 키는 macOS **Keychain**에 저장되며, 프로젝트 파일·UserDefaults·지원서 데이터에는 저장되지 않습니다. 다음 실행부터는 입력하지 않아도 저장된 키를 사용합니다.

모집요강 Agent 설정은 `StudioAgentRequirementsService.swift`의 `StudioAgentCatalog`에 있습니다. 현재 등록된 값은 다음과 같습니다.

- 목적: `graduateRequirements` (미국 대학원 모집요강)
- Agent Config ID: `6`
- 다른 Agent가 필요해지면 `applicationPackageAudit`처럼 새 목적과 Agent ID/Config ID를 이 카탈로그에 추가합니다.

Xcode 로컬 검증에서만 키를 UI 대신 스킴 환경 변수 `UPSTAGE_API_KEY`로 넣을 수도 있습니다. 이 값은 Keychain 값보다 우선합니다.

기존 지원자 문서 파싱 모델을 교체해야 할 때만 다음 설정을 선택적으로 사용합니다.

- `UPSTAGE_DOCUMENT_MODEL`: 기본값 `document-parse`
- `UPSTAGE_DOCUMENT_ENDPOINT`: 기본값 `https://api.upstage.ai/v1/document-digitization`
- `UPSTAGE_DOCUMENT_TIMEOUT`: 요청 제한 시간(초), 기본값 `90`

모집요강 Agent 호출은 `GraduateRequirementsAnalyzing` 프로토콜 뒤에 있으며, `StudioAgentRequirementsService`가 Agent API의 파일 업로드·실행·완료 조회·JSON 변환을 담당합니다. Agent가 돌려준 목록은 `RequirementItem`으로 저장돼 다음 **지원 서류** 화면의 파일 준비 슬롯과 전체 체크리스트에 바로 표시됩니다. 제목과 설명은 한국어로 반환해도 되며, 카테고리·필수 여부·출처 범주는 영문 enum 또는 한국어 표기를 모두 앱에서 처리합니다.

API 키, 지원자 이름, 지원자 서류 파일명, 원문 텍스트와 evidence excerpt는 앱 설정에 기록하지 않습니다. 가져온 지원자 문서 텍스트는 현재 프로세스의 메모리에만 유지하며 앱을 다시 열면 문서를 다시 추가해야 합니다. 로컬에는 학교·프로그램·학위·학기, 공식 모집요강의 파일명과 구조화된 요건, 민감값이 없는 검수 이력 개수만 저장합니다. Agent에 업로드한 모집요강 파일은 실행 성공·실패 뒤 모두 API의 파일 저장소에서 삭제를 시도합니다.

## 제품 경계

UpCheck는 제출 전 문서 QA만 수행합니다. 합격 가능성 예측, 지원 에세이 대필, 공식 발급 진위 확인, 학점 환산, 비자 승인 판단 또는 학교·정부 시스템 자동 제출은 하지 않습니다.
