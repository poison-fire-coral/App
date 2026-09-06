import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/theme/app_colors.dart';

/// 지도 마커 PNG 생성기 — 4단계.
///
///   flutter test tool/generate_marker_icons.dart
///
/// **왜 test/ 밖에 있나 (체크리스트 28번):** `flutter test`를 인자 없이 부르면
/// `test/**_test.dart`만 모은다. 이 파일이 거기 있으면 전체 테스트를 돌릴 때마다
/// PNG 108장이 다시 구워져 CI가 느려지고 작업 트리가 매번 더러워졌다.
/// `tool/`로 나오고 이름에서 `_test`를 떼면 자동 수집에서 빠지고,
/// 위처럼 **경로를 직접 주면 그대로 실행된다.**
///
/// **왜 그래도 `flutter test`로 부르나:** Flutter 캔버스(`ui.PictureRecorder`)를
/// 쓰려면 바인딩이 필요한데 `flutter test`가 그걸 가장 간단히 제공한다.
/// 런타임이 아니라 **빌드 전 한 번** 굽는 도구다.
///
/// 결과물이 제대로 있는지는 `test/marker_assets_test.dart`가 지킨다 —
/// 그쪽은 굽지 않고 존재와 디코딩만 확인해서 늘 돌아도 싸다.
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
    // ★1은 원래 ink500(3차 텍스트 색)이었다. 지도 타일 위에서 너무 옅어 묻혔고,
    // 완료 퀘스트를 "흐리게" 칠하는 처리와도 겹쳐 둘을 구분할 수 없었다.
    // 같은 잉크 계열에서 두 단 내려 잡는다 — 색상은 그대로, 대비만 확보한다.
    't1': AppColors.ink700,
    't2': AppColors.jade500,
    't3': AppColors.lapis500,
    't4': AppColors.amber500,
    't5': AppColors.quest500,
  };

  /// 퀘스트 유형 7종.
  ///
  /// 각 심볼은 `(캔버스, 상자, 흰색 페인트, 핀 색)`을 받는다. **핀 색을 넘기는 게
  /// 핵심이다** — 흰 도형 위에 흰색을 덧칠해서는 구멍이 뚫리지 않는다. 예전
  /// 카메라 렌즈는 `alpha: 0.001` 흰색이라 아무 일도 하지 않았고, 그래서 카메라가
  /// 그냥 둥근 덩어리로 보였다. 구멍은 핀 색으로 그려야 파인 것처럼 읽힌다.
  final symbols =
      <String, void Function(Canvas, Size, Paint, Color)>{
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
      tone,
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

/// 01 방문형 — **걷는 사람**.
///
/// 예전에는 발자국이었다. 시트·목록의 유형 배지가 `Icons.directions_walk`(사람)라
/// 같은 퀘스트인데 지도에서는 발바닥, 창에서는 사람으로 보였다.
/// 두 곳이 다른 기호를 쓰면 "아까 그 유형"으로 이어지지 않으므로 창 쪽에 맞춘다.
void _drawFootprint(Canvas c, Size s, Paint p, Color tone) {
  final limb = Paint()
    ..color = p.color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 2.1;

  // 머리
  c.drawCircle(const Offset(9.4, 2.7), 2.1, p);

  // 몸통 — 살짝 앞으로 기운 자세
  c.drawLine(const Offset(9.0, 5.4), const Offset(7.7, 9.2), limb);

  // 앞다리 / 뒷다리
  c.drawLine(const Offset(7.7, 9.2), const Offset(10.2, 14.6), limb);
  c.drawLine(const Offset(7.7, 9.2), const Offset(4.6, 12.7), limb);
  c.drawLine(const Offset(4.6, 12.7), const Offset(4.2, 14.9), limb);

  // 앞팔 / 뒷팔
  c.drawLine(const Offset(8.7, 6.6), const Offset(11.8, 8.3), limb);
  c.drawLine(const Offset(8.7, 6.6), const Offset(5.2, 7.2), limb);
}

/// 05 시간대 제한형 — **시계**.
///
/// 예전에는 반원(해) + 가로 막대(지평선) + 흰 원(달)이었다. 흰 바탕에 흰 원이라
/// 달은 보이지 않았고, 남은 것은 "반원과 막대" 뿐이라 지도에서는 그냥 가로줄
/// 하나로 보였다. 시계는 작아져도 바늘 두 개의 각도로 즉시 읽힌다.
void _drawSunMoon(Canvas c, Size s, Paint p, Color tone) {
  c.drawCircle(const Offset(8, 8), 7, p);

  // 바늘은 핀 색으로 판다. 굵게 그려야 축소해도 남는다.
  final hand = Paint()
    ..color = tone
    ..strokeWidth = 1.9
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  c.drawLine(const Offset(8, 8), const Offset(8, 3.6), hand); // 긴바늘 12시
  c.drawLine(const Offset(8, 8), const Offset(11.4, 9.4), hand); // 짧은바늘 4시
  c.drawCircle(const Offset(8, 8), 0.9, Paint()..color = tone);
}

/// 06 피사체 지정형 — **카메라**.
///
/// 렌즈를 흰색 `alpha: 0.001`로 그려 두어 사실상 아무것도 하지 않았다.
/// 그래서 카메라가 둥근 덩어리로 보였고 08(수집)과 구분되지 않았다.
/// 렌즈를 핀 색으로 파면 한 눈에 카메라가 된다.
void _drawCamera(Canvas c, Size s, Paint p, Color tone) {
  c.drawRRect(
    RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.8, 4.2, 14.4, 9.6), const Radius.circular(2.2)),
    p,
  );
  c.drawRRect(
    RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 2.2, 6, 2.8), const Radius.circular(1.2)),
    p,
  );

  // 렌즈 — 핀 색으로 뚫고, 안쪽에 흰 점을 남겨 유리처럼 보이게 한다.
  c.drawCircle(const Offset(8, 9), 3.2, Paint()..color = tone);
  c.drawCircle(const Offset(8, 9), 1.3, p);
}

/// 08 수집 사진형 — **여러 장의 사진**.
///
/// 예전에는 반투명 사각형 세 장을 겹쳐 놓아 축소하면 한 덩어리로 뭉갰다.
/// 장과 장 사이를 핀 색으로 갈라 놓으면 작아져도 "여러 장"이 남는다.
void _drawStack(Canvas c, Size s, Paint p, Color tone) {
  // 뒤 두 장은 흰 판 → 핀 색 틈 → 흰 판 순서로 쌓아 경계를 만든다.
  void sheet(double x, double y, double w, double h) {
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 0.9, y - 0.9, w + 1.8, h + 1.8),
          const Radius.circular(2.0)),
      Paint()..color = tone,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h), const Radius.circular(1.6)),
      p,
    );
  }

  sheet(1.0, 1.6, 9.6, 7.4);
  sheet(5.4, 7.0, 9.6, 7.4);
}

void _drawQuestion(Canvas c, Size s, Paint p, Color tone) {
  // 물음표도 축소에 강해 그대로 둔다.
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

/// 10 탐색형 — **나침반 바늘**.
///
/// 예전에는 얇은 원 테두리(1.8px) 안에 작은 바늘이라, 축소하면 테두리만 남아
/// 그냥 동그라미로 보였다. 테두리를 버리고 바늘 자체를 크게 세운다.
/// 위쪽 절반만 흰색으로 남기면 "북쪽을 가리키는 바늘"로 읽힌다.
void _drawCompass(Canvas c, Size s, Paint p, Color tone) {
  const cx = 8.0;
  const cy = 8.0;

  // 바깥 원 — 꽉 찬 흰 판. 바늘을 핀 색으로 파낼 바탕이다.
  c.drawCircle(const Offset(cx, cy), 7, p);

  // 아래쪽 반쪽 바늘: 핀 색으로 파서 두 갈래처럼 보이게 한다.
  final south = Path()
    ..moveTo(cx, cy + 5.6)
    ..lineTo(cx - 3.0, cy - 0.6)
    ..lineTo(cx + 3.0, cy - 0.6)
    ..close();
  c.drawPath(south, Paint()..color = tone);

  // 위쪽 바늘 둘레를 핀 색으로 얇게 감싸 흰 판과 분리한다.
  final northOutline = Path()
    ..moveTo(cx, cy - 6.4)
    ..lineTo(cx - 3.6, cy + 1.0)
    ..lineTo(cx + 3.6, cy + 1.0)
    ..close();
  c.drawPath(
    northOutline,
    Paint()
      ..color = tone
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round,
  );
}

/// 13 기록형 — **펜과 밑줄**.
///
/// 예전에는 통짜 사선 하나라 10(탐색)의 바늘과 헷갈렸다. 촉을 핀 색으로 갈라
/// 펜대와 나누고, 아래에 밑줄을 그어 "쓴다"는 뜻을 남긴다.
void _drawPen(Canvas c, Size s, Paint p, Color tone) {
  final body = Path()
    ..moveTo(11.6, 0.8)
    ..lineTo(15.0, 4.2)
    ..lineTo(6.2, 13.0)
    ..lineTo(1.6, 14.2)
    ..lineTo(2.8, 9.6)
    ..close();
  c.drawPath(body, p);

  // 펜대와 촉을 가르는 금 — 통짜 덩어리로 보이지 않게 한다.
  c.drawLine(
    const Offset(4.0, 10.6),
    const Offset(6.0, 12.6),
    Paint()
      ..color = tone
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round,
  );

  // 밑줄 — 기록형의 표식.
  c.drawRRect(
    RRect.fromRectAndRadius(
        const Rect.fromLTWH(1.4, 14.8, 13.2, 1.6), const Radius.circular(0.8)),
    p,
  );
}
