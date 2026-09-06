import 'package:flutter_test/flutter_test.dart';
import 'package:local_quest/models/quest_model.dart';

/// 유형에 따라 "무엇을 하면 끝나는지"가 달라진다. 예전에는 난이도로 추정한
/// `requiresPhoto` 하나만 보고 늘 "사진 1장"이라 적어서, 사진 3장을 모으는
/// 수집형과 정답을 고르는 퀴즈형에도 같은 문구가 붙었다.
QuestModel _quest({
  required String questType,
  int requiredCount = 1,
  int stars = 3,
}) =>
    QuestModel(
      id: '1',
      title: '테스트 퀘스트',
      summary: '',
      description: '',
      difficulty: QuestDifficulty.values[stars - 1],
      questType: questType,
      requiredCount: requiredCount,
      latitude: 37.5,
      longitude: 127.0,
      spotName: '어딘가',
      keywords: const [],
    );

void main() {
  group('완료 조건 문구는 유형을 따른다', () {
    test('수집형은 목표 장수를 그대로 말한다', () {
      final q = _quest(questType: 'PHOTO_COLLECT', requiredCount: 3);
      expect(q.completionCriteria, contains('사진 3장'));
    });

    test('사진 한 장짜리는 1장이라고 말한다', () {
      final q = _quest(questType: 'PHOTO_SINGLE');
      expect(q.completionCriteria, contains('사진 1장'));
    });

    test('퀴즈·탐색은 사진이 아니라 정답을 요구한다', () {
      for (final type in ['QUIZ', 'EXPLORATION']) {
        final q = _quest(questType: type);
        expect(q.completionCriteria, contains('정답'), reason: type);
        expect(q.completionCriteria, isNot(contains('사진')), reason: type);
      }
    });

    test('기록형은 한 줄을 요구한다', () {
      final q = _quest(questType: 'RECORD');
      expect(q.completionCriteria, contains('한 줄'));
      expect(q.completionCriteria, isNot(contains('사진')));
    });

    test('방문형은 도달만 말한다', () {
      // ★1은 requiresPhoto 가 false 라 사진 문구가 붙지 않는다.
      final q = _quest(questType: 'VISIT', stars: 1);
      expect(q.completionCriteria, contains('도달'));
      expect(q.completionCriteria, isNot(contains('사진')));
    });
  });

  group('requiredCount 파싱', () {
    test('서버가 안 보내면 1장이다', () {
      final q = QuestModel.fromJson({
        'id': 1,
        'title': 'x',
        'place': {'lat': 37.5, 'lng': 127.0, 'name': 'p'},
      });
      expect(q.requiredCount, 1);
    });

    test('0이나 음수가 오면 1로 본다 — 0장을 요구하면 인증이 성립하지 않는다', () {
      for (final bad in [0, -3]) {
        final q = QuestModel.fromJson({
          'id': 1,
          'title': 'x',
          'requiredCount': bad,
          'place': {'lat': 37.5, 'lng': 127.0, 'name': 'p'},
        });
        expect(q.requiredCount, 1, reason: '$bad');
      }
    });

    test('수집형 장수와 촬영 안내가 그대로 실려 온다', () {
      final q = QuestModel.fromJson({
        'id': 1,
        'title': 'x',
        'questType': 'PHOTO_COLLECT',
        'requiredCount': 4,
        'photoPrompt': '서로 다른 가게 4곳',
        'place': {'lat': 37.5, 'lng': 127.0, 'name': 'p'},
      });
      expect(q.requiredCount, 4);
      expect(q.photoPrompt, '서로 다른 가게 4곳');
      expect(q.completionCriteria, contains('사진 4장'));
    });

    test('빈 문자열 촬영 안내는 없는 것으로 본다', () {
      final q = QuestModel.fromJson({
        'id': 1,
        'title': 'x',
        'photoPrompt': '   ',
        'place': {'lat': 37.5, 'lng': 127.0, 'name': 'p'},
      });
      expect(q.photoPrompt, isNull);
    });
  });
}
