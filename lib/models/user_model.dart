import 'dart:convert';

/// 레벨 테이블 및 경험치 연산 시스템 (기획서 6c 기준)
class LevelSystem {
  static const List<int> levelRequiredExpTable = [
    0, 100, 150, 220, 300, 400, 500, 620, 770, 950,
    1150, 1350, 1550, 1750, 2150,
  ];

  /// 해당 레벨의 레벨업 필요 경험치 조회
  static int getRequiredExpForLevel(int level) {
    if (level < 1) return 100;
    if (level < levelRequiredExpTable.length) {
      return levelRequiredExpTable[level];
    }
    return 2000; // Lv 15 이상 고정
  }

  /// 프로필 테두리 링 진행률 연산 (0.0 ~ 1.0)
  static double calculateProgressPercentage(int currentLevel, int currentLevelExp) {
    int requiredExp = getRequiredExpForLevel(currentLevel);
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
  final int exp;
  final List<String> travelStyles;          // 여행 키워드 / 스타일
  final String transport;                    // 주요 이동수단
  final List<String> representativeBadgeIds; // 홈 화면 장착 대표 배지 (최대 3개)

  UserModel({
    required this.nickname,
    this.avatarPresetUrl = 'assets/avatars/avatar_1.png',
    this.homeRegion,
    this.level = 1,
    this.exp = 0,
    required this.travelStyles,
    required this.transport,
    this.representativeBadgeIds = const [],
  });

  /// 💡 홈 화면 프로필 테두리 링 전용 진행률 (0.0 ~ 1.0)
  double get levelProgress => LevelSystem.calculateProgressPercentage(level, exp);

  /// 💡 현재 레벨의 레벨업 필요 경험치
  int get requiredExp => LevelSystem.getRequiredExpForLevel(level);

  // copyWith 업데이트
  UserModel copyWith({
    String? nickname,
    String? avatarPresetUrl,
    String? homeRegion,
    int? level,
    int? exp,
    List<String>? travelStyles,
    String? transport,
    List<String>? representativeBadgeIds,
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
      );

  String toRawJson() => json.encode(toJson());
  factory UserModel.fromRawJson(String str) => UserModel.fromJson(json.decode(str));
}