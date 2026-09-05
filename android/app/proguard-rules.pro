# R8 유지 규칙.
#
# **왜 필요한가.** 릴리스에서 코드 축소를 켜면 "어디서도 참조되지 않는" 클래스가
# 지워진다. 리플렉션이나 네이티브에서만 불리는 것은 R8 이 참조를 볼 수 없어
# 지워지고, 그 사실은 **런타임에야** 드러난다 — 디버그 빌드는 멀쩡하고
# 릴리스에서만 죽는 종류의 문제라 가장 늦게 발견된다.
#
# 대부분의 플러그인은 자기 규칙(consumer rules)을 들고 오므로 여기는 최소한만 적는다.

# ── Flutter 엔진 ────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── 카카오 SDK ──────────────────────────────────────────────────────────────
# 로그인 응답을 리플렉션으로 역직렬화한다. 모델이 지워지면 로그인 직후 죽는다.
-keep class com.kakao.sdk.**.model.* { <fields>; }
-keep class * extends com.google.gson.TypeAdapter
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations

# ── Firebase / FCM ──────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# ── 예외 메시지 ─────────────────────────────────────────────────────────────
# 스택트레이스에 줄 번호가 남아야 크래시 보고를 읽을 수 있다.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
