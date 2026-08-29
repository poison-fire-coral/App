import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_exception.dart';
import 'token_store.dart';

/// 백엔드와 이야기하는 유일한 통로.
///
/// `QuestRepository`가 이미 static + `http` 스타일이라 dio 인터셉터를 새로 들이면
/// 패턴이 둘로 갈린다. 그래서 `http`를 감싼 static 함수 하나로 통일한다.
///
/// 하는 일 세 가지:
///  1. `{ data, error }` 봉투를 풀어 `data`만 돌려준다. `error`가 있으면 [ApiException].
///  2. 모든 요청에 `Authorization: Bearer` 주입.
///  3. 인증 만료를 만나면 refresh 후 **한 번만** 재시도. 동시 요청이 여러 개여도
///     갱신은 한 번만 나간다(단일비행).
class ApiClient {
  const ApiClient._();

  /// 요청 하나가 이 시간을 넘기면 네트워크 실패로 본다.
  /// `/quests/nearby`는 카카오 API를 4번 때리고 오므로 넉넉히 준다.
  static const Duration timeout = Duration(seconds: 20);

  /// 세션이 완전히 끊겼을 때(refresh까지 실패) 호출된다. main.dart가 로그아웃에 물린다.
  static void Function()? onAuthExpired;

  // ---------------------------------------------------------------------------
  // Base URL
  //   실행 시 --dart-define=API_BASE_URL=... 로 덮어쓸 수 있다.
  // ---------------------------------------------------------------------------
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    return 'https://chewing-asleep-vest.ngrok-free.dev/api/v1';
  }

  // ---------------------------------------------------------------------------
  // 공개 API
  // ---------------------------------------------------------------------------
  static Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) =>
      _send('GET', path, query: query, auth: auth);

  static Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) =>
      _send('POST', path, body: body, query: query, auth: auth);

  static Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  static Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  static Future<dynamic> delete(String path, {Object? body}) =>
      _send('DELETE', path, body: body);

  // ---------------------------------------------------------------------------
  // 내부
  // ---------------------------------------------------------------------------
  static Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) async {
    var res = await _raw(method, path, body: body, query: query, auth: auth);

    // 인증이 필요한 요청이 만료로 튕겼다면 한 번만 갱신하고 재시도한다.
    if (auth && _looksUnauthorized(res) && TokenStore.hasSession) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        res = await _raw(method, path, body: body, query: query, auth: auth);
      } else {
        await TokenStore.clear();
        onAuthExpired?.call();
      }
    }

    return _unwrap(res);
  }

  static Future<http.Response> _raw(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) async {
    final uri = _buildUri(path, query);
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'ngrok-skip-browser-warning': 'true', // ngrok 경고 화면 우회 헤더
      'bypass-tunnel-reminder': 'true', // localtunnel 경고 화면 우회 헤더
    };
    final token = TokenStore.accessToken;
    if (auth && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final encoded = body == null ? null : json.encode(body);

    try {
      switch (method) {
        case 'GET':
          return await http.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          return await http
              .post(uri, headers: headers, body: encoded)
              .timeout(timeout);
        case 'PATCH':
          return await http
              .patch(uri, headers: headers, body: encoded)
              .timeout(timeout);
        case 'PUT':
          return await http
              .put(uri, headers: headers, body: encoded)
              .timeout(timeout);
        case 'DELETE':
          return await http
              .delete(uri, headers: headers, body: encoded)
              .timeout(timeout);
        default:
          throw ArgumentError('지원하지 않는 메서드: $method');
      }
    } catch (e) {
      throw ApiException.fromNetworkFailure(e);
    }
  }

  static Uri _buildUri(String path, Map<String, dynamic>? query) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalized');
    if (query == null || query.isEmpty) return uri;

    // null 값은 아예 빼고, 나머지는 문자열로 눌러 담는다.
    final params = <String, String>{};
    query.forEach((k, v) {
      if (v == null) return;
      if (v is Iterable) {
        if (v.isEmpty) return;
        params[k] = v.join(',');
      } else {
        params[k] = '$v';
      }
    });
    return uri.replace(queryParameters: params.isEmpty ? null : params);
  }

  /// 인증 만료 판정.
  ///
  /// 상태 코드만 보면 안 된다 — 이 백엔드는 `UNAUTHORIZED`를 400으로도 내보낸다
  /// (`src/utils/CustomError.ts`의 문자열 분기가 statusCode를 안 건드림).
  static bool _looksUnauthorized(http.Response res) {
    if (res.statusCode == 401) return true;
    return _errorCodeOf(res) == 'UNAUTHORIZED';
  }

  static String? _errorCodeOf(http.Response res) {
    try {
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      if (decoded is Map && decoded['error'] is Map) {
        return decoded['error']['code'] as String?;
      }
    } catch (_) {
      // 본문이 JSON이 아니면 판정 불가
    }
    return null;
  }

  // ---- 리프레시 단일비행 -----------------------------------------------------
  // 홈에 들어가면 nearby · my · me 가 동시에 나가서 401이 세 개 터진다.
  // 갱신을 세 번 하면 refresh token 회전(rotation) 때문에 서로를 무효화시킨다.
  static Future<bool>? _refreshing;

  static Future<bool> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  static Future<bool> _doRefresh() async {
    final refresh = TokenStore.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _raw(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refresh},
        auth: false,
      );
      final data = _unwrap(res);
      if (data is Map &&
          data['accessToken'] is String &&
          data['refreshToken'] is String) {
        await TokenStore.save(
          access: data['accessToken'] as String,
          refresh: data['refreshToken'] as String,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// `{ data, error }` 봉투를 푼다.
  ///
  /// 주의: `quest.controller.ts`의 인라인 가드들은 `data` 키 없이 `{error:{...}}`만
  /// 내려보낸다. 그래서 `error`를 **먼저** 보고, 그 다음에 `data`를 꺼낸다.
  static dynamic _unwrap(http.Response res) {
    final raw = utf8.decode(res.bodyBytes);
    dynamic decoded;
    if (raw.isNotEmpty) {
      try {
        decoded = json.decode(raw);
      } catch (_) {
        throw ApiException(
          code: ApiException.malformed,
          message: 'JSON이 아닌 응답을 받았어요.',
          statusCode: res.statusCode,
        );
      }
    }

    if (decoded is Map) {
      final err = decoded['error'];
      if (err is Map) {
        throw ApiException(
          code: (err['code'] as String?) ?? 'UNKNOWN',
          message: (err['message'] as String?) ?? '',
          details: err['details'] is Map
              ? Map<String, dynamic>.from(err['details'] as Map)
              : null,
          statusCode: res.statusCode,
        );
      }
      if (decoded.containsKey('data')) return decoded['data'];
    }

    // 봉투가 없는 응답(예: health check)은 상태 코드로만 판단한다.
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    throw ApiException(
      code: 'HTTP_${res.statusCode}',
      message: raw.isEmpty ? '요청이 실패했어요.' : raw,
      statusCode: res.statusCode,
    );
  }
}