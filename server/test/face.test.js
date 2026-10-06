import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { applyFaceRequest, sanitizeFace } from '../src/face.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { Client, uid } from './helpers.js';

const BASE = { port: 0, moveSlackMeters: 200, saveIntervalMs: 60000, weatherForce: 'clear', questChance: 0 };

describe('거울: 얼굴 꾸미기', () => {
  const servers = [];
  const clients = [];
  const dirs = [];
  let rid = 0;
  const newRid = () => `f${++rid}`;

  function start(overrides = {}, saveDir = null) {
    const dir = saveDir ?? mkdtempSync(path.join(tmpdir(), 'solbaram-face-'));
    if (!saveDir) dirs.push(dir);
    const server = createServer({ ...BASE, saveDir: dir, ...overrides });
    servers.push(server);
    return { server, saveDir: dir };
  }
  async function join(server, { code = null, id = uid() } = {}) {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: id, code } : { t: 'create', v: PROTOCOL_VERSION, uid: id });
    return { c, welcome: await c.type('welcome'), id };
  }
  async function moveTo(c, x, z) {
    c.send({ t: 'move', x, y: 0.1, z, yaw: 0, vx: 0, vz: 0 });
    await c.next((m) => m.t === 'snap' && m.p.some((p) => p.x === x && p.z === z));
  }

  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });

  it('얼굴 데이터: 모르는 id 는 자리 기본값, 요청은 아는 항목·id 만', () => {
    const data = loadGameData(defaultConfig.dataDir, defaultConfig);
    assert.deepEqual(sanitizeFace({ eyes: 'nope', hair: 'curly' }, data.face, 2), {
      eyes: 'round', eye_color: 'cocoa', nose: 'button', mouth: 'smile', skin: 'peach', hair: 'curly', hair_color: 'dark',
    });
    const cur = sanitizeFace(null, data.face, 1);
    assert.equal(applyFaceRequest(cur, { eyes: 'star', mouth: 'cat' }, data.face).mouth, 'cat');
    assert.equal(applyFaceRequest(cur, { eyes: 'laser' }, data.face), null);
    assert.equal(applyFaceRequest(cur, { wings: 'big' }, data.face), null);
    assert.equal(applyFaceRequest(cur, {}, data.face), null);
    assert.equal(applyFaceRequest(cur, ['eyes'], data.face), null);
    for (const key of ['eyes', 'eye_color', 'nose', 'mouth', 'skin', 'hair', 'hair_color']) assert.ok(data.face.ids[key].size >= 8, `${key} 고를 거리 8가지 이상`);
  });

  it('거울 앞에서만 바꾸고, 바꾼 얼굴은 함께 노는 사람에게도 보이고 저장된다', async () => {
    const { server, saveDir } = start();
    const a = await join(server);
    const b = await join(server, { code: a.welcome.code });
    // 자리마다 기본 얼굴 (1번 단발 밤색, 2번 짧은 머리 먹색)
    assert.equal(a.welcome.prof.face.hair, 'bob');
    assert.equal(b.welcome.prof.face.hair, 'short');
    assert.equal(b.welcome.players.find((p) => p.id === 1).face.hair_color, 'brown', '상대 얼굴도 입장할 때 받는다');

    a.c.send({ t: 'set_face', rid: newRid(), face: { eyes: 'star' } });
    assert.equal((await a.c.type('error')).code, 'not_near_mirror', '광장 가운데는 거울에서 멀다');

    const mirror = server.data.layout.mirrors[0];
    await moveTo(a.c, mirror.x + 0.5, mirror.z - 1.0);
    a.c.send({ t: 'set_face', rid: newRid(), face: { eyes: 'laser' } });
    assert.equal((await a.c.type('error')).code, 'bad_face');
    const r = newRid();
    a.c.send({ t: 'set_face', rid: r, face: { eyes: 'star', hair: 'curly', hair_color: 'mint', skin: 'cocoa' } });
    const mine = await a.c.type('face');
    assert.equal(mine.rid, r);
    assert.deepEqual(mine.face, { eyes: 'star', eye_color: 'cocoa', nose: 'button', mouth: 'smile', skin: 'cocoa', hair: 'curly', hair_color: 'mint' });
    const seen = await b.c.type('face');
    assert.equal(seen.id, 1);
    assert.equal(seen.face.hair, 'curly');

    // 같은 사람이 다시 들어오면 그대로
    await server.close();
    const again = start({}, saveDir);
    const back = await join(again.server, { code: a.welcome.code, id: a.id });
    assert.equal(back.welcome.prof.face.hair_color, 'mint');
    const file = JSON.parse(readFileSync(path.join(saveDir, `${a.welcome.code}.json`), 'utf8'));
    assert.equal(Object.values(file.profiles).find((p) => p.slot === 1).face.eyes, 'star');
  });

  it('직접 놓은 거울 가구 앞에서도 바꿀 수 있다', async () => {
    const { server } = start({ startItems: 'standing_mirror:1' });
    const { c, welcome } = await join(server);
    const slot = welcome.inv.slots.findIndex((s) => s?.id === 'standing_mirror');
    await moveTo(c, 20, 30);
    c.send({ t: 'set_face', rid: newRid(), face: { mouth: 'cat' } });
    assert.equal((await c.type('error')).code, 'not_near_mirror');
    c.send({ t: 'place', rid: newRid(), slot, x: 21, z: 30, rot: 0 });
    await c.type('placed');
    c.send({ t: 'set_face', rid: newRid(), face: { mouth: 'cat' } });
    assert.equal((await c.type('face')).face.mouth, 'cat');
  });
});
