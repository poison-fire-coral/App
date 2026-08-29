import 'package:flutter/material.dart';

import '../data/terms.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import 'app_widgets.dart';

/// 약관 문서 한 편을 띄운다.
///
/// 가입(1c)과 설정(5d)이 같은 것을 부른다. 지금은 문서가 없어서 요약과
/// "준비 중" 안내만 나오지만, [TermsDocument.url]이 채워지면 이 함수 하나만
/// 고치면 두 화면이 함께 진짜 문서를 보게 된다.
Future<void> showTermsDocument(BuildContext context, TermsDocument doc) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: GrabHandle()),
            const SizedBox(height: AppSpacing.md),
            Text(doc.title, style: AppType.h1),
            const SizedBox(height: AppSpacing.sm),
            Text(doc.summary, style: AppType.bodyMuted),
            const SizedBox(height: AppSpacing.lg),
            NoteBox(
              child: Text(
                doc.hasDocument
                    // url이 있는데도 여기까지 왔다면 브라우저를 못 연 것이다.
                    // 주소를 글자로라도 보여줘야 사용자가 옮겨 적을 수 있다.
                    ? '전문은 아래 주소에서 볼 수 있어요.\n${doc.url}'
                    : '전문은 아직 준비 중이에요. 정식 출시 전까지 이 화면에서 볼 수 있게 됩니다.',
                style: AppType.bodyMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: '닫기',
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 동의 항목 한 줄 — 체크박스 · [필수]/[선택] 표시 · 제목 · "보기".
class TermsConsentRow extends StatelessWidget {
  final TermsDocument doc;
  final bool value;
  final ValueChanged<bool> onChanged;

  const TermsConsentRow({
    super.key,
    required this.doc,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => onChanged(!value),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  _CheckMark(checked: value),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    doc.isRequired ? '[필수] ' : '[선택] ',
                    style: AppType.caption.copyWith(
                      color: doc.isRequired
                          ? AppColors.quest500
                          : AppColors.textTertiary,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      doc.title,
                      style: AppType.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: () => showTermsDocument(context, doc),
          child: Text(
            '보기',
            style: AppType.caption.copyWith(
              color: AppColors.textTertiary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

/// "전체 동의" 한 줄. 선택 항목까지 포함해 한 번에 켜고 끈다.
class TermsAgreeAllRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const TermsAgreeAllRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            _CheckMark(checked: value, size: 24),
            const SizedBox(width: AppSpacing.md),
            Text(
              '아래 내용에 모두 동의합니다',
              style: AppType.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// 동그란 체크 표시. Checkbox 기본 위젯은 머티리얼 파랑이 그대로 나와
/// 나머지 화면과 색이 어긋난다.
class _CheckMark extends StatelessWidget {
  final bool checked;
  final double size;

  const _CheckMark({required this.checked, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? AppColors.quest500 : Colors.transparent,
        border: Border.all(
          color: checked ? AppColors.quest500 : AppColors.hairlineStrong,
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.check_rounded,
        size: size * 0.7,
        color: checked ? AppColors.textOnDark : AppColors.hairlineStrong,
      ),
    );
  }
}
