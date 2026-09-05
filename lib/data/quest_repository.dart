import 'package:flutter/foundation.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../models/api_exception.dart';
import '../models/quest_model.dart';
import '../models/viewport_quests.dart';
import '../services/api_client.dart';
import '../services/geo.dart';
import '../services/photo_uploader.dart';

class QuestRepository {
  /// GPS를 아직 못 잡았을 때 지도를 놓을 자리 (수원화성/행궁동, 시드 데이터가 있는 곳).
  ///
  /// **가짜 위치가 아니라 기본 중심점이다.** 권한을 받기 전이나 실내에서 첫 표본을
  /// 기다리는 동안 지도가 바다 한가운데를 보여주지 않게 하려는 것뿐이고,
  /// 실제 좌표가 들어오는 순간 [currentUserLocation]이 덮어쓴다.
  static const GeoPoint defaultMapCenter = GeoPoint(37.2882, 127.0163);

  /// KakaoMap LatLng 포맷이 필요한 경우
  static final LatLng defaultMapCenterLatLng = LatLng(37.2882, 127.0163);

  /// 앱 전역에서 사용할 실시간 사용자 GPS 위치.
  static GeoPoint currentUserLocation = defaultMapCenter;

  /// 위치 업데이트용 메서드
  static void updateUserLocation(double lat, double lng) {
    currentUserLocation = GeoPoint(lat, lng);
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

  /// 지도에 보이는 사각형 안의 퀘스트.
  ///
  /// **`/quests/nearby`와 무엇이 다른가**
  /// `nearby`는 내 위치 반경으로 찾고 매 호출마다 TourAPI를 때려 새 퀘스트를
  /// 만들어 넣는다(`quest.service.ts:348`). 지도를 옮길 때마다 부르기엔 너무
  /// 무겁다. 이쪽은 순수 조회라 가볍고, 지도가 보고 있는 범위와 정확히 맞는다.
  ///
  /// [zoom]은 **웹 지도 기준**(클수록 확대)이다. 카카오 레벨과 반대이므로
  /// 화면 쪽에서 `MapZoom.fromKakaoLevel`로 바꿔서 넘긴다. 서버는 이 값이
  /// 14 미만이면 격자로 묶은 클러스터를 돌려준다.
  ///
  /// [search]와 [keywords]는 서버가 이미 받는 파라미터다
  /// (`quest.service.ts:296`, `:305`). 앱에서 목록을 걸러 내면 **화면 밖에
  /// 있는 퀘스트는 영영 찾을 수 없다** — 그래서 둘 다 서버로 넘긴다.
  static Future<ViewportQuests> fetchQuestsInBounds({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    List<String>? keywords,
    String? search,
  }) async {
    final trimmed = search?.trim();

    final data = await ApiClient.get(
      '/quests',
      query: {
        'swLat': swLat,
        'swLng': swLng,
        'neLat': neLat,
        'neLng': neLng,
        'zoom': zoom,
        if (keywords != null && keywords.isNotEmpty) 'keywords': keywords,
        if (trimmed != null && trimmed.isNotEmpty) 'search': trimmed,
      },
      // 서버가 `optionalAuth`라 토큰이 **있으면** 각 퀘스트에 `isCompleted`를
      // 붙여 준다(22번). `auth: false`로 두면 로그인해 놓고도 완료 표식을
      // 영영 못 받는다 — 토큰이 없으면 그대로 비로그인으로 처리되므로
      // 지도가 안 뜨는 일은 없다.
    );

    if (data is! Map) return const ViewportQuests.empty();
    return ViewportQuests.fromJson(Map<String, dynamic>.from(data));
  }

  /// 범위를 가리지 않는 전국 검색.
  ///
  /// 검색은 지도 밖도 찾아야 의미가 있다. 좌표 없이 `search`만 보내면
  /// 서버가 `where`에서 place 범위 조건을 빼고 전체에서 찾는다.
  ///
  /// 서버가 100건에서 자르고(`SEARCH_MAX_RESULTS`), 내 위치를 함께 보내면
  /// 거리순으로 정렬해서 준다 — 체크리스트 12번. 받은 뒤 한 번 더 정렬하는 건
  /// 위치를 모르는 첫 진입(기본값이 목업 좌표일 때)을 위한 안전망이다.
  static Future<List<QuestModel>> searchQuests(
    String query, {
    int limit = 30,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final data = await ApiClient.get(
      '/quests',
      query: {
        'search': trimmed,
        'zoom': 15,
        // 상한을 자를 때 서버가 거리순으로 세우도록 기준점을 준다.
        'originLat': currentUserLocation.latitude,
        'originLng': currentUserLocation.longitude,
      },
      // 서버가 `optionalAuth`라 토큰이 **있으면** 각 퀘스트에 `isCompleted`를
      // 붙여 준다(22번). `auth: false`로 두면 로그인해 놓고도 완료 표식을
      // 영영 못 받는다 — 토큰이 없으면 그대로 비로그인으로 처리되므로
      // 지도가 안 뜨는 일은 없다.
    );

    if (data is! Map) return const [];
    final result = ViewportQuests.fromJson(Map<String, dynamic>.from(data));

    final sorted = [...result.quests]..sort((a, b) =>
        distanceFromUserMeters(a).compareTo(distanceFromUserMeters(b)));
    return sorted.length > limit ? sorted.sublist(0, limit) : sorted;
  }

  /// 내 위치 기준 근처 퀘스트.
  ///
  /// TourAPI 동기화를 겸하므로 **첫 진입과 "내 위치" 버튼에서만** 부른다.
  /// 지도를 옮길 때는 [fetchQuestsInBounds]를 쓴다.
  ///
  /// [keywords]에는 서버 어휘(`골목`·`맛집` …)를 넘겨야 한다. 온보딩 값
  /// (`골목산책` …)은 [KeywordTaxonomy]로 옮긴 뒤에 넘긴다.
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
      // 서버가 `optionalAuth`라 토큰이 **있으면** 각 퀘스트에 `isCompleted`를
      // 붙여 준다(22번). `auth: false`로 두면 로그인해 놓고도 완료 표식을
      // 영영 못 받는다 — 토큰이 없으면 그대로 비로그인으로 처리되므로
      // 지도가 안 뜨는 일은 없다.
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

  /// 퀘스트 하나를 id로 가져온다.
  ///
  /// 홈에서 고른 퀘스트가 지도의 현재 범위 밖일 수 있다. 그때 이걸로 좌표를
  /// 알아내 지도를 옮긴다. 못 찾으면 null — 부르는 쪽이 조용히 넘어간다.
  static Future<QuestModel?> fetchQuestById(String questId) async {
    try {
      final data = await ApiClient.get('/quests/$questId', auth: false);
      if (data is! Map) return null;
      return QuestModel.fromJson(Map<String, dynamic>.from(data));
    } on ApiException catch (e) {
      debugPrint('퀘스트 단건 조회 실패($questId): ${e.code}');
      return null;
    }
  }

  /// 사진 업로드용 presigned URL을 받아 온다.
  ///
  /// 서버가 S3에 직접 PUT할 수 있는 5분짜리 URL과, 업로드가 끝난 뒤
  /// `verify`에 실어 보낼 공개 주소를 함께 준다(`upload.service.ts:9`).
  /// 사진 바이트가 우리 서버를 거치지 않으므로 서버 대역폭을 쓰지 않는다.
  static Future<PresignedUpload> requestUploadUrl({
    required String questId,
    required String extension,
  }) async {
    final data = await ApiClient.post(
      '/quests/$questId/upload-url',
      body: {'ext': extension},
    );
    return PresignedUpload.fromJson(Map<String, dynamic>.from(data as Map));
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
    bool isMocked = false,
    String? photoUrl,
    String? photoVisibility,
    String? userText,
    String? emotionTag,
    String? answer,
  }) async {
    final data = await ApiClient.post('/quests/$questId/verify', body: {
      'requestId': requestId,
      'lat': lat,
      'lng': lng,
      'accuracyM': accuracyM,
      // 체크리스트 18번 — 운영체제가 모의 위치라고 표시한 표본인지.
      //
      // **서버는 아직 이 값을 읽지 않는다.** `VerifyQuestDto`에 자리가 없고
      // `quest_completions`에도 컬럼이 없어서 지금은 버려진다. BE가 필드와
      // 컬럼을 만들면(EXP 0 처리 + `is_abused` 기록) 앱 배포 없이 곧바로
      // 값이 흘러 들어간다.
      'isMocked': isMocked,
      'photoUrl': ?photoUrl,
      'photoVisibility': ?photoVisibility,
      'userText': ?userText,
      'emotionTag': ?emotionTag,
      // 09 퀴즈형·10 탐색형이 고른 답. 정답 비교는 서버에서만 한다.
      'answer': ?answer,
    });
    return Map<String, dynamic>.from(data as Map);
  }
}
