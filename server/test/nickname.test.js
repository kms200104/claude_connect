import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { cleanName, NAME_MAX } from '../src/nickname.js';
import { Client, uid } from './helpers.js';

describe('v14 닉네임', () => {
  let saveDir;
  let server;
  const clients = [];
  let rid = 0;
  const newRid = () => `n${++rid}`;
  const open = async () => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    return c;
  };

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-name-'));
    server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear' });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('이름 정리: 앞뒤 공백 · 띄어쓰기 한 칸 · 길이 · 기호', () => {
    assert.equal(cleanName('  솔  바람 '), '솔 바람');
    assert.equal(cleanName(''), '');
    assert.equal(cleanName('   '), '');
    assert.equal(cleanName('가'.repeat(NAME_MAX)), '가'.repeat(NAME_MAX));
    assert.equal(cleanName('가'.repeat(NAME_MAX + 1)), null);
    assert.equal(cleanName('a<b>'), null);
    assert.equal(cleanName('줄\n바꿈'), '줄 바꿈');
    assert.equal(cleanName(42), null);
  });

  it('입장할 때 이름을 같이 보내면 그 이름으로 · 바꾸면 같은 방 사람에게도 알린다 · 저장된다', async () => {
    const a = await open();
    const aUid = uid();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: aUid, name: ' 단풍 ' });
    const wa = await a.type('welcome');
    assert.equal(wa.players.find((p) => p.id === wa.id).name, '단풍');
    assert.equal(wa.prof.name, '단풍');
    const b = await open();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: wa.code });
    const wb = await b.type('welcome');
    assert.equal(wb.players.find((p) => p.id === wa.id).name, '단풍', '먼저 온 사람 이름이 보인다');
    assert.equal(wb.players.find((p) => p.id === wb.id).name, '', '안 정하면 빈 이름 (기본 이름)');
    const joined = await a.type('peer_joined');
    assert.equal(joined.p.name, '');

    a.send({ t: 'set_name', rid: newRid(), name: '솔바람지기' });
    const mine = await a.type('name');
    assert.equal(mine.name, '솔바람지기');
    const seen = await b.type('name');
    assert.deepEqual([seen.id, seen.name], [wa.id, '솔바람지기']);

    a.send({ t: 'set_name', rid: newRid(), name: '너무너무너무너무긴이름' });
    assert.equal((await a.type('error')).code, 'bad_name');

    // 다시 들어와도 그 이름 (같은 uid, 이름 없이).
    a.kill();
    const a2 = await open();
    a2.send({ t: 'join', v: PROTOCOL_VERSION, uid: aUid, code: wa.code });
    const again = await a2.type('welcome');
    assert.equal(again.prof.name, '솔바람지기');
  });
});
