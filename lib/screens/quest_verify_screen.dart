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

  const QuestVerifyResult({
    required this.hasPhoto,
    this.isPhotoPublic = true,
    this.photoUrl,
    this.localPhotoPath,
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
    Navigator.of(context).pop(const QuestVerifyResult(hasPhoto: false));
  }

  /// 찍기 전에는 안내를, 찍은 뒤에는 실제 사진을 보여준다.
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
                    Expanded(child: _buildPhotoArea()),
                    const SizedBox(height: AppSpacing.lg),
                    _buildPhotoNotice(),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: '갤러리',
                            onTap: _isPicking || _isUploading
                                ? null
                                : () => _pickPhoto(fromGallery: true),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 2,
                          child: PrimaryButton(
                            label: _isUploading
                                ? '사진 올리는 중…'
                                : _photo == null
                                    ? '촬영하기'
                                    : '이 사진으로 완료',
                            enabled: !_isPicking && !_isUploading,
                            onTap: _photo == null
                                ? () => _pickPhoto(fromGallery: false)
                                : _completeWithPhoto,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: GestureDetector(
                        onTap: _isUploading ? null : _completeWithoutPhoto,
                        child: Text('사진 없이 위치만으로 완료', style: AppType.caption),
                      ),
                    ),
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