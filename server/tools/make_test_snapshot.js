// 앱에 넣는 "테스트 서버"(autoload/net/local_test_server.gd)가 보낼 입장 정보(welcome) 를 진짜 서버에서 한 번 찍어 둔다.
// 서버 데이터(data/)나 프로토콜이 바뀌면 다시 돌린다:  node server/tools/make_test_snapshot.js
// 결과: data/testserver/welcome.json (방 코드·토큰·시계는 테스트 서버가 접속할 때 새로 채운다).
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocket } from 'ws';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, '../../data/testserver/welcome.json');
const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-snapshot-'));
const server = createServer({
  port: 0,
  saveDir,
  weatherForce: 'clear',
  eventForce: 'none',
  questChance: 0,
  startSol: 30000000,
  startItems: 'fishing_net:1,shovel:1,fabric_sofa:1,dining_table:1',
});
await new Promise((r) => setTimeout(r, 200));
const ws = new WebSocket(`ws://127.0.0.1:${server.port}`);
await new Promise((r) => ws.on('open', r));
const welcome = await new Promise((resolve) => {
  ws.on('message', (d) => {
    const m = JSON.parse(d.toString());
    if (m.t === 'welcome') resolve(m);
  });
  ws.send(JSON.stringify({ t: 'create', v: PROTOCOL_VERSION, uid: 'test-server-snapshot' }));
});
ws.close();
await server.close();
rmSync(saveDir, { recursive: true, force: true });
// 시세 기록은 짧게 (앱 용량), 방마다 바뀌는 값은 비운다.
for (const s of welcome.market?.stocks ?? []) s.hist = s.hist.slice(-30);
welcome.token = '';
welcome.code = '';
welcome.v = PROTOCOL_VERSION;
mkdirSync(path.dirname(out), { recursive: true });
writeFileSync(out, `${JSON.stringify(welcome)}\n`);
console.log(`[snapshot] ${out} (${Math.round(JSON.stringify(welcome).length / 1024)} KB, protocol ${PROTOCOL_VERSION})`);
process.exit(0);
