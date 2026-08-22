import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/theme/app_colors.dart';

/// 지도 마커 PNG 생성기 — 4단계.
///
/// **왜 테스트 파일인가:** Flutter의 캔버스를 쓰려면 바인딩이 필요한데,
/// `flutter test`가 그걸 가장 간단히 제공한다. 런타임이 아니라 **빌드 전 한 번** 굽는다.
///
///   flutter test test/generate_marker_icons_test.dart
///
/// **왜 PNG인가:** `kakao_map_plugin`이 에셋 바이트를 base64로 감싼 뒤 WebView에서
/// `new Blob([...], { type: 'image/png' })`로 되살린다 — MIME이 PNG로 고정이라
/// SVG를 넣으면 그려지지 않는다.
///
/// **모양은 퀘스트 유형, 색은 난이도.** 7종 × 5색 = 35장을 손으로 그리면 관리가 안 되므로
/// 아이콘을 코드로 그리고 색을 입혀 합성한다.
void main() {
  // testWidgets는 페이크 비동기라 picture.toImage()가 영영 완료되지 않는다.
  // 실제 비동기가 필요하므로 일반 test()를 쓴다.
  TestWidgetsFlutterBinding.ensureInitialized();

  const outDir = 'assets/markers';

  /// 난이도 5단 — 디자인 시스템 08장 QuestTierStyle 그대로.
  const tiers = <String, Color>{
    't1': AppColors.ink500,
    't2': AppColors.jade500,
    't3': AppColors.lapis500,
    't4': AppColors.amber500,
    't5': AppColors.quest500,
  };

  /// 퀘스트 유형 7종. 각 값은 32×32 상자 안에 흰색으로 그리는 심볼이다.
  final symbols = <String, void Function(Canvas, Size, Paint)>{
    'VISIT': _drawFootprint,
    'TIME_WINDOW': _drawSunMoon,
    'PHOTO_SINGLE': _drawCamera,
    'PHOTO_COLLECT': _drawStack,
    'QUIZ': _drawQuestion,
    'EXPLORATION': _drawCompass,
    'RECORD': _drawPen,
  };

  setUpAll(() {
    Directory(outDir).createSync(recursive: true);
  });

  /// 마커 한 장을 굽는다.
  Future<void> bake({
    required String questType,
    required String tierKey,
    required Color tone,
    required double scale,
  }) async {
    // 논리 크기 36×46 (물방울 핀 + 접지 그림자 여백)
    const w = 36.0;
    const h = 46.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);

    // ── 접지 그림자 ──────────────────────────────────────────────────
    // 디자인 시스템 10장: 드롭 섀도우 + 접지 그림자가 **같이** 있어야
    // "지면에 꽂혀 있다"로 읽힌다. 지도 타일 위에서 플랫한 마커는 가장 먼저 묻힌다.
    // MaskFilter.blur는 래스터 스레드를 요구해 헤드리스 테스트에서 멈춘다.
    // 옅은 타원을 겹쳐 같은 인상을 만든다.
    for (final layer in const [
      [17.0, 8.0, 0.07],
      [14.0, 6.0, 0.11],
      [11.0, 4.5, 0.16],
    ]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(w / 2, h - 4),
          width: layer[0],
          height: layer[1],
        ),
        Paint()..color = AppColors.shadowBase.withValues(alpha: layer[2]),
      );
    }

    // ── 핀 몸통 (물방울) ─────────────────────────────────────────────
    final pin = _pinPath(w, h);

    canvas.save();
    canvas.translate(0, 1.2);
    canvas.drawPath(
      pin,
      Paint()..color = AppColors.shadowBase.withValues(alpha: 0.16),
    );
    canvas.restore();

    canvas.drawPath(
      pin,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(w / 2, 0),
          const Offset(w / 2, h - 6),
          [Color.lerp(tone, Colors.white, 0.22)!, tone],
        ),
    );

    // 위에서 오는 빛 — 윗변 하이라이트
    canvas.save();
    canvas.clipPath(pin);
    canvas.drawCircle(
      const Offset(w / 2, 14),
      13,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
    canvas.restore();

    // 흰 테두리 — 밝은 타일 위에서 핀이 사라지지 않게
    canvas.drawPath(
      pin,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // ── 유형 심볼 ────────────────────────────────────────────────────
    canvas.save();
    canvas.translate(w / 2 - 8, 14 - 8); // 16×16 상자의 좌상단
    symbols[questType]!(
      canvas,
      const Size(16, 16),
      Paint()..color = Colors.white,
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage((w * scale).round(), (h * scale).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(bytes, isNotNull, reason: '$questType/$tierKey PNG 인코딩 실패');

    final suffix = scale == 1.0 ? '' : '@${scale.toInt()}x';
    final file = File('$outDir/${questType.toLowerCase()}_$tierKey$suffix.png');
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  test('퀘스트 마커 PNG 35종 × 3배율을 굽는다', () async {
    var made = 0;
    for (final questType in symbols.keys) {
      for (final entry in tiers.entries) {
        // 고밀도 화면에서 뭉개지지 않게 @2x·@3x도 함께 굽는다.
        for (final scale in [1.0, 2.0, 3.0]) {
          await bake(
            questType: questType,
            tierKey: entry.key,
            tone: entry.value,
            scale: scale,
          );
          made++;
        }
      }
    }
    // ignore: avoid_print
    print('마커 $made장 생성 → $outDir');
    expect(made, symbols.length * tiers.length * 3);
  });

  test('현위치 마커를 굽는다 (크림슨)', () async {
    for (final scale in [1.0, 2.0, 3.0]) {
      const size = 28.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale);

      const c = Offset(size / 2, size / 2);

      // 정확도 원 — 붉은 기운이 옅게 퍼진다
      canvas.drawCircle(
        c,
        13,
        Paint()..color = AppColors.quest500.withValues(alpha: 0.14),
      );
      // 그림자
      for (final layer in const [
        [10.5, 0.10],
        [9.5, 0.16],
        [8.6, 0.24],
      ]) {
        canvas.drawCircle(
          c.translate(0, 1.2),
          layer[0],
          Paint()..color = AppColors.shadowWarm.withValues(alpha: layer[1]),
        );
      }
      // 흰 링 — 퀘스트 핀(물방울)과 **모양 자체가 다르다.**
      // 색만 다르면 색약 사용자가 구별하지 못한다.
      canvas.drawCircle(c, 8, Paint()..color = Colors.white);
      canvas.drawCircle(
        c,
        6,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(size / 2, 8),
            const Offset(size / 2, 20),
            [
              Color.lerp(AppColors.quest500, Colors.white, 0.2)!,
              AppColors.quest600,
            ],
          ),
      );

      final picture = recorder.endRecording();
      final image =
          await picture.toImage((size * scale).round(), (size * scale).round());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);

      final suffix = scale == 1.0 ? '' : '@${scale.toInt()}x';
      File('$outDir/my_location$suffix.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    // ignore: avoid_print
    print('현위치 마커 생성 → $outDir/my_location.png');
  });
}

/// 물방울 핀 윤곽.
Path _pinPath(double w, double h) {
  final path = Path();
  const r = 13.0;
  final cx = w / 2;
  const cy = 14.0;
  final tip = Offset(cx, h - 6);

  // 원에서 접선을 따라 뾰족한 끝으로 내려온다.
  final d = (tip - Offset(cx, cy)).distance;
  final theta = math.acos(r / d);
  final base = math.atan2(tip.dy - cy, tip.dx - cx);

  path.addArc(
    Rect.fromCircle(center: Offset(cx, cy), radius: r),
    base + theta,
    2 * math.pi - 2 * theta,
  );
  path.lineTo(tip.dx, tip.dy);
  path.close();
  return path;
}

// ── 유형별 심볼 (16×16 상자, 흰색) ───────────────────────────────────────

void _drawFootprint(Canvas c, Size s, Paint p) {
  // 타원 두 개면 지도에서 '사람 아이콘'으로 읽힌다 — 실기기에서 확인했다.
  // 발바닥 + 발가락 4개로 그려야 발자국으로 읽힌다.
  final sole = Path()
    ..moveTo(5.2, 6.2)
    ..cubicTo(3.2, 8.4, 3.4, 12.2, 5.8, 14.0)
    ..cubicTo(8.2, 15.6, 11.0, 14.2, 11.2, 11.2)
    ..cubicTo(11.4, 8.4, 9.2, 5.4, 5.2, 6.2)
    ..close();
  c.drawPath(sole, p);

  c.drawOval(Rect.fromLTWH(3.3, 3.0, 2.5, 3.0), p);
  c.drawOval(Rect.fromLTWH(6.1, 1.4, 2.4, 3.0), p);
  c.drawOval(Rect.fromLTWH(8.7, 1.8, 2.2, 2.8), p);
  c.drawOval(Rect.fromLTWH(10.9, 3.4, 2.0, 2.4), p);
}

void _drawSunMoon(Canvas c, Size s, Paint p) {
  c.drawArc(Rect.fromLTWH(2, 3, 12, 12), math.pi, math.pi, true, p);
  c.drawRect(Rect.fromLTWH(1, 10.5, 14, 1.8), p);
  c.drawCircle(const Offset(8, 6.5), 2.4, Paint()..color = Colors.white);
}

void _drawCamera(Canvas c, Size s, Paint p) {
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(1, 4, 14, 9), const Radius.circular(2)),
    p,
  );
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(5, 2, 6, 3), const Radius.circular(1.2)),
    p,
  );
  // 렌즈는 반투명으로 눌러 구멍처럼 보이게 한다.
  // BlendMode.clear는 레이어를 요구해 헤드리스 렌더링에서 비용이 크다.
  c.drawCircle(
    const Offset(8, 8.5),
    3,
    Paint()..color = Colors.white.withValues(alpha: 0.001),
  );
}

void _drawStack(Canvas c, Size s, Paint p) {
  final faded = Paint()..color = Colors.white.withValues(alpha: 0.55);
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(0.5, 2, 10, 8), const Radius.circular(1.6)),
    faded,
  );
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(3, 4.5, 10, 8), const Radius.circular(1.6)),
    Paint()..color = Colors.white.withValues(alpha: 0.78),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(5.5, 7, 10, 8), const Radius.circular(1.6)),
    p,
  );
}

void _drawQuestion(Canvas c, Size s, Paint p) {
  final path = Path()
    ..moveTo(4, 5.5)
    ..cubicTo(4, 2, 6.5, 0.5, 8.5, 0.5)
    ..cubicTo(11, 0.5, 12.8, 2.2, 12.8, 4.6)
    ..cubicTo(12.8, 7.6, 9.6, 8, 9.6, 11)
    ..lineTo(7, 11)
    ..cubicTo(7, 7, 10.2, 7.2, 10.2, 4.6)
    ..cubicTo(10.2, 3.4, 9.5, 2.8, 8.5, 2.8)
    ..cubicTo(7.4, 2.8, 6.6, 3.7, 6.6, 5.5)
    ..close();
  c.drawPath(path, p);
  c.drawCircle(const Offset(8.3, 14), 1.7, p);
}

void _drawCompass(Canvas c, Size s, Paint p) {
  c.drawCircle(
    const Offset(8, 8),
    7,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = Colors.white,
  );
  final needle = Path()
    ..moveTo(11, 5)
    ..lineTo(9, 9)
    ..lineTo(5, 11)
    ..lineTo(7, 7)
    ..close();
  c.drawPath(needle, p);
}

void _drawPen(Canvas c, Size s, Paint p) {
  final body = Path()
    ..moveTo(12, 0.5)
    ..lineTo(15.5, 4)
    ..lineTo(5.5, 14)
    ..lineTo(1, 15)
    ..lineTo(2, 10.5)
    ..close();
  c.drawPath(body, p);
}
