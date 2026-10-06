import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { Client, sleep, uid } from './helpers.js';

describe('v15 휴대폰 꺼내 보기 · 누르기 (다른 사람 화면)', () => {
  let saveDir;
  let server;
  const clients = [];
  const open = async () => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    return c;
  };

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-phone-'));
    server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear' });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('꺼내 든 상태는 스냅샷 · 입장 정보로, 누르기는 몸짓으로 · 끊기면 내린다', async () => {
    const a = await open();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const wa = await a.type('welcome');
    const bUid = uid();
    let b = await open();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: bUid, code: wa.code });
    const wb = await b.type('welcome');
    assert.equal(wb.players.find((p) => p.id === wa.id).phone, false);

    // 들기 전 누르기는 무시된다.
    a.send({ t: 'phone_tap' });
    a.send({ t: 'phone', on: true });
    await b.next((m) => m.t === 'snap' && m.p.some((p) => p.id === wa.id && p.phone === true), 3000);
    a.send({ t: 'phone_tap' });
    const tap = await b.next((m) => m.t === 'act' && m.kind === 'phone_tap', 2000);
    assert.equal(tap.id, wa.id);
    // 너무 잦은 누르기는 거른다 (120ms).
    a.send({ t: 'phone_tap' });
    await sleep(60);
    const taps = [];
    b.next((m) => {
      if (m.t === 'act' && m.kind === 'phone_tap') taps.push(m);
      return false;
    }, 300).catch(() => {});
    await sleep(320);
    assert.equal(taps.length, 0, '120ms 안의 누르기는 한 번만');

    // 다시 들어와도 입장 정보에서 본다 (방은 2명).
    b.kill();
    await sleep(100);
    b = await open();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: bUid, code: wa.code });
    const again = await b.type('welcome');
    assert.equal(again.players.find((p) => p.id === wa.id).phone, true);

    a.send({ t: 'phone', on: false });
    await b.next((m) => m.t === 'snap' && m.p.some((p) => p.id === wa.id && p.phone === false), 3000);
    a.send({ t: 'phone', on: true });
    await b.next((m) => m.t === 'snap' && m.p.some((p) => p.id === wa.id && p.phone === true), 3000);
    a.kill();
    await b.next((m) => (m.t === 'snap' && m.p.some((p) => p.id === wa.id && p.phone === false)) || (m.t === 'peer_status' && m.id === wa.id && m.online === false), 5000);
  });
});
