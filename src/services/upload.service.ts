import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const region = process.env.AWS_REGION || 'ap-northeast-2';
const bucketName = process.env.AWS_S3_BUCKET_NAME || process.env.AWS_S3_BUCKET || 'localquest-bucket';

const s3Client = new S3Client({ region });

/**
 * 허용하는 확장자. **화이트리스트로 둔다.**
 *
 * 예전에는 클라이언트가 준 `ext`를 그대로 S3 키와 `ContentType`에 넣었다.
 * `../`이 섞이면 버킷 안 다른 경로를 가리킬 수 있고, `html`이 오면
 * `image/html`이 붙은 채로 올라가 브라우저가 열어 버린다.
 */
const ALLOWED_EXTENSIONS: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  heic: "image/heic",
  webp: "image/webp",
};

export function normalizeExtension(raw: unknown): string {
  const ext = String(raw ?? "").trim().toLowerCase().replace(/^\./, "");
  return ext in ALLOWED_EXTENSIONS ? ext : "jpg";
}

export async function getPresignedUploadUrl(
  userId: number,
  questId: number,
  rawExt: string
) {
  const ext = normalizeExtension(rawExt);
  const fileKey = `quests/${questId}/users/${userId}/${Date.now()}.${ext}`;
  const command = new PutObjectCommand({
    Bucket: bucketName,
    Key: fileKey,
    ContentType: ALLOWED_EXTENSIONS[ext]
  });

  // 5분(300초) 유효기간 설정
  const uploadUrl = await getSignedUrl(s3Client, command, { expiresIn: 300 });

  return {
    uploadUrl,
    fileKey,
    publicUrl: `https://${bucketName}.s3.${region}.amazonaws.com/${fileKey}`
  };
}

export function validatePhotoMetadata(
  photoExifTimestamp: Date,
  verificationTimestamp: Date
): boolean {
  // 촬영 시각이 인증 시각 기준 5분(300초) 이내여야 함
  const diffInSeconds = Math.abs(
    (verificationTimestamp.getTime() - photoExifTimestamp.getTime()) / 1000
  );
  return diffInSeconds <= 300;
}