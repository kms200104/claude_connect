import { createServer } from './server.js';

const server = createServer();
// 포트를 이미 다른 프로그램(대개 전에 켠 서버)이 쓰고 있으면 알아보기 쉽게 알려 주고 끝낸다 (종료 코드 2 — server.bat 이 본다).
server.wss.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[solbaram] port ${server.config.port} is already in use — an older server is probably still running.`);
    console.error('[solbaram] Close the other server window (or stop that node process), or start with another port: PORT=8081 npm start');
    process.exit(2);
  }
  console.error('[solbaram] server error:', err);
  process.exit(1);
});
server.wss.on('listening', () => {
  console.log(`[solbaram] listening on ws://0.0.0.0:${server.port} (tick ${server.config.tickRate}Hz, grace ${server.config.reconnectGraceMs}ms)`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    await server.close();
    process.exit(0);
  });
}
