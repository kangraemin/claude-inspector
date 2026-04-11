# Step 2: InMemory 레포지토리

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | InMemoryCaptureRepository — ICaptureRepository 구현 | add/getAll/updateResponse/clear 동작 | ✅ |
| TC-02 | LocalStorageAuthStore — IAuthCredentialStore 구현 | save/load/clear 동작 | ✅ |
| TC-03 | npx tsc --noEmit 에러 없음 | exit 0 | ✅ |

검증 명령어:
```bash
ls src/infrastructure/repositories/
npx tsc --noEmit && echo "tsc OK"
```

## 실행출력

```
$ ls src/infrastructure/repositories/
InMemoryCaptureRepository.ts
LocalStorageAuthStore.ts

$ npx tsc --noEmit && echo "tsc OK"
tsc OK
```

TC-01 ✅ InMemoryCaptureRepository — add/getAll/updateResponse/clear 동작
TC-02 ✅ LocalStorageAuthStore — save/load/clear 동작
TC-03 ✅ tsc --noEmit → exit 0
