import { prisma } from "../src/utils/prisma";

async function main() {
  console.log("테스트 데이터 생성 시작...");

  // 기존 데이터 초기화
  await prisma.userQuest.deleteMany();
  await prisma.quest.deleteMany();
  await prisma.place.deleteMany();

  // 1. 장소 데이터 생성 (서울/수원 인근)
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
      name: "서울 N서울타워",
      regionCode: "SEOUL_01",
      address: "서울특별시 용산구 남산공원길 105",
      lat: 37.5512,
      lng: 126.9882,
      congestionScore: 80,
      photoUrl: "https://example.com/seoultower.jpg",
    },
  });

  // 2. 퀘스트 데이터 생성
  await prisma.quest.createMany({
    data: [
      {
        placeId: place1.id,
        title: "방화수류정 야경 산책",
        story: "성곽길을 따라 오르며 야경을 감상하고 인증샷을 찍어보세요.",
        difficulty: 1,
        baseExp: 100,
        verifyType: "GPS",
        radiusM: 50,
        keywords: ["산책", "야경", "역사"],
        active: true,
      },
      {
        placeId: place2.id,
        title: "행궁동 카페 탐방",
        story: "골목길 사이 감성 카페를 찾아 방문해보세요.",
        difficulty: 2,
        baseExp: 150,
        verifyType: "GPS",
        radiusM: 30,
        keywords: ["카페", "데이트", "맛집"],
        active: true,
      },
      {
        placeId: place3.id,
        title: "남산타워 정상 정복",
        story: "남산 순환로를 따라 타워 정상까지 올라가보세요.",
        difficulty: 3,
        baseExp: 300,
        verifyType: "GPS",
        radiusM: 100,
        keywords: ["산책", "운동", "전망"],
        active: true,
      },
    ],
  });

  console.log("테스트 데이터 생성 완료!");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
