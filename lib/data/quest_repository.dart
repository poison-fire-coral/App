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