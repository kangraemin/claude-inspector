# 뱃지 클릭 스크롤 점프 수정
## 변경
- `public/index.html`: scrollIntoView를 requestAnimationFrame으로 감싸기 (2곳)
## 검증
- npm start → 프록시 모드에서 뱃지 클릭 시 점프 없이 smooth 스크롤
