import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/api_exception.dart';
import '../models/quest_model.dart';
import '../services/geo.dart';
import '../services/photo_uploader.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

/// 4b 인증 결과. 방문형 퀘스트는 GPS 도달이 필수이고 사진은 선택이다.
class QuestVerifyResult {
  final bool hasPhoto;

  /// 사진 공개 범위 (기획서 4b · 5d "사진 공개 범위")
  final bool isPhotoPublic;

  /// 업로드가 끝난 사진의 공개 URL.
  final String? photoUrl;

  /// 방금 찍은 사진의 기기 내 경로. 미리보기에만 쓴다.
  final String? localPhotoPath;

  /// 13 기록형 퀘스트에 남긴 한 줄. 다른 유형에서는 비어 있다.
  final String? userText;

  /// 09 퀴즈형 · 10 탐색형에서 고른 답. 채점은 서버가 한다.
  final String? answer;

  const QuestVerifyResult({
    required this.hasPhoto,
    this.isPhotoPublic = true,
    this.photoUrl,
    this.localPhotoPath,
    this.userText,
    this.answer,
  });
}

/// 4b · 방문 인증
class QuestVerifyScreen extends StatefulWidget {
  final QuestModel quest;
  final QuestSpot spot;
  final double accuracyMeters;

  const QuestVerifyScreen({
    super.key,
    required this.quest,
    required this.spot,
    required this.accuracyMeters,
  });

  @override
  State<QuestVerifyScreen> createState() => _QuestVerifyScreenState();
}

class _QuestVerifyScreenState extends State<QuestVerifyScreen> {
  bool _isPublic = true;
  XFile? _photo;
  bool _isPicking = false;

  /// 13 기록형에서만 쓰는 한 줄 입력.
  final TextEditingController _noteController = TextEditingController();

  /// 이 퀘스트가 기록형인가. 기록형은 한 줄을 남겨야 인증이 성립한다
  /// (서버도 `userText` 없이는 거절한다).
  bool get _needsNote => widget.quest.questType == 'RECORD';

  String? get _noteOrNull {
    final t = _noteController.text.trim();
    return t.isEmpty ? null : t;
  }

  /// 09 퀴즈형 · 10 탐색형에서 고른 선택지.
  String? _pickedAnswer;

  /// 문제와 선택지가 다 있어야 풀 수 있다. 하나라도 비면 그냥 방문형처럼 다룬다 —
  /// 문제를 못 그리는데 정답을 요구하면 인증이 영영 막힌다.
  bool get _needsAnswer =>
      (widget.quest.questType == 'QUIZ' ||
          widget.quest.questType == 'EXPLORATION') &&
      widget.quest.quizQuestion != null &&
      widget.quest.quizOptions.length >= 2;

  /// S3 업로드가 도는 중. 이 동안 버튼을 잠근다.
  bool _isUploading = false;

  // 💡 ImagePicker 인스턴스를 상태 객체에서 싱글톤처럼 유지하여 메모리 누수 및 크래시 방지
  final ImagePicker _picker = ImagePicker();

  /// 목업 퀘스트는 서버에 없어서(백엔드 `Quest.id`는 Int) presign을 받을 수 없다.
  bool get _isRemoteQuest => int.tryParse(widget.quest.id) != null;

  Future<void> _pickPhoto({required bool fromGallery}) async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      // 여기서 이미 장변 1600px · 품질 80으로 줄여서 받는다.
      // 네이티브 리사이즈라 순수 Dart로 다시 손대는 것보다 훨씬 빠르다.
      final picked = await _picker.pickImage(
        source: fromGallery ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (picked != null && mounted) {
        setState(() {
          _photo = picked;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진을 가져오지 못했어요. 위치만으로도 완료할 수 있어요. ($e)')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  /// 사진을 올리고 그 공개 주소와 함께 4a로 돌아간다.
  ///
  /// **업로드 실패가 퀘스트 완료를 막지 않는다.** 사진은 선택 항목인데
  /// 현장까지 가서 인증을 못 하면 손해가 너무 크다. 실패하면 사진만 빼고
  /// 계속할지 물어본다.
  Future<void> _completeWithPhoto() async {
    final photo = _photo;
    if (photo == null || _isUploading) return;

    if (!_isRemoteQuest) {
      // 목업 퀘스트 — 올릴 곳이 없다. 미리보기 경로만 들고 돌아간다.
      Navigator.of(context).pop(QuestVerifyResult(
        hasPhoto: true,
        isPhotoPublic: _isPublic,
        localPhotoPath: photo.path,
        userText: _noteOrNull,
        answer: _pickedAnswer,
      ));
      return;
    }

    setState(() => _isUploading = true);

    String? publicUrl;
    try {
      publicUrl = await PhotoUploader.upload(
        questId: widget.quest.id,
        file: File(photo.path),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);

      final proceed = await _askProceedWithoutPhoto(e);
      if (proceed != true || !mounted) return;

      Navigator.of(context).pop(QuestVerifyResult(
        hasPhoto: false,
        isPhotoPublic: _isPublic,
        localPhotoPath: photo.path,
        userText: _noteOrNull,
        answer: _pickedAnswer,
      ));
      return;
    }

    if (!mounted) return;
    setState(() => _isUploading = false);

    Navigator.of(context).pop(QuestVerifyResult(
      hasPhoto: true,
      isPhotoPublic: _isPublic,
      photoUrl: publicUrl,
      localPhotoPath: photo.path,
      userText: _noteOrNull,
      answer: _pickedAnswer,
    ));
  }

  Future<bool?> _askProceedWithoutPhoto(ApiException e) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.panel),
        title: const Text('사진을 올리지 못했어요', style: AppType.h2),
        content: Text(
          e.isNetwork
              ? '네트워크가 불안정한 것 같아요. 사진 없이 위치만으로 완료할까요?\n'
                  '(다시 시도해도 됩니다)'
              : '사진 없이 위치만으로 완료할까요?\n(다시 시도해도 됩니다)',
          style: AppType.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('다시 시도'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('사진 없이 완료'),
          ),
        ],
      ),
    );
  }

  void _completeWithoutPhoto() {
    Navigator.of(context).pop(QuestVerifyResult(
      hasPhoto: false,
      userText: _noteOrNull,
      answer: _pickedAnswer,
    ));
  }

  /// 찍기 전에는 안내를, 찍은 뒤에는 실제 사진을 보여준다.
  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Widget _buildPhotoArea() {
    final photo = _photo;
    if (photo == null) {
      return NoteBox(
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera_outlined,
                size: 36, color: AppColors.textDisabled),
            const SizedBox(height: 10),
            Text(
              '이곳의 사진을 한 장 남겨보세요',
              style: AppType.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '사진 없이 위치만으로도 완료할 수 있어요',
              style: AppType.caption.copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final imageFile = File(photo.path);

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.file(
            imageFile,
            fit: BoxFit.cover,
            // 💡 파일 읽기 실패 시 화면이 튕기는 현상 예방
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: AppColors.surface,
                alignment: Alignment.center,
                child: const Text(
                  '이미지를 불러올 수 없습니다.',
                  style: TextStyle(color: AppColors.textDisabled),
                ),
              );
            },
          ),
        ),
        Positioned(
          right: AppSpacing.sm,
          bottom: AppSpacing.sm,
          child: FloatingSurfaceButton(
            icon: Icons.refresh_rounded,
            onTap: _isPicking ? null : () => _pickPhoto(fromGallery: false),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.gutter,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const TagChip(
                          label: '✓ 위치 확인됨',
                          isSelected: true,
                          fontSize: 11,
                          accent: AppColors.jade500,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '오차 ${widget.accuracyMeters.round()}m · 최대 ${Geo.maxAccuracyMeters.round()}m',
                          style: AppType.numeric.copyWith(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(widget.spot.name, style: AppType.h1),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${widget.quest.title} · ${widget.quest.completionCriteria}',
                      style: AppType.caption,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_needsAnswer)
                      Expanded(child: SingleChildScrollView(child: _buildQuiz()))
                    else
                      Expanded(child: _buildPhotoArea()),
                    if (_needsNote) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _buildNoteField(),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    // 퀴즈형은 사진을 받지 않는다. 안내와 갤러리 버튼을 남겨 두면
                    // "답도 고르고 사진도 찍어야 하나" 하고 손이 멈춘다.
                    if (!_needsAnswer) ...[
                      _buildPhotoNotice(),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    Row(
                      children: [
                        if (!_needsAnswer) ...[
                          Expanded(
                            child: SecondaryButton(
                              label: '갤러리',
                              onTap: _isPicking || _isUploading
                                  ? null
                                  : () => _pickPhoto(fromGallery: true),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Expanded(
                          flex: 2,
                          child: PrimaryButton(
                            label: _isUploading
                                ? '사진 올리는 중…'
                                : _needsAnswer
                                    ? '이 답으로 완료'
                                    : _photo == null
                                        ? '촬영하기'
                                        : '이 사진으로 완료',
                            enabled: !_isPicking &&
                                !_isUploading &&
                                (!_needsNote || _noteOrNull != null) &&
                                (!_needsAnswer || _pickedAnswer != null),
                            onTap: _needsAnswer
                                ? _completeWithoutPhoto
                                : _photo == null
                                    ? () => _pickPhoto(fromGallery: false)
                                    : _completeWithPhoto,
                          ),
                        ),
                      ],
                    ),
                    // 사진형은 서버가 사진을 요구하므로 이 지름길을 열면
                    // 눌러 놓고 400을 맞는다. 퀴즈형은 사진 자체가 없다.
                    if (!_needsAnswer &&
                        widget.quest.questType != 'PHOTO_SINGLE') ...[
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: GestureDetector(
                          onTap: _isUploading ? null : _completeWithoutPhoto,
                          child:
                              Text('사진 없이 위치만으로 완료', style: AppType.caption),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: AppSurface.paper,
        boxShadow: AppElevation.e1,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Text('✕ 닫기',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showHelp,
            child: const Text('도움말',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ),
        ],
      ),
    );
  }

  /// 09 퀴즈형 · 10 탐색형의 문제와 선택지.
  ///
  /// 정답은 앱에 내려오지 않는다. 고른 값을 그대로 인증 요청에 실어 보내고,
  /// 맞았는지는 서버가 판정해 `WRONG_ANSWER`로 돌려준다. 앱에서 채점하면
  /// 응답만 들여다봐도 정답을 알 수 있다.
  Widget _buildQuiz() {
    final options = widget.quest.quizOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NoteBox.text(widget.quest.quizQuestion ?? ''),
        const SizedBox(height: AppSpacing.lg),
        for (final option in options) ...[
          _QuizOption(
            label: option,
            isSelected: _pickedAnswer == option,
            onTap: () => setState(() => _pickedAnswer = option),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  /// 13 기록형의 한 줄 입력.
  ///
  /// 기록형은 "무엇을 느꼈는지 남기는 것"이 인증의 알맹이다. 입력 자리가 없으면
  /// 걸어가기만 해도 완료되어 유형이 이름뿐이 된다 — 서버도 이 값 없이는 거절한다.
  Widget _buildNoteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('한 줄 남기기', style: AppType.h3),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            gradient: AppSurface.sunken,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.ink200),
          ),
          child: TextField(
            controller: _noteController,
            minLines: 2,
            maxLines: 3,
            maxLength: 200,
            style: AppType.body,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: widget.quest.summary.isEmpty
                  ? '여기서 느낀 것을 한 줄로'
                  : '여기서 느낀 것을 한 줄로',
              hintStyle: AppType.body.copyWith(color: AppColors.textDisabled),
              border: InputBorder.none,
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoNotice() {
    return SolidBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현장 사진 1장을 찍어 방문을 남겨주세요',
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('공개 범위',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              const SizedBox(width: 8),
              TagChip(
                label: '공개',
                isSelected: _isPublic,
                fontSize: 11,
                onTap: () => setState(() => _isPublic = true),
              ),
              const SizedBox(width: 6),
              TagChip(
                label: '비공개',
                isSelected: !_isPublic,
                fontSize: 11,
                onTap: () => setState(() => _isPublic = false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showHelp() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '방문 인증 안내',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                '· 방문형 퀘스트는 GPS 도달이 필수이고 사진은 선택입니다.\n'
                '· 달성 기준 : ${widget.quest.completionCriteria}\n'
                '· GPS 정확도가 ${Geo.maxAccuracyMeters.round()}m를 넘으면 재측정을 요구합니다.\n'
                '· 이동 속도가 ${Geo.abuseSpeedKmh.round()}km/h를 넘은 구간의 도달은 EXP가 지급되지 않습니다.',
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/// 퀴즈 선택지 한 칸.
///
/// 라디오 버튼 대신 카드로 만든 이유: 현장에서 한 손으로, 장갑을 끼고도 누를 수
/// 있어야 한다. 작은 원을 정확히 겨누게 하면 그 자리에서 몇 번씩 헛누른다.
class _QuizOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuizOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.quest50 : AppColors.ink0,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isSelected ? AppColors.quest500 : AppColors.ink200,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: isSelected ? AppColors.quest500 : AppColors.ink300,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppType.body.copyWith(
                  color: isSelected
                      ? AppColors.quest700
                      : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
