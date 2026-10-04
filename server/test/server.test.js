import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { Client, sleep, uid } from './helpers.js';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

describe('session server', () => {
  let server;
  const clients = [];
  const connect = async () => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    return c;
  };
  let saveDir;
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-test-'));
    server = createServer({ port: 0, saveDir, reconnectGraceMs: 400, tickRate: 50, rateLimitPerSec: 20, rateLimitBurst: 30 });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('방 만들기 → 코드로 참가, 두 번째 플레이어는 스폰 위치가 다르다', async () => {
    const a = await connect();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const wa = await a.type('welcome');
    assert.equal(wa.id, 1);
    assert.match(wa.code, /^[A-Z2-9]{6}$/);
    assert.equal(wa.players.length, 1);

    const b = await connect();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: wa.code.toLowerCase() });
    const wb = await b.type('welcome');
    assert.equal(wb.id, 2);
    assert.equal(wb.players.length, 2);
    assert.notEqual(wb.players.find((p) => p.id === 2).x, wa.players[0].x);
    const joined = await a.type('peer_joined');
    assert.equal(joined.p.id, 2);
  });

  it('없는 방 / 가득 찬 방 / 버전 불일치는 에러', async () => {
    const x = await connect();
    x.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: 'ZZZZZZ' });
    assert.equal((await x.type('error')).code, 'room_not_found');
    x.send({ t: 'create', v: 999, uid: uid() });
    assert.equal((await x.type('error')).code, 'bad_version');

    const a = await connect();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const { code } = await a.type('welcome');
    const b = await connect();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code });
    await b.type('welcome');
    const c = await connect();
    c.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code });
    assert.equal((await c.type('error')).code, 'room_full');
  });

  it('위치가 상대에게 스냅샷으로 전달된다', async () => {
    const a = await connect();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const { code } = await a.type('welcome');
    const b = await connect();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code });
    await b.type('welcome');
    a.send({ t: 'move', x: 0.2, y: 0.1, z: -0.2, yaw: 1.5, vx: 2, vz: -2 });
    const snap = await b.next((m) => m.t === 'snap' && m.p.find((p) => p.id === 1)?.yaw === 1.5);
    const p1 = snap.p.find((p) => p.id === 1);
    assert.equal(p1.x, 0.2);
    assert.equal(p1.z, -0.2);
    assert.equal(typeof snap.st, 'number');
  });

  it('속도 상한을 넘는 이동은 잘라내고 correct를 보낸다', async () => {
    const a = await connect();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await a.type('welcome');
    a.send({ t: 'move', x: 50, y: 0.1, z: 0, yaw: 0, vx: 0, vz: 0 });
    const c = await a.type('correct');
    assert.ok(c.x < 3, `x was ${c.x}`);
  });

  it('경계 밖 좌표는 경계로 되돌린다', async () => {
    const a = await connect();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await a.type('welcome');
    a.send({ t: 'move', x: 0, y: 500, z: 0, yaw: 0 });
    const c = await a.type('correct');
    assert.equal(c.y, server.config.maxY);
  });

  it('끊겼다가 token으로 resume하면 같은 자리로 복귀하고 상대가 알림을 받는다', async () => {
    const a = await connect();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const wa = await a.type('welcome');
    const b = await connect();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: wa.code });
    await b.type('welcome');
    a.send({ t: 'move', x: 0.3, y: 0.1, z: 0.3, yaw: 0, vx: 0, vz: 0 });
    await b.next((m) => m.t === 'snap' && m.p.find((p) => p.id === 1)?.x === 0.3);

    a.kill();
    const off = await b.next((m) => m.t === 'peer_status' && m.id === 1 && m.online === false);
    assert.ok(off);

    await sleep(100);
    const a2 = await connect();
    a2.send({ t: 'resume', v: PROTOCOL_VERSION, token: wa.token });
    const w2 = await a2.type('welcome');
    assert.equal(w2.resumed, true);
    assert.equal(w2.id, 1);
    assert.equal(w2.players.find((p) => p.id === 1).x, 0.3);
    const on = await b.next((m) => m.t === 'peer_status' && m.id === 1 && m.online === true);
    assert.ok(on);
  });

  it('유예 시간이 지나면 자리가 비워지고 resume은 실패한다', async () => {
    const a = await connect();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const wa = await a.type('welcome');
    const b = await connect();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: wa.code });
    await b.type('welcome');
    a.kill();
    const left = await b.type('peer_left', 1500);
    assert.equal(left.id, 1);

    const a2 = await connect();
    a2.send({ t: 'resume', v: PROTOCOL_VERSION, token: wa.token });
    assert.equal((await a2.type('error')).code, 'resume_failed');
  });

  it('서버가 끊김을 모르는 상태에서 resume하면 낡은 연결을 교체한다', async () => {
    const a = await connect();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const wa = await a.type('welcome');
    const a2 = await connect();
    a2.send({ t: 'resume', v: PROTOCOL_VERSION, token: wa.token });
    await a2.type('welcome');
    await sleep(50);
    assert.equal(a.closed, 4000);
  });

  it('잘못된 JSON·알 수 없는 타입·로그인 전 move는 에러', async () => {
    const a = await connect();
    a.ws.send('not json');
    assert.equal((await a.type('error')).code, 'bad_message');
    a.send({ t: 'nope' });
    assert.equal((await a.type('error')).code, 'bad_message');
    a.send({ t: 'move', x: 0, y: 0, z: 0, yaw: 0 });
    assert.equal((await a.type('error')).code, 'not_in_room');
  });

  it('초당 요청 제한을 넘으면 rate_limited', async () => {
    const a = await connect();
    for (let i = 0; i < 80; i++) a.send({ t: 'ping', c: i });
    const e = await a.type('error');
    assert.equal(e.code, 'rate_limited');
  });

  it('ping에 서버 시간으로 pong 한다', async () => {
    const a = await connect();
    a.send({ t: 'ping', c: 123 });
    const p = await a.type('pong');
    assert.equal(p.c, 123);
    assert.equal(typeof p.s, 'number');
  });
});
