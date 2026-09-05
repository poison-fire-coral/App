import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/terms.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import 'app_widgets.dart';

/// 문서를 브라우저에서 연다. 열지 못했으면 false.
///
/// 인앱 웹뷰가 아니라 바깥 브라우저를 쓴다 — 약관은 주소가 보여야 하는 문서다.
/// 어디서 온 글인지 확인할 수 없으면 읽는 의미가 절반은 사라진다.
Future<bool> _openDocument(TermsDocument doc) async {
  final url = doc.url;
  if (url == null || url.isEmpty) return false;
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// 약관 문서 한 편을 띄운다.
///
/// 가입(1c)과 설정(5d)이 같은 것을 부른다. 요약을 보여 주고, 전문은 브라우저로
/// 넘긴다 — 본문은 서버가 들고 있어서(`legal.router.ts`) 앱을 새로 배포하지
/// 않고도 고칠 수 있다.
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
            if (!doc.hasDocument) ...[
              NoteBox(
                child: Text(
                  '전문은 아직 준비 중이에요. 정식 출시 전까지 이 화면에서 볼 수 있게 됩니다.',
                  style: AppType.bodyMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ] else ...[
              PrimaryButton(
                label: '전문 보기',
                onTap: () async {
                  final opened = await _openDocument(doc);
                  if (!sheetContext.mounted) return;
                  if (!opened) {
                    // 브라우저를 못 열었으면 주소라도 보여준다 — 옮겨 적을 수 있다.
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      SnackBar(content: Text('브라우저를 열지 못했어요. ${doc.url}')),
                    );
                    return;
                  }
                  Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SecondaryButton(
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
                  // [필수]와 제목을 한 덩어리로 그린다.
                  //
                  // 예전에는 둘이 형제 위젯이라 [필수] 쪽이 줄어들 줄 몰랐고,
                  // 글자 크기를 키운 기기에서 폭을 1px 넘겼다. 한 문장으로 두면
                  // 넘칠 때 뒤에서부터 잘려 "[필수] 위치기반서비스…"로 읽힌다.
                  Flexible(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: doc.isRequired ? '[필수] ' : '[선택] ',
                          style: AppType.caption.copyWith(
                            color: doc.isRequired
                                ? AppColors.quest500
                                : AppColors.textTertiary,
                          ),
                        ),
                        TextSpan(text: doc.title, style: AppType.body),
                      ]),
                      maxLines: 1,
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
            Flexible(
              child: Text(
                '아래 내용에 모두 동의합니다',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body.copyWith(fontWeight: FontWeight.w600),
              ),
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
