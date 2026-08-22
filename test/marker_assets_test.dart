import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:local_quest/theme/app_assets.dart';

/// 4단계 회귀 — 마커 에셋이 **실제로 있고 PNG로 디코딩되는지**.
///
/// 없으면 지도에서 조용히 기본 핀으로 떨어져 아무도 눈치채지 못한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('7유형 × 5난이도 × 3배율이 모두 존재하고 PNG로 열린다', () async {
    for (final type in AppAssets.markerQuestTypes) {
      for (var stars = 1; stars <= 5; stars++) {
        for (final dpr in [1.0, 2.0, 3.0]) {
          final path = AppAssets.questMarker(
            questType: type,
            stars: stars,
            devicePixelRatio: dpr,
          );
          final file = File(path);
          expect(file.existsSync(), isTrue, reason: '없음: $path');

          final codec =
              await ui.instantiateImageCodec(file.readAsBytesSync());
          final frame = await codec.getNextFrame();
          // 논리 36×46 × 배율
          expect(frame.image.width, (36 * dpr).round(), reason: path);
          expect(frame.image.height, (46 * dpr).round(), reason: path);
        }
      }
    }
  });

  test('현위치 마커 3배율이 존재한다', () {
    for (final dpr in [1.0, 2.0, 3.0]) {
      expect(File(AppAssets.myLocationMarker(dpr)).existsSync(), isTrue);
    }
  });

  test('모르는 유형·범위 밖 난이도는 조용히 기본값으로 떨어진다', () {
    expect(
      AppAssets.questMarker(
          questType: 'NOPE', stars: 9, devicePixelRatio: 1.0),
      'assets/markers/visit_t5.png',
    );
  });

  test('배율 경계', () {
    expect(AppAssets.myLocationMarker(1.0), endsWith('my_location.png'));
    expect(AppAssets.myLocationMarker(2.0), endsWith('my_location@2x.png'));
    expect(AppAssets.myLocationMarker(3.5), endsWith('my_location@3x.png'));
  });

  test('pubspec에 assets/markers/가 선언돼 있다', () {
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- assets/markers/'));
  });
}
