import 'dart:convert';

import '../theme/app_assets.dart';

/// 레벨 테이블 및 경험치 연산 시스템 (기획서 6c 기준)
///
/// 공식은 Lv1–4 `100·1.45^(L-1)` · Lv5–14 `400·1.2^(L-5)` · Lv15+ `2000`이지만
/// 기획서 지시대로 10 단위 반올림한 값을 테이블에 하드코딩한다 (런타임 계산 X).
class LevelSystem {
  static const List<int> levelRequiredExpTable = [
    0, 100, 150, 220, 300, 400, 500, 620, 770, 950,
    1150, 1350, 1550, 1750, 2150,
  ];

  /// Lv15 이상은 2,000 고정
  static const int flatRequiredExp = 2000;

  /// Lv30에서 레벨 정지 · 시즌 포인트로 전환 (기획서 6c)
  static const int maxLevel = 30;

  /// 다음 레벨로 올라가는 데 필요한 경험치
  static int getRequiredExpForLevel(int level) {
    if (level < 1) return 100;
    if (level >= maxLevel) return flatRequiredExp;
    if (level < levelRequiredExpTable.length) {
      return levelRequiredExpTable[level];
    }
    return flatRequiredExp;
  }

  /// 프로필 테두리 링 진행률 연산 (0.0 ~ 1.0)
  static double calculateProgressPercentage(int currentLevel, int currentLevelExp) {
    final requiredExp = getRequiredExpForLevel(currentLevel);
    if (requiredExp <= 0) return 0.0;
    return (currentLevelExp / requiredExp).clamp(0.0, 1.0);
  }
}

/// 유저 프로필 데이터 모델 (기획서 1d, 2a, 5c 기준)
class UserModel {
  /// 서버 DB(users.id)의 정수 PK. 로컬에서만 만든 프로필이면 null.
  final int? serverId;

  final String nickname;

  /// 아바타 프리셋 id ('avatar_01' ~ 'avatar_06').
  /// 경로가 아니라 id를 저장한다 — 에셋 구조가 바뀌어도 DB를 안 건드리게.
  final String avatarId;

  final String? homeRegion;                 // 관심/홈 지역 (선택)
  final int level;
  final int exp;                            // 현재 레벨 구간에서 쌓은 경험치
  final List<String> travelStyles;          // 여행 키워드 / 스타일

  /// 활동 강도 ('가볍게' | '보통' | '많이 걷기').
  /// 예전 이름은 `transport`였는데 실제로 담기는 값과 뜻이 달라 바로잡았다.
  final String activityLevel;
  final List<String> representativeBadgeIds; // 홈 화면 장착 대표 배지 (최대 3개)

  /// 연속 접속 스트릭. 보상 배율 ×(1 + 0.05·일수), 상한 ×1.5 (기획서 6b)
  final int streakDays;

  /// 오늘 획득한 EXP 누계. 1일 상한 3,000 EXP 판정에 쓴다 (기획서 6b)
  final int dailyExpEarned;

  /// [dailyExpEarned]가 집계된 날짜. 날이 바뀌면 0으로 리셋한다.
  final DateTime? lastExpEarnedAt;

  /// 방문한 적 있는 시·군. 처음 방문한 지역은 ×1.5 (기획서 6b)
  final List<String> visitedRegions;

  /// 완료한 퀘스트 로그. 같은 퀘스트를 재수행하면 중복 기록되고, 재수행 배율 ×0.3 판정에 쓴다.
  final List<String> completedQuestIds;

  UserModel({
    required this.nickname,
    this.serverId,
    this.avatarId = AppAssets.defaultAvatarId,
    this.homeRegion,
    this.level = 1,
    this.exp = 0,
    required this.travelStyles,
    required this.activityLevel,
    this.representativeBadgeIds = const [],
    this.streakDays = 0,
    this.dailyExpEarned = 0,
    this.lastExpEarnedAt,
    this.visitedRegions = const [],
    this.completedQuestIds = const [],
  });

  /// 홈 화면 프로필 테두리 링 전용 진행률 (0.0 ~ 1.0)
  double get levelProgress => LevelSystem.calculateProgressPercentage(level, exp);

  /// 현재 레벨의 레벨업 필요 경험치
  int get requiredExp => LevelSystem.getRequiredExpForLevel(level);

  /// 다음 레벨까지 남은 경험치
  int get expToNextLevel => (requiredExp - exp).clamp(0, requiredExp);

  int get completedQuestCount => completedQuestIds.length;

  int get visitedRegionCount => visitedRegions.length;

  /// 오늘 기준으로 유효한 일일 획득량. 마지막 획득일이 어제 이전이면 0부터 다시 센다.
  int dailyExpEarnedOn(DateTime now) {
    final last = lastExpEarnedAt;
    if (last == null || !_isSameDay(last, now)) return 0;
    return dailyExpEarned;
  }

  /// [now] 기준으로 갱신된 연속 접속 스트릭. 하루를 건너뛰면 1부터 다시 센다.
  int streakDaysOn(DateTime now) {
    final last = lastExpEarnedAt;
    if (last == null) return 1;
    if (_isSameDay(last, now)) return streakDays == 0 ? 1 : streakDays;
    final lastDay = DateTime(last.year, last.month, last.day);
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(lastDay).inDays == 1 ? streakDays + 1 : 1;
  }

  bool hasVisited(String region) => region.isNotEmpty && visitedRegions.contains(region);

  bool hasCompleted(String questId) => completedQuestIds.contains(questId);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  UserModel copyWith({
    String? nickname,
    int? serverId,
    String? avatarId,
    String? homeRegion,
    int? level,
    int? exp,
    List<String>? travelStyles,
    String? activityLevel,
    List<String>? representativeBadgeIds,
    int? streakDays,
    int? dailyExpEarned,
    DateTime? lastExpEarnedAt,
    List<String>? visitedRegions,
    List<String>? completedQuestIds,
  }) {
    return UserModel(
      nickname: nickname ?? this.nickname,
      serverId: serverId ?? this.serverId,
      avatarId: avatarId ?? this.avatarId,
      homeRegion: homeRegion ?? this.homeRegion,
      level: level ?? this.level,
      exp: exp ?? this.exp,
      travelStyles: travelStyles ?? this.travelStyles,
      activityLevel: activityLevel ?? this.activityLevel,
      representativeBadgeIds: representativeBadgeIds ?? this.representativeBadgeIds,
      streakDays: streakDays ?? this.streakDays,
      dailyExpEarned: dailyExpEarned ?? this.dailyExpEarned,
      lastExpEarnedAt: lastExpEarnedAt ?? this.lastExpEarnedAt,
      visitedRegions: visitedRegions ?? this.visitedRegions,
      completedQuestIds: completedQuestIds ?? this.completedQuestIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'serverId': serverId,
        'nickname': nickname,
        'avatarId': avatarId,
        'homeRegion': homeRegion,
        'level': level,
        'exp': exp,
        'travelStyles': travelStyles,
        'activityLevel': activityLevel,
        'representativeBadgeIds': representativeBadgeIds,
        'streakDays': streakDays,
        'dailyExpEarned': dailyExpEarned,
        'lastExpEarnedAt': lastExpEarnedAt?.toIso8601String(),
        'visitedRegions': visitedRegions,
        'completedQuestIds': completedQuestIds,
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        nickname: json['nickname'] ?? '',
        serverId: json['serverId'] as int?,
        // 구버전 캐시에는 'assets/avatars/avatar_1.png' 같은 경로가 들어 있다.
        // normalizeAvatarId가 알 수 없는 값을 기본 프리셋으로 떨어뜨린다.
        avatarId: AppAssets.normalizeAvatarId(
          json['avatarId'] as String? ?? json['avatarPresetUrl'] as String?,
        ),
        homeRegion: json['homeRegion'],
        level: json['level'] ?? 1,
        exp: json['exp'] ?? 0,
        travelStyles: List<String>.from(json['travelStyles'] ?? []),
        activityLevel: json['activityLevel'] ?? json['transport'] ?? '보통',
        representativeBadgeIds: List<String>.from(json['representativeBadgeIds'] ?? []),
        streakDays: json['streakDays'] ?? 0,
        dailyExpEarned: json['dailyExpEarned'] ?? 0,
        lastExpEarnedAt: json['lastExpEarnedAt'] != null
            ? DateTime.tryParse(json['lastExpEarnedAt'])
            : null,
        visitedRegions: List<String>.from(json['visitedRegions'] ?? []),
        completedQuestIds: List<String>.from(json['completedQuestIds'] ?? []),
      );

  /// Prisma `User` 레코드(+keywords)를 앱 모델로 옮긴다.
  ///
  /// 서버 스키마와 이름이 다른 곳:
  ///  - `expCurrent`  → [exp]        (현재 레벨 구간의 누적치)
  ///  - `keywords`    → [travelStyles] (`[{userId, keywordId}]` 형태로 온다)
  ///  - `avatarId`    → 그대로. 단 알 수 없는 값은 기본 프리셋으로 떨어뜨린다.
  factory UserModel.fromServer(Map<String, dynamic> json) {
    final rawKeywords = json['keywords'];
    final keywords = <String>[];
    if (rawKeywords is List) {
      for (final k in rawKeywords) {
        if (k is Map && k['keywordId'] != null) {
          keywords.add('${k['keywordId']}');
        } else if (k is String) {
          keywords.add(k);
        }
      }
    }

    return UserModel(
      serverId: json['id'] as int?,
      nickname: json['nickname'] as String? ?? '',
      avatarId: AppAssets.normalizeAvatarId(json['avatarId'] as String?),
      homeRegion: json['homeRegion'] as String?,
      level: json['level'] as int? ?? 1,
      exp: json['expCurrent'] as int? ?? 0,
      travelStyles: keywords,
      activityLevel: json['activityLevel'] as String? ?? '보통',
      streakDays: json['streakDays'] as int? ?? 0,
      dailyExpEarned: json['dailyExpEarned'] as int? ?? 0,
      lastExpEarnedAt: json['lastExpResetAt'] != null
          ? DateTime.tryParse('${json['lastExpResetAt']}')
          : null,
    );
  }

  String toRawJson() => json.encode(toJson());
  factory UserModel.fromRawJson(String str) => UserModel.fromJson(json.decode(str));
}
