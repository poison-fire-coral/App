@Tags(['live'])
// 체크리스트 27번 — 실서버가 필요한 테스트. `flutter test`(CI 포함)는 dart_test.yaml
// 설정에 따라 이 태그를 건너뛴다. 서버를 띄워 놓고 직접 돌릴 때는:
//
//   npm run dev                                   # 다른 터미널에서 5001에 서버
//   flutter test --run-skipped test/quest_cycle_live_test.dart
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:local_quest/data/auth_repository.dart';
import 'package:local_quest/data/terms.dart';
import 'package:local_quest/data/quest_repository.dart';
import 'package:local_quest/models/api_exception.dart';
import 'package:local_quest/models/auth_models.dart';
import 'package:local_quest/models/quest_model.dart';
import 'package:local_quest/services/api_client.dart';
import 'package:local_quest/services/exp_service.dart';
import 'package:local_quest/services/token_store.dart';

/// S3 퀘스트 사이클을 **살아 있는 백엔드**를 상대로 끝까지 돈다.
///
///   수락 → 도달 인증 → EXP 확정 → 레벨 반영
///
/// 실행 전제: `npm run db:seed && npm run dev`, PostgreSQL 기동.
/// UI를 탭하기 전에 API 계약이 맞는지 여기서 먼저 확인한다.
///
///   flutter test test/quest_cycle_live_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test는 모든 요청에 400을 돌려주는 HttpOverrides를 기본으로 건다.
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
          '`npm run dev`로 서버를 먼저 띄울 것.');
    }
  }

  /// 시드 퀘스트가 깔린 수원화성 일대.
  const seedLat = 37.2882;
  const seedLng = 127.0163;

  /// 매 테스트마다 새 계정을 만들어 EXP 상한·재수행 배율이 얽히지 않게 한다.
  Future<void> signUpFresh(String tag) async {
    await TokenStore.clear();
    await AuthRepository.signup(SignupRequest(
      pending: PendingSignup(provider: 'GUEST', providerUid: '${tag}_$stamp'),
      nickname: '$tag$stamp'.substring(0, 10),
      keywords: const ['골목산책', '전통시장', '사진스팟'],
      termsVersion: kTermsVersion,
    ));
  }

  Future<QuestModel> firstNearbyQuest() async {
    final quests = await QuestRepository.fetchNearbyQuests(
      lat: seedLat,
      lng: seedLng,
      radiusM: 3000,
    );
    expect(quests, isNotEmpty,
        reason: '시드 퀘스트가 안 보인다. `npm run db:seed`를 먼저 돌릴 것.');

    // 목업이 아니라 서버 퀘스트여야 accept/verify가 된다(Quest.id는 Int).
    final remote = quests.firstWhere(
      (q) => int.tryParse(q.id) != null,
      orElse: () => throw StateError('서버 퀘스트가 없다 — 목업 폴백이 떴다'),
    );
    return remote;
  }

  // ---------------------------------------------------------------------------

  test('주변 퀘스트를 서버에서 받아온다', () async {
    requireBackend();
    await signUpFresh('n');

    final quest = await firstNearbyQuest();
    expect(int.tryParse(quest.id), isNotNull);
    expect(quest.title, isNotEmpty);
    expect(quest.latitude, closeTo(seedLat, 0.2));
    expect(quest.validRadiusMeters, greaterThan(0));
  });

  test('수락 → 인증 → EXP 확정까지 한 사이클이 돈다', () async {
    requireBackend();
    await signUpFresh('c');

    final quest = await firstNearbyQuest();
    final before = await AuthRepository.me();

    // 1. 수락
    await QuestRepository.acceptQuest(quest.id);

    // 2. 도달 인증 — 퀘스트 좌표를 그대로 보낸다(개발자 모드 순간이동과 같은 경로).
    final requestId = const Uuid().v4();
    final result = await QuestRepository.verifyQuest(
      questId: quest.id,
      requestId: requestId,
      lat: quest.latitude,
      lng: quest.longitude,
      accuracyM: 8,
    );

    // 3. 서버가 확정한 값이 앱 모델로 그대로 옮겨지는지
    expect(result['expAwarded'], isA<int>());
    final awarded = result['expAwarded'] as int;
    expect(awarded, greaterThan(0), reason: '어뷰징 판정에 걸렸을 수 있다');

    final breakdown = ExpBreakdown.fromServer(
      Map<String, dynamic>.from(result['breakdown'] as Map),
      isAbused: result['isAbused'] == true,
    );
    expect(breakdown.finalExp, awarded,
        reason: '앱이 표시할 EXP와 서버가 지급한 EXP가 달라선 안 된다');
    expect(breakdown.baseExp, quest.difficulty.baseExp);

    final levelInfo = Map<String, dynamic>.from(result['levelInfo'] as Map);
    final level = LevelUpResult.fromServer(
      levelInfo,
      previousLevel: before.level,
      gainedExp: awarded,
    );
    expect(level.level, greaterThanOrEqualTo(before.level));

    // 4. 서버가 실제로 사용자를 갱신했는지
    final after = await AuthRepository.me();
    expect(after.level, level.level);
    expect(after.exp, level.exp,
        reason: '홈 상단 레벨 링이 서버와 어긋나면 안 된다');
  });

  test('같은 requestId를 두 번 보내도 EXP가 두 번 들어가지 않는다', () async {
    requireBackend();
    await signUpFresh('i');

    final quest = await firstNearbyQuest();
    await QuestRepository.acceptQuest(quest.id);

    final requestId = const Uuid().v4();
    final first = await QuestRepository.verifyQuest(
      questId: quest.id,
      requestId: requestId,
      lat: quest.latitude,
      lng: quest.longitude,
      accuracyM: 8,
    );
    final afterFirst = await AuthRepository.me();

    // 네트워크 타임아웃 후 재시도를 흉내낸다 — 같은 UUID를 그대로 보낸다.
    final second = await QuestRepository.verifyQuest(
      questId: quest.id,
      requestId: requestId,
      lat: quest.latitude,
      lng: quest.longitude,
      accuracyM: 8,
    );
    final afterSecond = await AuthRepository.me();

    expect(second['isAlreadyProcessed'], isTrue,
        reason: '멱등 응답이 아니면 EXP가 두 번 들어간다');
    expect(afterSecond.exp, afterFirst.exp);
    expect(afterSecond.level, afterFirst.level);
    expect(first['expAwarded'], isNotNull);
  });

  test('반경 밖에서 인증하면 OUT_OF_RANGE로 막힌다', () async {
    requireBackend();
    await signUpFresh('o');

    final quest = await firstNearbyQuest();
    await QuestRepository.acceptQuest(quest.id);

    // 위도 1도 ≈ 111,320m. 반경보다 훨씬 밖으로 밀어낸다.
    final farLat = quest.latitude + (500 / 111320.0);

    try {
      await QuestRepository.verifyQuest(
        questId: quest.id,
        requestId: const Uuid().v4(),
        lat: farLat,
        lng: quest.longitude,
        accuracyM: 8,
      );
      fail('반경 밖인데 인증이 통과했다');
    } on ApiException catch (e) {
      expect(e.isOutOfRange, isTrue,
          reason: '실제로 온 코드: ${e.code} (HTTP ${e.statusCode})');
    }
  });

  test('GPS 정확도가 낮으면 ACCURACY_TOO_LOW로 막힌다', () async {
    requireBackend();
    await signUpFresh('a');

    final quest = await firstNearbyQuest();
    await QuestRepository.acceptQuest(quest.id);

    try {
      await QuestRepository.verifyQuest(
        questId: quest.id,
        requestId: const Uuid().v4(),
        lat: quest.latitude,
        lng: quest.longitude,
        accuracyM: 150, // 서버 상한 100m 초과
      );
      fail('정확도가 낮은데 인증이 통과했다');
    } on ApiException catch (e) {
      expect(e.isAccuracyTooLow, isTrue,
          reason: '실제로 온 코드: ${e.code} (HTTP ${e.statusCode})');
    }
  });

  test('이미 수락한 퀘스트를 다시 수락해도 오류가 아니다', () async {
    requireBackend();
    await signUpFresh('d');

    final quest = await firstNearbyQuest();
    await QuestRepository.acceptQuest(quest.id);

    // 409는 "이어서 하기"이므로 리포지토리가 삼켜야 한다.
    await QuestRepository.acceptQuest(quest.id);
  });

  test('완료한 퀘스트는 다시 수락할 수도, 다시 클리어할 수도 없다', () async {
    requireBackend();
    await signUpFresh('r');

    final quest = await firstNearbyQuest();
    await QuestRepository.acceptQuest(quest.id);

    final first = await QuestRepository.verifyQuest(
      questId: quest.id,
      requestId: const Uuid().v4(),
      lat: quest.latitude,
      lng: quest.longitude,
      accuracyM: 8,
    );
    expect(first['expAwarded'], greaterThan(0));
    final afterClear = await AuthRepository.me();

    // 1. 재수락. "이어서 하기"(QUEST_ALREADY_ACCEPTED)로 삼켜지면 안 된다.
    try {
      await QuestRepository.acceptQuest(quest.id);
      fail('완료한 퀘스트가 다시 수락됐다');
    } on ApiException catch (e) {
      expect(e.isAlreadyCompleted, isTrue,
          reason: '실제로 온 코드: ${e.code} (HTTP ${e.statusCode})');
    }

    // 2. 새 requestId로 재인증 — 멱등 경로를 우회한 재클리어 시도다.
    try {
      await QuestRepository.verifyQuest(
        questId: quest.id,
        requestId: const Uuid().v4(),
        lat: quest.latitude,
        lng: quest.longitude,
        accuracyM: 8,
      );
      fail('완료한 퀘스트가 다시 클리어됐다');
    } on ApiException catch (e) {
      expect(e.isAlreadyCompleted, isTrue,
          reason: '실제로 온 코드: ${e.code} (HTTP ${e.statusCode})');
    }

    // 3. EXP는 1도 늘지 않는다. 예전엔 여기서 ×0.3 재수행 보상이 들어갔다.
    final afterRetry = await AuthRepository.me();
    expect(afterRetry.exp, afterClear.exp);
    expect(afterRetry.level, afterClear.level);
  });

  test('수락을 취소하면 서버 기록도 지워진다', () async {
    requireBackend();
    await signUpFresh('b');

    final quest = await firstNearbyQuest();
    await QuestRepository.acceptQuest(quest.id);

    final mine = await QuestRepository.fetchMyQuests();
    expect(mine.any((q) => '${q['questId']}' == quest.id), isTrue);

    await QuestRepository.abandonQuest(quest.id);

    final after = await QuestRepository.fetchMyQuests();
    expect(after.any((q) => '${q['questId']}' == quest.id), isFalse);
  });
}
