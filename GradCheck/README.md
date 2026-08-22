# GradCheck

GradCheck는 해외 대학원 지원을 준비하는 사용자를 위한 네이티브 macOS 문서 QA 워크스페이스입니다. 여러 학교·프로그램의 지원서를 독립적으로 관리하고, 각 지원서의 공식 모집요강에서 추출한 필요 서류와 실제 파일을 대조해 누락·오탈자·문서 간 불일치를 페이지 근거와 함께 보여줍니다.

새 지원서는 `지원 목표 → 공식 모집요강 분석 → 필요 서류 검토 → 지원 파일 업로드` 순서로 만듭니다. CV, SOP, 성적표에 고정되지 않고 추천서 수량, GRE/GMAT, Writing Sample, 포트폴리오, 연구계획서, 학위증명, 여권·비자 서류 등 모집요강에서 확인된 항목으로 체크리스트가 동적으로 구성됩니다.

저장소에는 실제 개인정보가 없는 결정론적 샘플 워크스페이스와 오프라인 우선 문서 흐름이 포함되어 있습니다. 텍스트 레이어가 있는 PDF와 텍스트 파일은 로컬에서 읽고, 실행 환경에 `UPSTAGE_API_KEY`가 있을 때만 Upstage Document Parse 어댑터가 활성화됩니다.

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

## 선택 사항: Upstage 연결

Xcode 스킴의 환경 변수에 `UPSTAGE_API_KEY`를 설정하세요. 이후 가져온 PDF와 이미지는 GradCheck 검증 규칙을 실행하기 전에 Upstage Document Parse로 구조화됩니다. 키가 없으면 지원되는 PDF 및 텍스트 콘텐츠를 온디바이스로 추출하며 샘플 데모는 그대로 동작합니다.

모델 교체와 별도 배포 환경을 위해 다음 설정도 선택적으로 사용할 수 있습니다.

- `UPSTAGE_DOCUMENT_MODEL`: 기본값 `document-parse`
- `UPSTAGE_DOCUMENT_ENDPOINT`: 기본값 `https://api.upstage.ai/v1/document-digitization`
- `UPSTAGE_DOCUMENT_TIMEOUT`: 요청 제한 시간(초), 기본값 `90`

문서 분석은 `DocumentAnalyzing`/`DocumentModelService` 프로토콜 뒤에 있으며, 다른 Upstage 모델이나 추가 공급자를 앱의 ViewModel과 분리해 붙일 수 있습니다. 앱 상태는 `AppViewModel`, 다중 지원서 도메인은 `ApplicationPortfolio`/`ApplicationSession`, 저장은 `ApplicationRepository`가 담당합니다.

API 키, 지원자 이름, 지원자 서류 파일명, 원문 텍스트와 evidence excerpt는 앱 설정에 기록하지 않습니다. 가져온 지원자 문서 텍스트는 현재 프로세스의 메모리에만 유지하며 앱을 다시 열면 문서를 다시 추가해야 합니다. 로컬에는 학교·프로그램·학위·학기, 공식 모집요강의 파일명과 구조화된 요건, 민감값이 없는 검수 이력 개수만 저장합니다.

## 제품 경계

GradCheck는 제출 전 문서 QA만 수행합니다. 합격 가능성 예측, 지원 에세이 대필, 공식 발급 진위 확인, 학점 환산, 비자 승인 판단 또는 학교·정부 시스템 자동 제출은 하지 않습니다.
