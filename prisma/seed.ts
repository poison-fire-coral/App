import { prisma } from "../src/utils/prisma";

async function main() {
  console.log("테스트 데이터 생성 시작...");

  // 기존 데이터 초기화
  await prisma.questCompletion?.deleteMany().catch(() => {});
  await prisma.userQuest.deleteMany();
  await prisma.quest.deleteMany();
  await prisma.place.deleteMany();
  await prisma.levelTable.deleteMany();

  // 1. 레벨 테이블 데이터 생성
  await prisma.levelTable.createMany({
    data: [
      { level: 1, requiredExp: 0 },
      { level: 2, requiredExp: 100 },
      { level: 3, requiredExp: 250 },
      { level: 4, requiredExp: 450 },
      { level: 5, requiredExp: 700 },
      { level: 6, requiredExp: 1000 },
      { level: 7, requiredExp: 1400 },
      { level: 8, requiredExp: 1900 },
      { level: 9, requiredExp: 2500 },
      { level: 10, requiredExp: 3200 },
    ],
  });

  // 2. 장소 데이터 생성
  const place1 = await prisma.place.create({
    data: {
      name: "수원화성 방화수류정",
      regionCode: "SUWON_01",
      address: "경기도 수원시 팔달구 수원천로392번길 44-6",
      lat: 37.2882,
      lng: 127.0163,
      congestionScore: 25,
      photoUrl: "https://example.com/suwon.jpg",
    },
  });

  const place2 = await prisma.place.create({
    data: {
      name: "수원 행궁동 카페거리",
      regionCode: "SUWON_01",
      address: "경기도 수원시 팔달구 신풍로 23",
      lat: 37.2845,
      lng: 127.0135,
      congestionScore: 60,
      photoUrl: "https://example.com/haenggung.jpg",
    },
  });

  const place3 = await prisma.place.create({
    data: {
      name: "서울 N서울타워 및 남산 일대",
      regionCode: "SEOUL_01",
      address: "서울특별시 용산구 남산공원길 105",
      lat: 37.5512,
      lng: 126.9882,
      congestionScore: 80,
      photoUrl: "https://example.com/seoultower.jpg",
    },
  });

  // 3. 21개 시드 퀘스트 데이터 생성 (현재 스키마에 필드 일치)
  await prisma.quest.createMany({
    data: [
      // 01 방문형 (VISIT)
      { placeId: place1.id, title: "등대 끝까지", story: "방파제 입구에서 등대까지 300m. 끝에 서서 항구를 등지고 한 번 돌아보면 도시 전체가 보인다.", difficulty: 1, baseExp: 50, radiusM: 50, keywords: ["바다", "산책"], active: true },
      { placeId: place2.id, title: "이름 없는 계단", story: "지도에 이름이 없는 108칸 계단. 위쪽 골목까지 올라가면 인증된다. 내려올 땐 다른 길을 권한다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["골목", "체력"], active: true },
      { placeId: place2.id, title: "시장 뒷문으로 들어가기", story: "정문이 아니라 상인들이 쓰는 뒷문. 들어서는 풍경이 완전히 다르다.", difficulty: 1, baseExp: 50, radiusM: 50, keywords: ["시장", "로컬"], active: true },

      // 05 시간대 제한형 (TIME_LIMITED)
      { placeId: place2.id, title: "새벽 4시의 경매", story: "수협 위판장 경매는 해가 뜨기 전에 끝난다. 관광객이 거의 없는 두 시간.", difficulty: 3, baseExp: 220, radiusM: 50, keywords: ["시장", "로컬", "새벽"], active: true },
      { placeId: place1.id, title: "해 지기 30분 전, 언덕", story: "일몰 시각은 매일 자동 계산되어 창이 움직인다. 오늘은 19:12에 열린다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["노을", "산책"], active: true },
      { placeId: place2.id, title: "문 여는 순간의 국밥집", story: "첫 손님으로 앉아보기. 오픈 직후 30분은 육수가 가장 진하다는 말이 있다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["음식", "새벽"], active: true },

      // 06 피사체 지정형 (SUBJECT_PHOTO)
      { placeId: place2.id, title: "가장 오래된 간판", story: "이 골목에서 손글씨로 쓰인 간판 하나를 찾아 정면으로 담아라. 글자가 읽히게.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["골목", "기록"], active: true },
      { placeId: place1.id, title: "굴뚝과 하늘", story: "붉은 벽돌 굴뚝 전체가 프레임에 들어오는 자리는 딱 한 곳이다. 뒷골목 주차장에서 찾아보라.", difficulty: 3, baseExp: 220, radiusM: 50, keywords: ["근대건축", "사진"], active: true },
      { placeId: place2.id, title: "오늘의 메뉴판", story: "매일 손으로 고쳐 쓰는 메뉴판을 찍어라. 어제와 오늘이 다르다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["음식", "로컬"], active: true },

      // 08 수집 사진형 (COLLECTION_PHOTO)
      { placeId: place2.id, title: "골목 고양이 세 마리", story: "이 동네에 사는 고양이 세 마리를 각각 다른 골목에서 만나라. 쫓지 말 것.", difficulty: 4, baseExp: 400, radiusM: 200, keywords: ["골목", "고양이"], active: true },
      { placeId: place2.id, title: "파란 대문 다섯 개", story: "이 언덕 주택가엔 유난히 파란 페인트 대문이 많다. 다섯 개를 찾으면 이유를 알려준다.", difficulty: 4, baseExp: 400, radiusM: 300, keywords: ["골목", "수집"], active: true },
      { placeId: place2.id, title: "시장의 네 가지 냄새", story: "기름·건어물·나물·떡. 각 구역에서 한 장씩. 시장 지리를 저절로 익히게 된다.", difficulty: 3, baseExp: 220, radiusM: 200, keywords: ["시장", "음식"], active: true },

      // 09 퀴즈형 (QUIZ)
      { placeId: place1.id, title: "비석에 적힌 해", story: "\"이 비석이 세워진 연도는?\" 마당 왼쪽 끝, 이끼에 절반 덮인 글씨를 찾아야 한다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["역사"], active: true },
      { placeId: place2.id, title: "이 집에서 가장 싼 것", story: "벽에 붙은 메뉴판에서 제일 저렴한 메뉴 이름은? 정답을 맞히면 이 집 40년 역사를 알려준다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["음식", "로컬"], active: true },
      { placeId: place2.id, title: "몇 칸일까", story: "이 계단은 정확히 몇 칸인가. 세면서 오르는 수밖에 없다.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["골목", "체력"], active: true },

      // 10 탐색형 (EXPLORE)
      { placeId: place2.id, title: "벽화의 연도", story: "이 언덕 어딘가에 고래 벽화가 있다. 오른쪽 아래 서명 옆에 적힌 연도를 찾아라.", difficulty: 4, baseExp: 400, radiusM: 400, keywords: ["골목", "탐색"], active: true },
      { placeId: place3.id, title: "두 갈래 나무", story: "밑동이 둘로 갈라진 큰 나무 한 그루. 주민들은 여기서 만나기로 약속한다. 찾아서 찍어라.", difficulty: 4, baseExp: 400, radiusM: 500, keywords: ["자연", "탐색"], active: true },
      { placeId: place3.id, title: "폐선로의 끝", story: "기차가 다니지 않는 선로가 어느 집 담에서 끊긴다. 그 담의 색을 답하라.", difficulty: 4, baseExp: 400, radiusM: 300, keywords: ["근대건축", "탐색"], active: true },

      // 13 기록형 (RECORD)
      { placeId: place1.id, title: "여기 앉아서 한 줄", story: "바다가 보이는 벤치. 앉아서 지금 드는 생각을 한 줄 남겨라. 앞서 앉았던 사람의 문장을 보여준다.", difficulty: 1, baseExp: 50, radiusM: 50, keywords: ["바다", "기록"], active: true },
      { placeId: place2.id, title: "무슨 맛이었나", story: "방금 먹은 것을 별점 없이 문장으로만 설명하라. \"맛있다\"는 금지.", difficulty: 2, baseExp: 110, radiusM: 50, keywords: ["음식", "기록"], active: true },
      { placeId: place2.id, title: "다음 사람에게", story: "이 동네에서 당신만 알게 된 것 하나를 다음 여행자에게 남겨라.", difficulty: 1, baseExp: 50, radiusM: 50, keywords: ["로컬", "기록"], active: true },
    ],
  });

  console.log("테스트 데이터 생성 완료! (21개 퀘스트 시드 적용됨)");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });