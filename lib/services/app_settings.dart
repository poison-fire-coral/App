import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 설정 화면(5d)의 켜고 끄는 값들.
///
/// **왜 따로 두는가.** 예전에는 이 값들이 `SettingsScreen`의 지역 `setState`에만
/// 있었다. 화면을 닫으면 사라지고, 값을 읽어야 하는 지도·인증 화면에는 닿지도
/// 않았다. 스위치는 움직이는데 아무 일도 일어나지 않는 상태였고, 그중
/// "사진 기본 공개"는 개인정보에 관한 약속이라 없는 것보다 나빴다.
///
/// 알림 스위치는 OS 권한과 서버 등록이 얽혀 있어 [PushService]가 따로 들고 있다.
/// 여기 있는 것은 앱 안에서만 쓰는 값들이다.
class AppSettings {
  const AppSettings._();

  static const String _dataSaverKey = 'data_saver_enabled';
  static const String _photoPublicKey = 'photo_public_default';

  /// 지도 갱신을 아낄지. 기본은 끔 — 지도가 굼떠 보이는 것이 기본값이면 안 된다.
  static bool dataSaver = false;

  /// 인증 사진의 기본 공개 여부. 인증 화면은 이 값으로 시작하고,
  /// 사용자는 매번 그 자리에서 바꿀 수 있다.
  ///
  /// 기본을 공개로 두는 이유는 이 앱의 사진이 "내가 거기 갔다"는 기록이고
  /// 서로 보는 것이 본래 쓰임이기 때문이다. 다만 **되돌릴 수 있어야** 한다 —
  /// 그래서 설정에서 기본값을 바꾸면 다음 인증부터 곧바로 반영된다.
  static bool photoPublicByDefault = true;

  /// 앱이 시작할 때 한 번. 이후로는 메모리 값을 본다 —
  /// 지도 카메라가 멈출 때마다 디스크를 읽을 수는 없다.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      dataSaver = prefs.getBool(_dataSaverKey) ?? false;
      photoPublicByDefault = prefs.getBool(_photoPublicKey) ?? true;
    } catch (e) {
      // 저장소를 못 읽어도 기본값으로 그냥 돈다.
      debugPrint('설정을 불러오지 못했다: $e');
    }
  }

  static Future<void> setDataSaver(bool value) async {
    dataSaver = value;
    await _write(_dataSaverKey, value);
  }

  static Future<void> setPhotoPublicByDefault(bool value) async {
    photoPublicByDefault = value;
    await _write(_photoPublicKey, value);
  }

  static Future<void> _write(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      // 메모리 값은 이미 바뀌었으니 이번 실행 동안은 동작한다.
      debugPrint('설정을 저장하지 못했다($key): $e');
    }
  }

  /// 로그아웃·탈퇴에서 부른다. 다음 사용자가 앞사람의 설정을 물려받으면 안 된다.
  static Future<void> clear() async {
    dataSaver = false;
    photoPublicByDefault = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_dataSaverKey);
      await prefs.remove(_photoPublicKey);
    } catch (e) {
      debugPrint('설정을 지우지 못했다: $e');
    }
  }
}
