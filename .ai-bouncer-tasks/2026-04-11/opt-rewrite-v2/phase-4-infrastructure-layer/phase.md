## 목표
포트 구현체 (Electron IPC 어댑터, InMemory 레포지토리). window.electronAPI를 통해 IPC와 연결.

## 범위
- `src/infrastructure/electron/ElectronAnalysisService.ts`
- `src/infrastructure/electron/ElectronProxyGateway.ts`
- `src/infrastructure/electron/ElectronEventBus.ts`
- `src/infrastructure/repositories/InMemoryCaptureRepository.ts`
- `src/types/electron.d.ts` — window.electronAPI 타입 선언

## Steps
- Step 1: Electron 어댑터 (ElectronAnalysisService, ElectronProxyGateway, ElectronEventBus + 타입 선언)
- Step 2: InMemory 레포지토리 (InMemoryCaptureRepository)
