# README 깨진 링크 및 스크린샷 수정

## 변경 파일별 상세

### `README.md`
- **변경 이유**: `[How It Works](#how-it-works)` 앵커가 존재하지 않는 섹션을 가리킴
- **Before** (현재 코드):
```
[Install](#install) · [What You'll Learn](#what-youll-learn) · [Proxy Mode](#proxy-mode) · [How It Works](#how-it-works)
```
- **After** (변경 후):
```
[Install](#install) · [What You'll Learn](#what-youll-learn) · [Proxy Mode](#proxy-mode) · [Tech Stack](#tech-stack)
```
- **영향 범위**: 네비게이션 링크만 변경, 다른 파일 영향 없음

### `README.ko.md`
- **변경 이유 1**: `[동작 원리](#동작-원리)` 앵커가 존재하지 않는 섹션을 가리킴
- **Before**:
```
[설치](#설치) · [배울 수 있는 것들](#배울-수-있는-것들) · [프록시 모드](#프록시-모드) · [동작 원리](#동작-원리)
```
- **After**:
```
[설치](#설치) · [배울 수 있는 것들](#배울-수-있는-것들) · [프록시 모드](#프록시-모드) · [기술 스택](#기술-스택)
```

- **변경 이유 2**: 한국어 스크린샷 파일이 존재하는데 영어 스크린샷을 사용 중
- **Before**:
```html
<img src="public/screenshots/proxy-request-en.png" width="100%" alt="Proxy — CLAUDE.md Global/Local 섹션 칩과 인라인 텍스트 하이라이트가 표시된 Request 뷰" />
<img src="public/screenshots/proxy-analysis-en.png" width="100%" alt="Proxy — 5가지 메커니즘을 자동 감지하고 섹션 내용을 보여주는 Analysis 뷰" />
```
- **After**:
```html
<img src="public/screenshots/proxy-request-ko.png" width="100%" alt="Proxy — CLAUDE.md Global/Local 섹션 칩과 인라인 텍스트 하이라이트가 표시된 Request 뷰" />
<img src="public/screenshots/proxy-analysis-ko.png" width="100%" alt="Proxy — 5가지 메커니즘을 자동 감지하고 섹션 내용을 보여주는 Analysis 뷰" />
```
- **영향 범위**: 네비게이션 링크 + 스크린샷 경로만 변경

## 검증
- 검증 명령어: `grep -n 'how-it-works\|동작-원리\|proxy-request-en\|proxy-analysis-en' README.md README.ko.md`
- 기대 결과: 출력 없음 (모든 깨진 링크/잘못된 스크린샷 제거됨)
