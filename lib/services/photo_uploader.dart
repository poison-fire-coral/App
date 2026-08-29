import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/quest_repository.dart';
import '../models/api_exception.dart';

/// 서버가 발급한 presigned URL 한 벌.
class PresignedUpload {
  /// 여기로 파일 바이트를 PUT한다. 5분 뒤 만료된다.
  final String uploadUrl;

  /// 버킷 안 경로. 디버깅용.
  final String fileKey;

  /// 업로드가 끝난 뒤 `verify`에 실어 보낼 주소.
  final String publicUrl;

  const PresignedUpload({
    required this.uploadUrl,
    required this.fileKey,
    required this.publicUrl,
  });

  factory PresignedUpload.fromJson(Map<String, dynamic> json) =>
      PresignedUpload(
        uploadUrl: json['uploadUrl'] as String,
        fileKey: (json['fileKey'] as String?) ?? '',
        publicUrl: json['publicUrl'] as String,
      );
}

/// 인증 사진을 S3에 올린다.
///
/// **흐름**
/// ```
/// POST /quests/:id/upload-url   → presigned URL
/// PUT  <presigned URL>          → 사진 바이트 (우리 서버를 거치지 않는다)
/// POST /quests/:id/verify       → publicUrl 전달
/// ```
///
/// **압축은 어디서 하나**
/// `image_picker`가 `maxWidth: 1600, imageQuality: 80`으로 이미 줄여서 준다.
/// 순수 Dart로 다시 디코딩·리사이즈하면 큰 사진에서 UI가 멈추므로 하지 않는다.
///
/// **EXIF 촬영 시각은 왜 안 보내나**
/// 두 가지가 겹친다. 첫째, `image_picker`의 리사이즈가 EXIF를 벗겨 낸다.
/// 둘째, 서버 `verify`의 DTO에 촬영 시각을 받을 자리가 없고,
/// `upload.service.ts`의 `validatePhotoMetadata`는 어디서도 호출되지 않는다.
/// 지금 보내 봐야 버려진다 — 서버가 필드를 받게 되면(체크리스트 17번 BE 몫)
/// 그때 원본 바이트를 유지하는 경로와 함께 붙인다.
class PhotoUploader {
  const PhotoUploader._();

  /// 업로드 한 건의 제한 시간. 현장 LTE에서 1600px JPEG(≈300KB)면 넉넉하다.
  static const Duration timeout = Duration(seconds: 45);

  /// 파일 하나를 올리고 공개 주소를 돌려준다.
  ///
  /// 실패하면 [ApiException]을 던진다. **인증 자체를 막지는 않는다** —
  /// 부르는 쪽(4b)이 잡아서 "사진 없이 완료"로 빠져나갈 수 있게 한다.
  /// 사진은 선택 항목인데 업로드 실패로 퀘스트를 못 끝내면 손해가 크다.
  static Future<String> upload({
    required String questId,
    required File file,
  }) async {
    final ext = _extensionOf(file.path);
    final presigned = await QuestRepository.requestUploadUrl(
      questId: questId,
      extension: ext,
    );

    final bytes = await file.readAsBytes();

    final http.Response response;
    try {
      response = await http
          .put(
            Uri.parse(presigned.uploadUrl),
            // presigned URL은 서명할 때 쓴 Content-Type과 **정확히** 같아야 한다.
            // 서버가 `image/${ext}`로 서명하므로(`upload.service.ts:18`)
            // 여기서도 같은 문자열을 만든다. 다르면 S3가 403을 준다.
            headers: {'Content-Type': 'image/$ext'},
            body: bytes,
          )
          .timeout(timeout);
    } catch (e) {
      throw ApiException.fromNetworkFailure(e);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('S3 업로드 실패 ${response.statusCode}: ${response.body}');
      throw ApiException(
        code: 'UPLOAD_FAILED',
        message: '사진을 올리지 못했어요.',
        statusCode: response.statusCode,
      );
    }

    return presigned.publicUrl;
  }

  /// 확장자를 서버·S3가 이해하는 형태로 고른다.
  ///
  /// `image_picker`는 카메라에서 `.jpg`, 갤러리에서 원본 확장자를 준다.
  /// `jpeg`는 `jpg`로 눌러 두 경로가 같은 Content-Type을 쓰게 한다.
  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';

    final raw = path.substring(dot + 1).toLowerCase();
    return switch (raw) {
      'jpeg' => 'jpg',
      'jpg' || 'png' || 'webp' || 'heic' => raw,
      // 모르는 확장자는 jpg로 본다. 서명과 실제 타입이 어긋나는 것보다,
      // 둘 다 jpg라고 우기는 편이 업로드는 성공한다.
      _ => 'jpg',
    };
  }
}
