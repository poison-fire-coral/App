import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/geo.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// DEV-ONLY — 개발용 도구 모음
///
/// **제출 전 제거 절차**
///   1. `lib/dev/` 디렉터리를 통째로 삭제한다.
///   2. `grep -rn "DEV-ONLY" lib/` 로 호출부를 찾아 그 블록만 지운다.
///   3. `flutter analyze` 로 남은 import를 정리한다.
///
/// 그래서 이 파일 밖으로 새는 코드를 최소화했고, 호출부마다 `// DEV-ONLY` 태그를 단다.
/// ─────────────────────────────────────────────────────────────────────────────
class DevTools {
  const DevTools._();

  static const String _prefsKey = 'dev_mode_enabled';

  /// 설정 화면에서 켜고 끈다. 꺼져 있으면 개발용 UI가 아예 나타나지 않는다.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// 고정 개발 계정.
  ///
  /// **`providerUid`를 반드시 보내야 한다.** 서버(`auth.service.ts:45-47`)는 이 값이
  /// 없으면 `guest_${Date.now()}_랜덤`을 만들어버려서, 매번 새 계정이 생기고
  /// 온보딩이 무한 반복된다.
  static const String guestUid = 'dev_local_001';

  /// 내 위치를 여기로 고정한다. 시드 퀘스트가 수원 일대에 있어서,
  /// 집에서 켜면 주변 퀘스트가 0건으로 나온다.
  static const GeoPoint suwonHwaseong = GeoPoint(37.2882, 127.0163);

  /// null이 아니면 위치를 이 좌표로 위조한다.
  static GeoPoint? locationOverride;

  static bool get isLocationOverridden => locationOverride != null;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      enabled.value = false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    if (!value) locationOverride = null; // 끄면 위조도 같이 푼다
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // 저장 실패해도 이번 세션은 메모리 값으로 동작한다.
    }
  }

  static void toggleLocationOverride() {
    locationOverride = locationOverride == null ? suwonHwaseong : null;
  }
}
