import 'package:flutter_test/flutter_test.dart';
import 'package:local_quest/data/badge_api.dart';

/// 실기기에서 잡은 회귀: 서버가 `progress: 1, achieved: true`를 줬는데
/// 보상 화면이 로컬 카운트를 읽어 "0 / 1 진행 중"으로 표시했다.
Map<String, dynamic> _b({
  required int id,
  required String name,
  int progress = 0,
  int threshold = 1,
  bool achieved = false,
  bool justEarned = false,
  bool hidden = false,
}) =>
    {
      'badgeId': id,
      'name': name,
      'artKey': 'first_step',
      'progress': progress,
      'threshold': threshold,
      'achieved': achieved,
      'justEarned': justEarned,
      'hidden': hidden,
    };

void main() {
  test('방금 딴 배지가 진행 중인 배지보다 우선한다', () {
    final picked = VerifyBadgeProgress.pick([
      _b(id: 2, name: '스무 걸음', progress: 1, threshold: 20),
      _b(id: 1, name: '첫 발자국', progress: 1, achieved: true, justEarned: true),
    ]);
    expect(picked!.name, '첫 발자국');
    expect(picked.label, '1 / 1 · 달성');
    expect(picked.ratio, 1.0);
  });

  test('딴 게 없으면 완성에 가장 가까운 진행 중 배지', () {
    final picked = VerifyBadgeProgress.pick([
      _b(id: 2, name: '스무 걸음', progress: 2, threshold: 20),
      _b(id: 3, name: '경기 순례자', progress: 4, threshold: 5),
      _b(id: 4, name: '아직', progress: 0, threshold: 5),
    ]);
    expect(picked!.name, '경기 순례자');
    expect(picked.label, '4 / 5 진행 중');
  });

  test('히든 배지는 딴 순간에만 드러난다', () {
    expect(
      VerifyBadgeProgress.pick([
        _b(id: 9, name: '새벽을 여는 사람', progress: 1, threshold: 3, hidden: true),
      ]),
      isNull,
    );
    expect(
      VerifyBadgeProgress.pick([
        _b(
          id: 9,
          name: '새벽을 여는 사람',
          progress: 3,
          threshold: 3,
          achieved: true,
          justEarned: true,
          hidden: true,
        ),
      ])!.name,
      '새벽을 여는 사람',
    );
  });

  test('진행이 0뿐이거나 응답이 없으면 카드를 띄우지 않는다', () {
    expect(VerifyBadgeProgress.pick(null), isNull);
    expect(VerifyBadgeProgress.pick([]), isNull);
    expect(
      VerifyBadgeProgress.pick([_b(id: 1, name: '첫 발자국', threshold: 1)]),
      isNull,
    );
  });

  test('여러 개를 동시에 땄으면 더 어려운 쪽(threshold 큰 쪽)을 보여준다', () {
    final picked = VerifyBadgeProgress.pick([
      _b(id: 1, name: '첫 발자국', progress: 1, achieved: true, justEarned: true),
      _b(
        id: 2,
        name: '스무 걸음',
        progress: 20,
        threshold: 20,
        achieved: true,
        justEarned: true,
      ),
    ]);
    expect(picked!.name, '스무 걸음');
  });

  test('threshold가 0이어도 나누기로 죽지 않는다', () {
    expect(
      VerifyBadgeProgress.fromJson(
        _b(id: 1, name: 'x', progress: 1, threshold: 0),
      ).ratio,
      0,
    );
  });
}
