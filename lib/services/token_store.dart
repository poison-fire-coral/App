import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT 보관소.
///
/// 의뢰서 S1 FE 7이 "토큰 secure storage 저장"을 명시한다.
/// refresh token은 14일짜리라 안드로이드 평문 XML(shared_preferences)에 두면 안 된다.
/// 프로필 캐시·진행중 퀘스트 같은 비민감 데이터는 계속 shared_preferences를 쓴다.
///
/// 매 요청마다 보안저장소를 await 하면 느리므로 메모리에 캐시하고,
/// 쓰기만 저장소로 흘려보낸다.
class TokenStore {
  const TokenStore._();

  /// 안드로이드 기본값이 이미 AES-GCM 저장 + RSA-OAEP 키 래핑이고,
  /// resetOnError가 켜져 있어 키스토어가 깨져도 앱이 죽지 않는다.
  static const _storage = FlutterSecureStorage();

  static const _kAccess = 'lq_access_token';
  static const _kRefresh = 'lq_refresh_token';

  static String? _access;
  static String? _refresh;
  static bool _loaded = false;

  static String? get accessToken => _access;
  static String? get refreshToken => _refresh;

  /// refresh token이 있으면 "로그인된 세션이 있다"고 본다.
  /// access token은 1시간짜리라 만료됐어도 갱신하면 되기 때문이다.
  static bool get hasSession => _refresh != null && _refresh!.isNotEmpty;

  /// 앱 시작 시 한 번. 두 번째 호출부터는 즉시 반환한다.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final all = await _storage.readAll();
      _access = all[_kAccess];
      _refresh = all[_kRefresh];
    } catch (_) {
      // 키스토어가 깨졌거나(기기 복원 등) 접근 불가. 로그아웃 상태로 시작한다.
      _access = null;
      _refresh = null;
    }
    _loaded = true;
  }

  static Future<void> save({
    required String access,
    required String refresh,
  }) async {
    _access = access;
    _refresh = refresh;
    _loaded = true;
    try {
      await _storage.write(key: _kAccess, value: access);
      await _storage.write(key: _kRefresh, value: refresh);
    } catch (_) {
      // 저장에 실패해도 이번 세션은 메모리 값으로 계속 굴러간다.
    }
  }

  static Future<void> clear() async {
    _access = null;
    _refresh = null;
    _loaded = true;
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
    } catch (_) {
      // 무시
    }
  }

  /// 개발자 모드에서 refresh 인터셉터를 시험하려고 access token만 망가뜨린다.
  static void debugCorruptAccessToken() {
    _access = 'corrupted.for.testing';
  }
}
