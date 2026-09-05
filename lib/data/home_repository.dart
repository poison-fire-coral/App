import '../models/quest_model.dart';
import '../services/api_client.dart';
import 'badge_api.dart';

/// `GET /home` 한 번의 응답 — 체크리스트 20번.
///
/// 예전에는 홈이 배지 목록과 근처 퀘스트를 **따로** 불렀다. 홈은 앱에서 가장
/// 자주 열리는 화면이라 그 왕복 수가 그대로 체감 속도가 된다.
class HomeSummary {
  /// 진행 중인 퀘스트 원본(`userQuest` + `quest` + `place`).
  ///
  /// 화면의 캐러셀은 아직 `main.dart`가 들고 있는 [ActiveQuest] 목록을 쓴다.
  /// 여기 값은 그 목록을 서버 기준으로 맞출 때를 위해 그대로 남겨 둔다.
  final List<Map<String, dynamic>> activeQuests;

  /// 추천 퀘스트. 좌표를 함께 보냈다면 가까운 순으로 정렬돼 온다.
  final List<QuestModel> recommendedQuests;

  /// 홈 3칸에 세울 배지 — 대표 먼저, 남는 칸은 최근 획득.
  final List<BadgeSummary> badges;

  final int badgeTotal;
  final int badgeAchieved;

  const HomeSummary({
    required this.activeQuests,
    required this.recommendedQuests,
    required this.badges,
    required this.badgeTotal,
    required this.badgeAchieved,
  });

  const HomeSummary.empty()
      : activeQuests = const [],
        recommendedQuests = const [],
        badges = const [],
        badgeTotal = 0,
        badgeAchieved = 0;

  factory HomeSummary.fromJson(Map<String, dynamic> json) {
    final summary = json['badgeSummary'];

    return HomeSummary(
      activeQuests: [
        for (final e in (json['activeQuests'] as List? ?? []))
          Map<String, dynamic>.from(e as Map),
      ],
      recommendedQuests: [
        for (final e in (json['recommendedQuests'] as List? ?? []))
          QuestModel.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      badges: [
        for (final e in (json['badges'] as List? ?? []))
          BadgeSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      badgeTotal: summary is Map ? (summary['total'] as num?)?.toInt() ?? 0 : 0,
      badgeAchieved:
          summary is Map ? (summary['achieved'] as num?)?.toInt() ?? 0 : 0,
    );
  }
}

class HomeRepository {
  const HomeRepository._();

  /// 홈에 필요한 것을 한 번에 받아 온다.
  ///
  /// [lat]·[lng]를 주면 추천이 **가까운 순**으로 온다. 주지 않으면 서버가
  /// 키워드와 홈지역만 보고 고른다 — 위치 권한을 아직 안 준 상태에서도
  /// 홈이 비어 보이지 않게 하려는 것이다.
  static Future<HomeSummary> fetchSummary({double? lat, double? lng}) async {
    final data = await ApiClient.get(
      '/home',
      query: {
        'lat': ?lat,
        'lng': ?lng,
      },
    );

    if (data is! Map) return const HomeSummary.empty();
    return HomeSummary.fromJson(Map<String, dynamic>.from(data));
  }
}
