// v12: 같은 공간에 있는 느낌 — 내가 하는 일(낚시 장면 · 대화 말풍선)이 상대에게 전해지는지.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION, SAY_GAP_MS, SAY_MAX_CHARS } from '../src/protocol.js';
import { Client, sleep, uid } from './helpers.js';

const FAST = { fishTimeScale: 0.01, fishHookGraceMs: 500, moveSlackMeters: 200, random: () => 0, reconnectGraceMs: 300, saveIntervalMs: 60000 };
// 서쪽 연못(lake) 동쪽 물가 (성성호수공원 배치, fishing.test.js 와 같은 자리).
const AT_POND = { x: -42.6, y: 0.1, z: 35.4 };

describe('함께 있는 느낌 (act · say)', () => {
  let saveDir;
  let server;
  const clients = [];
  const open = async () => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    return c;
  };
  let rid = 0;
  const newRid = () => `p${++rid}`;

  /** 방장 a 와 손님 b. */
  async function pair() {
    const a = await open();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const wa = await a.type('welcome');
    const b = await open();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: wa.code });
    await b.type('welcome');
    await a.type('peer_joined');
    return { a, b };
  }

  async function moveTo(client, at) {
    client.send({ t: 'move', ...at, yaw: 0, vx: 0, vz: 0 });
    await client.next((m) => m.t === 'snap' && m.p.some((p) => Math.abs(p.x - at.x) < 0.01 && Math.abs(p.z - at.z) < 0.01), 2000);
  }

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-presence-'));
    server = createServer({ port: 0, saveDir, ...FAST });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('낚시: 던지기 · 입질 · 끌어올리기 · 낚음이 상대에게 차례로 전해진다', async () => {
    const { a, b } = await pair();
    await moveTo(a, AT_POND);
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    const cast = await b.next((m) => m.t === 'act' && m.kind === 'fish' && m.e === 'cast');
    assert.equal(cast.id, 1);
    assert.equal(cast.spot, 'lake');
    await a.type('fish_bite');
    await b.next((m) => m.t === 'act' && m.kind === 'fish' && m.e === 'bite');
    await sleep(120);
    a.send({ t: 'fish_hook', rid: r, reaction: 120 });
    const reel = await a.type('fish_reel');
    await b.next((m) => m.t === 'act' && m.kind === 'fish' && m.e === 'reel');
    await sleep(reel.taps * 45 + 20);
    a.send({ t: 'fish_reel', rid: r, taps: Array.from({ length: reel.taps }, (_, i) => i * 45 + 10) });
    const result = await a.type('fish_result');
    assert.equal(result.ok, true);
    const land = await b.next((m) => m.t === 'act' && m.kind === 'fish' && m.e === 'land');
    assert.equal(land.fish, result.fish, '상대 화면에도 같은 물고기를 들어 보인다');
    // 내 낚시 장면은 나에게 다시 오지 않는다.
    assert.equal(a.inbox.some((m) => m.t === 'act' && m.kind === 'fish'), false);
  });

  it('낚시를 그만두면 상대 화면의 찌도 걷힌다', async () => {
    const { a, b } = await pair();
    await moveTo(a, AT_POND);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    await b.next((m) => m.t === 'act' && m.kind === 'fish' && m.e === 'cast');
    a.send({ t: 'fish_cancel' });
    const end = await b.next((m) => m.t === 'act' && m.kind === 'fish' && m.e === 'end');
    assert.equal(end.reason, 'cancelled');
  });

  it('대화: 주민에게 말을 걸면 상대가 알고, 대사는 그 주민 머리 위 말풍선으로 들린다', async () => {
    const { a, b } = await pair();
    const npcs = await a.type('npcs', 3000);
    const n = npcs.n[0];
    await moveTo(a, { x: n.x + 1.0, y: 0.1, z: n.z });
    a.send({ t: 'talk', rid: newRid(), npc: n.id });
    await a.type('talk_open');
    const talk = await b.next((m) => m.t === 'act' && m.kind === 'talk');
    assert.equal(talk.e, n.id);
    a.send({ t: 'say', who: 'npc', npc: n.id, tx: '안녕! 오늘 날씨 좋다.' });
    const said = await b.type('say');
    assert.deepEqual([said.id, said.npc, said.tx], [1, n.id, '안녕! 오늘 날씨 좋다.']);
    await sleep(SAY_GAP_MS + 20);
    // 내가 고른 말은 내 머리 위 (npc 가 빈 값). 너무 긴 말은 자르고, 제어 문자는 지운다.
    a.send({ t: 'say', who: 'me', npc: '', tx: `고민 상담\n${'가'.repeat(200)}` });
    const mine = await b.type('say');
    assert.equal(mine.npc, '');
    assert.equal(mine.tx.length, SAY_MAX_CHARS);
    assert.equal(mine.tx.includes('\n'), false);
    // 너무 잦으면 버린다.
    a.send({ t: 'say', who: 'me', tx: '하나' });
    assert.equal((await a.type('error')).code, 'too_fast');
    a.send({ t: 'talk_end' });
    assert.equal((await b.next((m) => m.t === 'act' && m.kind === 'talk_end')).e, n.id);
  });

  it('대화 중이 아니면 주민 대사를 보낼 수 없고, 가게 사람 대사는 된다', async () => {
    const { a, b } = await pair();
    a.send({ t: 'say', who: 'npc', npc: 'morak', tx: '나는 모락이야' });
    assert.equal((await a.type('error')).code, 'not_talking');
    await sleep(SAY_GAP_MS + 20);
    a.send({ t: 'say', who: 'npc', npc: 'shopkeeper', tx: '어서 오세요!' });
    assert.equal((await b.type('say')).npc, 'shopkeeper');
  });
});
