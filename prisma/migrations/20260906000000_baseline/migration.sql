-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "QuestType" AS ENUM ('VISIT', 'TIME_WINDOW', 'PHOTO_SINGLE', 'PHOTO_COLLECT', 'QUIZ', 'EXPLORATION', 'RECORD');

-- CreateTable
CREATE TABLE "users" (
    "id" SERIAL NOT NULL,
    "provider" TEXT NOT NULL,
    "provider_uid" TEXT NOT NULL,
    "email" TEXT,
    "nickname" TEXT NOT NULL,
    "avatar_id" TEXT,
    "home_region" TEXT,
    "activity_level" TEXT,
    "refresh_token" TEXT,
    "terms_agreed" BOOLEAN NOT NULL DEFAULT false,
    "terms_agreed_at" TIMESTAMP(3),
    "terms_version" TEXT,
    "marketing_agreed" BOOLEAN NOT NULL DEFAULT false,
    "marketing_agreed_at" TIMESTAMP(3),
    "level" INTEGER NOT NULL DEFAULT 1,
    "exp_total" INTEGER NOT NULL DEFAULT 0,
    "exp_current" INTEGER NOT NULL DEFAULT 0,
    "daily_exp_earned" INTEGER NOT NULL DEFAULT 0,
    "last_exp_reset_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "streak_days" INTEGER NOT NULL DEFAULT 0,
    "last_active_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

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

-- CreateTable
CREATE TABLE "user_keywords" (
    "user_id" INTEGER NOT NULL,
    "keyword_id" TEXT NOT NULL,

    CONSTRAINT "user_keywords_pkey" PRIMARY KEY ("user_id","keyword_id")
);

-- CreateTable
CREATE TABLE "places" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "region_code" TEXT NOT NULL,
    "address" TEXT,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "image_url" TEXT,
    "congestion_score" INTEGER NOT NULL DEFAULT 1,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "places_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quests" (
    "id" SERIAL NOT NULL,
    "place_id" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "story" TEXT,
    "quest_type" "QuestType" NOT NULL DEFAULT 'VISIT',
    "difficulty" INTEGER NOT NULL DEFAULT 1,
    "half_step" BOOLEAN NOT NULL DEFAULT false,
    "base_exp" INTEGER NOT NULL,
    "radius_m" INTEGER NOT NULL DEFAULT 50,
    "keywords" TEXT[],
    "active" BOOLEAN NOT NULL DEFAULT true,
    "score_a" INTEGER NOT NULL DEFAULT 0,
    "score_b" INTEGER NOT NULL DEFAULT 0,
    "score_c" INTEGER NOT NULL DEFAULT 0,
    "score_d" INTEGER NOT NULL DEFAULT 0,
    "score_e" INTEGER NOT NULL DEFAULT 0,
    "score_f" INTEGER NOT NULL DEFAULT 0,
    "time_window_start" TEXT,
    "time_window_end" TEXT,
    "photo_prompt" TEXT,
    "required_count" INTEGER NOT NULL DEFAULT 1,
    "quiz_question" TEXT,
    "quiz_options" JSONB,
    "quiz_answer" TEXT,
    "quiz_explanation" TEXT,

    CONSTRAINT "quests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_quests" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "quest_id" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'accepted',
    "current_progress" INTEGER NOT NULL DEFAULT 0,
    "last_lat" DOUBLE PRECISION,
    "last_lng" DOUBLE PRECISION,
    "last_verified_at" TIMESTAMP(3),
    "started_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" TIMESTAMP(3),

    CONSTRAINT "user_quests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "quest_completions" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "quest_id" INTEGER NOT NULL,
    "exp_awarded" INTEGER NOT NULL,
    "multipliers_json" JSONB,
    "photo_url" TEXT,
    "photo_visibility" TEXT NOT NULL DEFAULT 'PUBLIC',
    "photo_urls" JSONB,
    "user_text" TEXT,
    "emotion_tag" TEXT,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "accuracy_m" DOUBLE PRECISION NOT NULL,
    "is_abused" BOOLEAN NOT NULL DEFAULT false,
    "request_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "quest_completions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "badges" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "art_url" TEXT NOT NULL,
    "rule_json" JSONB NOT NULL,
    "threshold" INTEGER NOT NULL,
    "region_code" TEXT,
    "hidden" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "badges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_badges" (
    "user_id" INTEGER NOT NULL,
    "badge_id" INTEGER NOT NULL,
    "progress" INTEGER NOT NULL DEFAULT 0,
    "achieved_at" TIMESTAMP(3),
    "is_featured" BOOLEAN NOT NULL DEFAULT false,
    "featured_order" INTEGER,

    CONSTRAINT "user_badges_pkey" PRIMARY KEY ("user_id","badge_id")
);

-- CreateTable
CREATE TABLE "level_table" (
    "level" INTEGER NOT NULL,
    "required_exp" INTEGER NOT NULL,

    CONSTRAINT "level_table_pkey" PRIMARY KEY ("level")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_nickname_key" ON "users"("nickname");

-- CreateIndex
CREATE UNIQUE INDEX "user_devices_fcm_token_key" ON "user_devices"("fcm_token");

-- CreateIndex
CREATE INDEX "user_devices_user_id_idx" ON "user_devices"("user_id");

-- CreateIndex
CREATE INDEX "places_lat_lng_idx" ON "places"("lat", "lng");

-- CreateIndex
CREATE UNIQUE INDEX "user_quests_user_id_quest_id_key" ON "user_quests"("user_id", "quest_id");

-- CreateIndex
CREATE UNIQUE INDEX "quest_completions_request_id_key" ON "quest_completions"("request_id");

-- CreateIndex
CREATE INDEX "quest_completions_is_abused_created_at_idx" ON "quest_completions"("is_abused", "created_at");

-- AddForeignKey
ALTER TABLE "user_devices" ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_keywords" ADD CONSTRAINT "user_keywords_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quests" ADD CONSTRAINT "quests_place_id_fkey" FOREIGN KEY ("place_id") REFERENCES "places"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_quests" ADD CONSTRAINT "user_quests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_quests" ADD CONSTRAINT "user_quests_quest_id_fkey" FOREIGN KEY ("quest_id") REFERENCES "quests"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quest_completions" ADD CONSTRAINT "quest_completions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "quest_completions" ADD CONSTRAINT "quest_completions_quest_id_fkey" FOREIGN KEY ("quest_id") REFERENCES "quests"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_badges" ADD CONSTRAINT "user_badges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_badges" ADD CONSTRAINT "user_badges_badge_id_fkey" FOREIGN KEY ("badge_id") REFERENCES "badges"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

