import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const region = process.env.AWS_REGION || 'ap-northeast-2';
const bucketName = process.env.AWS_S3_BUCKET_NAME || process.env.AWS_S3_BUCKET || 'localquest-bucket';

const s3Client = new S3Client({ region });

export async function getPresignedUploadUrl(
  userId: number,
  questId: number,
  ext: string
) {
  const fileKey = `quests/${questId}/users/${userId}/${Date.now()}.${ext}`;
  const command = new PutObjectCommand({
    Bucket: bucketName,
    Key: fileKey,
    ContentType: `image/${ext}`
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