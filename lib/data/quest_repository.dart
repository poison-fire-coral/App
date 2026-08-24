import '../models/api_exception.dart';
import '../services/api_client.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../models/quest_model.dart';
import '../services/geo.dart';
import 'package:flutter/foundation.dart';

class QuestRepository {
  /// 가상 내 위치 (수원화성/행궁동 시드 데이터 위치)
  static const GeoPoint mockUserLocation = GeoPoint(37.2882, 127.0163);

  /// KakaoMap LatLng 포맷이 필요한 경우
  static final LatLng mockUserLatLng = LatLng(37.2882, 127.0163);

  /// 앱 전역에서 사용할 실시간 사용자 GPS 위치 (기본값은 목업 위치)
  static GeoPoint currentUserLocation = mockUserLocation;

  /// 위치 업데이트용 메서드
  static void updateUserLocation(double lat, double lng) {
    currentUserLocation = GeoPoint(lat, lng);
  }

  /// 💡 models/quest_model.dart의 정의와 100% 일치하도록 구성한 목업 데이터
  static final List<QuestModel> mockQuests = [
    QuestModel(
      id: 'q_01',
      title: '화성행궁 골목 탐방',
      summary: '행궁동 골목길의 숨은 명소를 찾아 떠나는 여행',
      description: '아름다운 행궁동 골목길의 숨은 명소를 찾아보세요.',
      difficulty: QuestDifficulty.star3,
      latitude: 37.2882,
      longitude: 127.0163,
      spotName: '화성행궁 정문 (신풍루)',
      regionLabel: '수원 행궁동',
      keywords: const ['역사', '산책', '카페'],
      spots: const [
        QuestSpot(
          name: '화성행궁 정문 (신풍루)',
          latitude: 37.2882,
          longitude: 127.0163,
        ),
        QuestSpot(
          name: '행리단길 카페거리',
          latitude: 37.2890,
          longitude: 127.0170,
        ),
      ],
    ),
    QuestModel(
      id: 'q_02',
      title: '방화수류정 성곽길 산책',
      summary: '수원화성의 탁 트인 절경을 감상하는 코스',
      description: '수원화성에서 가장 경치가 뛰어난 방화수류정을 거닐어 보세요.',
      difficulty: QuestDifficulty.star4,
      latitude: 37.2850,
      longitude: 127.0180,
      spotName: '방화수류정 연못',
      regionLabel: '수원 성곽길',
      keywords: const ['풍경', '힐링', '야경'],
      spots: const [
        QuestSpot(
          name: '방화수류정 연못',
          latitude: 37.2850,
          longitude: 127.0180,
        ),
      ],
    ),
    QuestModel(
      id: 'q_03',
      title: '장안문 역사 기행',
      summary: '수원화성 북문 장안문 탐방',
      description: '수원화성의 북문인 장안문의 웅장함을 느껴보세요.',
      difficulty: QuestDifficulty.star2,
      latitude: 37.2910,
      longitude: 127.0145,
      spotName: '장안문 성곽 입구',
      regionLabel: '수원 장안문',
      keywords: const ['역사', '문화재'],
      spots: const [
        QuestSpot(
          name: '장안문 성곽 입구',
          latitude: 37.2910,
          longitude: 127.0145,
        ),
      ],
    ),
  ];

  /// ID로 퀘스트 단건 조회 (main.dart에서 사용)
  static QuestModel? findById(String id) {
    try {
      return mockQuests.firstWhere((q) => q.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 동기 방식 추천 퀘스트 목록 조회 (main.dart에서 사용)
  static List<QuestModel> nearby({Set<String>? excludeIds}) {
    if (excludeIds == null || excludeIds.isEmpty) {
      return List.unmodifiable(mockQuests);
    }
    return mockQuests.where((q) => !excludeIds.contains(q.id)).toList();
  }

  /// .env 백엔드 설정에 맞춘 5001번 포트 Base URL
  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:5001/api/v1';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001/api/v1'; // 안드로이드 에뮬레이터
    }
    return 'http://192.168.219.198:5001/api/v1';// ios 실제 기기
  }


  /// 사용자 위치 기준 거리를 '350m', '1.2km' 형식 문자열로 반환
  static String distanceFromUser(
    dynamic target, [
    dynamic p2,
    dynamic p3,
  ]) {
    final meters = distanceFromUserMeters(target, p2, p3);
    return Geo.formatDistance(meters);
  }

  /// 사용자 위치 기준 거리를 미터(m) 수치(double)로 반환
  static double distanceFromUserMeters(
    dynamic target, [
    dynamic p2,
    dynamic p3,
  ]) {
    double targetLat = 0.0;
    double targetLng = 0.0;
    // mockUserLocation 대신 실시간 업데이트된 currentUserLocation 사용
    GeoPoint userPoint = currentUserLocation;

    if (target is QuestModel) {
      targetLat = target.latitude;
      targetLng = target.longitude;
      if (p2 is GeoPoint) {
        userPoint = p2;
      } else if (p2 is LatLng) {
        userPoint = GeoPoint(p2.latitude, p2.longitude);
      }
    } else if (target is GeoPoint) {
      targetLat = target.latitude;
      targetLng = target.longitude;
      if (p2 is GeoPoint) {
        userPoint = p2;
      } else if (p2 is LatLng) {
        userPoint = GeoPoint(p2.latitude, p2.longitude);
      }
    } else if (target is LatLng) {
      targetLat = target.latitude;
      targetLng = target.longitude;
      if (p2 is GeoPoint) {
        userPoint = p2;
      } else if (p2 is LatLng) {
        userPoint = GeoPoint(p2.latitude, p2.longitude);
      }
    } else if (target is num && p2 is num) {
      targetLat = target.toDouble();
      targetLng = p2.toDouble();
      if (p3 is GeoPoint) {
        userPoint = p3;
      } else if (p3 is LatLng) {
        userPoint = GeoPoint(p3.latitude, p3.longitude);
      }
    }

    return Geo.distanceBetween(
      userPoint.latitude,
      userPoint.longitude,
      targetLat,
      targetLng,
    );
  }

  // ---------------------------------------------------------------------------
  // 서버 호출 — 인증 헤더·에러 봉투는 ApiClient가 처리한다.
  // 실패는 예외로 던진다. 조용히 목업으로 갈아치우면 "왜 다른 데이터가 뜨지"를 못 찾는다.
  // ---------------------------------------------------------------------------

  /// 내 위치 기준 근처 퀘스트.
  ///
  /// 온보딩 키워드(`#골목산책` …)와 서버 퀘스트 키워드(`산책`, `공원` …)는 어휘가
  /// 완전히 달라서, 온보딩 값을 그대로 넘기면 결과가 항상 0건이다.
  /// 매핑 테이블이 생기기 전까지 [keywords]는 지도 필터에서만 쓴다.
  static Future<List<QuestModel>> fetchNearbyQuests({
    required double lat,
    required double lng,
    int radiusM = 5000,
    List<String>? keywords,
  }) async {
    updateUserLocation(lat, lng);

    final data = await ApiClient.get(
      '/quests/nearby',
      query: {
        'lat': lat,
        'lng': lng,
        'radiusM': radiusM,
        if (keywords != null && keywords.isNotEmpty && !keywords.contains('전체'))
          'keywords': keywords,
      },
      auth: false,
    );

    if (data is! List) return const [];
    return [
      for (final entry in data)
        QuestModel.fromJson(Map<String, dynamic>.from(entry as Map)),
    ];
  }

  /// 진행 중인 내 퀘스트. 앱을 다시 켰을 때 서버 기준으로 목록을 맞춘다.
  static Future<List<Map<String, dynamic>>> fetchMyQuests({
    String status = 'in_progress',
  }) async {
    final data = await ApiClient.get('/quests/my', query: {'status': status});
    if (data is! List) return const [];
    return [
      for (final entry in data) Map<String, dynamic>.from(entry as Map),
    ];
  }

  /// 퀘스트 수락.
  ///
  /// 이미 수락해 진행 중이면 서버가 409 `QUEST_ALREADY_ACCEPTED`를 준다. 그건 오류가
  /// 아니라 "이어서 하기"이므로 여기서 삼킨다.
  ///
  /// 반면 이미 완료한 퀘스트는 409 `QUEST_ALREADY_DONE`으로 오고, 이건 삼키면 안 된다.
  /// 삼키면 앱이 수락에 성공한 줄 알고 퀘스트 흐름을 열어버리는데, 현장에 도착해
  /// 인증을 누르는 순간 서버가 다시 거절한다. 여기서 바로 알려주는 게 맞다.
  static Future<void> acceptQuest(String questId) async {
    try {
      await ApiClient.post('/quests/$questId/accept');
    } on ApiException catch (e) {
      if (e.isAlreadyAccepted) return;
      rethrow;
    }
  }

  /// 수락 취소(포기).
  static Future<void> abandonQuest(String questId) async {
    try {
      await ApiClient.delete('/quests/$questId/accept');
    } on ApiException catch (e) {
      // 서버에 기록이 없으면 이미 목적을 달성한 것이다.
      if (e.code == 'QUEST_NOT_FOUND' || e.code == 'NOT_FOUND') return;
      rethrow;
    }
  }

  /// 도달 인증. 서버가 거리·정확도·어뷰징을 재검증하고 EXP까지 확정해 돌려준다.
  ///
  /// [requestId]는 재시도할 때 **같은 값**을 보내야 한다. 그래야 서버가
  /// `{isAlreadyProcessed: true}`로 응답하며 EXP 이중 지급을 막는다.
  static Future<Map<String, dynamic>> verifyQuest({
    required String questId,
    required String requestId,
    required double lat,
    required double lng,
    required double accuracyM,
    String? photoUrl,
    String? photoVisibility,
    String? userText,
    String? emotionTag,
  }) async {
    final data = await ApiClient.post('/quests/$questId/verify', body: {
      'requestId': requestId,
      'lat': lat,
      'lng': lng,
      'accuracyM': accuracyM,
      'photoUrl': ?photoUrl,
      'photoVisibility': ?photoVisibility,
      'userText': ?userText,
      'emotionTag': ?emotionTag,
    });
    return Map<String, dynamic>.from(data as Map);
  }
}
