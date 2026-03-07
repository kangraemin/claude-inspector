# 뱃지 클릭 스크롤 점프 수정 v2
## 변경
- `public/index.html`: `code.scrollTop = prevScrollTop`을 동기 실행에서 `requestAnimationFrame` 내부로 이동 (1줄 변경)
## 검증
- npm start → 프록시 모드에서 뱃지 클릭 시 현재 스크롤 위치에서 부드럽게 이동 확인
- e2e 테스트 실행
