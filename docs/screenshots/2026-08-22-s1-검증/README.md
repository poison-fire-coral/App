# S1 실기기 검증 기록 — 2026-08-22

기기: SM S931N (Android 16) · 백엔드: 로컬 5001 (`adb reverse`)
빌드: `flutter build apk --debug --dart-define=API_BASE_URL=http://localhost:5001/api/v1`

---

## 발견한 버그 3건

### 01 → 02 · 로그인 화면이 통째로 비어 있었다

`SingleChildScrollView` 안에서 `Spacer`를 써서 배치에 실패했다.
스크롤뷰는 최대 높이가 무한이라 flex 자식을 놓을 수 없다.

```
RenderFlex children have non-zero flex but incoming height constraints are unbounded.
```

`flutter analyze`도 빌드도 통과했다. **컴파일되는 것과 그려지는 것은 다르다.**
`IntrinsicHeight`로 해결. 회귀 방지: `test/screens_render_test.dart`

### 05 · 실기기인데 에뮬레이터 주소로 요청이 나갔다

`--dart-define=API_BASE_URL` 없이 빌드하면 `10.0.2.2`(에뮬레이터 전용)로 붙는다.
실기기에선 갈 곳이 없어 타임아웃까지 로딩만 돈다.
**실기기 빌드에는 dart-define을 반드시 넣을 것.**

### 13 → 14 · NoteBox 안의 글자가 앱 전역에서 안 보였다

"빛은 위에서 온다"를 테두리 네 면에 다른 색으로 표현했는데,
Flutter는 `borderRadius`가 있는 비균일 테두리를 만나면
**paint 단계에서 예외를 던지고 자식을 통째로 그리지 않는다.**

```
A borderRadius can only be given on borders with uniform colors.
```

11곳이 영향받고 있었다. 그늘을 inset 그림자로 바꿔 해결.
회귀 방지: `test/widgets_paint_test.dart`

---

## 요구사항 확인

| 화면 | 확인한 것 |
|---|---|
| 04 | 개발자 모드를 켜면 GUEST 로그인 버튼이 나타난다 |
| 06 | 홈 — 진행 중 퀘스트만 e3, 추천은 e2, 등급별 TierBadge 색 분리, amber EXP 알약 |
| 07 | 온보딩 1D — 아바타 6종, 뒤로 버튼, 8권역 드롭다운. 조건 미충족이라 버튼 2개 모두 비활성 |
| 08 | `abc@1` → "한글·영문·숫자만 쓸 수 있어요" + 붉은 테두리 |
| 09 | 형식 통과 → 중복확인만 활성, **판정 메시지는 아직 없음**, 다음은 여전히 잠김 |
| 10 | 중복확인이 실제 백엔드를 타고 통과 → jade 메시지 + 다음 활성 |
| 11 | 온보딩 1E — 키워드 **0개 선택 상태로 시작**, "3개 남음", 다음 비활성 |
| 12 | 3개 선택 → "3개 선택됨 · 더 고르셔도 좋아요" + 다음 활성 |

03은 구글 로그인 SDK가 실제로 동작함을 확인한 것(계정 선택창).
사용자 개인 계정이라 진행하지 않고 GUEST로 전환했다.

---

## 아직 안 해본 것

퀘스트 수락 → 순간이동 → 인증 → 보상 → 레벨업 사이클.

확인할 것: 앱이 표시한 EXP == `quest_completions.exp_awarded`,
홈 상단 레벨 링 == `users.level` / `users.exp_current`.
