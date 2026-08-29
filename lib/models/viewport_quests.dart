import 'quest_model.dart';

/// 클러스터 하나 — 좌표와 그 안에 묶인 퀘스트 수.
class QuestCluster {
  final double latitude;
  final double longitude;
  final int count;

  const QuestCluster({
    required this.latitude,
    required this.longitude,
    required this.count,
  });

  factory QuestCluster.fromJson(Map<String, dynamic> json) => QuestCluster(
        latitude: (json['lat'] as num?)?.toDouble() ?? 0,
        longitude: (json['lng'] as num?)?.toDouble() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  /// 지도 오버레이 id로 쓴다.
  ///
  /// **좌표와 개수를 id에 넣는 게 핵심이다.** 카카오 플러그인의
  /// `addCustomOverlay`는 같은 id가 이미 있으면 조용히 무시한다. `cluster_0`
  /// 처럼 순번을 쓰면 지도를 옮겨도 예전 자리의 원이 그대로 남는다.
  String get overlayId =>
      'lq_cluster_${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}_$count';
}

/// `GET /quests?swLat&swLng&neLat&neLng&zoom` 의 응답.
///
/// 서버가 zoom에 따라 **모양이 다른 두 가지**를 돌려준다
/// (`quest.service.ts:314` — zoom 14 미만이면 격자로 묶는다).
///  - 확대 상태: `{isClustered:false, quests:[...]}`
///  - 축소 상태: `{isClustered:true,  clusters:[{lat,lng,count}]}`
///
/// 화면이 매번 `json['isClustered']`를 뒤지지 않도록 여기서 한 번만 가른다.
class ViewportQuests {
  final bool isClustered;

  /// 서버가 이 범위에서 찾은 전체 개수. 클러스터일 때도 채워진다.
  final int totalQuests;

  /// `isClustered == false`일 때만 채워진다.
  final List<QuestModel> quests;

  /// `isClustered == true`일 때만 채워진다.
  final List<QuestCluster> clusters;

  /// 서버가 준 개수가 [renderLimit]을 넘어 [quests]를 잘랐는지.
  ///
  /// 서버 `findMany`에 아직 `take` 상한이 없다(체크리스트 08번 BE 몫).
  /// 그래서 범위가 넓으면 수천 건이 그대로 내려올 수 있고, 그 수만큼
  /// WebView에 마커를 꽂으면 지도가 멈춘다. 내려받는 건 못 막지만
  /// 그리는 건 막을 수 있다.
  final bool isTruncated;

  const ViewportQuests({
    required this.isClustered,
    required this.totalQuests,
    this.quests = const [],
    this.clusters = const [],
    this.isTruncated = false,
  });

  const ViewportQuests.empty()
      : isClustered = false,
        totalQuests = 0,
        quests = const [],
        clusters = const [],
        isTruncated = false;

  /// 한 화면에 꽂을 마커 상한.
  ///
  /// 200은 서버가 08번에서 넣기로 한 `take`와 같은 수다. 서버가 상한을 갖게
  /// 되면 이 자르기는 저절로 아무 일도 하지 않게 된다 — 그때 지워도 되고,
  /// 이중 안전장치로 남겨 둬도 된다.
  static const int renderLimit = 200;

  factory ViewportQuests.fromJson(Map<String, dynamic> json) {
    final total = (json['totalQuests'] as num?)?.toInt() ?? 0;

    if (json['isClustered'] == true) {
      final raw = json['clusters'];
      return ViewportQuests(
        isClustered: true,
        totalQuests: total,
        clusters: [
          if (raw is List)
            for (final entry in raw)
              QuestCluster.fromJson(Map<String, dynamic>.from(entry as Map)),
        ],
      );
    }

    final raw = json['quests'];
    final parsed = <QuestModel>[
      if (raw is List)
        for (final entry in raw)
          QuestModel.fromJson(Map<String, dynamic>.from(entry as Map)),
    ];

    return ViewportQuests(
      isClustered: false,
      totalQuests: total == 0 ? parsed.length : total,
      quests: parsed.length > renderLimit
          ? parsed.sublist(0, renderLimit)
          : parsed,
      isTruncated: parsed.length > renderLimit,
    );
  }
}
