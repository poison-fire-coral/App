
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../models/quest_model.dart';
import '../services/geo.dart';

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
    return 'http://localhost:5001/api/v1'; // iOS 시뮬레이터 및 기본
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
      if (p2 is GeoPoint) userPoint = p2;
      else if (p2 is LatLng) userPoint = GeoPoint(p2.latitude, p2.longitude);
    } else if (target is GeoPoint) {
      targetLat = target.latitude;
      targetLng = target.longitude;
      if (p2 is GeoPoint) userPoint = p2;
      else if (p2 is LatLng) userPoint = GeoPoint(p2.latitude, p2.longitude);
    } else if (target is LatLng) {
      targetLat = target.latitude;
      targetLng = target.longitude;
      if (p2 is GeoPoint) userPoint = p2;
      else if (p2 is LatLng) userPoint = GeoPoint(p2.latitude, p2.longitude);
    } else if (target is num && p2 is num) {
      targetLat = target.toDouble();
      targetLng = p2.toDouble();
      if (p3 is GeoPoint) userPoint = p3;
      else if (p3 is LatLng) userPoint = GeoPoint(p3.latitude, p3.longitude);
    }

    return Geo.distanceBetween(
      userPoint.latitude,
      userPoint.longitude,
      targetLat,
      targetLng,
    );
  }

  /// 1. 내 위치 기반 근처 퀘스트 조회 (GET /api/v1/quests/nearby)
  static Future<List<QuestModel>> fetchNearbyQuests({
    required double lat,
    required double lng,
    int radiusM = 50000,
    List<String>? keywords,
    String? authToken,
  }) async {
    // API 호출 시 들어오는 실시간 사용자 GPS 좌표로 currentUserLocation 갱신
    updateUserLocation(lat, lng);

    try {
      final Map<String, String> queryParams = {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radiusM': radiusM.toString(),
      };

      if (keywords != null && keywords.isNotEmpty && !keywords.contains('전체')) {
        queryParams['keywords'] = keywords.join(',');
      }

      final uri = Uri.parse('$baseUrl/quests/nearby').replace(queryParameters: queryParams);

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> data = body['data'] ?? [];

        return data.map((json) => QuestModel.fromJson(json)).toList();
      } else {
        debugPrint('퀘스트 API 오류: ${response.statusCode} - ${response.body}');
        return mockQuests;
      }
    } catch (e) {
      debugPrint('백엔드 통신 에러 (fetchNearbyQuests): $e');
      return mockQuests;
    }
  }

  /// 2. 퀘스트 수락 (POST /api/v1/quests/:id/accept)
  static Future<bool> acceptQuest({
    required String questId,
    required String authToken,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/quests/$questId/accept');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('퀘스트 수락 통신 에러: $e');
      return false;
    }
  }

  /// 3. 퀘스트 도달 인증 (POST /api/v1/quests/:id/verify)
  static Future<Map<String, dynamic>?> verifyQuest({
    required String questId,
    required String requestId,
    required double lat,
    required double lng,
    required double accuracyM,
    String? photoUrl,
    String? userText,
    String? emotionTag,
    required String authToken,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/quests/$questId/verify');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'requestId': requestId,
          'lat': lat,
          'lng': lng,
          'accuracyM': accuracyM,
          'photoUrl': photoUrl,
          'userText': userText,
          'emotionTag': emotionTag,
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['data'];
      } else {
        debugPrint('인증 오류: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('퀘스트 인증 통신 에러: $e');
      return null;
    }
  }
}
=======
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

