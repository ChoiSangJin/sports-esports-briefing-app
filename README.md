# 스포츠 한눈에

Android ARM64용 Flutter 스포츠·e스포츠 스코어보드. 백엔드와 로그인 없이 기기에서 데이터를 조회하고, 사용자가 등록한 Gemini 키로 한국어 브리핑을 생성합니다.

## 실행 및 검증

Flutter **3.35.7** / Dart 3.9.2, JDK 21, Android SDK 36, NDK 27.0.12077973을 사용합니다. 최소 Android 7.0(API 24), ARM64 기기가 필요합니다.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test --reporter expanded
flutter run -d <android-device-id>
```

이 클라우드 작업은 이미 격리돼 있습니다. 기존 `/workspace/sports-esports-briefing-app` 체크아웃을 사용하며 추가 worktree를 만들 필요가 없습니다. 실기기 없이도 어댑터·저장소·캐시·화면 테스트와 APK 빌드가 가능합니다. API 조회 진단은 `dart run scripts/api_smoke.dart`로 실행합니다. 이 명령은 제공처별 가용성을 출력하며 전체 통과를 뜻하는 테스트가 아닙니다.

## 기능

- 리그 필터, 기기 날짜 기준 이전/오늘/다음/달력 탐색, 새로고침, 리그 즐겨찾기 저장
- ESPN NFL/NBA/MLB 스코어와 이닝·쿼터 기록, 상세 리포트·팀 통계
- Jolpica F1 포디움과 전체 드라이버 결과·포인트
- LoL e스포츠 **공식 일정 페이지**의 여러 지역 리그·국제대회 대진과 세트 스코어, 공개 범위 밖 날짜 안내
- **KBO 공식 게임센터 JSON**으로 일정·스코어 조회, 한국 시간 변환, 예정/진행/종료/취소 구분
- Tactical Dark 색상, 리그 네온 액센트, 고정폭 숫자, 승리 팀 강조
- Gemini 키 연결 테스트·암호화 저장·삭제, Google 모델 목록 조회·페이지네이션·모델 ID 직접 입력, AI Studio 링크
- 새 한글 이름, 스코어보드·공 아이콘, Android 적응형 아이콘. 기존 앱 ID·서명·사용자 설정 유지
- 모델별 로컬 요약 캐시, 명시적 재요약, 중복 동시 호출 억제. 종료 경기는 영구 보관하며 진행 중 경기는 5분 후 만료

## 데이터와 개인정보

API 키는 코드나 SharedPreferences에 저장하지 않습니다. Android Keystore 기반 `flutter_secure_storage`를 사용하며 Android 백업을 비활성화했습니다. 키는 검증 요청 성공 후 저장됩니다. 오류 원문은 키나 요청 내용을 노출할 수 있어 사용자 화면·로그에 출력하지 않습니다.

요약 버튼을 누르면 경기 자료와 API 키를 Google Gemini로 전송합니다. 연결 테스트도 Google 요청을 수행합니다. 사용자 Google 계정의 요금·할당량·지역·모델 접근 제한이 적용됩니다. 무료 또는 무제한 사용은 보장하지 않습니다. 요약은 일반 로컬 저장소에 보관됩니다. 앱 삭제 시 설정과 키·캐시가 삭제됩니다.

외부 데이터는 공개 웹사이트와 비공식 API에 의존합니다. LoL과 KBO는 공식 사이트 데이터를 사용하지만, 외부 개발자용으로 안정성을 보장하는 계약형 API는 아닙니다. 제공처 오류는 빈 일정과 구분해 표시하고, 원문 공식 페이지 링크를 제공합니다. LoL은 공식 페이지에 포함된 최근·예정 경기 범위를 표시하며 범위 밖 날짜를 전체 역사 데이터로 간주하지 않습니다. F1은 **확정 결과**를 제공하며 미래 일정·랩별 텔레메트리는 포함하지 않습니다. 키 없이 스코어 조회가 가능합니다. [제공처 조사와 구현 근거](docs/data-sources.md)를 참고하세요.

Gemini 모델은 2.5에 고정하지 않습니다. 설정에서 키 입력 → **사용 가능 모델 불러오기** → 모델 선택(또는 ID 직접 입력) → **연결 테스트 및 암호화 저장**을 진행하세요. 목록은 `generateContent` 지원 모델을 대상으로 하며 명시적인 이미지·음성·임베딩 모델을 제외합니다. 목록에 보여도 실제 접근 권한·할당량은 연결 테스트로 확인해야 합니다. 기존 사용자의 선택 모델은 자동 변경하지 않습니다. 모델별 요금·할당량이 다르며, 새 모델이 나와도 앱 코드를 바꿀 필요 없이 다시 조회할 수 있습니다.

현 버전은 핵심 스코어보드/요약 앱입니다. 독립 RSS 뉴스 피드, 팀별 즐겨찾기, ML Kit 번역 모델 다운로드는 아직 구현하지 않았습니다. 실제 Android 기기에서의 Keystore·외부 브라우저·네트워크와 실제 사용자 키의 Gemini 호출은 별도 확인이 필요합니다.

## 폴더 구조

```text
lib/
  main.dart
  models/unified_match_model.dart
  theme/tactical_dark_theme.dart
  features/
    scores/data/                 # ESPN, Jolpica, official LoL/KBO data
    scores/presentation/         # dashboard, cards, match detail + AI
    settings/api_key_sheet.dart
  services/                     # encrypted keys, Gemini REST/catalog, cache, Riverpod state
test/                           # parsing, failure isolation, cache, widget flow
android/                        # ARM64 Android host, production signing
.github/workflows/              # CI and signed release workflow
```

## 서명 APK 배포

개발·CI는 debug APK를 빌드합니다. 배포용 release 빌드는 디버그 키로 대체하지 않습니다. 아래 환경 변수로 **동일한 배포 키**를 계속 사용해야 기존 앱을 업데이트할 수 있습니다.

```sh
export ANDROID_KEYSTORE_PATH=/secure/path/release.jks
export ANDROID_KEY_ALIAS=sportsbriefing
# ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_PASSWORD는 안전한 실행 환경에서 설정
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

출력: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. `apksigner verify --verbose`로 서명 확인 후 GitHub Release에 APK와 SHA256SUMS를 게시합니다. Android에서 다운로드한 APK의 설치를 허용해야 합니다. Play Store 게시는 별도 작업입니다.

반복 배포는 `Android Release` Actions workflow를 main에서 실행합니다. 저장소 Actions secrets에 `ANDROID_KEYSTORE_BASE64`(keystore의 base64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`가 필요합니다. 비밀값은 코드·이슈·PR·공개 Release에 올리지 마세요. 키와 비밀번호는 안전하게 별도 백업해야 합니다. 릴리스 전에 pubspec 버전과 Android versionCode를 증가시켜 주세요.

선택 날짜에 경기가 없으면 다음 예정 경기를 날짜·시간과 함께 표시합니다. LoL은 공개 일정 범위, F1은 당해/다음 해 달력, ESPN/KBO는 검색 시작일부터 14일 범위를 사용합니다. 과거 날짜 선택 시 예정 경기 검색은 오늘부터 시작합니다.

MLB/NFL/NBA의 중첩 팀 통계를 공통 처리합니다. 기사 본문이 없으면 확인된 주요 경기 기록과 ESPN 제공 관련 기사 링크를 구분해 표시합니다. 관련 뉴스는 해당 경기의 확정 근거로 AI에 전달하지 않습니다. 팀 비교 표와 F1 순위 표는 화면 너비에 맞춰 줄바꿈하며 가로 스크롤 없이 표시합니다.

LoL 상세는 공식 window 피드에서 경기 ID·팀 매핑·종료 프레임을 확인한 뒤 선수별 K/D/A·챔피언·CS·골드·레벨 및 팀 오브젝트 기록을 표시합니다. 기본 초기 프레임을 최종 결과로 사용하지 않습니다. 세트 상태와 공식 영상(한국어 우선)도 제공합니다. KBO 상세는 공식 GetBoxScoreScroll의 선수별 타격·투구·팀 합계·결승타 등 주요 기록과 공식 사이트의 관련 팀 기사 링크를 제공합니다. 폭이 넓은 선수 기록은 항목을 펼친 2열 표로 표시합니다. 원본 데이터가 없거나 조회에 실패하면 해당 항목을 별도로 안내합니다.
