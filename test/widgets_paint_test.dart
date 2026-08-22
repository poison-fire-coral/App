import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/theme/app_colors.dart';
import 'package:local_quest/theme/app_theme.dart';
import 'package:local_quest/theme/design_tokens.dart';
import 'package:local_quest/widgets/app_widgets.dart';

/// 공용 위젯이 **실제로 페인트되는지** 확인한다.
///
/// 이 테스트를 만든 이유: `NoteBox`가 "빛은 위에서 온다" 원칙을 표현하려고
/// 테두리 네 면에 서로 다른 색을 줬는데, Flutter는 `borderRadius`가 있는
/// 비균일 테두리를 만나면 **paint 단계에서 예외를 던지고 자식을 통째로 그리지
/// 않는다.** 그래서 앱 전역에서 NoteBox 안의 글자가 보이지 않았다.
///
/// `flutter analyze`도, 위젯을 찾는 테스트도 전부 통과했다. 레이아웃은 정상이고
/// **그리는 순간에만** 터지기 때문이다. 그래서 여기서는 `tester.takeException()`으로
/// paint 예외까지 확인한다.
void main() {
  Future<void> pumpAndPaint(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '위젯을 그리는 도중 예외가 났다. 화면에 내용이 안 보이게 된다.');
  }

  group('오목한 면 (NoteBox)', () {
    testWidgets('예외 없이 그려지고 글자가 보인다', (tester) async {
      await pumpAndPaint(
        tester,
        NoteBox(child: Text('내 위치는 도착 확인에만 씁니다.', style: AppType.bodyMuted)),
      );
      expect(find.textContaining('내 위치는'), findsOneWidget);
      expect(tester.getSize(find.textContaining('내 위치는')).height,
          greaterThan(0));
    });

    testWidgets('.text 팩토리도 마찬가지', (tester) async {
      await pumpAndPaint(tester, NoteBox.text('주변에 추천할 퀘스트가 없어요.'));
      expect(find.textContaining('추천할 퀘스트'), findsOneWidget);
    });

    testWidgets('높이를 지정해도 안전하다', (tester) async {
      await pumpAndPaint(
        tester,
        NoteBox(
          height: 120,
          alignment: Alignment.center,
          child: const Text('가운데'),
        ),
      );
      expect(find.text('가운데'), findsOneWidget);
    });
  });

  group('나머지 표면 위젯도 그려진다', () {
    testWidgets('AppCard', (tester) async {
      await pumpAndPaint(
        tester,
        const AppCard(child: Text('카드 내용')),
      );
      expect(find.text('카드 내용'), findsOneWidget);
    });

    testWidgets('AppCard + accentEdge', (tester) async {
      await pumpAndPaint(
        tester,
        const AppCard(accentEdge: AppColors.quest500, child: Text('강조 카드')),
      );
      expect(find.text('강조 카드'), findsOneWidget);
    });

    testWidgets('SolidBox', (tester) async {
      await pumpAndPaint(tester, SolidBox.text('실선 박스'));
      expect(find.text('실선 박스'), findsOneWidget);
    });

    testWidgets('AppSheetSurface', (tester) async {
      await pumpAndPaint(
        tester,
        const AppSheetSurface(child: Text('시트 내용')),
      );
      expect(find.text('시트 내용'), findsOneWidget);
    });

    testWidgets('PrimaryButton (활성/비활성)', (tester) async {
      await pumpAndPaint(tester, PrimaryButton(label: '수락', onTap: () {}));
      expect(find.text('수락'), findsOneWidget);

      await pumpAndPaint(
        tester,
        const PrimaryButton(label: '도착해야 인증할 수 있어요', enabled: false),
      );
      expect(find.text('도착해야 인증할 수 있어요'), findsOneWidget);
    });

    testWidgets('TagChip (선택/비선택)', (tester) async {
      await pumpAndPaint(tester, const TagChip(label: '#골목산책'));
      await pumpAndPaint(
        tester,
        const TagChip(label: '#골목산책', isSelected: true),
      );
      expect(find.text('#골목산책'), findsOneWidget);
    });

    testWidgets('TierBadge 5등급 전부', (tester) async {
      for (var stars = 1; stars <= 5; stars++) {
        await pumpAndPaint(tester, TierBadge(stars: stars));
      }
    });

    testWidgets('RewardPill', (tester) async {
      await pumpAndPaint(
        tester,
        const RewardPill(exp: 110, multiplierNote: '한산 ×1.4'),
      );
      expect(find.textContaining('110'), findsOneWidget);
    });

    testWidgets('ProgressBar (0 · 중간 · 1)', (tester) async {
      for (final v in [0.0, 0.65, 1.0]) {
        await pumpAndPaint(tester, ProgressBar(value: v));
      }
    });

    testWidgets('ProgressBar는 트랙이 접히지 않고 부모 폭을 채운다', (tester) async {
      // 가운데 정렬 Column 안에서 폭이 접혀 트랙이 사라졌던 회귀를 막는다.
      await pumpAndPaint(
        tester,
        const SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [ProgressBar(value: 0.75)],
          ),
        ),
      );
      expect(tester.getSize(find.byType(ProgressBar)).width, 300);
    });

    testWidgets('SectionHeader', (tester) async {
      await pumpAndPaint(
        tester,
        const SectionHeader(title: '내 주변 추천 퀘스트', trailingText: '새로고침'),
      );
      expect(find.text('내 주변 추천 퀘스트'), findsOneWidget);
    });

    testWidgets('QuestMarker · MarkerCluster', (tester) async {
      await pumpAndPaint(tester, const QuestMarker());
      await pumpAndPaint(tester, const QuestMarker(isActive: true));
      await pumpAndPaint(tester, const MarkerCluster(count: 12));
    });

    testWidgets('FloatingSurfaceButton', (tester) async {
      await pumpAndPaint(
        tester,
        const FloatingSurfaceButton(icon: Icons.my_location_rounded),
      );
    });

    testWidgets('AppBottomNav', (tester) async {
      await pumpAndPaint(
        tester,
        AppBottomNav(current: AppTab.home, onSelect: (_) {}),
      );
      expect(find.text('홈'), findsOneWidget);
    });

    testWidgets('AppTopBar', (tester) async {
      await pumpAndPaint(
        tester,
        const AppTopBar(
          nickname: '모험가한글',
          level: 7,
          levelProgress: 0.62,
          avatarId: 'avatar_03',
        ),
      );
      expect(find.text('모험가한글'), findsOneWidget);
    });
  });
}
