import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quest_repository.dart';
import '../models/api_exception.dart';

/// 아직 서버에 못 보낸 도달 인증 한 건.
///
/// `verifyQuest`가 받는 인자를 그대로 담는다. 필드가 늘면 여기와
/// [QuestRepository.verifyQuest] 두 곳만 맞추면 된다.
@immutable
class PendingVerification {
  /// **재시도해도 같은 값이어야 한다.** 서버가 이 값으로 멱등을 판정해
  /// `{isAlreadyProcessed: true}`를 돌려주고 EXP를 두 번 주지 않는다.
  final String requestId;

  final String questId;
  final double lat;
  final double lng;
  final double accuracyM;
  final bool isMocked;
  final String? photoUrl;
  final String? photoVisibility;
  final String? userText;
  final String? emotionTag;

  /// 인증을 **시도한** 시각. 보낸 시각이 아니다.
  ///
  /// 오래 묵은 것을 버리는 기준이다.
  final DateTime queuedAt;

  const PendingVerification({
    required this.requestId,
    required this.questId,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.queuedAt,
    this.isMocked = false,
    this.photoUrl,
    this.photoVisibility,
    this.userText,
    this.emotionTag,
  });

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'questId': questId,
        'lat': lat,
        'lng': lng,
        'accuracyM': accuracyM,
        'isMocked': isMocked,
        'photoUrl': photoUrl,
        'photoVisibility': photoVisibility,
        'userText': userText,
        'emotionTag': emotionTag,
        'queuedAt': queuedAt.toIso8601String(),
      };

  /// 못 읽는 줄이면 null. 저장 형식이 바뀌었을 때 그 한 줄 때문에
  /// 큐 전체를 못 읽는 일이 없도록 부르는 쪽이 걸러 낸다.
  static PendingVerification? fromJson(Map<String, dynamic> json) {
    final requestId = json['requestId'] as String?;
    final questId = json['questId'] as String?;
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    if (requestId == null || questId == null || lat == null || lng == null) {
      return null;
    }

    return PendingVerification(
      requestId: requestId,
      questId: questId,
      lat: lat,
      lng: lng,
      accuracyM: (json['accuracyM'] as num?)?.toDouble() ?? 0,
      isMocked: json['isMocked'] == true,
      photoUrl: json['photoUrl'] as String?,
      photoVisibility: json['photoVisibility'] as String?,
      userText: json['userText'] as String?,
      emotionTag: json['emotionTag'] as String?,
      queuedAt: DateTime.tryParse('${json['queuedAt']}') ?? DateTime.now(),
    );
  }
}

/// 못 보낸 도달 인증을 들고 있다가 연결되면 다시 보낸다 — 체크리스트 29번.
///
/// **왜 필요한가.** 산·해안·골목 퀘스트가 있는 서비스에서 목적지에 도착한
/// 순간 신호가 없는 건 예외가 아니라 정상 경로다. 여기서 인증이 그냥
/// 사라지면 사용자는 현장까지 걸어간 대가를 못 받는다.
///
/// **왜 큐가 단순한가.** 서버가 이미 `requestId`로 멱등을 보장한다. 같은 걸
/// 열 번 보내도 완료는 하나고 EXP도 한 번이다. 그래서 이 큐는 "성공할 때까지
/// 같은 요청을 다시 보낸다"만 하면 되고, 중복 방지를 스스로 책임지지 않는다.
///
/// **하지 않는 일.** 보상 화면을 다시 띄우지 않는다. 오프라인에서 완료한
/// 순간 앱이 로컬 계산으로 EXP를 보여 줬고 그 화면은 이미 지나갔다. 대신
/// [flush]가 무언가 보냈다고 알려 주면 부르는 쪽이 `GET /users/me`로 사용자를
/// 다시 받아 서버가 계산한 값으로 덮는다 — 진실은 서버에 있다.
class VerifyQueue {
  const VerifyQueue._();

  static const String _prefsKey = 'pending_verifications';

  /// 이보다 오래 묵은 항목은 보내지 않고 버린다.
  ///
  /// 서버가 배율을 **받는 시점** 기준으로 계산하기 때문이다. 비피크 시간대
  /// (15번)가 대표적이라, 사흘 전 새벽에 찍은 인증을 지금 보내면 엉뚱한
  /// 배율이 붙는다. 못 준 EXP보다 틀린 EXP가 나쁘다.
  static const Duration maxAge = Duration(days: 2);

  /// 쌓아 둘 수 있는 최대 건수. 넘치면 오래된 것부터 버린다.
  ///
  /// 정상적으로는 1~2건이다. 이 숫자에 닿았다면 며칠째 오프라인이라는
  /// 뜻이고, 그쯤이면 앞쪽 항목은 어차피 [maxAge]에 걸린다.
  static const int maxItems = 20;

  /// [flush]가 겹쳐 도는 것을 막는다. 앱 시작과 인증 실패가 같은 순간에
  /// 겹치면 같은 요청을 두 번 보내게 되는데, 멱등이라 해롭진 않아도 낭비다.
  static bool _isFlushing = false;

  // ---------------------------------------------------------------------------
  // 저장
  // ---------------------------------------------------------------------------

  static Future<List<PendingVerification>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      return <PendingVerification>[
        for (final entry in decoded)
          if (entry is Map)
            ?PendingVerification.fromJson(Map<String, dynamic>.from(entry)),
      ];
    } catch (e) {
      debugPrint('대기 중인 인증을 읽지 못했다: $e');
      return const [];
    }
  }

  static Future<void> _save(List<PendingVerification> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (items.isEmpty) {
        await prefs.remove(_prefsKey);
        return;
      }
      await prefs.setString(
        _prefsKey,
        jsonEncode([for (final item in items) item.toJson()]),
      );
    } catch (e) {
      debugPrint('대기 중인 인증을 저장하지 못했다: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 쌓기
  // ---------------------------------------------------------------------------

  /// 못 보낸 인증을 쌓아 둔다.
  ///
  /// 같은 `requestId`가 이미 있으면 덮어쓴다 — 같은 인증을 두 줄로 들고
  /// 있을 이유가 없다.
  static Future<void> enqueue(PendingVerification item) async {
    final items = <PendingVerification>[
      for (final existing in await load())
        if (existing.requestId != item.requestId) existing,
      item,
    ];

    await _save(
      items.length > maxItems ? items.sublist(items.length - maxItems) : items,
    );
  }

  static Future<int> pendingCount() async => (await load()).length;

  // ---------------------------------------------------------------------------
  // 보내기
  // ---------------------------------------------------------------------------

  /// 쌓인 인증을 순서대로 다시 보낸다.
  ///
  /// 돌려주는 값은 **이번에 서버가 받아 준 건수**다. 0보다 크면 부르는 쪽이
  /// 사용자 정보를 다시 받아 EXP·레벨을 서버 값으로 맞춰야 한다.
  ///
  /// **네트워크 실패를 만나면 멈춘다.** 첫 건이 연결 실패로 막혔다면 나머지도
  /// 같은 이유로 막힐 것이 뻔하다. 스무 번 두드려 봐야 배터리만 쓴다.
  ///
  /// **서버가 거절한 건은 버린다.** 반경 밖·이미 완료 같은 응답은 다시
  /// 보낸다고 달라지지 않는다. 영원히 재시도하는 항목을 남기면 앱을 열
  /// 때마다 같은 실패를 반복한다.
  static Future<int> flush() async {
    if (_isFlushing) return 0;
    _isFlushing = true;

    try {
      final items = await load();
      if (items.isEmpty) return 0;

      final now = DateTime.now();
      final remaining = <PendingVerification>[];
      var delivered = 0;
      var stopped = false;

      for (final item in items) {
        if (stopped) {
          remaining.add(item);
          continue;
        }

        if (now.difference(item.queuedAt) > maxAge) {
          debugPrint('너무 오래된 인증을 버린다: ${item.questId} (${item.queuedAt})');
          continue;
        }

        try {
          await QuestRepository.verifyQuest(
            questId: item.questId,
            requestId: item.requestId,
            lat: item.lat,
            lng: item.lng,
            accuracyM: item.accuracyM,
            isMocked: item.isMocked,
            photoUrl: item.photoUrl,
            photoVisibility: item.photoVisibility,
            userText: item.userText,
            emotionTag: item.emotionTag,
          );
          delivered++;
        } on ApiException catch (e) {
          if (e.isNetwork || e.isUnauthorized) {
            // 아직 연결이 없거나(네트워크) 세션이 풀렸다(인증). 둘 다 이 건의
            // 잘못이 아니라 상황이라 그대로 두고 다음 기회를 본다.
            // ApiClient가 refresh를 이미 한 번 시도한 뒤라 여기서 더 할 게 없다.
            remaining.add(item);
            stopped = true;
            continue;
          }

          // 서버가 판단해서 거절했다. 다시 보내도 같은 답이 온다.
          debugPrint('대기 인증을 버린다(${item.questId}): ${e.code} ${e.message}');
        }
      }

      await _save(remaining);
      return delivered;
    } finally {
      _isFlushing = false;
    }
  }

  /// 로그아웃·탈퇴할 때 남은 것을 지운다. 다른 계정으로 로그인했을 때
  /// 앞사람의 인증이 나가면 안 된다.
  static Future<void> clear() => _save(const []);
}
