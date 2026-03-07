# Homebrew Cask 배포 준비

## Phase 0: 뱃지 클릭 버그 수정
- `public/index.html`: highlightMechInJsonTree의 `.jt-str` 셀렉터를 `.jt-str, .jt-str-expanded, .jt-str-preview`로 확장

## Phase 1: package.json 수정
- `artifactName`: `Claude-Inspector-${version}-${arch}.${ext}`
- `notarize`: `{ "teamId": "${env.APPLE_TEAM_ID}" }`

## Phase 2: GitHub Actions Release Workflow
- `.github/workflows/release.yml`: tag push → build → release → tap update

## Phase 3: Homebrew Tap 파일
- `homebrew-tap/Casks/claude-inspector.rb`: Cask formula
- `homebrew-tap/README.md`: 설치 가이드

## 검증
- npm run dist:mac → 정규화된 DMG 파일명
- actionlint → workflow 문법
