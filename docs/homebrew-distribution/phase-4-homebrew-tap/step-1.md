# Phase 4 Step 1: Create Homebrew tap reference files

## 변경 대상
- `homebrew-tap/Casks/claude-inspector.rb` (신규)
- `homebrew-tap/README.md` (신규)

## TC

| TC | 설명 | 예상 결과 | 실제 결과 |
|----|------|-----------|-----------|
| TC-1 | Cask formula with on_arm/on_intel | 양 아키텍처 URL + sha256 | ✅ |
| TC-2 | README with install guide | brew tap + install 명령어 | ✅ |
