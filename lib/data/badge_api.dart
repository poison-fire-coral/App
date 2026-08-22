import '../services/api_client.dart';

/// 5a 그리드가 그리는 세 가지 상태.
enum BadgeState {
  /// 획득 — 볼록한 면 + jade
  achieved,

  /// 진행 중 — 카운터와 진행바를 보여준다
  inProgress,

  /// 미공개 — `?` 만. 히든 배지이거나 아직 한 걸음도 못 뗀 것
  locked,
}

BadgeState _stateFrom(String? raw) => switch (raw) {
      'achieved' => BadgeState.achieved,
      'inProgress' => BadgeState.inProgress,
      _ => BadgeState.locked,
    };

/// 목록 한 칸.
///
/// 히든 배지를 아직 못 땄으면 서버가 [name]·[description]·[artKey]를 null로 지운다.
/// 앱을 뜯어 미리 보는 걸 막으려면 가리는 일이 서버에서 일어나야 한다.
class BadgeSummary {
  final int badgeId;
  final String? name;
  final String? description;
  final String? artKey;
  final int progress;
  final int threshold;
  final BadgeState state;
  final bool hidden;
  final String? regionCode;
  final DateTime? achievedAt;
  final bool isFeatured;

  const BadgeSummary({
    required this.badgeId,
    required this.progress,
    required this.threshold,
    required this.state,
    required this.hidden,
    this.name,
    this.description,
    this.artKey,
    this.regionCode,
    this.achievedAt,
    this.isFeatured = false,
  });

  /// 0.0 ~ 1.0
  double get ratio =>
      threshold <= 0 ? 0 : (progress / threshold).clamp(0.0, 1.0);

  String get progressLabel => '$progress / $threshold';

  /// 미공개 배지에 보여줄 이름. 실제 이름은 서버가 안 준다.
  String get displayName => name ?? '???';

  factory BadgeSummary.fromJson(Map<String, dynamic> json) => BadgeSummary(
        badgeId: json['badgeId'] as int,
        name: json['name'] as String?,
        description: json['description'] as String?,
        artKey: json['artKey'] as String?,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        threshold: (json['threshold'] as num?)?.toInt() ?? 0,
        state: _stateFrom(json['state'] as String?),
        hidden: json['hidden'] == true,
        regionCode: json['regionCode'] as String?,
        achievedAt: json['achievedAt'] == null
            ? null
            : DateTime.tryParse('${json['achievedAt']}'),
        isFeatured: json['isFeatured'] == true,
      );
}

class BadgeListResult {
  final int total;
  final int achieved;
  final List<BadgeSummary> items;

  const BadgeListResult({
    required this.total,
    required this.achieved,
    required this.items,
  });

  String get headline => '배지 $achieved / $total';
  double get ratio => total <= 0 ? 0 : (achieved / total).clamp(0.0, 1.0);
}

/// 배지 상세의 "달성한 퀘스트" 한 줄.
class BadgeHistoryEntry {
  final DateTime date;
  final String questTitle;
  final String? placeName;
  final String? regionCode;

  const BadgeHistoryEntry({
    required this.date,
    required this.questTitle,
    this.placeName,
    this.regionCode,
  });

  factory BadgeHistoryEntry.fromJson(Map<String, dynamic> json) =>
      BadgeHistoryEntry(
        date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
        questTitle: json['questTitle'] as String? ?? '',
        placeName: json['placeName'] as String?,
        regionCode: json['regionCode'] as String?,
      );
}

class BadgeDetail {
  final int badgeId;
  final String name;
  final String description;
  final String? artKey;
  final int progress;
  final int threshold;
  final bool achieved;
  final DateTime? achievedAt;
  final bool isFeatured;
  final List<BadgeHistoryEntry> history;

  const BadgeDetail({
    required this.badgeId,
    required this.name,
    required this.description,
    required this.progress,
    required this.threshold,
    required this.achieved,
    required this.history,
    this.artKey,
    this.achievedAt,
    this.isFeatured = false,
  });

  double get ratio =>
      threshold <= 0 ? 0 : (progress / threshold).clamp(0.0, 1.0);

  factory BadgeDetail.fromJson(Map<String, dynamic> json) => BadgeDetail(
        badgeId: json['badgeId'] as int,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        artKey: json['artKey'] as String?,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        threshold: (json['threshold'] as num?)?.toInt() ?? 0,
        achieved: json['achieved'] == true,
        achievedAt: json['achievedAt'] == null
            ? null
            : DateTime.tryParse('${json['achievedAt']}'),
        isFeatured: json['isFeatured'] == true,
        history: [
          for (final e in (json['history'] as List? ?? []))
            BadgeHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
}

/// 홈 3칸에 세우는 대표 배지.
class FeaturedBadge {
  final int badgeId;
  final String name;
  final String? artKey;

  const FeaturedBadge({
    required this.badgeId,
    required this.name,
    this.artKey,
  });

  factory FeaturedBadge.fromJson(Map<String, dynamic> json) => FeaturedBadge(
        badgeId: json['badgeId'] as int,
        name: json['name'] as String? ?? '',
        artKey: json['artKey'] as String?,
      );
}

/// 프로필 화면(5c)의 발자국 한 줄.
class Footprint {
  final DateTime date;
  final String questTitle;
  final String? placeName;
  final String? regionCode;
  final int expAwarded;

  const Footprint({
    required this.date,
    required this.questTitle,
    required this.expAwarded,
    this.placeName,
    this.regionCode,
  });

  factory Footprint.fromJson(Map<String, dynamic> json) => Footprint(
        date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
        questTitle: json['questTitle'] as String? ?? '',
        placeName: json['placeName'] as String?,
        regionCode: json['regionCode'] as String?,
        expAwarded: (json['expAwarded'] as num?)?.toInt() ?? 0,
      );
}

class ProfileSummary {
  final int completed;
  final int regions;
  final int badges;
  final List<Footprint> footprints;

  const ProfileSummary({
    required this.completed,
    required this.regions,
    required this.badges,
    required this.footprints,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    final stats = Map<String, dynamic>.from(json['stats'] as Map? ?? {});
    return ProfileSummary(
      completed: (stats['completed'] as num?)?.toInt() ?? 0,
      regions: (stats['regions'] as num?)?.toInt() ?? 0,
      badges: (stats['badges'] as num?)?.toInt() ?? 0,
      footprints: [
        for (final e in (json['footprints'] as List? ?? []))
          Footprint.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }
}

/// 배지·프로필 서버 호출. `QuestRepository`와 같은 static 유틸 스타일.
class BadgeApi {
  const BadgeApi._();

  static Future<BadgeListResult> list({
    String? region,
    String? questType,
  }) async {
    final data = await ApiClient.get('/badges', query: {
      'region': ?region,
      'questType': ?questType,
    });
    final map = Map<String, dynamic>.from(data as Map);
    return BadgeListResult(
      total: (map['total'] as num?)?.toInt() ?? 0,
      achieved: (map['achieved'] as num?)?.toInt() ?? 0,
      items: [
        for (final e in (map['items'] as List? ?? []))
          BadgeSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }

  static Future<BadgeDetail> detail(int badgeId) async {
    final data = await ApiClient.get('/badges/$badgeId');
    return BadgeDetail.fromJson(Map<String, dynamic>.from(data as Map));
  }

  static Future<List<FeaturedBadge>> featured() async {
    final data = await ApiClient.get('/users/me/featured-badges');
    return [
      for (final e in (data as List? ?? []))
        FeaturedBadge.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  }

  /// 대표 배지를 통째로 교체한다. 빈 배열을 보내면 전부 해제된다.
  static Future<List<FeaturedBadge>> setFeatured(List<int> badgeIds) async {
    final data = await ApiClient.put(
      '/users/me/featured-badges',
      body: {'badgeIds': badgeIds},
    );
    return [
      for (final e in (data as List? ?? []))
        FeaturedBadge.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  }

  static Future<ProfileSummary> profileSummary() async {
    final data = await ApiClient.get('/users/me/profile');
    return ProfileSummary.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

/// verify 응답의 `badgeProgress` 한 줄.
///
/// 보상 화면(4c)이 쓴다. 예전에는 로컬 키워드 카운트로 배지를 그려서
/// 서버가 이미 준 배지를 "0 / 1 진행 중"으로 표시했다 — 실기기에서 잡았다.
class VerifyBadgeProgress {
  final int badgeId;
  final String name;
  final String? artKey;
  final int progress;
  final int threshold;
  final bool achieved;
  final bool justEarned;
  final bool hidden;

  const VerifyBadgeProgress({
    required this.badgeId,
    required this.name,
    required this.artKey,
    required this.progress,
    required this.threshold,
    required this.achieved,
    required this.justEarned,
    required this.hidden,
  });

  factory VerifyBadgeProgress.fromJson(Map<String, dynamic> json) =>
      VerifyBadgeProgress(
        badgeId: (json['badgeId'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        artKey: json['artKey'] as String?,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        threshold: (json['threshold'] as num?)?.toInt() ?? 1,
        achieved: json['achieved'] == true,
        justEarned: json['justEarned'] == true,
        hidden: json['hidden'] == true,
      );

  double get ratio =>
      threshold <= 0 ? 0 : (progress / threshold).clamp(0.0, 1.0);

  String get label =>
      achieved ? '$progress / $threshold · 달성' : '$progress / $threshold 진행 중';

  /// 보상 화면에 **한 개만** 띄운다. 13개를 다 나열하면 축하가 아니라 목록이다.
  ///
  /// 우선순위: 방금 딴 것 → 이번에 진행된 것 중 완성에 가장 가까운 것.
  /// 히든 배지는 딴 순간에만 드러낸다. 진행 중일 때 이름을 보이면 히든이 아니다.
  static VerifyBadgeProgress? pick(dynamic raw) {
    if (raw is! List) return null;
    final all = [
      for (final item in raw)
        if (item is Map) VerifyBadgeProgress.fromJson(Map<String, dynamic>.from(item)),
    ];

    final earned = all.where((b) => b.justEarned).toList();
    if (earned.isNotEmpty) {
      earned.sort((a, b) => b.threshold.compareTo(a.threshold));
      return earned.first;
    }

    final ongoing = all
        .where((b) => !b.hidden && !b.achieved && b.progress > 0)
        .toList();
    if (ongoing.isEmpty) return null;
    ongoing.sort((a, b) => b.ratio.compareTo(a.ratio));
    return ongoing.first;
  }
}
