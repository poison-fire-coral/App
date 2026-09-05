import { prisma } from "../src/utils/prisma";


/**
 * 배지 정의 (S4).
 *
 * 규칙은 **DB에 데이터로** 둔다. 의뢰서 S4 BE 2가 "코드에 하드코딩 금지"를 명시했고,
 * 그래야 임계값을 앱 재배포 없이 조정할 수 있다.
 *
 * ruleJson 스키마는 네 가지뿐이다:
 *   { type: "TOTAL" }                          아무 퀘스트나
 *   { type: "REGION",       value: "경기" }     특정 지역
 *   { type: "REGION_COUNT" }                   서로 다른 지역 N곳
 *   { type: "QUEST_TYPE",   value: "QUIZ" }    특정 유형
 *
 * 목표치는 ruleJson이 아니라 `threshold` 컬럼에만 둔다.
 * 두 군데에 넣으면 어느 쪽이 진실인지 헷갈린다.
 *
 * 이전 버전은 키워드 기반이었는데, 온보딩(`#골목산책`)·시드(`골목`)·카카오(`산책`)의
 * 어휘가 세 갈래로 갈려 6개 중 5개가 영원히 열리지 않았다. 지역·유형은 자유 텍스트가
 * 아니라 DB 컬럼이라 그 문제가 없다.
 */
const BADGES = [
  // ── 특수 ──────────────────────────────────────────────────────────────
  {
    name: "첫 발자국",
    description: "첫 퀘스트를 마쳤어요. 여기서부터가 시작이에요.",
    ruleJson: { type: "TOTAL" },
    threshold: 1,
    artKey: "first_step",
  },
  {
    name: "스무 걸음",
    description: "퀘스트 20개를 마쳤어요. 이제 익숙한 길이 생겼겠네요.",
    ruleJson: { type: "TOTAL" },
    threshold: 20,
    artKey: "twenty_steps",
  },

  // ── 지역 ──────────────────────────────────────────────────────────────
  {
    name: "경기 순례자",
    description: "경기에서 퀘스트 5개를 마쳤어요.",
    ruleJson: { type: "REGION", value: "경기" },
    threshold: 5,
    regionCode: "경기",
    artKey: "region_gyeonggi",
  },
  {
    name: "서울 산책자",
    description: "서울에서 퀘스트 5개를 마쳤어요.",
    ruleJson: { type: "REGION", value: "서울" },
    threshold: 5,
    regionCode: "서울",
    artKey: "region_seoul",
  },
  {
    name: "제주 바람",
    description: "제주에서 퀘스트 3개를 마쳤어요.",
    ruleJson: { type: "REGION", value: "제주" },
    threshold: 3,
    regionCode: "제주",
    artKey: "region_jeju",
  },
  {
    name: "팔도 유람",
    description: "서로 다른 다섯 지역에 발자국을 남겼어요.",
    ruleJson: { type: "REGION_COUNT" },
    threshold: 5,
    artKey: "region_all",
  },

  // ── 유형 ──────────────────────────────────────────────────────────────
  {
    name: "셔터를 누르는 손",
    description: "피사체 지정형 퀘스트 3개를 마쳤어요.",
    ruleJson: { type: "QUEST_TYPE", value: "PHOTO_SINGLE" },
    threshold: 3,
    artKey: "type_photo",
  },
  {
    name: "모으는 재미",
    description: "수집 사진형 퀘스트 3개를 마쳤어요.",
    ruleJson: { type: "QUEST_TYPE", value: "PHOTO_COLLECT" },
    threshold: 3,
    artKey: "type_collect",
  },
  {
    name: "수수께끼 풀이",
    description: "퀴즈형 퀘스트 3개를 마쳤어요.",
    ruleJson: { type: "QUEST_TYPE", value: "QUIZ" },
    threshold: 3,
    artKey: "type_quiz",
  },
  {
    name: "길 없는 길",
    description: "탐색형 퀘스트 3개를 마쳤어요.",
    ruleJson: { type: "QUEST_TYPE", value: "EXPLORATION" },
    threshold: 3,
    artKey: "type_explore",
  },
  {
    name: "해 질 무렵",
    description: "시간대 제한형 퀘스트 3개를 마쳤어요.",
    ruleJson: { type: "QUEST_TYPE", value: "TIME_WINDOW" },
    threshold: 3,
    artKey: "type_time",
  },
  {
    name: "기록하는 사람",
    description: "기록형 퀘스트 3개를 마쳤어요.",
    ruleJson: { type: "QUEST_TYPE", value: "RECORD" },
    threshold: 3,
    artKey: "type_record",
  },

  // ── 히든 ──────────────────────────────────────────────────────────────
  // 5a 화면의 "미공개(?)" 상태를 실제로 채운다. 목록 API가 이름·설명을 가린다.
  {
    name: "새벽을 여는 사람",
    description: "시간대 제한형 퀘스트를 10개 마쳤어요.",
    ruleJson: { type: "QUEST_TYPE", value: "TIME_WINDOW" },
    threshold: 10,
    hidden: true,
    artKey: "hidden_dawn",
  },
];

async function main() {
  console.log("테스트 데이터 생성 시작...");

  // 기존 데이터 초기화
  await prisma.questCompletion?.deleteMany().catch(() => {});
  await prisma.userQuest.deleteMany();
  await prisma.quest.deleteMany();
  await prisma.place.deleteMany();
  await prisma.levelTable.deleteMany();

  // 1. 레벨 테이블 (기획서 6c)
  //
  //  주의: 서버는 `row(N).requiredExp`를 "레벨 N-1 → N 승급 비용"으로 읽는다
  //  (exp-engine.service.ts:67). 그래서 클라이언트 LevelSystem 테이블을
  //  한 칸 밀어 넣어야 양쪽 레벨이 정확히 일치한다.
  //
  //  Lv15까지는 기획서에 명시된 값을 그대로 쓰고, Lv16~30은 2,000 고정이다.
  //  (이전 시드는 값이 기획서와 달랐고 Lv10에서 끊겨 그 위로 레벨업이 멈췄다)
  await prisma.levelTable.createMany({
    data: [
      { level: 1, requiredExp: 0 },
      { level: 2, requiredExp: 100 },
      { level: 3, requiredExp: 150 },
      { level: 4, requiredExp: 220 },
      { level: 5, requiredExp: 300 },
      { level: 6, requiredExp: 400 },
      { level: 7, requiredExp: 500 },
      { level: 8, requiredExp: 620 },
      { level: 9, requiredExp: 770 },
      { level: 10, requiredExp: 950 },
      { level: 11, requiredExp: 1150 },
      { level: 12, requiredExp: 1350 },
      { level: 13, requiredExp: 1550 },
      { level: 14, requiredExp: 1750 },
      { level: 15, requiredExp: 2150 },
      { level: 16, requiredExp: 2000 },
      { level: 17, requiredExp: 2000 },
      { level: 18, requiredExp: 2000 },
      { level: 19, requiredExp: 2000 },
      { level: 20, requiredExp: 2000 },
      { level: 21, requiredExp: 2000 },
      { level: 22, requiredExp: 2000 },
      { level: 23, requiredExp: 2000 },
      { level: 24, requiredExp: 2000 },
      { level: 25, requiredExp: 2000 },
      { level: 26, requiredExp: 2000 },
      { level: 27, requiredExp: 2000 },
      { level: 28, requiredExp: 2000 },
      { level: 29, requiredExp: 2000 },
      { level: 30, requiredExp: 2000 },
    ],
  });

  // 2. 장소 데이터 생성
  //
  // **퀘스트마다 장소 행을 따로 만든다.** 예전에는 앵커 3곳만 만들고 퀘스트 21개를
  // 거기에 매달았는데, `Quest`에는 좌표가 없고 `Place`에만 있어서 같은 앵커에 달린
  // 퀘스트들이 지도에서 **완전히 포개졌다** — 행궁동 한 점에 14개가 겹쳐 맨 위 하나만
  // 눌렸다. 인증 반경의 중심도 실제 목표 지점이 아니라 동네 대표 좌표였다.
  //
  // 앵커를 중심으로 25m 링 위에 흩뿌린다. 같은 동네라는 사실(이름·주소·지역)은
  // 그대로 두고 좌표만 갈라 놓는다.
  const ANCHORS = {
    suwonHwaseong: {
      name: "수원화성 방화수류정",
      // 카카오 로컬 API가 만드는 Place와 같은 형식을 쓴다(주소 첫 토큰).
      // 지역 배지가 시드·카카오 양쪽을 같은 기준으로 세려면 표기가 하나여야 한다.
      regionCode: "경기",
      address: "경기도 수원시 팔달구 수원천로392번길 44-6",
      lat: 37.2882,
      lng: 127.0163,
      congestionScore: 25,
      imageUrl: "https://example.com/suwon.jpg",
    },
    haenggung: {
      name: "수원 행궁동 카페거리",
      regionCode: "경기",
      address: "경기도 수원시 팔달구 신풍로 23",
      lat: 37.2845,
      lng: 127.0135,
      congestionScore: 60,
      imageUrl: "https://example.com/haenggung.jpg",
    },
    namsan: {
      name: "서울 N서울타워 및 남산 일대",
      regionCode: "서울",
      address: "서울특별시 용산구 남산공원길 105",
      lat: 37.5512,
      lng: 126.9882,
      congestionScore: 80,
      imageUrl: "https://example.com/seoultower.jpg",
    },
  } as const;

  type AnchorKey = keyof typeof ANCHORS;

  /** 앵커별로 몇 개째인지 세어 링 위 각도를 정한다. */
  const spotCount: Record<string, number> = {};

  /**
   * 앵커 주변에 퀘스트 하나짜리 장소를 만든다.
   *
   * 한 바퀴(8칸)를 채우면 반지름을 한 단계 넓힌다. 25m는 인증 반경(50m)보다
   * 작아 "같은 자리"라는 감각을 해치지 않으면서, 지도에서는 핀이 갈라진다.
   */
  async function spotFor(key: AnchorKey) {
    const a = ANCHORS[key];
    const i = spotCount[key] ?? 0;
    spotCount[key] = i + 1;

    if (i === 0) {
      return prisma.place.create({ data: { ...a } });
    }

    const ring = Math.ceil(i / 8);
    const angle = ((i - 1) % 8) * (Math.PI / 4);
    const meters = 25 * ring;

    // 위도 1e-5 ≈ 1.11m. 경도는 위도가 올라갈수록 좁아지므로 cos을 곱한다.
    const dLat = (meters * Math.cos(angle)) / 111_320;
    const dLng =
      (meters * Math.sin(angle)) / (111_320 * Math.cos((a.lat * Math.PI) / 180));

    return prisma.place.create({
      data: {
        ...a,
        lat: Number((a.lat + dLat).toFixed(6)),
        lng: Number((a.lng + dLng).toFixed(6)),
      },
    });
  }

  // 3. 21개 시드 퀘스트 데이터 생성 (현재 스키마에 필드 일치)
  // `createMany`가 아니라 하나씩 만든다 — 퀘스트마다 자기 좌표를 가진 장소를
  // 먼저 만들어야 해서다. 21건이라 왕복 수는 문제가 되지 않는다.
  const SEED_QUESTS: Array<
    { anchor: AnchorKey } & Omit<
      Parameters<typeof prisma.quest.create>[0]["data"],
      "placeId" | "place"
    >
  > = [
      // ── 01 방문형 ─────────────────────────────────────────────
      { anchor: "suwonHwaseong", title: "등대 끝까지", story: "방파제 입구에서 등대까지 300m. 끝에 서서 항구를 등지고 한 번 돌아보면 도시 전체가 보인다.", difficulty: 1, baseExp: 50, radiusM: 50, keywords: ["바다", "산책"], active: true, questType: "VISIT" },
      { anchor: "haenggung", title: "이름 없는 계단", story: "지도에 이름이 없는 108칸 계단. 위쪽 골목까지 올라가면 인증된다. 내려올 땐 다른 길을 권한다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["골목", "체력"], active: true, questType: "VISIT" },
      { anchor: "haenggung", title: "시장 뒷문으로 들어가기", story: "정문이 아니라 상인들이 쓰는 뒷문. 들어서는 풍경이 완전히 다르다.", difficulty: 1, baseExp: 50, radiusM: 50, keywords: ["시장", "로컬"], active: true, questType: "VISIT" },

      // ── 05 시간대 제한형 ──────────────────────────────────────
      { anchor: "haenggung", title: "새벽 4시의 경매", timeWindowStart: "04:00", timeWindowEnd: "06:00", story: "수협 위판장 경매는 해가 뜨기 전에 끝난다. 관광객이 거의 없는 두 시간.", difficulty: 3, baseExp: 220, radiusM: 50, keywords: ["시장", "로컬", "새벽"], active: true, questType: "TIME_WINDOW" },
      { anchor: "suwonHwaseong", title: "해 지기 30분 전, 언덕", timeWindowStart: "SUNSET-30", timeWindowEnd: "SUNSET+20", story: "일몰 시각은 매일 자동 계산되어 창이 움직인다. 오늘은 19:12에 열린다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["노을", "산책"], active: true, questType: "TIME_WINDOW" },
      { anchor: "haenggung", title: "문 여는 순간의 국밥집", timeWindowStart: "07:00", timeWindowEnd: "07:30", story: "첫 손님으로 앉아보기. 오픈 직후 30분은 육수가 가장 진하다는 말이 있다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["음식", "새벽"], active: true, questType: "TIME_WINDOW" },

      // ── 06 피사체 지정형 ──────────────────────────────────────
      { anchor: "haenggung", title: "가장 오래된 간판", photoPrompt: "손글씨 간판을 정면에서, 글자가 읽히게", story: "이 골목에서 손글씨로 쓰인 간판 하나를 찾아 정면으로 담아라. 글자가 읽히게.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["골목", "기록"], active: true, questType: "PHOTO_SINGLE" },
      { anchor: "suwonHwaseong", title: "굴뚝과 하늘", photoPrompt: "굴뚝 전체가 프레임에 들어오도록", story: "붉은 벽돌 굴뚝 전체가 프레임에 들어오는 자리는 딱 한 곳이다. 뒷골목 주차장에서 찾아보라.", difficulty: 3, baseExp: 220, radiusM: 50, keywords: ["근대건축", "사진"], active: true, questType: "PHOTO_SINGLE" },
      { anchor: "haenggung", title: "오늘의 메뉴판", photoPrompt: "오늘 날짜의 메뉴판 전체", story: "매일 손으로 고쳐 쓰는 메뉴판을 찍어라. 어제와 오늘이 다르다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["음식", "로컬"], active: true, questType: "PHOTO_SINGLE" },

      // ── 08 수집 사진형 ────────────────────────────────────────
      { anchor: "haenggung", title: "골목 고양이 세 마리", requiredCount: 3, story: "이 동네에 사는 고양이 세 마리를 각각 다른 골목에서 만나라. 쫓지 말 것.", difficulty: 4, baseExp: 400, radiusM: 200, keywords: ["골목", "고양이"], active: true, questType: "PHOTO_COLLECT" },
      { anchor: "haenggung", title: "파란 대문 다섯 개", requiredCount: 5, story: "이 언덕 주택가엔 유난히 파란 페인트 대문이 많다. 다섯 개를 찾으면 이유를 알려준다.", difficulty: 4, baseExp: 400, radiusM: 300, keywords: ["골목", "수집"], active: true, questType: "PHOTO_COLLECT" },
      { anchor: "haenggung", title: "시장의 네 가지 냄새", requiredCount: 4, story: "기름·건어물·나물·떡. 각 구역에서 한 장씩. 시장 지리를 저절로 익히게 된다.", difficulty: 3, baseExp: 220, radiusM: 200, keywords: ["시장", "음식"], active: true, questType: "PHOTO_COLLECT" },

      // ── 09 퀴즈형 ─────────────────────────────────────────────
      { anchor: "suwonHwaseong", title: "비석에 적힌 해", quizQuestion: "이 비석이 세워진 연도는?", quizOptions: ["1794년", "1834년", "1901년"], quizAnswer: "1794년", quizExplanation: "정조 18년, 화성 축성이 시작된 해다.", story: "\"이 비석이 세워진 연도는?\" 마당 왼쪽 끝, 이끼에 절반 덮인 글씨를 찾아야 한다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["역사"], active: true, questType: "QUIZ" },
      { anchor: "haenggung", title: "이 집에서 가장 싼 것", quizQuestion: "메뉴판에서 가장 저렴한 메뉴는?", quizOptions: ["잔치국수", "비빔밥", "수제비"], quizAnswer: "잔치국수", quizExplanation: "40년째 가격을 거의 올리지 않은 메뉴다.", story: "벽에 붙은 메뉴판에서 제일 저렴한 메뉴 이름은? 정답을 맞히면 이 집 40년 역사를 알려준다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["음식", "로컬"], active: true, questType: "QUIZ" },
      { anchor: "haenggung", title: "몇 칸일까", quizQuestion: "이 계단은 몇 칸인가?", quizOptions: ["96칸", "108칸", "120칸"], quizAnswer: "108칸", quizExplanation: "백팔번뇌에서 따온 숫자라는 이야기가 전해진다.", story: "이 계단은 정확히 몇 칸인가. 세면서 오르는 수밖에 없다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["골목", "체력"], active: true, questType: "QUIZ" },

      // ── 10 탐색형 ─────────────────────────────────────────────
      // TODO(콘텐츠): 탐색형은 `quizQuestion`·`quizOptions`·`quizAnswer`가 있어야
      // 채점된다. 비어 있으면 서버가 채점을 건너뛰어 도달만으로 완료된다.
      // 현장을 아는 사람이 실제 값을 채워야 한다 — 지어내면 현장에서 틀린다.
      { anchor: "haenggung", title: "벽화의 연도", story: "이 언덕 어딘가에 고래 벽화가 있다. 오른쪽 아래 서명 옆에 적힌 연도를 찾아라.", difficulty: 4, baseExp: 400, radiusM: 400, keywords: ["골목", "탐색"], active: true, questType: "EXPLORATION" },
            // 스토리가 "찾아서 찍어라"이므로 사진형이다. 탐색형으로 두면 정답을 물어야
      // 하는데 물을 것이 없어, 걸어가기만 해도 완료되는 이름뿐인 유형이 된다.
      { anchor: "namsan", title: "두 갈래 나무", story: "밑동이 둘로 갈라진 큰 나무 한 그루. 주민들은 여기서 만나기로 약속한다. 찾아서 찍어라.", difficulty: 4, baseExp: 400, radiusM: 500, keywords: ["자연", "탐색"], active: true, questType: "PHOTO_SINGLE", photoPrompt: "밑동이 둘로 갈라진 나무" },
      { anchor: "namsan", title: "폐선로의 끝", story: "기차가 다니지 않는 선로가 어느 집 담에서 끊긴다. 그 담의 색을 답하라.", difficulty: 4, baseExp: 400, radiusM: 300, keywords: ["근대건축", "탐색"], active: true, questType: "EXPLORATION" },

      // ── 13 기록형 ─────────────────────────────────────────────
      { anchor: "suwonHwaseong", title: "여기 앉아서 한 줄", story: "바다가 보이는 벤치. 앉아서 지금 드는 생각을 한 줄 남겨라. 앞서 앉았던 사람의 문장을 보여준다.", difficulty: 1, baseExp: 50, radiusM: 50, keywords: ["바다", "기록"], active: true, questType: "RECORD" },
      { anchor: "haenggung", title: "무슨 맛이었나", story: "방금 먹은 것을 별점 없이 문장으로만 설명하라. \"맛있다\"는 금지.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["음식", "기록"], active: true, questType: "RECORD" },
      { anchor: "haenggung", title: "다음 사람에게", story: "이 동네에서 당신만 알게 된 것 하나를 다음 여행자에게 남겨라.", difficulty: 1, baseExp: 50, radiusM: 50, keywords: ["로컬", "기록"], active: true, questType: "RECORD" },
  ];

  for (const { anchor, ...quest } of SEED_QUESTS) {
    const spot = await spotFor(anchor);
    await prisma.quest.create({ data: { ...quest, placeId: spot.id } });
  }

  // 4. 배지 정의
  await prisma.userBadge.deleteMany();
  await prisma.badge.deleteMany();
  await prisma.badge.createMany({
    data: BADGES.map((b) => ({
      name: b.name,
      description: b.description,
      // artKey는 앱이 그릴 SVG를 고르는 열쇠다. 서버는 파일 경로를 모른다.
      artUrl: b.artKey,
      ruleJson: b.ruleJson,
      threshold: b.threshold,
      regionCode: b.regionCode ?? null,
      hidden: b.hidden ?? false,
    })),
  });

  console.log(`테스트 데이터 생성 완료 — 퀘스트 21개(7종 유형), 배지 ${BADGES.length}개`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });