import 'user_model.dart';

/// 소셜 로그인 SDK에서 막 받아온 자격증명. 아직 우리 서버는 모르는 상태다.
class SocialCredential {
  /// 서버가 아는 값: 'KAKAO' | 'GOOGLE' | 'GUEST'
  final String provider;

  /// 카카오·구글 **access token**.
  ///
  /// idToken이 아니다 — 서버(`auth.service.ts:210`)가 이걸 그대로
  /// `oauth2/v3/userinfo`에 `Bearer`로 붙여 검증한다.
  final String? token;

  /// GUEST 로그인 전용. 서버는 이 값이 없으면 매번 새 uid를 만들어버려서
  /// 개발용 계정이 계속 갈린다(`auth.service.ts:45-47`).
  final String? providerUid;

  const SocialCredential({
    required this.provider,
    this.token,
    this.providerUid,
  });

  const SocialCredential.kakao(String accessToken)
      : provider = 'KAKAO',
        token = accessToken,
        providerUid = null;

  const SocialCredential.google(String accessToken)
      : provider = 'GOOGLE',
        token = accessToken,
        providerUid = null;

  /// 개발용 고정 계정. 카카오 리다이렉트 스킴이 매니페스트에 없어서
  /// 실기기 카카오 로그인이 아직 콜백을 못 받는 동안 쓴다.
  const SocialCredential.guest(String uid)
      : provider = 'GUEST',
        token = null,
        providerUid = uid;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        if (token != null) 'token': token,
        if (providerUid != null) 'providerUid': providerUid,
      };
}

/// 로그인은 됐는데 우리 DB에 계정이 없을 때 서버가 `error.details`로 돌려주는 것.
/// 온보딩을 거쳐 `/auth/signup`으로 되돌려 보내야 한다.
class PendingSignup {
  final String provider;
  final String providerUid;
  final String? email;

  const PendingSignup({
    required this.provider,
    required this.providerUid,
    this.email,
  });

  static PendingSignup? fromDetails(Map<String, dynamic>? details) {
    if (details == null) return null;
    final provider = details['provider'] as String?;
    final uid = details['providerUid'] as String?;
    if (provider == null || uid == null) return null;
    return PendingSignup(
      provider: provider,
      providerUid: uid,
      email: details['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'providerUid': providerUid,
        'email': email,
      };

  factory PendingSignup.fromJson(Map<String, dynamic> json) => PendingSignup(
        provider: json['provider'] as String,
        providerUid: json['providerUid'] as String,
        email: json['email'] as String?,
      );
}

/// 온보딩이 다 채워지면 서버로 보내는 가입 요청.
class SignupRequest {
  final PendingSignup pending;
  final String nickname;
  final String? avatarId;
  final String? homeRegion;
  final String? activityLevel;
  final List<String> keywords;
  final bool termsAgreed;
  final String termsVersion;

  const SignupRequest({
    required this.pending,
    required this.nickname,
    required this.keywords,
    required this.termsVersion,
    this.avatarId,
    this.homeRegion,
    this.activityLevel,
    this.termsAgreed = true,
  });

  Map<String, dynamic> toJson() => {
        'provider': pending.provider,
        'providerUid': pending.providerUid,
        if (pending.email != null) 'email': pending.email,
        'nickname': nickname,
        if (avatarId != null) 'avatarId': avatarId,
        if (homeRegion != null) 'homeRegion': homeRegion,
        if (activityLevel != null) 'activityLevel': activityLevel,
        'keywords': keywords,
        'termsAgreed': termsAgreed,
        'termsVersion': termsVersion,
      };
}

/// 로그인·가입 성공 시 서버가 준 세션 한 벌.
class AuthSession {
  final String accessToken;
  final String refreshToken;
  final UserModel user;
  final bool isNewUser;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.isNewUser = false,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        user: UserModel.fromServer(
          Map<String, dynamic>.from(json['user'] as Map),
        ),
        isNewUser: json['isNewUser'] == true,
      );
}

/// `AuthRepository.login()`의 결과. 두 갈래로만 갈린다.
/// (진짜 실패는 [ApiException]으로 던진다 — 결과 타입으로 감싸지 않는다.)
sealed class LoginOutcome {
  const LoginOutcome();
}

class LoginSuccess extends LoginOutcome {
  final AuthSession session;
  const LoginSuccess(this.session);
}

/// 미가입. 온보딩으로 보내고, 끝나면 [PendingSignup]을 그대로 signup에 실어 보낸다.
class LoginNeedsSignup extends LoginOutcome {
  final PendingSignup pending;
  const LoginNeedsSignup(this.pending);
}
