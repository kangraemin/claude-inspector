# Phase 2 Step 1: Add artifactName and notarize to package.json

## 변경 대상
- `package.json`: `build.mac` 섹션

## TC

| TC | 설명 | 예상 결과 | 실제 결과 |
|----|------|-----------|-----------|
| TC-1 | artifactName 추가 | `Claude-Inspector-${version}-${arch}.${ext}` | ✅ 추가 완료 |
| TC-2 | notarize 설정 추가 | `teamId: ${env.APPLE_TEAM_ID}` | ✅ 추가 완료 |
