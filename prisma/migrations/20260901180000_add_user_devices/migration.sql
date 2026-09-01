-- 체크리스트 24번 — 푸시 알림 기기 토큰 저장소.
--
-- prisma migrate diff 로 생성했다. DB 없이 만들었으므로 적용은
--   npx prisma migrate deploy
-- 로 한다 (migrate dev 는 섀도 DB가 필요하다).

-- CreateTable
CREATE TABLE "user_devices" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "fcm_token" TEXT NOT NULL,
    "platform" TEXT,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "user_devices_fcm_token_key" ON "user_devices"("fcm_token");

-- CreateIndex
CREATE INDEX "user_devices_user_id_idx" ON "user_devices"("user_id");

-- AddForeignKey
ALTER TABLE "user_devices" ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

