@Tags(['live'])
// 체크리스트 27번 — 실서버가 필요한 테스트. `flutter test`(CI 포함)는 dart_test.yaml
// 설정에 따라 이 태그를 건너뛴다. 서버를 띄워 놓고 직접 돌릴 때는:
//
//   npm run dev                                     # 다른 터미널에서 5001에 서버
//   flutter test --run-skipped test/auth_flow_live_test.dart
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/data/auth_repository.dart';
import 'package:local_quest/data/terms.dart';
import 'package:local_quest/models/api_exception.dart';
import 'package:local_quest/models/auth_models.dart';
import 'package:local_quest/services/api_client.dart';
import 'package:local_quest/services/token_store.dart';

/// 살아 있는 백엔드를 상대로 인증 코어를 검증한다.
///
/// 실행 전제: `npm run dev` 로 서버가 5001에 떠 있고 DB가 붙어 있을 것.
/// 서버가 없으면 테스트를 건너뛴다(실패시키지 않는다).
///
///   flutter test test/auth_flow_live_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test는 기본으로 모든 요청에 400을 돌려주는 HttpOverrides를 걸어 둔다.
  // 실제 서버와 이야기해야 하므로 해제한다. (이걸 빼먹으면 테스트가 조용히 다 통과한다)
  HttpOverrides.global = null;

  // flutter_secure_storage는 플랫폼 채널을 타므로 테스트에서는 메모리 맵으로 대체한다.
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

  /// 매 실행마다 새 계정을 쓴다. 그래야 재실행해도 결과가 같다.
  final stamp = DateTime.now().millisecondsSinceEpoch.toString();
  final uid = 'test_$stamp';
  final nickname = 't$stamp'.substring(0, 10);

  Future<bool> backendIsUp() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final base = Uri.parse(ApiClient.baseUrl);
      final req = await client.getUrl(Uri.parse('${base.scheme}://${base.host}:${base.port}/'));
      final res = await req.close();
      await res.drain<void>();
      client.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  late bool up;
  setUpAll(() async {
    up = await backendIsUp();
  });

  /// 백엔드가 없으면 **조용히 통과시키지 않는다**.
  /// 침묵이 성공처럼 보이면 회귀를 놓친다.
  void requireBackend() {
    if (!up) {
      fail('백엔드(${ApiClient.baseUrl})가 응답하지 않는다. '
          '`npm run dev`로 서버를 먼저 띄울 것.');
    }
  }

  setUp(() async {
    fakeSecureStore.clear();
    await TokenStore.clear();
  });

  test('미가입 계정 로그인은 LoginNeedsSignup을 준다 (HTTP 400이지만 실패가 아니다)', () async {
    requireBackend();
    final outcome = await AuthRepository.login(SocialCredential.guest(uid));

    expect(outcome, isA<LoginNeedsSignup>());
    final pending = (outcome as LoginNeedsSignup).pending;
    expect(pending.provider, 'GUEST');
    expect(pending.providerUid, uid);
  });

  test('닉네임 중복확인은 한글도 정상 처리된다', () async {
    requireBackend();
    expect(await AuthRepository.isNicknameAvailable('아무도안쓰는이름'), isTrue);
  });

  test('가입 → 토큰 저장 → me() → 재로그인 성공', () async {
    requireBackend();

    // 1. 가입
    final session = await AuthRepository.signup(SignupRequest(
      pending: PendingSignup(provider: 'GUEST', providerUid: uid),
      nickname: nickname,
      avatarId: 'avatar_03',
      homeRegion: '경기',
      activityLevel: '보통',
      keywords: const ['골목산책', '전통시장', '사진스팟'],
      termsVersion: kTermsVersion,
    ));
    expect(session.user.nickname, nickname);
    expect(session.user.avatarId, 'avatar_03');
    expect(session.user.homeRegion, '경기');
    expect(session.user.serverId, isNotNull);

    // 토큰이 실제로 보관됐는지
    expect(TokenStore.hasSession, isTrue);
    expect(TokenStore.accessToken, isNotEmpty);

    // 2. Bearer가 자동으로 붙는지
    final me = await AuthRepository.me();
    expect(me.nickname, nickname);
    expect(me.travelStyles, containsAll(['골목산책', '전통시장', '사진스팟']));

    // 3. 이제는 가입된 계정이므로 로그인이 바로 성공해야 한다
    await TokenStore.clear();
    final outcome = await AuthRepository.login(SocialCredential.guest(uid));
    expect(outcome, isA<LoginSuccess>());
  });

  test('access token이 망가져도 refresh로 자동 복구된다', () async {
    requireBackend();

    await AuthRepository.signup(SignupRequest(
      pending: PendingSignup(provider: 'GUEST', providerUid: '${uid}_r'),
      nickname: 'r$stamp'.substring(0, 10),
      keywords: const ['골목산책', '전통시장', '사진스팟'],
      termsVersion: kTermsVersion,
    ));

    TokenStore.debugCorruptAccessToken();
    final me = await AuthRepository.me(); // 401 → refresh → 재시도
    expect(me.serverId, isNotNull);
    expect(TokenStore.accessToken, isNot('corrupted.for.testing'));
  });

  test('refresh까지 무효하면 세션을 비우고 onAuthExpired를 부른다', () async {
    requireBackend();

    var expiredCalls = 0;
    ApiClient.onAuthExpired = () => expiredCalls++;
    addTearDown(() => ApiClient.onAuthExpired = null);

    await TokenStore.save(access: 'bad.access', refresh: 'bad.refresh');
    await expectLater(AuthRepository.me(), throwsA(isA<ApiException>()));

    expect(expiredCalls, 1);
    expect(TokenStore.hasSession, isFalse);
  });

  test('중복 닉네임 가입은 DUPLICATE_NICKNAME으로 걸린다', () async {
    requireBackend();

    try {
      await AuthRepository.signup(SignupRequest(
        pending: PendingSignup(provider: 'GUEST', providerUid: '${uid}_dup'),
        nickname: nickname, // 위에서 이미 쓴 이름
        keywords: const ['골목산책', '전통시장', '사진스팟'],
        termsVersion: kTermsVersion,
      ));
      fail('중복 닉네임인데 가입이 통과했다');
    } on ApiException catch (e) {
      expect(e.isDuplicateNickname, isTrue,
          reason: '실제로 온 코드: ${e.code} (HTTP ${e.statusCode})');
    }
  });
}