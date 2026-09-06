import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 나침반 방위각을 화면에 적용할 **누적** 회전각으로 바꾼다.
///
/// 방위각은 359° 다음에 0°가 온다. 그 값을 그대로 `transform:rotate()`에 넣으면
/// 부채꼴이 한 바퀴를 거꾸로 되감는다. 두 각의 최단 차이(-180~180)만 더하면
/// 359°→1°가 +2°가 되고, 값은 360을 넘어 계속 자란다 — 회전은 mod 360이라
/// 무한히 커져도 화면 결과는 같다.
///
/// 지도(3a)와 진행 화면(4a)이 같은 규칙을 써야 두 화면에서 같은 방향을 가리킨다.
class ConeAngle {
  double _value = 0;
  double? _source;

  /// 지금까지 누적된 회전각(도).
  double get value => _value;

  /// 방위각 하나를 먹이고 갱신된 누적 회전각을 돌려준다.
  double advance(double degrees) {
    final previous = _source;
    _value += previous == null ? degrees : ((degrees - previous + 540) % 360) - 180;
    _source = degrees;
    return _value;
  }
}

/// 현위치 점에서 뻗어 나가는 시야 부채꼴 — 카카오맵 WebView용 HTML.
///
/// **꼭짓점이 현위치 한가운데에 있다.** 예전에는 점에서 14px 떨어진 곳에서
/// 시작하는 삼각형이라, 지도 위에서 종이비행기 하나가 따로 떠 있는 것처럼
/// 보였다 — 현위치 마커와 다른 물건으로 읽혔다. 이제 점을 꼭짓점 삼아
/// 밖으로 벌어지고, 멀어질수록 옅어진다. 둘이 한 덩어리로 읽힌다.
///
/// 상자는 [headingConeBoxSize]×[headingConeBoxSize]이고 한가운데가 현위치다.
/// 상자를 통째로 돌려서 방향을 만든다.
///
/// 플러그인이 이 문자열을 **작은따옴표로 감싼 JS**에 그대로 넣는다 —
/// 작은따옴표와 줄바꿈을 쓰면 안 된다.
const double headingConeBoxSize = 76;

/// 부채꼴이 뻗는 길이(px). 현위치 점 반지름(14)보다 충분히 길어야 방향이 읽힌다.
const double _coneReach = 34;

/// 부채꼴이 벌어지는 폭(px). 밑변의 절반이다.
const double _coneHalfWidth = 21;

String headingConeHtml(String elementId, double rotation) {
  final deg = rotation.toStringAsFixed(1);
  const c = headingConeBoxSize / 2;
  const left = c - _coneHalfWidth;
  const top = c - _coneReach;
  const w = _coneHalfWidth * 2;

  return '<div id="$elementId" style="width:${headingConeBoxSize}px;'
      'height:${headingConeBoxSize}px;position:relative;pointer-events:none;'
      'transform:rotate(${deg}deg);transform-origin:${c}px ${c}px;'
      'transition:transform 150ms linear;will-change:transform;">'
      '<div style="position:absolute;left:${left}px;top:${top}px;'
      'width:${w}px;height:${_coneReach}px;'
      'background:linear-gradient(to top,rgba(158,43,30,0.42),rgba(158,43,30,0.02));'
      'clip-path:polygon(50% 100%,0% 0%,100% 0%);'
      '-webkit-clip-path:polygon(50% 100%,0% 0%,100% 0%);"></div>'
      '</div>';
}

/// 위 HTML과 **같은 모양**의 Flutter 판. 지도를 못 띄웠을 때 쓰는 폴백 경로에서만 쓴다.
///
/// 상자 한가운데가 현위치이고, 거기서 위쪽으로 부채꼴이 뻗는다.
/// 회전은 바깥에서 [Transform.rotate]로 준다.
class HeadingCone extends StatelessWidget {
  const HeadingCone({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: headingConeBoxSize,
      height: headingConeBoxSize,
      child: CustomPaint(painter: _HeadingConePainter()),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 꼭짓점이 한가운데(=현위치)에 있고 위쪽(0°, 북)으로 벌어진다.
    // 회전은 부모 Transform이 맡는다.
    final top = cy - _coneReach;
    final path = Path()
      ..moveTo(cx, cy)
      ..lineTo(cx - _coneHalfWidth, top)
      ..lineTo(cx + _coneHalfWidth, top)
      ..close();

    // 멀어질수록 옅어진다 — HTML 쪽 linear-gradient 와 같은 값.
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, cy),
          Offset(cx, top),
          [
            AppColors.quest500.withValues(alpha: 0.42),
            AppColors.quest500.withValues(alpha: 0.02),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) => false;
}

/// 시계 방향 방위각(도)에서 라디안으로. 다른 곳에서 쓰지 않도록 여기 둔다.
double degreesToRadians(double degrees) => degrees * math.pi / 180;
