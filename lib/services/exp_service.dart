import '../models/quest_model.dart';
import '../models/user_model.dart';


/// 보상 배율 산출에 필요한 입력값 (기획서 6b)
class ExpFactors {
  /// 난이도 기본 EXP. 반개 보정 전 값이다 (★★ = 110).
  final int baseExp;

  /// 반개(★½) 표시 퀘스트면 ×1.15 (기획서 6a)
  final bool hasHalfStar;

  /// 혼잡도 배율 — 한산 ×1.4 · 보통 ×1.0 · 혼잡 ×0.7
  final double crowdMultiplier;

  /// 처음 방문한 시·군이면 ×1.5
  final bool isNewRegion;

  /// 평일 오전 비피크 시간대면 ×1.2
  final bool isOffPeak;

  /// 연속 접속 스트릭. 일당 +5%, 상한 ×1.5
  final int streakDays;

  /// 동일 퀘스트 재수행이면 ×0.3
  final bool isRepeat;

  /// 40km/h 초과 구간 도달이면 EXP 0 (기획서 6d 안티 어뷰징)
  final bool isSpeedAbuse;

  const ExpFactors({
    required this.baseExp,
    this.hasHalfStar = false,
    this.crowdMultiplier = 1.0,
    this.isNewRegion = false,
    this.isOffPeak = false,
    this.streakDays = 0,
    this.isRepeat = false,
    this.isSpeedAbuse = false,
  });
}

/// 배율 계산 내역. 4c 보상 화면에서 "기본 110 × 혼잡도 1.4" 문구를 만드는 데 쓴다.
class ExpBreakdown {
  final int baseExp;

  /// 1.0이 아닌 배율만 담긴 (표시명 → 배율) 목록
  final Map<String, double> multipliers;

  /// 배율만 적용한 값 (상한 적용 전)
  final int calculated;

  /// 단일 퀘스트 상한 1,600을 적용한 값
  final int singleCapped;

  /// 1일 상한 3,000까지 적용한 최종 지급량
  final int finalExp;

  final bool isSpeedAbuse;

  const ExpBreakdown({
    required this.baseExp,
    required this.multipliers,
    required this.calculated,
    required this.singleCapped,
    required this.finalExp,
    this.isSpeedAbuse = false,
  });

  /// 서버 `verify` 응답의 breakdown을 그대로 옮긴다.
  ///
  /// 의뢰서 절대원칙 ①이 "EXP 판정은 100% 서버 계산, 클라이언트는 결과만 표시"라
  /// 못박고 있다. 로컬 계산은 수락 전 예상치·오프라인 폴백으로만 남긴다.
  ///
  /// 서버 모양: `{baseExp, mHalf, mCong, mArea, mTime, mStreak, mReattempt,
  /// calculatedExp, singleCappedExp, finalExp}` 또는 어뷰징 시 `{abusePenalty: true}`.
  factory ExpBreakdown.fromServer(
    Map<String, dynamic> raw, {
    bool isAbused = false,
  }) {
    if (isAbused || raw['abusePenalty'] == true) {
      return const ExpBreakdown(
        baseExp: 0,
        multipliers: {},
        calculated: 0,
        singleCapped: 0,
        finalExp: 0,
        isSpeedAbuse: true,
      );
    }

    const labels = <String, String>{
      'mHalf': '반개',
      'mCong': '혼잡도',
      'mArea': '첫 지역',
      'mTime': '비피크',
      'mStreak': '스트릭',
      'mReattempt': '재수행',
    };

    final multipliers = <String, double>{};
    labels.forEach((key, label) {
      final value = (raw[key] as num?)?.toDouble() ?? 1.0;
      if ((value - 1.0).abs() > 1e-9) multipliers[label] = value;
    });

    final finalExp = (raw['finalExp'] as num?)?.toInt() ?? 0;
    return ExpBreakdown(
      baseExp: (raw['baseExp'] as num?)?.toInt() ?? 0,
      multipliers: multipliers,
      calculated: (raw['calculatedExp'] as num?)?.toInt() ?? finalExp,
      singleCapped: (raw['singleCappedExp'] as num?)?.toInt() ?? finalExp,
      finalExp: finalExp,
    );
  }

  bool get isSingleCapped => calculated > singleCapped;

  bool get isDailyCapped => singleCapped > finalExp;

  /// "기본 110 × 혼잡도 1.4" 형태의 한 줄 요약
  String get summaryLine {
    if (isSpeedAbuse) return '이동 속도 초과로 EXP가 지급되지 않았어요';
    if (multipliers.isEmpty) return '기본 $baseExp';
    final parts = multipliers.entries
        .map((e) => '${e.key} ${_formatMultiplier(e.value)}')
        .join(' × ');
    return '기본 $baseExp × $parts';
  }

  /// 소수 첫째 자리로 떨어지면 "1.4", 아니면 "1.05"처럼 둘째 자리까지 표시한다.
  static String _formatMultiplier(double value) {
    final oneDecimal = (value * 10).roundToDouble() / 10;
    if ((value - oneDecimal).abs() < 1e-9) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }
}

/// 레벨업 정산 결과 (기획서 6c · 초과 EXP는 다음 레벨로 이월)
class LevelUpResult {
  final int previousLevel;
  final int level;

  /// 현재 레벨 구간에 남은 경험치
  final int exp;

  final int gainedExp;

  /// 이번에 새로 해금된 콘텐츠 (기획서 6d)
  final List<String> unlocks;

  /// 서버가 알려준 "다음 레벨까지 필요한 EXP".
  ///
  /// 서버 `level_table`과 클라이언트 [LevelSystem] 테이블이 서로 다르므로,
  /// 서버가 값을 주면 그걸 쓰고 없을 때만 로컬 테이블로 떨어진다.
  final int? nextRequiredExp;

  const LevelUpResult({
    required this.previousLevel,
    required this.level,
    required this.exp,
    required this.gainedExp,
    this.unlocks = const [],
    this.nextRequiredExp,
  });

  /// 서버 `verify` 응답의 `levelInfo`를 옮긴다.
  factory LevelUpResult.fromServer(
    Map<String, dynamic> levelInfo, {
    required int previousLevel,
    required int gainedExp,
  }) {
    final level = (levelInfo['level'] as num?)?.toInt() ?? previousLevel;
    return LevelUpResult(
      previousLevel: previousLevel,
      level: level,
      exp: (levelInfo['expCurrent'] as num?)?.toInt() ?? 0,
      gainedExp: gainedExp,
      nextRequiredExp: (levelInfo['nextRequiredExp'] as num?)?.toInt(),
      // 해금 안내 문구는 클라이언트 기획 데이터라 그대로 쓴다.
      unlocks: [
        for (var l = previousLevel + 1; l <= level; l++)
          ...?ExpService.levelUnlocks[l],
      ],
    );
  }

  bool get leveledUp => level > previousLevel;

  int get requiredExp =>
      nextRequiredExp ?? LevelSystem.getRequiredExpForLevel(level);

  int get expToNextLevel => (requiredExp - exp).clamp(0, requiredExp);

  double get progress {
    final required = requiredExp;
    if (required <= 0) return 1;
    return (exp / required).clamp(0.0, 1.0);
  }
}

/// 기획서 6a~6d의 보상·레벨 규칙을 담은 정산 엔진.
/// 백엔드 `src/services/exp-engine.service.ts`와 동일한 공식을 클라이언트에서 미리 계산한다.
class ExpService {
  const ExpService._();

  /// 단일 퀘스트 상한 (기획서 6b)
  static const int singleQuestCap = 1600;

  /// 1일 획득 상한 · 이월 없음 (기획서 6b)
  static const int dailyCap = 3000;

  static const double crowdLowMultiplier = 1.4;
  static const double crowdHighMultiplier = 0.7;
  static const double newRegionMultiplier = 1.5;
  static const double offPeakMultiplier = 1.2;
  static const double streakPerDay = 0.05;
  static const double streakMaxMultiplier = 1.5;
  static const double repeatMultiplier = 0.3;

  /// 레벨 도달 시 해금되는 콘텐츠 (기획서 6d)
  static const Map<int, List<String>> levelUnlocks = {
    5: ['히든 퀘스트 표시'],
    8: ['난이도 ★★★★ 퀘스트'],
    12: ['칭호 슬롯', '대표 배지 3칸'],
    15: ['난이도 ★★★★★ 이벤트 퀘스트'],
    30: ['시즌 배지', '퀘스트 제안 권한'],
  };

  /// 평일 오전을 비피크로 본다 (기획서 6b)
  static bool isOffPeak(DateTime now) =>
      now.weekday <= DateTime.friday && now.hour >= 6 && now.hour < 12;

  /// 최종 = floor(기본EXP × 혼잡도 × 신규지역 × 시간대 × 스트릭 × 재수행)
  static ExpBreakdown calculate(ExpFactors factors, {required int dailyExpEarned}) {
    if (factors.isSpeedAbuse) {
      return ExpBreakdown(
        baseExp: factors.baseExp,
        multipliers: const {},
        calculated: 0,
        singleCapped: 0,
        finalExp: 0,
        isSpeedAbuse: true,
      );
    }

    final multipliers = <String, double>{};

    if (factors.hasHalfStar) {
      multipliers['반개'] = QuestDifficulty.halfStarMultiplier;
    }
    if (factors.crowdMultiplier != 1.0) {
      multipliers['혼잡도'] = factors.crowdMultiplier;
    }
    if (factors.isNewRegion) {
      multipliers['첫 지역'] = newRegionMultiplier;
    }
    if (factors.isOffPeak) {
      multipliers['비피크'] = offPeakMultiplier;
    }
    final streak = _streakMultiplier(factors.streakDays);
    if (streak != 1.0) {
      multipliers['스트릭'] = streak;
    }
    if (factors.isRepeat) {
      multipliers['재수행'] = repeatMultiplier;
    }

    var value = factors.baseExp.toDouble();
    for (final multiplier in multipliers.values) {
      value *= multiplier;
    }

    final calculated = value.floor();
    final singleCapped = calculated > singleQuestCap ? singleQuestCap : calculated;
    final remainingToday = (dailyCap - dailyExpEarned).clamp(0, dailyCap);
    final finalExp = singleCapped > remainingToday ? remainingToday : singleCapped;

    return ExpBreakdown(
      baseExp: factors.baseExp,
      multipliers: multipliers,
      calculated: calculated,
      singleCapped: singleCapped,
      finalExp: finalExp,
    );
  }

  static double _streakMultiplier(int streakDays) {
    if (streakDays <= 0) return 1.0;
    final raw = 1.0 + streakDays * streakPerDay;
    return raw > streakMaxMultiplier ? streakMaxMultiplier : raw;
  }

  /// 획득 EXP를 반영해 레벨과 잔여 경험치를 다시 계산한다. 초과분은 다음 레벨로 이월.
  static LevelUpResult applyExp({
    required int currentLevel,
    required int currentExp,
    required int gainedExp,
  }) {
    var level = currentLevel;
    var exp = currentExp + gainedExp;
    final unlocks = <String>[];

    while (level < LevelSystem.maxLevel) {
      final required = LevelSystem.getRequiredExpForLevel(level);
      if (required <= 0 || exp < required) break;
      exp -= required;
      level += 1;
      final unlocked = levelUnlocks[level];
      if (unlocked != null) unlocks.addAll(unlocked);
    }

    // Lv30은 레벨 정지 구간이라 경험치를 더 쌓지 않는다 (기획서 6c)
    if (level >= LevelSystem.maxLevel) {
      exp = 0;
    }

    return LevelUpResult(
      previousLevel: currentLevel,
      level: level,
      exp: exp,
      gainedExp: gainedExp,
      unlocks: unlocks,
    );
  }

  /// 퀘스트 하나를 완료했을 때 적용할 배율 조건을 유저·퀘스트 상태에서 뽑아낸다.
  static ExpFactors factorsFor({
    required QuestModel quest,
    required UserModel user,
    required DateTime now,
    bool isSpeedAbuse = false,
  }) {
    return ExpFactors(
      baseExp: quest.difficulty.baseExp,
      hasHalfStar: quest.hasHalfStar,
      crowdMultiplier: quest.crowdMultiplier,
      isNewRegion: !user.hasVisited(quest.regionLabel),
      isOffPeak: isOffPeak(now),
      streakDays: user.streakDaysOn(now),
      isRepeat: user.hasCompleted(quest.id),
      isSpeedAbuse: isSpeedAbuse,
    );
  }
}
