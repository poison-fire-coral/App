import '../services/geo.dart';

/// 퀘스트 난이도 및 기본 EXP
enum QuestDifficulty {
  star1(1, 50, '산책'),
  star2(2, 110, '기본'),
  star3(3, 220, '탐험'),
  star4(4, 400, '원정'),
  star5(5, 700, '전설');

  final int stars;
  final int baseExp;
  final String label;

  const QuestDifficulty(this.stars, this.baseExp, this.label);

  static const double halfStarMultiplier = 1.15;

  static int getExpWithHalfStar({required QuestDifficulty base, bool hasHalfStar = false}) {
    if (!hasHalfStar) return base.baseExp;
    return (base.baseExp * halfStarMultiplier).floor();
  }
}

/// 퀘스트가 요구하는 방문 지점 하나
class QuestSpot {
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const QuestSpot({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 50,
  });

  GeoPoint get point => GeoPoint(latitude, longitude);
}

/// 퀘스트 데이터 모델
class QuestModel {
  final String id;
  final String title;
  final String summary;
  final String description;
  final QuestDifficulty difficulty;

  /// 서버 `Quest.questType` (VISIT · TIME_WINDOW · PHOTO_SINGLE · PHOTO_COLLECT
  /// · QUIZ · EXPLORATION · RECORD). 지도 마커의 **모양**을 정한다.
  /// 목업 퀘스트에는 없으므로 기본값은 VISIT.
  final String questType;
  final bool hasHalfStar;
  final double latitude;
  final double longitude;
  final double validRadiusMeters;
  final String spotName;
  final String regionLabel;
  final String? imageUrl;
  final List<String> keywords;

  final double crowdMultiplier;
  final List<QuestSpot> spots;
  final bool requiresPhoto;

  /// 이 사람이 이미 끝낸 퀘스트인지 — 체크리스트 22번.
  ///
  /// **서버가 판단한다.** 앱도 `user.completedQuestIds`로 알기는 하지만 그건
  /// SharedPreferences라 기기를 바꾸면 사라진다. 서버가 `quest_completions`를
  /// 보고 채워 주는 값이 진실이고, 비로그인이면 늘 false다.
  ///
  /// 완료해도 목록에서 **빼지 않는다.** 지도에서 사라지면 "여기 뭐 있었는데"가
  /// 되고, 재방문(x0.3, 16번)으로 가는 길도 막힌다. 흐리게 그릴 뿐이다.
  final bool isCompleted;

  QuestModel({
    required this.id,
    required this.title,
    required this.summary,
    required this.description,
    required this.difficulty,
    this.questType = 'VISIT',
    this.hasHalfStar = false,
    required this.latitude,
    required this.longitude,
    this.validRadiusMeters = 50.0,
    required this.spotName,
    this.regionLabel = '',
    this.imageUrl,
    required this.keywords,
    this.crowdMultiplier = 1.0,
    this.spots = const [],
    this.isCompleted = false,
    bool? requiresPhoto,
  }) : requiresPhoto = requiresPhoto ?? difficulty != QuestDifficulty.star1;

  GeoPoint get point => GeoPoint(latitude, longitude);

  List<QuestSpot> get visitSpots => spots.isNotEmpty
      ? spots
      : [
          QuestSpot(
            name: spotName,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: validRadiusMeters,
          ),
        ];

  int get spotCount => visitSpots.length;

  String get starLabel => '★' * difficulty.stars + (hasHalfStar ? '½' : '');

  int get displayExp =>
      QuestDifficulty.getExpWithHalfStar(base: difficulty, hasHalfStar: hasHalfStar);

  int get estimatedExp => (difficulty.baseExp * _halfStarFactor * crowdMultiplier).floor();

  double get _halfStarFactor => hasHalfStar ? QuestDifficulty.halfStarMultiplier : 1.0;

  String get crowdLabel {
    if (crowdMultiplier >= 1.3) return '한산';
    if (crowdMultiplier <= 0.8) return '혼잡';
    return '보통';
  }

  String get completionCriteria {
    final spotPart = spotCount > 1
        ? '지점 $spotCount곳 순서대로 도달'
        : '목표 좌표 반경 ${visitSpots.first.radiusMeters.round()}m 도달';
    return requiresPhoto ? '$spotPart · 사진 1장' : spotPart;
  }

  /// 진행 중 퀘스트를 로컬에 통째로 저장하기 위한 직렬화.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'story': description,
        'summary': summary,
        'difficulty': difficulty.stars,
        'questType': questType,
        'halfStep': hasHalfStar,
        'radiusM': validRadiusMeters,
        'imageUrl': imageUrl,
        'keywords': keywords,
        'requiresPhoto': requiresPhoto,
        'crowdMultiplier': crowdMultiplier,
        'isCompleted': isCompleted,
        'spots': [
          for (final spot in spots)
            {
              'name': spot.name,
              'lat': spot.latitude,
              'lng': spot.longitude,
              'radiusM': spot.radiusMeters,
            },
        ],
        'place': {
          'name': spotName,
          'address': regionLabel,
          'lat': latitude,
          'lng': longitude,
          'imageUrl': imageUrl,
        },
      };

  /// 백엔드 Prisma JSON (Quest + Place) -> Flutter QuestModel 변환 팩토리
  factory QuestModel.fromJson(Map<String, dynamic> json) {
    final place = json['place'] as Map<String, dynamic>? ?? {};

    // 1. 난이도 변환 (1~5 -> QuestDifficulty)
    final int diffInt = json['difficulty'] as int? ?? 1;
    QuestDifficulty diff;
    switch (diffInt) {
      case 1: diff = QuestDifficulty.star1; break;
      case 2: diff = QuestDifficulty.star2; break;
      case 3: diff = QuestDifficulty.star3; break;
      case 4: diff = QuestDifficulty.star4; break;
      case 5: diff = QuestDifficulty.star5; break;
      default: diff = QuestDifficulty.star1;
    }

    // 2. 혼잡도 변환 (congestionScore 0~100)
    double crowdMult = 1.0;
    if (place.containsKey('congestionScore')) {
      final score = (place['congestionScore'] as num).toDouble();
      if (score <= 30) {
        crowdMult = 1.4; // 한산
      } else if (score >= 70) {
        crowdMult = 0.7; // 혼잡
      } else {
        crowdMult = 1.0; // 보통
      }
    }

    final double lat = (place['lat'] as num?)?.toDouble() ?? (json['latitude'] as num?)?.toDouble() ?? 0.0;
    final double lng = (place['lng'] as num?)?.toDouble() ?? (json['longitude'] as num?)?.toDouble() ?? 0.0;

    // 3. 대표 이미지 URL 추출 (place.imageUrl 또는 루트의 imageUrl)
    final String? rawImageUrl = (place['imageUrl'] as String?) ?? (json['imageUrl'] as String?);
    final String? parsedImageUrl = (rawImageUrl != null && rawImageUrl.trim().isNotEmpty)
        ? rawImageUrl
        : null;

    return QuestModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      summary: json['story'] ?? json['summary'] ?? '',
      description: json['story'] ?? json['description'] ?? '',
      difficulty: diff,
      questType: (json['questType'] as String?) ?? 'VISIT',
      hasHalfStar: json['halfStep'] ?? false,
      latitude: lat,
      longitude: lng,
      validRadiusMeters: (json['radiusM'] as num?)?.toDouble() ?? 50.0,
      spotName: place['name'] ?? json['spotName'] ?? '',
      regionLabel: place['address'] ?? place['regionCode'] ?? json['regionLabel'] ?? '',
      imageUrl: parsedImageUrl,
      keywords: List<String>.from(json['keywords'] ?? []),
      crowdMultiplier: crowdMult,
      isCompleted: json['isCompleted'] == true,
      requiresPhoto: json['requiresPhoto'] as bool?,
      spots: [
        if (json['spots'] is List)
          for (final raw in (json['spots'] as List))
            QuestSpot(
              name: '${(raw as Map)['name'] ?? ''}',
              latitude: (raw['lat'] as num?)?.toDouble() ?? lat,
              longitude: (raw['lng'] as num?)?.toDouble() ?? lng,
              radiusMeters: (raw['radiusM'] as num?)?.toDouble() ?? 50,
            ),
      ],
    );
  }
}