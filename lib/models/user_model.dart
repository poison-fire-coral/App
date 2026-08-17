import 'dart:convert';

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
  final String nickname;
  final String avatarPresetUrl;            // 기본 아바타 (6종 중 선택)
  final String? homeRegion;                 // 관심/홈 지역 (선택)
  final int level;
  final int exp;                            // 현재 레벨 구간에서 쌓은 경험치
  final List<String> travelStyles;          // 여행 키워드 / 스타일
  final String transport;                    // 주요 이동수단
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
    this.avatarPresetUrl = 'assets/avatars/avatar_1.png',
    this.homeRegion,
    this.level = 1,
    this.exp = 0,
    required this.travelStyles,
    required this.transport,
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
    String? avatarPresetUrl,
    String? homeRegion,
    int? level,
    int? exp,
    List<String>? travelStyles,
    String? transport,
    List<String>? representativeBadgeIds,
    int? streakDays,
    int? dailyExpEarned,
    DateTime? lastExpEarnedAt,
    List<String>? visitedRegions,
    List<String>? completedQuestIds,
  }) {
    return UserModel(
      nickname: nickname ?? this.nickname,
      avatarPresetUrl: avatarPresetUrl ?? this.avatarPresetUrl,
      homeRegion: homeRegion ?? this.homeRegion,
      level: level ?? this.level,
      exp: exp ?? this.exp,
      travelStyles: travelStyles ?? this.travelStyles,
      transport: transport ?? this.transport,
      representativeBadgeIds: representativeBadgeIds ?? this.representativeBadgeIds,
      streakDays: streakDays ?? this.streakDays,
      dailyExpEarned: dailyExpEarned ?? this.dailyExpEarned,
      lastExpEarnedAt: lastExpEarnedAt ?? this.lastExpEarnedAt,
      visitedRegions: visitedRegions ?? this.visitedRegions,
      completedQuestIds: completedQuestIds ?? this.completedQuestIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'avatarPresetUrl': avatarPresetUrl,
        'homeRegion': homeRegion,
        'level': level,
        'exp': exp,
        'travelStyles': travelStyles,
        'transport': transport,
        'representativeBadgeIds': representativeBadgeIds,
        'streakDays': streakDays,
        'dailyExpEarned': dailyExpEarned,
        'lastExpEarnedAt': lastExpEarnedAt?.toIso8601String(),
        'visitedRegions': visitedRegions,
        'completedQuestIds': completedQuestIds,
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        nickname: json['nickname'] ?? '',
        avatarPresetUrl: json['avatarPresetUrl'] ?? 'assets/avatars/avatar_1.png',
        homeRegion: json['homeRegion'],
        level: json['level'] ?? 1,
        exp: json['exp'] ?? 0,
        travelStyles: List<String>.from(json['travelStyles'] ?? []),
        transport: json['transport'] ?? '',
        representativeBadgeIds: List<String>.from(json['representativeBadgeIds'] ?? []),
        streakDays: json['streakDays'] ?? 0,
        dailyExpEarned: json['dailyExpEarned'] ?? 0,
        lastExpEarnedAt: json['lastExpEarnedAt'] != null
            ? DateTime.tryParse(json['lastExpEarnedAt'])
            : null,
        visitedRegions: List<String>.from(json['visitedRegions'] ?? []),
        completedQuestIds: List<String>.from(json['completedQuestIds'] ?? []),
      );

  String toRawJson() => json.encode(toJson());
  factory UserModel.fromRawJson(String str) => UserModel.fromJson(json.decode(str));
}
