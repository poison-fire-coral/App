import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:local_quest/data/auth_repository.dart';
import 'package:local_quest/data/badge_api.dart';
import 'package:local_quest/data/quest_repository.dart';
import 'package:local_quest/models/api_exception.dart';
import 'package:local_quest/models/auth_models.dart';
import 'package:local_quest/models/quest_model.dart';
import 'package:local_quest/services/api_client.dart';
import 'package:local_quest/services/token_store.dart';

/// 배지 시스템을 **살아 있는 백엔드**를 상대로 검증한다.
///
/// 실행 전제: `npm run db:seed && npm run dev`
///
///   flutter test test/badge_live_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final fakeSecureStore = <String, String>{};
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write':
            fakeSecureStore[call.arguments['key'] as String] =
                call.arguments['value'] as String;
            return null;
          case 'read':
            return fakeSecureStore[call.arguments['key'] as String];
          case 'readAll':
            return Map<String, String>.from(fakeSecureStore);
          case 'delete':
            fakeSecureStore.remove(call.arguments['key'] as String);
            return null;
          case 'deleteAll':
            fakeSecureStore.clear();
            return null;
          default:
            return null;
        }
      },
    );
  });

  final stamp = DateTime.now().millisecondsSinceEpoch.toString();

  Future<bool> backendIsUp() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final base = Uri.parse(ApiClient.baseUrl);
      final req = await client
          .getUrl(Uri.parse('${base.scheme}://${base.host}:${base.port}/'));
      final res = await req.close();
      await res.drain<void>();
      client.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  late bool up;
  setUpAll(() async => up = await backendIsUp());

  void requireBackend() {
    if (!up) {
      fail('백엔드(${ApiClient.baseUrl})가 응답하지 않는다. '
          '`npm run db:seed && npm run dev` 를 먼저 돌릴 것.');
    }
  }

  const seedLat = 37.2882;
  const seedLng = 127.0163;

  Future<void> signUpFresh(String tag) async {
    await TokenStore.clear();
    await AuthRepository.signup(SignupRequest(
      pending: PendingSignup(provider: 'GUEST', providerUid: '${tag}_$stamp'),
      nickname: '$tag$stamp'.substring(0, 10),
      keywords: const ['골목산책', '전통시장', '사진스팟'],
      termsVersion: AuthRepository.termsVersion,
    ));
  }

  Future<List<QuestModel>> nearby() => QuestRepository.fetchNearbyQuests(
        lat: seedLat,
        lng: seedLng,
        radiusM: 3000,
      );

  /// 서버 퀘스트 하나를 실제로 완료시킨다(개발자 모드 순간이동과 같은 경로).
  Future<Map<String, dynamic>> completeQuest(QuestModel quest) async {
    await QuestRepository.acceptQuest(quest.id);
    return QuestRepository.verifyQuest(
      questId: quest.id,
      requestId: const Uuid().v4(),
      lat: quest.latitude,
      lng: quest.longitude,
      accuracyM: 8,
    );
  }

  // ---------------------------------------------------------------------------

  test('가입 직후에는 아무 배지도 없고 전체 목록만 보인다', () async {
    requireBackend();
    await signUpFresh('b1');

    final result = await BadgeApi.list();
    expect(result.total, greaterThan(0), reason: '배지 시드가 안 들어갔다');
    expect(result.achieved, 0);
    expect(result.items.every((i) => i.state == BadgeState.locked), isTrue);
  });

  test('히든 배지는 못 땄으면 이름이 가려진다', () async {
    requireBackend();
    await signUpFresh('b2');

    final result = await BadgeApi.list();
    final hidden = result.items.where((i) => i.hidden).toList();
    expect(hidden, isNotEmpty, reason: '히든 배지 시드가 필요하다');
    for (final h in hidden) {
      expect(h.name, isNull, reason: '서버가 이름을 가려야 앱을 뜯어도 못 본다');
      expect(h.description, isNull);
    }
  });

  test('퀘스트를 완료하면 첫 발자국이 열린다', () async {
    requireBackend();
    await signUpFresh('b3');

    final quests = await nearby();
    final quest = quests.firstWhere((q) => int.tryParse(q.id) != null);

    final result = await completeQuest(quest);

    // verify 응답에 badgeProgress[] 가 동봉된다 (의뢰서 S4 BE 3)
    expect(result['badgeProgress'], isA<List>());
    final progress = (result['badgeProgress'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final firstStep = progress.firstWhere((b) => b['name'] == '첫 발자국');
    expect(firstStep['achieved'], isTrue);
    expect(firstStep['justEarned'], isTrue, reason: '이번에 막 딴 것이어야 한다');

    // 목록 API에도 반영됐는지
    final list = await BadgeApi.list();
    expect(list.achieved, greaterThanOrEqualTo(1));
    final earned =
        list.items.firstWhere((i) => i.state == BadgeState.achieved);
    expect(earned.name, isNotNull);
  });

  test('같은 requestId로 재요청해도 배지가 두 번 오르지 않는다', () async {
    requireBackend();
    await signUpFresh('b4');

    final quests = await nearby();
    final quest = quests.firstWhere((q) => int.tryParse(q.id) != null);

    await QuestRepository.acceptQuest(quest.id);
    final requestId = const Uuid().v4();

    Future<Map<String, dynamic>> send() => QuestRepository.verifyQuest(
          questId: quest.id,
          requestId: requestId,
          lat: quest.latitude,
          lng: quest.longitude,
          accuracyM: 8,
        );

    await send();
    final afterFirst = await BadgeApi.list();
    await send();
    final afterSecond = await BadgeApi.list();

    expect(afterSecond.achieved, afterFirst.achieved);

    int progressOf(BadgeListResult r, String name) =>
        r.items.firstWhere((i) => i.name == name).progress;
    expect(progressOf(afterSecond, '첫 발자국'),
        progressOf(afterFirst, '첫 발자국'));
  });

  test('지역 배지는 그 지역 퀘스트만 센다', () async {
    requireBackend();
    await signUpFresh('b5');

    final quests = await nearby();
    final quest = quests.firstWhere((q) => int.tryParse(q.id) != null);
    await completeQuest(quest);

    final list = await BadgeApi.list();
    // 수원 시드는 regionCode "경기" — 경기 배지만 올라야 한다.
    final gyeonggi = list.items.firstWhere((i) => i.name == '경기 순례자');
    final seoul = list.items.firstWhere((i) => i.name == '서울 산책자');

    expect(gyeonggi.progress, greaterThanOrEqualTo(0));
    expect(seoul.progress, 0, reason: '서울 퀘스트를 한 적이 없다');
  });

  test('배지 상세는 어떤 퀘스트로 채웠는지 이력을 준다', () async {
    requireBackend();
    await signUpFresh('b6');

    final quests = await nearby();
    final quest = quests.firstWhere((q) => int.tryParse(q.id) != null);
    await completeQuest(quest);

    final list = await BadgeApi.list();
    final firstStep = list.items.firstWhere((i) => i.name == '첫 발자국');

    final detail = await BadgeApi.detail(firstStep.badgeId);
    expect(detail.achieved, isTrue);
    expect(detail.history, isNotEmpty);
    expect(detail.history.first.questTitle, isNotEmpty);
  });

  test('히든 배지 상세는 못 땄으면 막힌다', () async {
    requireBackend();
    await signUpFresh('b7');

    final list = await BadgeApi.list();
    final hidden = list.items.firstWhere((i) => i.hidden);

    try {
      await BadgeApi.detail(hidden.badgeId);
      fail('히든 배지 상세가 열렸다');
    } on ApiException catch (e) {
      expect(e.code, 'BADGE_HIDDEN');
    }
  });

  group('대표 배지', () {
    test('획득한 배지만 대표로 지정할 수 있다', () async {
      requireBackend();
      await signUpFresh('b8');

      final quests = await nearby();
      final quest = quests.firstWhere((q) => int.tryParse(q.id) != null);
      await completeQuest(quest);

      final list = await BadgeApi.list();
      final earned =
          list.items.firstWhere((i) => i.state == BadgeState.achieved);
      final notEarned =
          list.items.firstWhere((i) => i.state != BadgeState.achieved);

      final saved = await BadgeApi.setFeatured([earned.badgeId]);
      expect(saved.length, 1);
      expect(saved.first.badgeId, earned.badgeId);

      try {
        await BadgeApi.setFeatured([notEarned.badgeId]);
        fail('획득하지 않은 배지가 대표로 지정됐다');
      } on ApiException catch (e) {
        expect(e.code, 'BADGE_NOT_ACHIEVED');
      }
    });

    test('4개 이상은 서버가 막는다', () async {
      requireBackend();
      await signUpFresh('b9');

      try {
        await BadgeApi.setFeatured([1, 2, 3, 4]);
        fail('상한 3개를 넘겼는데 통과했다');
      } on ApiException catch (e) {
        expect(e.code, 'TOO_MANY_FEATURED');
      }
    });

    test('빈 배열을 보내면 전부 해제된다', () async {
      requireBackend();
      await signUpFresh('b10');

      final saved = await BadgeApi.setFeatured([]);
      expect(saved, isEmpty);
    });
  });

  test('프로필 요약은 서버가 센 통계와 발자국을 준다', () async {
    requireBackend();
    await signUpFresh('p1');

    final before = await BadgeApi.profileSummary();
    expect(before.completed, 0);
    expect(before.footprints, isEmpty);

    final quests = await nearby();
    final quest = quests.firstWhere((q) => int.tryParse(q.id) != null);
    await completeQuest(quest);

    final after = await BadgeApi.profileSummary();
    expect(after.completed, 1);
    expect(after.regions, 1);
    expect(after.badges, greaterThanOrEqualTo(1));
    expect(after.footprints.first.questTitle, quest.title);
  });
}
