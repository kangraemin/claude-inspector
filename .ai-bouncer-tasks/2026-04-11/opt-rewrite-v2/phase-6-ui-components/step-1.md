# Step 1: ProxyPanel + ProxyList

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | Header.tsx — 로고, 언어 토글 버튼 | 컴포넌트 파일 존재 | ✅ |
| TC-02 | ProxyControl.tsx — Start/Stop 버튼, 상태 표시 | 컴포넌트 파일 존재 | ✅ |
| TC-03 | ProxyList.tsx — captures 목록 표시 | 컴포넌트 파일 존재 | ✅ |
| TC-04 | i18n/index.ts — t() 함수 동작 | ko/en 문자열 반환 | ✅ |
| TC-05 | npx tsc --noEmit 에러 없음 | exit 0 | ✅ |

검증 명령어:
```bash
ls src/presentation/components/Header/ src/presentation/components/ProxyPanel/ src/i18n/
npx tsc --noEmit && echo "tsc OK"
```

## 실행출력

```
$ ls src/presentation/components/Header/ src/presentation/components/ProxyPanel/ src/i18n/
src/i18n/:
index.ts

src/presentation/components/Header/:
Header.tsx

src/presentation/components/ProxyPanel/:
ProxyControl.tsx
ProxyList.tsx

$ npx tsc --noEmit && echo "tsc OK"
tsc OK
```

TC-01 ✅ Header.tsx — 로고, 언어 토글 버튼
TC-02 ✅ ProxyControl.tsx — Start/Stop 버튼, 상태 표시
TC-03 ✅ ProxyList.tsx — captures 목록 표시
TC-04 ✅ i18n/index.ts — t() 함수 동작
TC-05 ✅ tsc --noEmit → exit 0
