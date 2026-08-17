import 'package:flutter/material.dart';

import '../services/exp_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

/// 4d · 레벨업
///
/// 레벨은 랭킹이 아니라 콘텐츠 해금 게이트다 (기획서 6d).
class LevelUpScreen extends StatelessWidget {
  final LevelUpResult result;

  const LevelUpScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgCream,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              children: [
                const Spacer(),
                const Text(
                  'LEVEL UP',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryRed,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                _buildLevelTransition(),
                const SizedBox(height: 18),
                SizedBox(
                  width: 230,
                  child: ProgressBar(value: result.progress),
                ),
                const SizedBox(height: 8),
                Text(
                  '다음 레벨까지 ${result.expToNextLevel} EXP',
                  style: const TextStyle(fontSize: 13, color: AppColors.subText),
                ),
                const SizedBox(height: 20),
                if (result.unlocks.isNotEmpty) _buildUnlockCard(),
                const Spacer(),
                PrimaryButton(
                  label: '계속하기',
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelTransition() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 62,
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.darkBorder, width: 1.5),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            'Lv.${result.previousLevel}',
            style: const TextStyle(fontSize: 14, color: AppColors.darkBorder),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('→', style: TextStyle(fontSize: 16, color: AppColors.darkBorder)),
        ),
        Container(
          width: 62,
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryRed,
            border: Border.all(color: AppColors.darkBorder, width: 1.5),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(
            'Lv.${result.level}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildUnlockCard() {
    return SizedBox(
      width: 240,
      child: SolidBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '해금됨',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
            ),
            const SizedBox(height: 6),
            for (final unlock in result.unlocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '· $unlock',
                  style: const TextStyle(fontSize: 13, color: AppColors.darkBorder, height: 1.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
