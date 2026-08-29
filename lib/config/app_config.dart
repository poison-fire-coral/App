import 'package:flutter/foundation.dart';

/// 빌드할 때 밖에서 주입하는 값들.
///
/// **왜 상수를 소스에 두지 않는가**
/// 카카오 앱 키가 `main.dart`에 리터럴로 박혀 있으면 저장소를 공개하는 순간
/// 그대로 새어 나간다. 키 자체가 도메인·패키지명으로 묶여 있어 즉시 악용되진
/// 않지만, 남의 앱이 우리 쿼터를 태울 수는 있다. 제출 전 체크리스트 02·03번.
///
/// **어떻게 넘기는가**
/// ```
/// flutter run \
///   --dart-define=KAKAO_NATIVE_APP_KEY=... \
///   --dart-define=KAKAO_JS_KEY=... \
///   --dart-define=API_BASE_URL=http://localhost:5001/api/v1 \
///   --dart-define=DEV_TOOLS=true
/// ```
/// `.vscode/launch.json`의 실행 구성이 이미 이 값들을 넣어 준다.
/// CI·스토어 빌드에서는 시크릿에서 꺼내 같은 플래그로 넘긴다.
///
/// **여기 없는 것**
/// iOS `Runner/Info.plist`의 `kakao{네이티브키}` URL 스킴은 네이티브 빌드
/// 설정이라 `--dart-define`이 닿지 않는다. xcconfig 변수로 빼는 건 별도 작업이다.
class AppConfig {
  const AppConfig._();

  // ---------------------------------------------------------------------------
  // 카카오
  // ---------------------------------------------------------------------------

  /// 카카오 로그인 SDK 네이티브 앱 키.
  static const String kakaoNativeAppKey =
      String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

  /// 카카오 지도 SDK JavaScript 키.
  static const String kakaoJavaScriptKey =
      String.fromEnvironment('KAKAO_JS_KEY');

  // ---------------------------------------------------------------------------
  // 개발자 도구
  // ---------------------------------------------------------------------------

  /// `lib/dev/`를 화면에 노출할지.
  ///
  /// **컴파일 타임 상수여야 한다.** 런타임 스위치(`DevTools.enabled`)만으로는
  /// 개발용 코드가 릴리스 번들에 그대로 남는다. 이 값이 `false`로 고정되면
  /// AOT 컴파일러가 `if (kDevToolsEnabled) { ... }` 블록을 통째로 지우고,
  /// 그 안에서만 부르던 `DevTools`·`DevQuestPanel`도 함께 트리쉐이킹된다.
  ///
  /// 기본값을 [kDebugMode]로 둔 이유: 디버그 빌드는 플래그 없이도 개발 계정
  /// 버튼이 나와야 하고, `flutter build apk --release`는 아무것도 안 넘겨도
  /// 자동으로 꺼져야 한다. 릴리스에서 굳이 켜려면 `DEV_TOOLS=true`를 준다.
  static const bool devToolsEnabled =
      bool.fromEnvironment('DEV_TOOLS', defaultValue: kDebugMode);

  // ---------------------------------------------------------------------------
  // 진단
  // ---------------------------------------------------------------------------

  /// 빠진 필수 키 이름들. 비어 있지 않으면 그 기능이 동작하지 않는다.
  ///
  /// 앱을 죽이지는 않는다 — 지도만 못 쓰고 나머지는 돌아가는 편이,
  /// 키 하나 때문에 아무것도 못 켜는 것보다 낫다. 대신 로그로 크게 알린다.
  static List<String> get missingKeys => [
        if (kakaoNativeAppKey.isEmpty) 'KAKAO_NATIVE_APP_KEY',
        if (kakaoJavaScriptKey.isEmpty) 'KAKAO_JS_KEY',
      ];

  /// 시작할 때 한 번 부른다.
  static void warnIfIncomplete() {
    final missing = missingKeys;
    if (missing.isEmpty) return;

    debugPrint(
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
      '  빌드에 키가 빠졌습니다: ${missing.join(', ')}\n'
      '  카카오 로그인·지도가 동작하지 않습니다.\n'
      '  --dart-define=<이름>=<값> 으로 넘기거나\n'
      '  VS Code의 "Flutter (실기기 / API_BASE_URL 주입)" 구성을 쓰세요.\n'
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
    );
  }
}
