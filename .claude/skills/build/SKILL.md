---
name: build
description: Build and package Claude Inspector as a distributable Electron app (.dmg / .exe)
user-invocable: true
---

## Claude Inspector 빌드

```bash
npm run dist        # 현재 플랫폼 (macOS면 .dmg)
npm run dist:mac    # macOS arm64 + x64 .dmg
npm run dist:win    # Windows .exe (NSIS)
```

Output: `release/` 디렉토리

## 빌드 전 체크
- `npm start` 로 앱 실행해서 최종 동작 확인
- `git status` 로 미커밋 변경사항 확인

## 현재 상태
- 버전: !`node -e "const p=require('./package.json');console.log(p.version)"`
- 브랜치: !`git branch --show-current`
- 미커밋: !`git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' '` 개 파일
