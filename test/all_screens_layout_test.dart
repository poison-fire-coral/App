import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/models/active_quest.dart';
import 'package:local_quest/models/quest_completion.dart';
import 'package:local_quest/models/quest_model.dart';
import 'package:local_quest/models/user_model.dart';
import 'package:local_quest/screens/badge_screen.dart';
import 'package:local_quest/screens/home_screen.dart';
import 'package:local_quest/screens/profile_screen.dart';
import 'package:local_quest/screens/quest_active_screen.dart';
import 'package:local_quest/screens/quest_reward_screen.dart';
import 'package:local_quest/screens/quest_verify_screen.dart';
import 'package:local_quest/screens/settings_screen.dart';
import 'package:local_quest/services/exp_service.dart';
import 'package:local_quest/services/geo.dart';
import 'package:local_quest/services/location_service.dart';
import 'package:local_quest/theme/app_theme.dart';

/// 남은 화면 전부를 여러 기기 크기에서 실제로 배치해 본다.
///
/// `screens_render_test.dart`가 로그인·온보딩 계열을 맡고, 여기서 그 뒤의
/// 화면들을 맡는다. 잡으려는 것은 두 가지다.
///
/// 1. **레이아웃 실패** — `Spacer`를 스크롤뷰 안에 넣는 것 같은 실수. 컴파일도
///    되고 analyze도 통과하지만 실기기에서 화면이 통째로 빈다.
/// 2. **오버플로** — 작은 화면에서만 터지는 "BOTTOM OVERFLOWED BY n PIXELS".
///    노란 줄무늬는 디버그에서만 보이고 릴리스에서는 그냥 잘려 나가서,
///    실기기를 큰 폰으로만 보면 끝까지 모른다.
///
/// 두 경우 모두 프레임워크가 예외로 알리므로 `takeException()`으로 잡힌다.
void main() {
  /// 흔한 기기 크기. 320×568은 지금 파는 폰 중 가장 좁은 축(SE 1세대급)이라
  /// 여기서 안 넘치면 대부분의 기기에서 안 넘친다.
  const sizes = <String, Size>{
    '아주 좁은 폰 (320×568)': Size(320, 568),
    '작은 폰 (360×640)': Size(360, 640),
    '보통 폰 (412×915)': Size(412, 915),
  };

  /// 글자 크기를 키운 기기. 시스템 설정에서 올리는 사람이 적지 않고,
  /// 그때 처음 넘치는 화면이 많다 — 기본 배율로만 보면 끝까지 모른다.
  const largeTextScale = 1.3;

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: screen,
      ),
    ));
    // 첫 프레임 뒤의 비동기 로드(위치·서버)가 setState를 부를 수 있다.
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  }

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

    // 큰 글자는 가장 좁은 화면과 겹칠 때 터진다. 그 조합만 따로 본다.
    testWidgets('$name — 작은 폰 · 글자 크게(×$largeTextScale)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpScreen(tester, build(), textScale: largeTextScale);
    });
  }

  // ---------------------------------------------------------------------------
  // 표본
  // ---------------------------------------------------------------------------

  UserModel user() => UserModel(
        nickname: '테스터',
        serverId: 1,
        level: 5,
        exp: 120,
        travelStyles: const ['골목산책', '야경'],
        activityLevel: '보통',
        visitedRegions: const ['서울'],
        completedQuestIds: const ['1', '2'],
      );

  QuestModel quest({
    String type = 'VISIT',
    int requiredCount = 1,
    String title = '성북동 골목 걷기',
  }) =>
      QuestModel(
        id: '1',
        title: title,
        summary: '오래된 골목을 천천히 걸어보세요.',
        description: '오래된 골목을 천천히 걸어보세요. 담장마다 다른 이야기가 붙어 있습니다.',
        difficulty: QuestDifficulty.star3,
        questType: type,
        requiredCount: requiredCount,
        photoPrompt: type == 'PHOTO_COLLECT' ? '서로 다른 골목 $requiredCount곳' : null,
        quizQuestion: type == 'QUIZ' ? '이 비석이 세워진 연도는?' : null,
        quizOptions: type == 'QUIZ' ? const ['1794년', '1834년', '1901년'] : const [],
        latitude: 37.5921,
        longitude: 127.0186,
        spotName: '성북동 골목',
        regionLabel: '서울 성북구',
        keywords: const ['골목', '산책', '역사'],
      );

  ActiveQuest active({String type = 'VISIT'}) => ActiveQuest(
        quest: quest(type: type),
        startedAt: DateTime(2026, 9, 1),
      );

  QuestCompletionResult reward() => QuestCompletionResult(
        quest: quest(),
        breakdown: ExpService.calculate(
          const ExpFactors(
            baseExp: 220,
            isNewRegion: true,
            streakDays: 3,
          ),
          dailyExpEarned: 0,
        ),
        levelResult: const LevelUpResult(
          previousLevel: 5,
          level: 5,
          exp: 320,
          gainedExp: 220,
          unlocks: [],
          nextRequiredExp: 500,
        ),
      );

  // ---------------------------------------------------------------------------
  // 화면
  // ---------------------------------------------------------------------------

  forEachSize(
    '홈',
    () => HomeScreen(
      user: user(),
      activeQuests: [active()],
      onContinueQuest: (_) {},
      onSelectQuest: (_) {},
    ),
  );

  forEachSize(
    '홈 (진행 중 없음)',
    () => HomeScreen(
      user: user(),
      onContinueQuest: (_) {},
      onSelectQuest: (_) {},
    ),
  );

  forEachSize('배지 컬렉션', () => BadgeScreen(user: user()));

  forEachSize(
    '프로필',
    () => ProfileScreen(user: user(), onBack: () {}),
  );

  forEachSize(
    '설정',
    () => SettingsScreen(
      onBack: () {},
      onEditProfile: () {},
      onEditKeywords: () {},
      onLogout: () {},
      onDeleteAccount: () async {},
    ),
  );

  forEachSize(
    '보상',
    () => QuestRewardScreen(result: reward(), onConfirm: (_) {}),
  );

  // 진행 화면은 카카오 JS 키가 없으면 지도 대신 폴백을 그린다.
  // 테스트에서는 키가 비어 있으므로 여기서 검증되는 것은 그 폴백 경로다.
  forEachSize(
    '퀘스트 진행 (지도 폴백)',
    () => QuestActiveScreen(
      activeQuest: active(),
      onSpotVerified: (_) {},
      onQuestCompleted: (_, _) async => reward(),
      onAbandon: (_) {},
      locationService: SimulatedLocationService(
        origin: const GeoPoint(37.5900, 127.0150),
      ),
    ),
  );

  // 인증 화면은 유형마다 다른 것을 그린다. 넷 다 배치되는지 본다.
  for (final type in ['VISIT', 'PHOTO_SINGLE', 'PHOTO_COLLECT', 'RECORD', 'QUIZ']) {
    forEachSize(
      '인증 · $type',
      () => QuestVerifyScreen(
        quest: quest(type: type, requiredCount: type == 'PHOTO_COLLECT' ? 3 : 1),
        spot: quest().visitSpots.first,
        accuracyMeters: 12,
      ),
    );
  }
}
