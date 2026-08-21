import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/models/active_quest.dart';
import 'package:local_quest/models/quest_model.dart';

QuestModel _quest({required int spotCount}) => QuestModel(
      id: 'q_test',
      title: '테스트 퀘스트',
      summary: '요약',
      description: '설명',
      difficulty: QuestDifficulty.star2,
      latitude: 37.2882,
      longitude: 127.0163,
      spotName: '수원화성',
      regionLabel: '경기 수원시',
      keywords: const ['산책'],
      spots: [
        for (var i = 0; i < spotCount; i++)
          QuestSpot(
            name: '지점 ${i + 1}',
            latitude: 37.2882 + i * 0.001,
            longitude: 127.0163,
          ),
      ],
    );

ActiveQuest _active(QuestModel quest) =>
    ActiveQuest(quest: quest, startedAt: DateTime(2026, 8, 22));

void main() {
  group('단일 지점 — 접근률이 곧 진행률', () {
    test('출발 전에는 0', () {
      expect(_active(_quest(spotCount: 1)).progress, 0);
    });

    test('절반쯤 다가가면 절반쯤 찬다', () {
      final a = _active(_quest(spotCount: 1))
          .withApproach(remainingMeters: 250, initialMeters: 500);
      expect(a.progress, closeTo(0.5, 0.001));
    });

    test('도착하면 1', () {
      final a = _active(_quest(spotCount: 1))
          .withApproach(remainingMeters: 0, initialMeters: 500);
      expect(a.progress, 1);
    });
  });

  group('다중 지점 — 지점 수와 접근률을 함께 센다', () {
    test('2지점 중 1개 완료 + 다음 지점 30% 접근 = 65%', () {
      final a = _active(_quest(spotCount: 2))
          .advanced()
          .withApproach(remainingMeters: 700, initialMeters: 1000);
      expect(a.verifiedSpotCount, 1);
      expect(a.progress, closeTo(0.65, 0.001));
    });

    test('요구사항 그대로 — 1/2 부분완료는 50% 이상에서 계속 움직인다', () {
      final half = _active(_quest(spotCount: 2)).advanced();
      expect(half.progress, closeTo(0.5, 0.001));

      final moving =
          half.withApproach(remainingMeters: 500, initialMeters: 1000);
      expect(moving.progress, greaterThan(half.progress));
    });

    test('전부 인증하면 1', () {
      final a = _active(_quest(spotCount: 3)).advanced().advanced().advanced();
      expect(a.isFinished, isTrue);
      expect(a.progress, 1);
    });

    test('인증하면 접근률이 다음 구간을 위해 0으로 돌아간다', () {
      final a = _active(_quest(spotCount: 2))
          .withApproach(remainingMeters: 100, initialMeters: 1000)
          .advanced();
      expect(a.approachProgress, 0);
    });
  });

  group('진행 문구', () {
    test('출발 전', () {
      expect(_active(_quest(spotCount: 1)).progressLabel, '수락함 · 아직 출발 전');
    });

    test('이동 중에는 남은 거리를 보여준다', () {
      final a = _active(_quest(spotCount: 1))
          .withApproach(remainingMeters: 320, initialMeters: 1000);
      expect(a.progressLabel, contains('320m'));
    });

    test('반경 안에 들어오면 인증 안내로 바뀐다', () {
      final a = _active(_quest(spotCount: 1))
          .withApproach(remainingMeters: 20, initialMeters: 1000);
      expect(a.progressLabel, '도착 · 인증할 수 있어요');
    });

    test('다중 지점은 지점 수를 센다', () {
      final a = _active(_quest(spotCount: 3)).advanced();
      expect(a.progressLabel, '1 / 3 지점 완료');
    });
  });

  group('저장과 복원', () {
    test('퀘스트 본문까지 담겨서 목업 저장소 없이도 복원된다', () {
      final original = _active(_quest(spotCount: 2))
          .advanced()
          .withApproach(remainingMeters: 400, initialMeters: 1000);

      final restored = ActiveQuest.fromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.quest.id, 'q_test');
      expect(restored.quest.title, '테스트 퀘스트');
      expect(restored.quest.spotCount, 2);
      expect(restored.verifiedSpotCount, 1);
      expect(restored.progress, closeTo(original.progress, 0.001));
    });

    test('멱등 키가 보존된다 — 재시도해도 EXP가 두 번 들어가지 않게', () {
      final a = _active(_quest(spotCount: 1))
          .copyWith(pendingRequestId: 'uuid-1234');
      expect(ActiveQuest.fromJson(a.toJson())!.pendingRequestId, 'uuid-1234');
    });

    test('스냅샷이 없는 구버전 데이터는 폴백 퀘스트로 되살린다', () {
      final legacy = {
        'questId': 'q_test',
        'verifiedSpotCount': 1,
        'startedAt': DateTime(2026, 8, 22).toIso8601String(),
      };
      final restored =
          ActiveQuest.fromJson(legacy, fallbackQuest: _quest(spotCount: 2));
      expect(restored, isNotNull);
      expect(restored!.verifiedSpotCount, 1);
    });

    test('스냅샷도 폴백도 없으면 버린다', () {
      expect(ActiveQuest.fromJson({'questId': 'gone'}), isNull);
    });
  });
}
