# 로컬 퀘스트 API 서버.
#
# **이미지 하나로 어디든 간다.** Northflank·Render·Fly·Cloud Run 모두 이 파일
# 하나면 되고, 무료 티어 정책이 바뀌어도 옮기는 데 코드를 고칠 필요가 없다.
# 그게 특정 플랫폼 설정 파일 대신 Dockerfile 을 둔 이유다.
#
# 주의: 이 저장소는 Flutter 앱과 서버가 한 트리에 있다. `.dockerignore` 가
# `lib/ android/ ios/ assets/ …` 를 걷어내지 않으면 이미지에 앱이 통째로 들어간다.

# ---------------------------------------------------------------------------
# 1) 빌드 — devDependencies 로 prisma generate + tsc
# ---------------------------------------------------------------------------
FROM node:22-slim AS build

WORKDIR /app

# 의존성 레이어를 먼저 굳힌다. 소스만 바뀌면 npm ci 를 다시 돌지 않는다.
COPY package.json package-lock.json ./
COPY prisma ./prisma
COPY prisma.config.ts ./

# postinstall 이 prisma generate 를 부른다. 스키마가 위에서 이미 복사돼 있어야 한다.
RUN npm ci

COPY tsconfig.json ./
COPY src ./src

RUN npm run build

# ---------------------------------------------------------------------------
# 2) 실행 — 운영 의존성 + 빌드 산출물만
# ---------------------------------------------------------------------------
FROM node:22-slim AS runtime

# Prisma 는 OpenSSL 을 찾는다. slim 이미지에는 빠져 있어 없으면 기동에 실패한다.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV NODE_ENV=production

COPY package.json package-lock.json ./
COPY prisma ./prisma
COPY prisma.config.ts ./

RUN npm ci --omit=dev && npm cache clean --force

COPY --from=build /app/dist ./dist

# root 로 돌 이유가 없다. node 이미지에 이미 있는 비특권 사용자를 쓴다.
USER node

EXPOSE 5001

# 기동 전에 마이그레이션을 적용한다.
#
# `migrate deploy` 는 이미 적용된 것을 건너뛰므로 재시작마다 돌아도 안전하다.
# 실패하면 컨테이너가 뜨지 않는다 — 스키마가 어긋난 채로 서비스하는 것보다 낫다.
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/index.js"]
