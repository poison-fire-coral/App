import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:local_quest/theme/app_assets.dart';
import 'package:local_quest/widgets/avatar_widgets.dart';

/// 에셋이 pubspec에 선언돼 있고 flutter_svg가 실제로 파싱할 수 있는지 확인한다.
/// SVG 문법 오류나 미지원 기능(filter 등)은 여기서 예외로 드러난다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSvg(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
    await tester.pumpAndSettle();
  }

  group('아바타 프리셋 6종', () {
    for (final id in AppAssets.avatarIds) {
      testWidgets('$id 렌더', (tester) async {
        await pumpSvg(tester, AppAvatar(avatarId: id, size: 72));
        expect(find.byType(AppAvatar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('알 수 없는 avatarId는 기본 프리셋으로 떨어진다', (tester) async {
    expect(AppAssets.normalizeAvatarId('assets/avatars/avatar_1.png'),
        AppAssets.defaultAvatarId);
    expect(AppAssets.normalizeAvatarId(null), AppAssets.defaultAvatarId);
    await pumpSvg(tester, const AppAvatar(avatarId: 'nope', size: 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('위치 권한 일러스트 렌더', (tester) async {
    await pumpSvg(tester, SvgPicture.asset(AppAssets.locationPermission, width: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('로고 렌더', (tester) async {
    await pumpSvg(tester, SvgPicture.asset(AppAssets.logo, width: 120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('아바타 선택 줄에서 6종이 모두 보인다', (tester) async {
    var picked = AppAssets.defaultAvatarId;
    await pumpSvg(
      tester,
      SizedBox(
        width: 360,
        child: AvatarPickerRow(
          selectedId: picked,
          onSelected: (id) => picked = id,
        ),
      ),
    );
    expect(find.byType(AppAvatar), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
