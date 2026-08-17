import '../models/quest_model.dart';
import '../services/geo.dart';

/// 목업 퀘스트 저장소. 홈(2a 추천 목록)과 지도(3a 마커)가 같은 데이터를 공유한다.
/// 백엔드 `GET /quests` 연동 시 이 클래스만 API 호출로 교체하면 된다.
class QuestRepository {
  const QuestRepository._();

  /// 임시 사용자 현재 위치 (전주 한옥마을 초입 부근 고정 좌표)
  static const GeoPoint mockUserLocation = GeoPoint(35.8150, 127.1540);

  static final List<QuestModel> all = [
    QuestModel(
      id: 'q1',
      title: '남부시장 야시장 방문',
      summary: '남부시장 야시장 서쪽 끝까지 걸어 들어가 가장 오래된 점포를 찾아보세요.',
      description: '남부시장 야시장 서쪽 끝까지 걸어 들어가 가장 오래된 점포를 찾아보세요.',
      difficulty: QuestDifficulty.star2,
      latitude: 35.8115,
      longitude: 127.1470,
      spotName: '남부시장 야시장',
      regionLabel: '전주시 완산구',
      keywords: const ['#전통시장', '#야시장'],
      crowdMultiplier: 1.4,
    ),
    QuestModel(
      id: 'q2',
      title: '청년몰 골목 한바퀴',
      summary: '남부시장 청년몰 골목을 한 바퀴 돌며 로컬 브랜드 소품샵 2곳을 방문해 보세요.',
      description: '남부시장 청년몰 골목을 한 바퀴 돌며 로컬 브랜드 소품샵 2곳을 방문해 보세요.',
      difficulty: QuestDifficulty.star1,
      latitude: 35.8110,
      longitude: 127.1465,
      spotName: '남부시장 청년몰',
      regionLabel: '전주시 완산구',
      keywords: const ['#로컬브랜드', '#소품샵', '#골목산책'],
      crowdMultiplier: 1.0,
    ),
    QuestModel(
      id: 'q3',
      title: '경기전 돌담길 걷기',
      summary: '경기전 돌담을 따라 걸으며 가장 마음에 드는 풍경을 사진으로 남겨보세요.',
      description: '경기전 돌담을 따라 걸으며 가장 마음에 드는 풍경을 사진으로 남겨보세요.',
      difficulty: QuestDifficulty.star1,
      latitude: 35.8156,
      longitude: 127.1523,
      spotName: '경기전',
      regionLabel: '전주시 완산구',
      keywords: const ['#한옥·고택', '#역사유적'],
      crowdMultiplier: 0.7,
    ),
    QuestModel(
      id: 'q4',
      title: '전동성당 사진 남기기',
      summary: '전동성당 정면이 가장 잘 보이는 자리에서 인증 사진을 남겨보세요.',
      description: '전동성당 정면이 가장 잘 보이는 자리에서 인증 사진을 남겨보세요.',
      difficulty: QuestDifficulty.star2,
      latitude: 35.8135,
      longitude: 127.1538,
      spotName: '전동성당',
      regionLabel: '전주시 완산구',
      keywords: const ['#종교건축', '#사진스팟'],
      crowdMultiplier: 1.0,
    ),
    QuestModel(
      id: 'q5',
      title: '산지천 야경 담기',
      summary: '해질 무렵 산지천을 따라 걸으며 야경 사진 한 장을 남겨보세요.',
      description: '해질 무렵 산지천을 따라 걸으며 야경 사진 한 장을 남겨보세요.',
      difficulty: QuestDifficulty.star2,
      hasHalfStar: true,
      latitude: 35.8175,
      longitude: 127.1575,
      spotName: '산지천',
      regionLabel: '전주시 완산구',
      keywords: const ['#야경', '#사진스팟'],
      crowdMultiplier: 1.2,
    ),
    QuestModel(
      id: 'q6',
      title: '한옥마을 골목 3곳 찍기',
      summary: '한옥마을 골목 세 곳을 순서대로 지나며 각 지점에서 사진을 남겨보세요.',
      description: '한옥마을 안쪽 골목 세 곳을 순서대로 지나며, 각 지점에서 마음에 드는 장면을 사진으로 남겨보세요.',
      difficulty: QuestDifficulty.star3,
      latitude: 35.8163,
      longitude: 127.1607,
      spotName: '한옥마을 골목',
      regionLabel: '전주시 완산구',
      keywords: const ['#골목산책', '#한옥·고택', '#사진스팟'],
      crowdMultiplier: 1.0,
      spots: const [
        QuestSpot(name: '골목 초입', latitude: 35.8163, longitude: 127.1607),
        QuestSpot(name: '중간 갈래길', latitude: 35.8171, longitude: 127.1616),
        QuestSpot(name: '골목 끝 담장', latitude: 35.8178, longitude: 127.1624),
      ],
    ),
    QuestModel(
      id: 'q7',
      title: '자만벽화마을 벽화 찾기',
      summary: '자만벽화마을 골목을 오르며 서로 다른 벽화 세 점을 찾아보세요.',
      description: '자만벽화마을 골목을 오르며 서로 다른 벽화 세 점을 찾아 사진으로 남겨보세요.',
      difficulty: QuestDifficulty.star3,
      hasHalfStar: true,
      latitude: 35.8206,
      longitude: 127.1653,
      spotName: '자만벽화마을',
      regionLabel: '전주시 덕진구',
      keywords: const ['#벽화·거리예술', '#사진스팟', '#골목산책'],
      crowdMultiplier: 1.5,
      spots: const [
        QuestSpot(name: '마을 입구 계단', latitude: 35.8206, longitude: 127.1653),
        QuestSpot(name: '언덕 중턱 담벼락', latitude: 35.8213, longitude: 127.1661),
        QuestSpot(name: '전망 좋은 꼭대기', latitude: 35.8220, longitude: 127.1668),
      ],
    ),
  ];

  static QuestModel? findById(String id) {
    for (final quest in all) {
      if (quest.id == id) return quest;
    }
    return null;
  }

  /// 현재 위치에서 가까운 순으로 정렬한 추천 퀘스트 (홈 2a "내 주변 추천 퀘스트")
  static List<QuestModel> nearby({
    GeoPoint origin = mockUserLocation,
    Set<String> excludeIds = const {},
    int limit = 5,
  }) {
    final candidates = all.where((q) => !excludeIds.contains(q.id)).toList()
      ..sort((a, b) => Geo.distanceMeters(origin, a.point).compareTo(Geo.distanceMeters(origin, b.point)));
    return candidates.take(limit).toList();
  }

  static double distanceFromUser(QuestModel quest, {GeoPoint origin = mockUserLocation}) {
    return Geo.distanceMeters(origin, quest.point);
  }
}
