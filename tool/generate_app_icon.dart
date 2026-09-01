import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/theme/app_colors.dart';

/// 앱 아이콘·스플래시 원본 생성기 — 체크리스트 33번.
///
///   flutter test tool/generate_app_icon.dart
///
/// `assets/brand/logo.svg` 하나에서 세 장을 굽는다.
///
///   assets/brand/app_icon.png             1024  런처 아이콘 원본
///                                               (flutter_launcher_icons 입력)
///   assets/brand/app_icon_foreground.png  1024  적응형 아이콘 앞면(배경 투명).
///                                               안전 여백은 여기서 주지 않는다 —
///                                               ic_launcher.xml의 inset 16%가 넣는다.
///   android/.../drawable/splash_logo.png   288  런치 스크린 가운데 그림
///
/// **왜 도구인가 (28번과 같은 이유).** `tool/`에 있고 이름에 `_test`가 없어
/// `flutter test` 자동 수집에서 빠진다. 로고가 바뀔 때만 손으로 돌린다.
///
/// **왜 `flutter test`로 부르나.** `flutter_svg`로 SVG를 래스터화하려면
/// Flutter 바인딩과 에셋 번들이 필요하고, 그걸 가장 간단히 주는 게 이 명령이다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 로고를 [size]×[size] 캔버스 한가운데에 [inset] 비율만큼 여백을 두고 그린다.
  ///
  /// [background]가 null이면 배경을 칠하지 않는다(투명) — 적응형 아이콘의
  /// 앞면은 런처가 뒤에 자기 배경을 깔기 때문에 투명이어야 한다.
  Future<void> bake({
    required String outPath,
    required int size,
    required double inset,
    Color? background,
  }) async {
    final raw = await rootBundle.loadString('assets/brand/logo.svg');
    final picture = await vg.loadPicture(SvgStringLoader(raw), null);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final canvasSize = size.toDouble();

    if (background != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, canvasSize, canvasSize),
        Paint()..color = background,
      );
    }

    // logo.svg의 viewBox는 120×120이다. 그 좌표계를 요청한 크기로 늘린 뒤
    // 여백만큼 안으로 밀어 넣는다.
    final drawn = canvasSize * (1 - inset * 2);
    final scale = drawn / 120.0;

    canvas.save();
    canvas.translate(canvasSize * inset, canvasSize * inset);
    canvas.scale(scale);
    canvas.drawPicture(picture.picture);
    canvas.restore();

    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(bytes, isNotNull, reason: '$outPath PNG 인코딩 실패');

    final file = File(outPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());

    picture.picture.dispose();
    image.dispose();

    // ignore: avoid_print
    print('$outPath (${size}px)');
  }

  test('런처 아이콘 원본을 굽는다', () async {
    // 여백 0 — logo.svg가 이미 자기 안에 둥근 사각 판을 그리고 있어서
    // 여기서 또 줄이면 아이콘 안에 액자가 두 겹으로 생긴다.
    await bake(
      outPath: 'assets/brand/app_icon.png',
      size: 1024,
      inset: 0,
      background: AppColors.ink50,
    );
  });

  test('적응형 아이콘 앞면을 굽는다', () async {
    // **여백을 여기서 주지 않는다.** 적응형 아이콘은 108dp 중 가운데 72dp만
    // 늘 보이고 바깥 1/6씩은 런처 모양대로 잘리는데, 그 안전 여백은
    // flutter_launcher_icons가 만드는 mipmap-anydpi-v26/ic_launcher.xml이
    // `android:inset="16%"`로 이미 넣는다. 여기서 또 비우면 여백이 두 겹이 되어
    // 인장이 아이콘 한가운데 조그맣게 박힌다.
    //
    // 배경은 런처가 `@color/ic_launcher_background`로 깔기 때문에 투명이다.
    await bake(
      outPath: 'assets/brand/app_icon_foreground.png',
      size: 1024,
      inset: 0,
      background: null,
    );
  });

  test('런치 스크린 로고를 굽는다', () async {
    // 배경은 launch_background.xml이 칠하므로 여기서는 투명하게 둔다.
    // 라이트/다크에서 같은 그림을 쓰되 배경색만 갈린다.
    await bake(
      outPath: 'android/app/src/main/res/drawable/splash_logo.png',
      size: 288,
      inset: 0,
      background: null,
    );
  });
}
