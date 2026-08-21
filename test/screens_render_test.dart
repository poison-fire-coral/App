import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/models/auth_models.dart';
import 'package:local_quest/models/user_model.dart';
import 'package:local_quest/screens/level_up_screen.dart';
import 'package:local_quest/screens/login_screen.dart';
import 'package:local_quest/screens/onboarding_screen.dart';
import 'package:local_quest/screens/signup_screen.dart';
import 'package:local_quest/screens/splash_screen.dart';
import 'package:local_quest/services/exp_service.dart';
import 'package:local_quest/theme/app_theme.dart';

/// 화면이 **실제로 레이아웃되는지** 확인한다.
///
/// 이 테스트를 만든 이유: 로그인 화면이 `SingleChildScrollView` 안에서 `Spacer`를
/// 쓰는 바람에 "RenderFlex children have non-zero flex but incoming height
/// constraints are unbounded"로 배치에 실패해 **화면이 통째로 비어 있었다.**
/// `flutter analyze`도 통과하고 빌드도 성공했지만 실기기에서 아무것도 안 보였다.
/// 컴파일이 되는 것과 그려지는 것은 다르다.
void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
    await tester.pump(const Duration(milliseconds: 500));

    // 레이아웃 실패는 예외로 드러난다. 조용히 넘어가면 빈 화면이 배포된다.
    expect(tester.takeException(), isNull);
  }

  /// 흔한 기기 크기들. 작은 화면에서만 터지는 오버플로도 잡는다.
  const sizes = <String, Size>{
    '작은 폰 (360×640)': Size(360, 640),
    '보통 폰 (412×915)': Size(412, 915),
  };

  void forEachSize(String name, Widget Function() build) {
    for (final entry in sizes.entries) {
      testWidgets('$name — ${entry.key}', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpScreen(tester, build());
      });
    }
  }

  forEachSize('스플래시', () => const SplashScreen(progress: 0.5));

  forEachSize(
    '로그인',
    () => LoginScreen(
      onPickProvider: (_) {},
      onGoSignup: () {},
    ),
  );

  forEachSize(
    '로그인 (개발자 모드 버튼 포함)',
    () => LoginScreen(
      onPickProvider: (_) {},
      onGoSignup: () {},
      onGuest: () {},
    ),
  );

  forEachSize(
    '가입 방법 선택',
    () => SignupScreen(onPickProvider: (_) {}, onBack: () {}),
  );

  forEachSize(
    '온보딩 (신규 가입)',
    () => OnboardingScreen(
      mode: OnboardingMode.signup,
      pending: const PendingSignup(provider: 'GUEST', providerUid: 'u1'),
      onComplete: (_) {},
      onBack: () {},
    ),
  );

  forEachSize(
    '레벨업',
    () => const LevelUpScreen(
      result: LevelUpResult(
        previousLevel: 4,
        level: 5,
        exp: 120,
        gainedExp: 400,
        unlocks: ['히든 퀘스트 해금'],
        nextRequiredExp: 300,
      ),
    ),
  );

  group('로그인 화면 내용이 실제로 보인다', () {
    testWidgets('빈 화면이 아니다', (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(onPickProvider: (_) {}, onGoSignup: () {}),
      );
      expect(find.text('로컬 퀘스트'), findsOneWidget);
      expect(find.text('카카오로 계속하기'), findsOneWidget);
      expect(find.text('아직 계정이 없어요 · 회원가입'), findsOneWidget);
    });

    testWidgets('개발자 모드가 꺼져 있으면 GUEST 버튼이 없다', (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(onPickProvider: (_) {}, onGoSignup: () {}),
      );
      expect(find.text('개발용 계정으로 로그인'), findsNothing);
    });
  });

  group('온보딩 게이트', () {
    testWidgets('닉네임이 비어 있으면 다음으로 못 넘어간다', (tester) async {
      await pumpScreen(
        tester,
        OnboardingScreen(
          mode: OnboardingMode.signup,
          pending: const PendingSignup(provider: 'GUEST', providerUid: 'u1'),
          onComplete: (_) {},
          onBack: () {},
        ),
      );

      expect(find.text('모험가 이름을 정해주세요'), findsOneWidget);

      // 중복확인 전이므로 어떤 판정 메시지도 떠 있으면 안 된다.
      expect(find.text('사용할 수 있는 이름이에요'), findsNothing);
      expect(find.text('이미 누군가 쓰고 있어요'), findsNothing);
    });

    testWidgets('취향 재설정 모드는 기존 값을 채워 온다', (tester) async {
      await pumpScreen(
        tester,
        OnboardingScreen(
          mode: OnboardingMode.editProfile,
          initialData: UserModel(
            nickname: '모험가한글',
            avatarId: 'avatar_03',
            travelStyles: const ['골목산책', '전통시장', '사진스팟'],
            activityLevel: '보통',
          ),
          onComplete: (_) {},
          onBack: () {},
        ),
      );
      expect(find.text('모험가한글'), findsOneWidget);
    });
  });
}
