import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

import '../models/auth_models.dart';

/// 소셜 SDK에서 **access token**을 받아오는 일만 한다.
/// 우리 서버와의 대화는 [AuthRepository]가 맡는다.
///
/// 왜 access token인가: 서버(`auth.service.ts:210`)가 받은 토큰을 그대로
/// `oauth2/v3/userinfo`에 `Bearer`로 붙여 검증한다. idToken을 보내면 실패한다.
/// (`social.util.ts`에 idToken 버전이 있긴 하나 아무 데서도 import되지 않는다)
class AuthService {
  const AuthService._();

  /// 사용자가 취소하면 null. 진짜 오류는 [SocialAuthException].
  static Future<SocialCredential?> signInWithKakao() async {
    try {
      kakao.OAuthToken token;

      if (await kakao.isKakaoTalkInstalled()) {
        try {
          token = await kakao.UserApi.instance.loginWithKakaoTalk();
        } on PlatformException catch (e) {
          // 사용자가 카카오톡 화면에서 직접 취소한 경우엔 계정 로그인으로 넘어가지 않는다.
          if (e.code == 'CANCELED') return null;
          token = await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await kakao.UserApi.instance.loginWithKakaoAccount();
      }

      return SocialCredential.kakao(token.accessToken);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      throw SocialAuthException('카카오 로그인에 실패했어요.', e);
    } catch (e) {
      debugPrint('카카오 로그인 실패: $e');
      throw SocialAuthException('카카오 로그인에 실패했어요.', e);
    }
  }

  static Future<SocialCredential?> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();

      // 이전 세션이 남아 있으면 계정 선택 화면이 안 뜬다. 매번 고르게 한다.
      await googleSignIn.signOut();

      final account = await googleSignIn.signIn();
      if (account == null) return null; // 사용자가 취소

      final auth = await account.authentication;
      final accessToken = auth.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw SocialAuthException('구글 토큰을 받지 못했어요.', null);
      }
      return SocialCredential.google(accessToken);
    } on SocialAuthException {
      rethrow;
    } catch (e) {
      debugPrint('구글 로그인 실패: $e');
      throw SocialAuthException('구글 로그인에 실패했어요.', e);
    }
  }

  /// 카카오 세션까지 정리한다. 서버 토큰은 [TokenStore]가 따로 지운다.
  static Future<void> signOutSocial() async {
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {
      // 로그인한 적이 없으면 예외가 난다. 무시해도 된다.
    }
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // 위와 같음
    }
  }
}

class SocialAuthException implements Exception {
  final String message;
  final Object? cause;
  const SocialAuthException(this.message, this.cause);

  @override
  String toString() => 'SocialAuthException: $message';
}
