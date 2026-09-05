import 'dart:math' as math;

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

/// 현위치 점 뒤에 까는 부채꼴 — 카카오맵 WebView용 HTML.
///
/// 64×64 상자 한가운데가 현위치다. 부채꼴은 반지름 14px(현위치 점) 밖에서
/// 시작하므로 점을 가리지 않는다. 상자를 통째로 돌려서 방향을 만든다.
///
/// 플러그인이 이 문자열을 **작은따옴표로 감싼 JS**에 그대로 넣는다 —
/// 작은따옴표와 줄바꿈을 쓰면 안 된다.
String headingConeHtml(String elementId, double rotation) {
  final deg = rotation.toStringAsFixed(1);
  return '<div id="$elementId" style="width:64px;height:64px;'
      'position:relative;pointer-events:none;'
      'transform:rotate(${deg}deg);transform-origin:32px 32px;'
      'transition:transform 150ms linear;will-change:transform;">'
      '<div style="position:absolute;left:21px;top:0px;width:0;height:0;'
      'border-left:11px solid transparent;border-right:11px solid transparent;'
      'border-bottom:18px solid rgba(158,43,30,0.55);"></div>'
      '</div>';
}

/// 위 HTML과 **같은 모양**의 Flutter 판. 지도를 못 띄웠을 때 쓰는 폴백 경로에서만 쓴다.
///
/// 64×64 안에서 위쪽을 향한 삼각형 하나. 회전은 바깥에서 [Transform.rotate]로 준다.
class HeadingCone extends StatelessWidget {
  const HeadingCone({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: CustomPaint(painter: _HeadingConePainter()),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    // 위쪽(=0°, 북)을 향하는 삼각형. 회전은 부모 Transform이 맡는다.
    // HTML 쪽 CSS border 삼각형과 같은 치수 — 밑변 22, 높이 18, 꼭짓점이 위다.
    final path = Path()
      ..moveTo(cx, 0)
      ..lineTo(cx - 11, 18)
      ..lineTo(cx + 11, 18)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = AppColors.quest500.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) => false;
}

/// 시계 방향 방위각(도)에서 라디안으로. 다른 곳에서 쓰지 않도록 여기 둔다.
double degreesToRadians(double degrees) => degrees * math.pi / 180;
