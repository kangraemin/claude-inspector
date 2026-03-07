# Phase 3 Step 1: Create GitHub Actions release workflow

## 변경 대상
- `.github/workflows/release.yml` (신규)

## TC

| TC | 설명 | 예상 결과 | 실제 결과 |
|----|------|-----------|-----------|
| TC-1 | v* 태그 push 트리거 | `on.push.tags: ['v*']` | ✅ |
| TC-2 | matrix build (arm64 + x64) | macos-latest + macos-13 | ✅ |
| TC-3 | release job with softprops/action-gh-release | artifact upload + release | ✅ |
| TC-4 | update-homebrew job | SHA256 계산 + tap repo 업데이트 | ✅ |
