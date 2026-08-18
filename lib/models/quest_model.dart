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

/// 퀘스트 데이터 모델 (기획서 3b, 3c, 4a 기준)
class QuestModel {
  final String id;
  final String title;
  final String summary;
  final String description;
  final QuestDifficulty difficulty;
  final bool hasHalfStar;
  final double latitude;
  final double longitude;
  final double validRadiusMeters;
  final String spotName;
  final String regionLabel;
  final List<String> keywords;

  /// 혼잡도 배율 · 기획서 6b 기준 (한산 ×1.4 · 보통 ×1.0 · 혼잡 ×0.7)
  final double crowdMultiplier;

  /// 순차 방문 지점. 비어 있으면 대표 좌표 한 곳짜리 퀘스트로 취급한다.
  final List<QuestSpot> spots;

  /// 방문 인증 시 사진을 요구하는지 (★★ 이상은 도달 + 사진 인증 · 기획서 6a)
  final bool requiresPhoto;

  QuestModel({
    required this.id,
    required this.title,
    required this.summary,
    required this.description,
    required this.difficulty,
    this.hasHalfStar = false,
    required this.latitude,
    required this.longitude,
    this.validRadiusMeters = 50.0,
    required this.spotName,
    this.regionLabel = '',
    required this.keywords,
    this.crowdMultiplier = 1.0,
    this.spots = const [],
    bool? requiresPhoto,
  }) : requiresPhoto = requiresPhoto ?? difficulty != QuestDifficulty.star1;

  GeoPoint get point => GeoPoint(latitude, longitude);

  /// 실제로 방문해야 하는 지점 목록 (지점이 지정되지 않았으면 대표 좌표 1곳)
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

  /// UI 표시용 별 문자열 (반개는 ½로 표시)
  String get starLabel => '★' * difficulty.stars + (hasHalfStar ? '½' : '');

  /// 지도 시트에 "보상 : EXP n"으로 노출하는 표시용 값 (반개 보정까지만 반영).
  ///
  /// 실제 지급량은 [ExpService]가 `floor(난이도 기본 EXP × 배율들)`로 한 번에 계산한다.
  /// 여기서 먼저 내림해 버리면 반올림 오차가 두 번 쌓이므로 표시 외의 용도로 쓰지 않는다.
  int get displayExp =>
      QuestDifficulty.getExpWithHalfStar(base: difficulty, hasHalfStar: hasHalfStar);

  /// 혼잡도까지 반영한 예상 보상 EXP (최종 정산은 ExpService가 담당)
  int get estimatedExp => (difficulty.baseExp * _halfStarFactor * crowdMultiplier).floor();

  double get _halfStarFactor => hasHalfStar ? QuestDifficulty.halfStarMultiplier : 1.0;

  /// 혼잡도 배율의 사람이 읽는 라벨 (기획서 6b)
  String get crowdLabel {
    if (crowdMultiplier >= 1.3) return '한산';
    if (crowdMultiplier <= 0.8) return '혼잡';
    return '보통';
  }

  /// 4a·4b에 표시하는 달성 기준 문구
  String get completionCriteria {
    final spotPart = spotCount > 1
        ? '지점 $spotCount곳 순서대로 도달'
        : '목표 좌표 반경 ${visitSpots.first.radiusMeters.round()}m 도달';
    return requiresPhoto ? '$spotPart · 사진 1장' : spotPart;
  }
}
