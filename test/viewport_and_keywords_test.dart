import 'package:flutter_test/flutter_test.dart';

import 'package:local_quest/data/keyword_taxonomy.dart';
import 'package:local_quest/models/viewport_quests.dart';
import 'package:local_quest/services/map_zoom.dart';

/// 지도 뷰포트 전환(체크리스트 08~12)에서 **조용히 틀리기 쉬운** 부분들.
///
/// 화면을 띄우지 않고 검증할 수 있는 순수 로직만 모았다. 나머지(카메라 idle
/// 디바운스·오버레이)는 WebView가 있어야 해서 실기기 확인 몫이다.
void main() {
  group('MapZoom — 카카오 레벨과 서버 zoom은 방향이 반대다', () {
    test('확대할수록 서버 zoom이 커진다', () {
      // 카카오는 1이 최대 확대. 서버는 그 반대다.
      expect(MapZoom.fromKakaoLevel(1), greaterThan(MapZoom.fromKakaoLevel(14)));
      expect(MapZoom.fromKakaoLevel(3), 18);
      expect(MapZoom.fromKakaoLevel(6), 15);
    });

    test('레벨 7까지는 개별 마커, 8부터 클러스터다', () {
      // 이 경계가 뒤집히면 골목을 볼 때 클러스터가 뜨고
      // 전국을 펼칠 때 마커 수천 개가 쏟아진다.
      expect(MapZoom.isClusteredAt(7), isFalse);
      expect(MapZoom.isClusteredAt(8), isTrue);
      expect(MapZoom.clusterKakaoLevel, 7);
    });

    test('범위를 벗어난 레벨도 안전하게 눌린다', () {
      expect(MapZoom.fromKakaoLevel(0), MapZoom.fromKakaoLevel(1));
      expect(MapZoom.fromKakaoLevel(99), MapZoom.fromKakaoLevel(14));
      expect(MapZoom.toKakaoLevel(999), MapZoom.minKakaoLevel);
    });

    test('두 방향 환산이 서로를 되돌린다', () {
      for (var level = MapZoom.minKakaoLevel;
          level <= MapZoom.maxKakaoLevel;
          level++) {
        expect(MapZoom.toKakaoLevel(MapZoom.fromKakaoLevel(level)), level);
      }
    });
  });

  group('ViewportQuests — 서버 응답의 두 모양', () {
    test('축소 상태면 클러스터로 읽는다', () {
      final result = ViewportQuests.fromJson({
        'isClustered': true,
        'zoom': 12,
        'totalQuests': 340,
        'clusters': [
          {'lat': 37.28, 'lng': 127.01, 'count': 200},
          {'lat': 35.15, 'lng': 129.05, 'count': 140},
        ],
      });

      expect(result.isClustered, isTrue);
      expect(result.clusters, hasLength(2));
      expect(result.quests, isEmpty);
      expect(result.totalQuests, 340);
    });

    test('확대 상태면 퀘스트 목록으로 읽는다', () {
      final result = ViewportQuests.fromJson({
        'isClustered': false,
        'zoom': 18,
        'totalQuests': 2,
        'quests': [
          {
            'id': 1,
            'title': '등대 끝까지',
            'difficulty': 1,
            'place': {'name': '방파제', 'lat': 35.1, 'lng': 129.0},
          },
          {
            'id': 2,
            'title': '이름 없는 계단',
            'difficulty': 2,
            'place': {'name': '언덕', 'lat': 35.2, 'lng': 129.1},
          },
        ],
      });

      expect(result.isClustered, isFalse);
      expect(result.quests, hasLength(2));
      expect(result.quests.first.id, '1');
      expect(result.isTruncated, isFalse);
    });

    test('서버가 상한 없이 쏟아부으면 그리는 쪽에서 자른다', () {
      // 서버 `findMany`에 아직 `take`가 없다(체크리스트 08번 BE 몫).
      // 그 상태에서 줌아웃하면 수천 건이 그대로 내려온다.
      final result = ViewportQuests.fromJson({
        'isClustered': false,
        'totalQuests': 1000,
        'quests': [
          for (var i = 0; i < 1000; i++)
            {
              'id': i,
              'title': '퀘스트 $i',
              'difficulty': 1,
              'place': {'name': '장소', 'lat': 37.0, 'lng': 127.0},
            },
        ],
      });

      expect(result.quests, hasLength(ViewportQuests.renderLimit));
      expect(result.isTruncated, isTrue);
      // 몇 개를 숨겼는지 사용자에게 말해 줄 수 있어야 한다.
      expect(result.totalQuests, 1000);
    });

    test('모양을 알 수 없는 응답에도 터지지 않는다', () {
      final result = ViewportQuests.fromJson({});
      expect(result.quests, isEmpty);
      expect(result.clusters, isEmpty);
      expect(result.isClustered, isFalse);
    });
  });

  group('KeywordTaxonomy — 온보딩 어휘와 서버 어휘를 잇는다', () {
    test('온보딩 값을 그대로 서버에 넘기면 안 된다는 걸 표로 해결한다', () {
      // 서버 Quest.keywords에는 '골목산책'이라는 값이 없다. '골목'과 '산책'이 있다.
      expect(KeywordTaxonomy.questKeywordsForStyle('골목산책'),
          containsAll(<String>['골목', '산책']));
      expect(KeywordTaxonomy.questKeywordsForStyle('로컬맛집'), contains('맛집'));
    });

    test('해시가 붙어 있어도 같은 값으로 본다', () {
      expect(
        KeywordTaxonomy.questKeywordsForStyle('#골목산책'),
        KeywordTaxonomy.questKeywordsForStyle('골목산책'),
      );
    });

    test('모르는 키워드는 빈 목록이다', () {
      expect(KeywordTaxonomy.questKeywordsForStyle('없는키워드'), isEmpty);
    });

    test('여러 취향을 펼치면 순서를 지키고 중복을 없앤다', () {
      final result =
          KeywordTaxonomy.questKeywordsForStyles(['골목산책', '벽화·거리예술']);

      // 둘 다 '골목'을 가리키지만 한 번만 나온다.
      expect(result.where((k) => k == '골목'), hasLength(1));
      // 앞 취향에서 나온 것이 앞에 온다.
      expect(result.indexOf('골목'), lessThan(result.indexOf('사진')));
    });

    test('필터 칩은 내 취향을 앞세우고 나머지를 뒤에 붙인다', () {
      final chips = KeywordTaxonomy.filterChipOrder(['사진스팟']);

      expect(chips.first, '사진');
      // 취향과 무관한 공통 키워드도 사라지지 않는다 — 되돌릴 수 있어야 한다.
      expect(chips, contains('맛집'));
      // 중복 없이 한 번씩만.
      expect(chips.toSet(), hasLength(chips.length));
    });

    test('취향을 안 고른 사용자도 칩을 본다', () {
      expect(KeywordTaxonomy.filterChipOrder(const []),
          KeywordTaxonomy.commonQuestKeywords);
    });
  });
}
