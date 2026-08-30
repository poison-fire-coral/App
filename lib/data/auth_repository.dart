import '../models/api_exception.dart';
import '../models/auth_models.dart';
import '../models/user_model.dart';
import '../services/api_client.dart';
import '../services/token_store.dart';
import 'terms.dart';

/// 계정 관련 서버 호출. `QuestRepository`와 같은 static 유틸 스타일.
class AuthRepository {
  const AuthRepository._();

  /// 동의 화면 없이 가입하던 시절의 버전 문자열.
  ///
  /// 이제는 온보딩 1c가 실제 동의를 받고 [kTermsVersion]을 보낸다.
  /// 이 상수는 **읽기 전용**이다 — 서버에 이 값으로 남아 있는 사용자는
  /// 약관을 본 적이 없으므로, 문서가 확정되면 재동의 대상이다.
  static const String legacyImplicitTermsVersion = '2026-08-implicit-v1';

  /// 이 사용자에게 재동의를 받아야 하는지.
  ///
  /// 문서가 서고 [kTermsVersion]이 올라가면 여기가 자동으로 true가 된다.
  /// (재동의 화면 자체는 아직 없다 — 문서가 없으면 물어볼 내용도 없다)
  static bool needsReconsent(String? storedVersion) =>
      storedVersion == null || storedVersion != kTermsVersion;

  // ---------------------------------------------------------------------------
  // 로그인
  // ---------------------------------------------------------------------------

  /// 소셜 자격증명으로 로그인한다.
  ///
  /// 미가입이면 예외를 던지지 않고 [LoginNeedsSignup]을 돌려준다 — 그건 실패가
  /// 아니라 정상 분기다. 진짜 실패(네트워크·서버 오류)만 [ApiException]으로 던진다.
  static Future<LoginOutcome> login(SocialCredential credential) async {
    try {
      final data = await ApiClient.post(
        '/auth/login',
        body: credential.toJson(),
        auth: false,
      );
      final session = AuthSession.fromJson(Map<String, dynamic>.from(data));
      await TokenStore.save(
        access: session.accessToken,
        refresh: session.refreshToken,
      );
      return LoginSuccess(session);
    } on ApiException catch (e) {
      // 상태 코드가 아니라 코드 문자열로 분기한다. 이 백엔드는 이걸 400으로 보낸다.
      if (e.isNotRegistered) {
        final pending = PendingSignup.fromDetails(e.details);
        if (pending != null) return LoginNeedsSignup(pending);

        // details가 비어 오면 가입을 이어갈 수 없다. GUEST는 uid를 우리가 아니까 복구 가능.
        if (credential.providerUid != null) {
          return LoginNeedsSignup(PendingSignup(
            provider: credential.provider,
            providerUid: credential.providerUid!,
          ));
        }
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // 닉네임
  // ---------------------------------------------------------------------------

  /// 사용 가능하면 true. 인증이 필요 없어서 가입 전에도 부를 수 있다.
  static Future<bool> isNicknameAvailable(String nickname) async {
    final data = await ApiClient.get(
      '/auth/check-nickname',
      query: {'nickname': nickname},
      auth: false,
    );
    if (data is Map && data['isAvailable'] is bool) {
      return data['isAvailable'] as bool;
    }
    throw const ApiException(
      code: ApiException.malformed,
      message: '중복 확인 응답을 이해하지 못했어요.',
    );
  }

  // ---------------------------------------------------------------------------
  // 가입 · 프로필
  // ---------------------------------------------------------------------------

  /// 온보딩에서 모은 값으로 계정을 만든다. 성공하면 토큰까지 저장한다.
  static Future<AuthSession> signup(SignupRequest request) async {
    final data = await ApiClient.post(
      '/auth/signup',
      body: request.toJson(),
      auth: false,
    );
    final session = AuthSession.fromJson(Map<String, dynamic>.from(data));
    await TokenStore.save(
      access: session.accessToken,
      refresh: session.refreshToken,
    );
    return session;
  }

  /// 현재 로그인한 사용자. 스플래시에서 세션 복원에 쓴다.
  static Future<UserModel> me() async {
    final data = await ApiClient.get('/users/me');
    return UserModel.fromServer(Map<String, dynamic>.from(data));
  }

  /// 이미 가입한 사용자의 프로필 일부를 고친다(취향 재설정 경로).
  static Future<UserModel> updateProfile({
    String? nickname,
    String? avatarId,
    String? homeRegion,
    String? activityLevel,
    List<String>? keywords,
  }) async {
    final data = await ApiClient.patch('/users/me', body: {
      'nickname': ?nickname,
      'avatarId': ?avatarId,
      'homeRegion': ?homeRegion,
      'activityLevel': ?activityLevel,
      'keywords': ?keywords,
    });
    return UserModel.fromServer(Map<String, dynamic>.from(data));
  }

  /// 서버에는 로그아웃 엔드포인트가 없다. 토큰만 버리면 된다.
  static Future<void> logout() => TokenStore.clear();

  /// 회원 탈퇴: 서버 계정을 삭제하고 로컬 저장 토큰을 비운다.
  static Future<void> deleteAccount() async {
    await ApiClient.delete('/users/me');
    await TokenStore.clear();
  }
}