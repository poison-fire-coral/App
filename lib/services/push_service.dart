import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_repository.dart';
import '../models/api_exception.dart';

/// 푸시 알림 — 체크리스트 24번.
///
/// **앱이 하는 일은 세 가지뿐이다.** 권한을 받고, FCM 토큰을 얻고, 그 토큰을
/// 서버에 등록한다. 언제 무엇을 보낼지는 전부 서버가 정한다
/// (`src/jobs/nearbyQuestPush.job.ts`).
///
/// **토큰은 한 번 받고 마는 값이 아니다.** 앱을 지웠다 깔거나, 데이터를
/// 지우거나, FCM 이 자체 판단으로 갱신하면 바뀐다. 그래서 로그인할 때마다
/// 다시 등록하고 [FirebaseMessaging.onTokenRefresh] 도 구독한다.
///
/// **실패해도 앱을 막지 않는다.** 알림은 부가 기능이다. 권한을 거절당하거나
/// 네트워크가 없어 등록에 실패해도 나머지는 그대로 돌아가야 한다.
class PushService {
  const PushService._();

  /// 사용자가 설정에서 켜 둔 값. OS 권한과는 **다른 것**이다.
  ///
  /// OS 권한은 한 번 거절하면 앱에서 다시 물을 수 없고 설정 앱으로 보내야
  /// 한다. 그래서 우리 스위치를 따로 두고, 켤 때만 권한을 요청한다.
  static const String _prefsKey = 'push_enabled';

  /// 마지막으로 서버에 등록한 토큰. 로그아웃할 때 무엇을 뺄지 알아야 한다.
  static String? _registeredToken;

  static bool _listening = false;

  // ---------------------------------------------------------------------------
  // 설정값
  // ---------------------------------------------------------------------------

  /// 설정 화면의 스위치 상태. 기본값은 켬 — 온보딩에서 알림을 안내하고
  /// 시작하므로, 아무것도 안 건드린 사용자는 받기를 기대한다.
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _saveEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('알림 설정을 저장하지 못했다: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 등록
  // ---------------------------------------------------------------------------

  /// 로그인 직후에 부른다.
  ///
  /// 스위치가 꺼져 있으면 권한도 토큰도 건드리지 않는다 — 끈 사람에게
  /// 권한 팝업을 띄우는 건 그 자체로 배신이다.
  static Future<void> registerIfEnabled() async {
    if (!await isEnabled()) return;
    await _register(askPermission: false);
  }

  /// 설정 스위치를 켜고 끌 때 부른다. 실제로 켜졌는지 돌려준다.
  ///
  /// **켜기를 눌렀는데 false 가 돌아올 수 있다.** OS 권한을 거절한 경우다.
  /// 부르는 쪽이 그때 "설정에서 알림을 허용해 주세요"로 안내한다.
  static Future<bool> setEnabled(bool enabled) async {
    if (!enabled) {
      await _saveEnabled(false);
      await _unregister();
      return false;
    }

    final ok = await _register(askPermission: true);
    await _saveEnabled(ok);
    return ok;
  }

  static Future<bool> _register({required bool askPermission}) async {
    try {
      final messaging = FirebaseMessaging.instance;

      // iOS·안드로이드 13+ 는 권한이 필요하다. 이미 정해진 상태라면
      // requestPermission 은 팝업 없이 그 상태를 돌려준다.
      final settings = askPermission
          ? await messaging.requestPermission()
          : await messaging.getNotificationSettings();

      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!granted) return false;

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return false;

      await AuthRepository.registerPushDevice(
        fcmToken: token,
        platform: _platformName,
      );
      _registeredToken = token;

      _listenForRefresh();
      return true;
    } on ApiException catch (e) {
      // 서버에 못 닿았다. 다음 로그인 때 다시 시도한다.
      debugPrint('푸시 토큰 등록 실패: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('푸시 초기화 실패: $e');
      return false;
    }
  }

  /// FCM 이 토큰을 갈아 끼우면 서버에도 새 값을 알린다.
  ///
  /// 이걸 빼먹으면 어느 날 조용히 알림이 끊기고, 사용자는 "알림이 안 와요"
  /// 라고만 말할 수 있다 — 가장 찾기 어려운 종류의 고장이다.
  static void _listenForRefresh() {
    if (_listening) return;
    _listening = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      try {
        await AuthRepository.registerPushDevice(
          fcmToken: token,
          platform: _platformName,
        );
        _registeredToken = token;
      } catch (e) {
        debugPrint('갱신된 푸시 토큰 등록 실패: $e');
      }
    });
  }

  /// 로그아웃·탈퇴할 때 부른다.
  ///
  /// 안 부르면 로그아웃한 기기로 이전 계정의 알림이 계속 간다.
  static Future<void> unregisterOnLogout() => _unregister();

  static Future<void> _unregister() async {
    final token = _registeredToken ?? await _currentToken();
    if (token == null) return;

    try {
      await AuthRepository.unregisterPushDevice(fcmToken: token);
    } catch (e) {
      // 서버에 못 닿아도 로그아웃 자체를 막지 않는다. 다음에 이 토큰이
      // 다른 계정으로 등록되면 upsert 가 소유자를 옮겨 준다.
      debugPrint('푸시 토큰 해제 실패: $e');
    }
    _registeredToken = null;
  }

  static Future<String?> _currentToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  static String get _platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
