import "dotenv/config";
import { defineConfig } from "@prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    seed: "npx tsx prisma/seed.ts", // <-- 이 줄 추가
  },
  datasource: {
    url: process.env.DATABASE_URL,
  },
});