import 'package:flutter/material.dart';

import '../models/quest_model.dart';
import '../services/geo.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

/// 4b 인증 결과. 방문형 퀘스트는 GPS 도달이 필수이고 사진은 선택이다.
class QuestVerifyResult {
  final bool hasPhoto;

  /// 사진 공개 범위 (기획서 4b · 5d "사진 공개 범위")
  final bool isPhotoPublic;

  const QuestVerifyResult({required this.hasPhoto, this.isPhotoPublic = true});
}

/// 4b · 방문 인증
///
/// 카메라 플러그인이 아직 없어 뷰파인더는 placeholder로 두고,
/// "촬영하고 완료"는 사진을 남긴 것으로만 표시한다.
/// 실제 촬영을 붙일 때 [_capture]만 image_picker 호출로 바꾸면 된다.
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

  void _capture({required bool fromGallery}) {
    // TODO: image_picker 도입 시 실제 촬영/선택 결과로 교체
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(fromGallery ? '갤러리 연동은 준비 중이라 사진을 남긴 것으로 처리했어요.' : '사진을 남겼어요.'),
      ),
    );
    Navigator.of(context).pop(QuestVerifyResult(hasPhoto: true, isPhotoPublic: _isPublic));
  }

  void _completeWithoutPhoto() {
    Navigator.of(context).pop(const QuestVerifyResult(hasPhoto: false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const TagChip(label: '✓ 위치 확인됨', isSelected: true, fontSize: 11),
                        const SizedBox(width: 8),
                        Text(
                          '오차 ${widget.accuracyMeters.round()}m · 최대 ${Geo.maxAccuracyMeters.round()}m',
                          style: const TextStyle(fontSize: 11, color: AppColors.subText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.spot.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.quest.title} · ${widget.quest.completionCriteria}',
                      style: const TextStyle(fontSize: 12, color: AppColors.subText),
                    ),
                    const SizedBox(height: 12),
                    const Expanded(
                      child: NoteBox(
                        alignment: Alignment.center,
                        child: Text(
                          '카메라 뷰파인더\nplaceholder',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.noteText, height: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPhotoNotice(),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: '갤러리',
                            onTap: () => _capture(fromGallery: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: PrimaryButton(
                            label: '촬영하고 완료',
                            onTap: () => _capture(fromGallery: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: GestureDetector(
                        onTap: _completeWithoutPhoto,
                        child: const Text(
                          '사진 없이 위치만으로 완료',
                          style: TextStyle(fontSize: 12, color: AppColors.subText),
                        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.darkBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Text('✕ 닫기', style: TextStyle(fontSize: 12, color: AppColors.subText)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showHelp,
            child: const Text('도움말', style: TextStyle(fontSize: 12, color: AppColors.subText)),
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
            style: TextStyle(fontSize: 13, color: AppColors.darkBorder),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('공개 범위', style: TextStyle(fontSize: 12, color: AppColors.subText)),
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
      backgroundColor: AppColors.bgCream,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '방문 인증 안내',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
              ),
              const SizedBox(height: 10),
              Text(
                '· 방문형 퀘스트는 GPS 도달이 필수이고 사진은 선택입니다.\n'
                '· 달성 기준 : ${widget.quest.completionCriteria}\n'
                '· GPS 정확도가 ${Geo.maxAccuracyMeters.round()}m를 넘으면 재측정을 요구합니다.\n'
                '· 이동 속도가 ${Geo.abuseSpeedKmh.round()}km/h를 넘은 구간의 도달은 EXP가 지급되지 않습니다.',
                style: const TextStyle(fontSize: 13, color: AppColors.noteText, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
