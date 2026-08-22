import 'package:flutter/material.dart';

import '../data/badge_api.dart';
import '../models/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';
import '../widgets/badge_widgets.dart';

/// 5b · 배지 상세
///
/// 희소도·랭킹은 넣지 않는다 — 와이어프레임이 명시적으로 뺐다.
/// **어떤 퀘스트로 채웠는지 이력만** 보여준다. 그게 이 앱의 태도다.
class BadgeDetailScreen extends StatefulWidget {
  final int badgeId;

  const BadgeDetailScreen({super.key, required this.badgeId});

  @override
  State<BadgeDetailScreen> createState() => _BadgeDetailScreenState();
}

class _BadgeDetailScreenState extends State<BadgeDetailScreen> {
  BadgeDetail? _detail;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  /// 대표 배지를 바꿨으면 목록 화면이 테두리를 다시 그려야 한다.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await BadgeApi.detail(widget.badgeId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.displayMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFeatured() async {
    final detail = _detail;
    if (detail == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final current = await BadgeApi.featured();
      final ids = current.map((f) => f.badgeId).toList();

      if (detail.isFeatured) {
        ids.remove(detail.badgeId);
      } else {
        if (ids.length >= 3) {
          // 서버도 막지만, 먼저 물어보는 편이 친절하다.
          if (!mounted) return;
          final replace = await _askWhichToReplace(current);
          if (replace == null) {
            setState(() => _isSaving = false);
            return;
          }
          ids.remove(replace);
        }
        ids.add(detail.badgeId);
      }

      await BadgeApi.setFeatured(ids);
      _changed = true;
      await _load();
      if (mounted) {
        _toast(detail.isFeatured ? '대표 배지에서 내렸어요.' : '대표 배지로 올렸어요.');
      }
    } on ApiException catch (e) {
      if (mounted) _toast(e.displayMessage);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<int?> _askWhichToReplace(List<FeaturedBadge> current) {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.panel),
        title: const Text('대표 배지는 3개까지예요', style: AppType.h2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('무엇을 내릴까요?', style: AppType.bodyMuted),
            const SizedBox(height: AppSpacing.md),
            for (final f in current)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: BadgeArt(artKey: f.artKey, size: 34),
                title: Text(f.name, style: AppType.body),
                onTap: () => Navigator.of(dialogContext).pop(f.badgeId),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.sm,
                    top: AppSpacing.sm,
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(_changed),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.textSecondary,
                    tooltip: '배지 목록으로',
                  ),
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.quest500,
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: NoteBox.text(error),
      );
    }

    final detail = _detail!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: BadgeArt(
              artKey: detail.artKey,
              size: 148,
              dimmed: !detail.achieved,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(detail.name, style: AppType.display.copyWith(fontSize: 24),
              textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(detail.description, style: AppType.bodyMuted,
              textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xl),

          // 진행 상황 — 획득이면 jade, 아직이면 기본색
          AppCard(
            color: detail.achieved ? AppColors.jade50 : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.achieved
                      ? '진행 ${detail.progress} / ${detail.threshold} · 완료'
                      : '진행 ${detail.progress} / ${detail.threshold}',
                  style: AppType.h3.copyWith(
                    color: detail.achieved
                        ? AppColors.jade700
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ProgressBar(
                  value: detail.ratio,
                  accent: detail.achieved ? AppColors.jade500 : null,
                ),
                if (detail.achievedAt != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '획득 ${_formatDate(detail.achievedAt!)}',
                    style: AppType.caption.copyWith(color: AppColors.jade700),
                  ),
                ],
              ],
            ),
          ),

          if (detail.history.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: '달성한 퀘스트'),
            const SizedBox(height: AppSpacing.md),
            for (final entry in detail.history)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.questTitle, style: AppType.h3),
                            const SizedBox(height: 2),
                            Text(
                              [
                                _formatDate(entry.date),
                                if (entry.placeName != null) entry.placeName!,
                              ].join(' · '),
                              style: AppType.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          const SizedBox(height: AppSpacing.xl),
          if (detail.achieved)
            PrimaryButton(
              label: detail.isFeatured ? '대표 배지에서 내리기' : '대표 배지로 설정',
              enabled: !_isSaving,
              onTap: _toggleFeatured,
            )
          else
            NoteBox.text('아직 획득하지 않았어요. 조건을 채우면 대표 배지로 세울 수 있어요.'),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')}';
}
