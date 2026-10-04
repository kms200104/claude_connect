import { createServer } from './server.js';

const server = createServer();
server.wss.on('listening', () => {
  console.log(`[solbaram] listening on ws://0.0.0.0:${server.port} (tick ${server.config.tickRate}Hz, grace ${server.config.reconnectGraceMs}ms)`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    await server.close();
    process.exit(0);
  });
}
