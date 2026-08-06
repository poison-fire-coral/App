import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  // ---------------------------------------------------------------------------
  // 1. 카카오 로그인
  // ---------------------------------------------------------------------------
  static Future<bool> signInWithKakao() async {
    try {
      // 카카오톡 앱 설치 여부 확인
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          await kakao.UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          // 카카오톡 로그인 취소/실패 시 카카오 계정으로 재시도
          if (error is PlatformException && error.code == 'CANCELED') return false;
          await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        // 앱 미설치 시 웹 브라우저 계정 로그인
        await kakao.UserApi.instance.loginWithKakaoAccount();
      }

      // 유저 정보 가져오기 (필요 시 활용)
      final user = await kakao.UserApi.instance.me();
      debugPrint('카카오 로그인 성공 유저 ID: ${user.id}');
      return true;
    } catch (e) {
      debugPrint('카카오 로그인 실패: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Google 로그인
  // ---------------------------------------------------------------------------
  static Future<bool> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return false; // 사용자가 취소함

      debugPrint('Google 로그인 성공: ${googleUser.email}');
      return true;
    } catch (e) {
      debugPrint('Google 로그인 실패: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Apple 로그인
  // ---------------------------------------------------------------------------
  static Future<bool> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      debugPrint('Apple 로그인 성공 ID: ${credential.userIdentifier}');
      return true;
    } catch (e) {
      debugPrint('Apple 로그인 실패: $e');
      return false;
    }
  }
}