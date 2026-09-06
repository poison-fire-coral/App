# 마이그레이션

## 왜 히스토리가 하나뿐인가

2026-09-06에 **베이스라인을 다시 잡았다.**

그전까지 마이그레이션은 두 개(`init`, `add_user_devices`)뿐이었는데,
그 사이 스키마는 `prisma db push`로 계속 바뀌어 왔다. 그래서 히스토리가
`schema.prisma`를 재현하지 못했다 — 빠져 있던 것만 해도 이 정도다.

- `QuestType` enum 자체 (퀘스트 7종 유형)
- `users.refresh_token` (없으면 토큰 갱신이 통째로 깨진다)
- `places.image_url` (히스토리에는 `photo_url`로 남아 있었다)
- `quests`의 유형별 컬럼 10여 개 (`quiz_*`, `time_window_*`, `required_count` …)
- `places(lat, lng)`와 `quest_completions(is_abused, created_at)` 인덱스

즉 **빈 DB에 `migrate deploy`를 하면 서버가 기동하자마자 깨지는 DB**가 나왔다.
운영 DB를 만들 수 없는 상태였다.

옛 마이그레이션 두 개를 지우고, 현재 스키마 전체를 재현하는 단일
`20260906000000_baseline`으로 대체했다.

## 새 데이터베이스 (운영 포함)

```bash
npx prisma migrate deploy
```

베이스라인이 처음부터 전부 만든다. 확인:

```bash
# 스키마와 DB가 일치하면 아무 SQL도 나오지 않는다
npx prisma migrate diff --from-schema-datasource prisma/schema.prisma \
                        --to-schema prisma/schema.prisma --script
```

## 이미 테이블이 있는 데이터베이스 (기존 로컬 개발 DB)

베이스라인을 **실행하지 말고 "이미 적용됨"으로만 표시한다.**
실행하면 있는 테이블을 다시 만들려다 실패한다.

```bash
npx prisma migrate resolve --applied 20260906000000_baseline
```

그다음 위의 `migrate diff`로 차이가 없는지 확인한다. 차이가 나오면 그 DB는
스키마보다 뒤처져 있는 것이므로, 나온 SQL을 직접 적용하거나
(개발 DB라면) 지우고 다시 만든다.

## 앞으로

스키마를 고칠 때는 `prisma db push`가 아니라 `prisma migrate dev`를 쓴다.
`db push`는 히스토리를 남기지 않아서, 지금 겪은 일이 그대로 반복된다.
