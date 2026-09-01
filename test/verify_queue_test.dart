import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_quest/services/verify_queue.dart';

/// 체크리스트 29번 — 오프라인 재시도 큐.
///
/// 여기서는 **쌓고 읽는 부분만** 본다. [VerifyQueue.flush]는 실서버로 나가므로
/// live 태그가 붙은 쪽 몫이다. 큐가 잃어버리지 않는지, 같은 인증을 두 줄로
/// 만들지 않는지가 이 파일이 지키는 것이다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PendingVerification item(String requestId, {DateTime? at}) =>
      PendingVerification(
        requestId: requestId,
        questId: '42',
        lat: 37.2882,
        lng: 127.0163,
        accuracyM: 12.5,
        queuedAt: at ?? DateTime.now(),
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('빈 큐는 빈 목록이다', () async {
    expect(await VerifyQueue.load(), isEmpty);
    expect(await VerifyQueue.pendingCount(), 0);
  });

  test('쌓은 순서대로 나온다', () async {
    await VerifyQueue.enqueue(item('a'));
    await VerifyQueue.enqueue(item('b'));

    final loaded = await VerifyQueue.load();
    expect(loaded.map((e) => e.requestId), ['a', 'b']);
  });

  test('모든 필드가 왕복해도 그대로다', () async {
    final at = DateTime(2026, 9, 1, 14, 30);
    await VerifyQueue.enqueue(PendingVerification(
      requestId: 'r1',
      questId: '77',
      lat: 37.5,
      lng: 127.5,
      accuracyM: 8.25,
      isMocked: true,
      photoUrl: 'https://example.com/a.jpg',
      photoVisibility: 'PRIVATE',
      userText: '노을이 좋았다',
      emotionTag: 'CALM',
      queuedAt: at,
    ));

    final back = (await VerifyQueue.load()).single;
    expect(back.questId, '77');
    expect(back.accuracyM, 8.25);
    expect(back.isMocked, isTrue);
    expect(back.photoUrl, 'https://example.com/a.jpg');
    expect(back.photoVisibility, 'PRIVATE');
    expect(back.userText, '노을이 좋았다');
    expect(back.emotionTag, 'CALM');
    expect(back.queuedAt, at);
  });

  test('같은 requestId를 다시 쌓으면 덮어쓴다 — 두 줄이 되지 않는다', () async {
    // 서버가 requestId로 멱등을 보장하므로 두 줄이어도 EXP는 한 번이지만,
    // 큐가 스스로 중복을 만들면 maxItems 자리를 헛되이 먹는다.
    await VerifyQueue.enqueue(item('same'));
    await VerifyQueue.enqueue(item('same'));

    expect(await VerifyQueue.pendingCount(), 1);
  });

  test('maxItems를 넘기면 오래된 앞쪽부터 버린다', () async {
    for (var i = 0; i < VerifyQueue.maxItems + 3; i++) {
      await VerifyQueue.enqueue(item('r$i'));
    }

    final loaded = await VerifyQueue.load();
    expect(loaded.length, VerifyQueue.maxItems);
    // 가장 오래된 r0·r1·r2가 밀려 나가고 마지막 것은 남아 있어야 한다.
    expect(loaded.first.requestId, 'r3');
    expect(loaded.last.requestId, 'r${VerifyQueue.maxItems + 2}');
  });

  test('clear는 통째로 비운다', () async {
    await VerifyQueue.enqueue(item('a'));
    await VerifyQueue.clear();

    expect(await VerifyQueue.load(), isEmpty);
  });

  test('못 읽는 줄이 섞여 있어도 나머지는 살아남는다', () async {
    // 저장 형식이 바뀌었을 때 한 줄 때문에 큐 전체를 잃으면 안 된다.
    SharedPreferences.setMockInitialValues({
      'pending_verifications': jsonEncode([
        {'requestId': 'ok', 'questId': '1', 'lat': 37.0, 'lng': 127.0},
        {'questId': '2', 'lat': 37.0, 'lng': 127.0}, // requestId 없음
        {'requestId': 'lat없음', 'questId': '3'},
        'string이 들어옴',
      ]),
    });

    final loaded = await VerifyQueue.load();
    expect(loaded.map((e) => e.requestId), ['ok']);
  });

  test('저장된 값이 깨져 있으면 빈 목록으로 시작한다', () async {
    SharedPreferences.setMockInitialValues({
      'pending_verifications': '{이건 JSON이 아니다',
    });

    expect(await VerifyQueue.load(), isEmpty);
  });
}
