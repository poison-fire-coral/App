import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/models/user_model.dart';
import 'package:local_quest/services/exp_service.dart';

void main() {
  group('서버 breakdown을 그대로 옮긴다', () {
    test('1.0이 아닌 배율만 요약에 실린다', () {
      final b = ExpBreakdown.fromServer(const {
        'baseExp': 220,
        'mHalf': 1.0,
        'mCong': 1.4,
        'mArea': 1.5,
        'mTime': 1.0,
        'mStreak': 1.0,
        'mReattempt': 1.0,
        'calculatedExp': 462,
        'singleCappedExp': 462,
        'finalExp': 462,
      });

      expect(b.baseExp, 220);
      expect(b.finalExp, 462);
      expect(b.multipliers.keys, ['혼잡도', '첫 지역']);
      expect(b.summaryLine, '기본 220 × 혼잡도 1.4 × 첫 지역 1.5');
      expect(b.isSingleCapped, isFalse);
      expect(b.isDailyCapped, isFalse);
    });

    test('단일 퀘스트 상한과 일일 상한을 구분해 읽는다', () {
      final b = ExpBreakdown.fromServer(const {
        'baseExp': 700,
        'mArea': 1.5,
        'mStreak': 1.5,
        'calculatedExp': 1575,
        'singleCappedExp': 1575,
        'finalExp': 900, // 일일 상한에 걸림
      });
      expect(b.isSingleCapped, isFalse);
      expect(b.isDailyCapped, isTrue);
    });

    test('어뷰징이면 0으로 떨어지고 문구가 바뀐다', () {
      final b = ExpBreakdown.fromServer(const {'abusePenalty': true});
      expect(b.finalExp, 0);
      expect(b.isSpeedAbuse, isTrue);
      expect(b.summaryLine, contains('지급되지 않았'));
    });

    test('isAbused 플래그만 와도 0으로 본다', () {
      final b = ExpBreakdown.fromServer(
        const {'baseExp': 220, 'finalExp': 462},
        isAbused: true,
      );
      expect(b.finalExp, 0);
    });
  });

  group('레벨 정보는 서버 값을 진실로 삼는다', () {
    test('nextRequiredExp가 오면 그것으로 진행률을 계산한다', () {
      final r = LevelUpResult.fromServer(
        const {'isLevelUp': true, 'level': 5, 'expCurrent': 150,
               'nextRequiredExp': 300},
        previousLevel: 4,
        gainedExp: 400,
      );

      expect(r.leveledUp, isTrue);
      expect(r.level, 5);
      expect(r.requiredExp, 300);
      expect(r.expToNextLevel, 150);
      expect(r.progress, closeTo(0.5, 0.001));
    });

    test('서버가 안 주면 로컬 테이블로 떨어진다', () {
      final r = LevelUpResult.fromServer(
        const {'level': 5, 'expCurrent': 150},
        previousLevel: 5,
        gainedExp: 50,
      );
      expect(r.requiredExp, LevelSystem.getRequiredExpForLevel(5));
    });

    test('여러 레벨을 한 번에 올라가면 해금 안내가 모두 모인다', () {
      final r = LevelUpResult.fromServer(
        const {'level': 8, 'expCurrent': 0},
        previousLevel: 4,
        gainedExp: 3000,
      );
      // Lv5(히든 퀘스트) · Lv8(★★★★) 두 구간을 지난다
      expect(r.unlocks.length, greaterThanOrEqualTo(2));
    });

    test('레벨업이 아니면 leveledUp이 false', () {
      final r = LevelUpResult.fromServer(
        const {'level': 3, 'expCurrent': 40, 'nextRequiredExp': 220},
        previousLevel: 3,
        gainedExp: 40,
      );
      expect(r.leveledUp, isFalse);
      expect(r.unlocks, isEmpty);
    });
  });

  group('서버 level_table과 클라이언트 LevelSystem이 어긋나지 않아야 한다', () {
    // 서버는 row(N).requiredExp 를 "N-1 → N 승급 비용"으로 읽는다.
    // 즉 row(L+1) 이 클라이언트 getRequiredExpForLevel(L) 과 같아야 한다.
    // prisma/seed.ts 를 이 표에 맞춰 재생성했으므로 여기서 고정해 둔다.
    const serverRows = <int, int>{
      2: 100, 3: 150, 4: 220, 5: 300, 6: 400, 7: 500, 8: 620,
      9: 770, 10: 950, 11: 1150, 12: 1350, 13: 1550, 14: 1750,
      15: 2150, 16: 2000, 30: 2000,
    };

    for (final entry in serverRows.entries) {
      final level = entry.key - 1;
      test('Lv$level 승급 비용이 서버(${entry.value})와 같다', () {
        expect(LevelSystem.getRequiredExpForLevel(level), entry.value);
      });
    }
  });
}
