import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { sanitizeChats } from '../src/messenger.js';
import { Client, uid } from './helpers.js';

// 마을톡 (v0.11): 친구와 주고받기, 주민에게 보내면 답장, 친한 주민이 먼저 연락, 끊겨 있어도 쌓여 있다.
describe('마을톡', () => {
  let server;
  let saveDir;
  const clients = [];
  before(async () => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-msg-'));
    server = createServer({ port: 0, saveDir, startFriendship: 10, messengerCheckMs: 50, messengerReplyScale: 0.01, random: () => 0, saveIntervalMs: 60000, weatherForce: 'clear' });
    await new Promise((r) => setTimeout(r, 100));
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });
  async function enter(code) {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    return { c, welcome: await c.type('welcome') };
  }

  it('처음 들어오면 환영 인사, 친구에게 보내면 친구 쪽 대화방에 들어간다', async () => {
    const { c: a, welcome } = await enter();
    assert.ok(welcome.chats['sys:town'].m[0].tx.includes('마을톡'));
    const { c: b } = await enter(welcome.code);
    a.send({ t: 'msg_send', rid: 'm1', th: 'pl:2', tx: '  같이 낚시 갈래?  ' });
    const mine = await a.next((m) => m.t === 'msg' && m.th === 'pl:2');
    assert.deepEqual([mine.m.f, mine.m.tx], ['me', '같이 낚시 갈래?']);
    const got = await b.next((m) => m.t === 'msg' && m.th === 'pl:1');
    assert.deepEqual([got.m.f, got.m.tx], ['p1', '같이 낚시 갈래?']);
    // 없는 방·빈 글·나 자신·시스템 방에는 못 보낸다.
    for (const [th, tx] of [['pl:9', 'x'], ['pl:1', ''], ['pl:1', 'me'], ['sys:bank', 'hi'], ['../x', 'hi']]) {
      a.send({ t: 'msg_send', rid: `bad-${th}-${tx}`, th, tx });
      assert.equal((await a.type('error')).code, 'bad_message', th);
    }
  });

  it('주민에게 보내면 잠시 뒤 답장, 친한 주민은 먼저 연락한다 (하루 daily_max 통까지)', async () => {
    const { c: a } = await enter();
    a.send({ t: 'msg_send', rid: 'n1', th: 'npc:morak', tx: '할머니 안녕하세요' });
    await a.next((m) => m.t === 'msg' && m.th === 'npc:morak' && m.m.f === 'me');
    const reply = await a.next((m) => m.t === 'msg' && m.th === 'npc:morak' && m.m.f === 'morak');
    assert.ok(reply.m.tx.length > 0);
    // 먼저 연락 (주민마다 하루 한 번, 사람마다 하루 3통): 잠시 모아서 센다.
    await new Promise((r) => setTimeout(r, 900));
    const first = a.inbox.filter((m) => m.t === 'msg' && m.th.startsWith('npc:') && m.m.f !== 'me' && m.m.tx !== reply.m.tx);
    assert.equal(first.length, 3, '하루 3통까지');
    assert.equal(new Set(first.map((m) => m.th)).size, 3, '서로 다른 주민');
  });

  it('저장 형식을 고친다', () => {
    const rules = { max_messages: 2, max_text: 5 };
    const out = sanitizeChats({ 'pl:2': { m: [{ f: 'me', tx: '1', at: 1 }, { f: 'p2', tx: '1234567', at: 2 }, { f: 'me', tx: '3', at: 3 }], read: 9 }, evil: { m: [] }, 'npc:x': { m: 'no' } }, rules);
    assert.deepEqual(Object.keys(out), ['pl:2']);
    assert.deepEqual(out['pl:2'], { m: [{ f: 'p2', tx: '12345', at: 2 }, { f: 'me', tx: '3', at: 3 }], read: 2 });
  });
});
