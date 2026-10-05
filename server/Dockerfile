# 솔바람 마을 세션 서버 (항상 켜 두기용). 저장소 맨 위에서 빌드한다 — 서버가 data/ 를 클라이언트와 같이 읽기 때문:
#   docker build -f server/Dockerfile -t solbaram-server .
#   docker run -d --restart unless-stopped -p 8080:8080 -v solbaram-saves:/srv/saves --name solbaram solbaram-server
FROM node:22-slim
WORKDIR /app/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev
COPY server/src ./src
COPY data /app/data
ENV NODE_ENV=production \
    PORT=8080 \
    SAVE_DIR=/srv/saves \
    DATA_DIR=/app/data
VOLUME ["/srv/saves"]
EXPOSE 8080
# SIGTERM 을 받으면 방을 저장하고 닫는다 (src/index.js).
STOPSIGNAL SIGTERM
CMD ["node", "src/index.js"]
