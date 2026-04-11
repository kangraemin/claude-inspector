# Phase 5: Presentation Layer

## 목표
DI 컨테이너, Zustand 스토어, 훅, App 최상위 구조를 구현하여 React 데이터 흐름을 완성한다.

## 범위
- `src/presentation/di/container.ts` — 의존성 주입 컨테이너
- `src/presentation/store/captureStore.ts` — 캡처 목록 상태
- `src/presentation/store/aiflowStore.ts` — AI Flow 분석/최적화/채팅 상태
- `src/presentation/store/uiStore.ts` — UI 상태 (탭, 검색, 필터)
- `src/presentation/hooks/useAnalyzeAiFlow.ts`
- `src/presentation/hooks/useOptimization.ts`
- `src/presentation/hooks/useProxy.ts`
- `src/presentation/hooks/useElectronEvents.ts`
- `src/App.tsx` — DI Provider + 최상위 레이아웃

## Steps
1. DI 컨테이너 및 Zustand 스토어
2. hooks
3. App 최상위 구조
