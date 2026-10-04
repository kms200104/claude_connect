import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { Client, sleep, uid } from './helpers.js';

// random=0 → 항상 첫 물고기(붕어, 창 700ms), 가짜 입질 0번, 최소 대기. 시간은 1/100로 줄인다.
const FAST = { fishTimeScale: 0.01, fishHookGraceMs: 500, moveSlackMeters: 100, random: () => 0, reconnectGraceMs: 300, saveIntervalMs: 60000 };
const AT_POND = { x: -9, y: 0.1, z: 2 };

describe('낚시 · 인벤토리 · 저장', () => {
  let saveDir;
  let server;
  const clients = [];
  const open = async (s = server) => {
    const c = new Client(s.port);
    clients.push(c);
    await c.opened;
    return c;
  };
  async function enter(client, { code, id = uid() } = {}) {
    client.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: id, code } : { t: 'create', v: PROTOCOL_VERSION, uid: id });
    const welcome = await client.type('welcome');
    return { welcome, uid: id };
  }
  async function goToPond(client) {
    client.send({ t: 'move', ...AT_POND, yaw: 0, vx: 0, vz: 0 });
    await client.next((m) => m.t === 'snap' && m.p.some((p) => p.x === AT_POND.x));
  }
  let rid = 0;
  const newRid = () => `r${++rid}`;

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-fish-'));
    server = createServer({ port: 0, saveDir, ...FAST });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('낚시터에서 멀면 던질 수 없다', async () => {
    const a = await open();
    await enter(a);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    assert.equal((await a.type('error')).code, 'not_at_spot');
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'nowhere' });
    assert.equal((await a.type('error')).code, 'not_at_spot');
  });

  it('성공: 입질 후 제때 당기면 인벤토리에 들어오고 파일에 저장된다', async () => {
    const a = await open();
    const { welcome } = await enter(a);
    assert.equal(welcome.inv.slots.length, 25);
    assert.deepEqual(welcome.inv.slots.slice(0, 3), [{ id: 'rod', n: 1 }, { id: 'axe', n: 1 }, null], '낚싯대·도끼를 들고 시작');
    assert.deepEqual({ quick: welcome.inv.quick, cap: welcome.inv.cap, held: welcome.inv.held }, { quick: 5, cap: 20, held: 0 });
    await goToPond(a);
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    assert.equal((await a.type('fish_started')).rid, r);
    const bite = await a.type('fish_bite');
    assert.equal(bite.windowMs, 700);
    assert.equal(bite.fish, undefined, '물고기 종류는 결과 전에 알리지 않는다');
    await sleep(120);
    a.send({ t: 'fish_hook', rid: r, reaction: 120 });
    const result = await a.type('fish_result');
    assert.deepEqual({ ok: result.ok, fish: result.fish }, { ok: true, fish: 'crucian' });
    const inv = await a.type('inventory');
    assert.deepEqual(inv.slots[5], { id: 'crucian', n: 1 }, '가방 첫 칸에 들어간다');

    await server.rooms.flushAll();
    const saved = JSON.parse(readFileSync(path.join(saveDir, `${welcome.code}.json`), 'utf8'));
    assert.equal(saved.schema, 2);
    assert.deepEqual(saved.profiles[Object.keys(saved.profiles)[0]].slots[5], { id: 'crucian', n: 1 });
    assert.equal(saved.world.totalCatches, 1);
    assert.equal(saved.world.species.crucian, 1);
  });

  it('입질 전에 당기면 실패(early)', async () => {
    const a = await open();
    await enter(a);
    await goToPond(a);
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    await a.type('fish_started');
    a.send({ t: 'fish_hook', rid: r, reaction: 0 });
    const result = await a.type('fish_result');
    assert.deepEqual({ ok: result.ok, reason: result.reason }, { ok: false, reason: 'early' });
  });

  it('허용 창을 넘겨 당기면 실패(late)', async () => {
    const a = await open();
    await enter(a);
    await goToPond(a);
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    await a.type('fish_bite');
    await sleep(760);
    a.send({ t: 'fish_hook', rid: r, reaction: 750 });
    assert.equal((await a.type('fish_result')).reason, 'late');
  });

  it('반응이 없으면 물고기가 도망간다(escaped)', async () => {
    const a = await open();
    await enter(a);
    await goToPond(a);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    await a.type('fish_bite');
    const result = await a.type('fish_result', 3000);
    assert.equal(result.reason, 'escaped');
  });

  it('사람이 불가능한 반응 시간이나 서버가 잰 시간과 모순되는 값은 거부', async () => {
    const a = await open();
    await enter(a);
    await goToPond(a);
    let r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    await a.type('fish_bite');
    await sleep(100);
    a.send({ t: 'fish_hook', rid: r, reaction: 5 }); // 5ms: 너무 빠름
    assert.equal((await a.type('fish_result')).ok, false);

    r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    await a.type('fish_bite');
    a.send({ t: 'fish_hook', rid: r, reaction: 600 }); // 방금 입질이 왔는데 600ms 걸렸다는 건 거짓
    assert.equal((await a.type('fish_result')).ok, false);
  });

  it('같은 요청 ID는 한 번만 처리하고, 낚시 중 다시 던지면 에러', async () => {
    const a = await open();
    await enter(a);
    await goToPond(a);
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' }); // 중복 → 무시
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    assert.equal((await a.type('error')).code, 'already_fishing');
    await a.type('fish_started');
    assert.equal(a.inbox.filter((m) => m.t === 'fish_started').length, 0);
  });

  it('낚시 중 멀리 움직이면 취소되고, 직접 취소할 수도 있다', async () => {
    const a = await open();
    await enter(a);
    await goToPond(a);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    await a.type('fish_started');
    a.send({ t: 'move', x: -12, y: 0.1, z: 2, yaw: 0, vx: 0, vz: 0 });
    assert.equal((await a.type('fish_result')).reason, 'moved');

    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    await a.type('fish_started');
    a.send({ t: 'fish_cancel' });
    assert.equal((await a.type('fish_result')).reason, 'cancelled');
  });

  it('낚시 중에는 스냅샷에 fishing 플래그가 실린다', async () => {
    const a = await open();
    const { welcome } = await enter(a);
    const b = await open();
    await enter(b, { code: welcome.code });
    await goToPond(a);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    const snap = await b.next((m) => m.t === 'snap' && m.p.find((p) => p.id === 1)?.fishing === true);
    assert.ok(snap);
  });

  it('낚싯대를 손에 들고 있어야 던질 수 있다', async () => {
    const a = await open();
    await enter(a);
    await goToPond(a);
    a.send({ t: 'equip', slot: -1 });
    assert.equal((await a.type('inventory')).held, -1);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    assert.equal((await a.type('error')).code, 'no_tool');
    a.send({ t: 'equip', slot: 1 }); // 도끼
    await a.type('inventory');
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    assert.equal((await a.type('error')).code, 'no_tool');
    a.send({ t: 'equip', slot: 9 });
    assert.equal((await a.type('error')).code, 'bad_item');
  });

  it('인벤토리 버리기: 가진 만큼만, 도구·빈 칸은 거부', async () => {
    const a = await open();
    await enter(a);
    await goToPond(a);
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    await a.type('fish_bite');
    await sleep(100);
    a.send({ t: 'fish_hook', rid: r, reaction: 100 });
    await a.type('fish_result');
    await a.type('inventory');

    a.send({ t: 'inv_discard', rid: newRid(), slot: 5, n: 5 });
    assert.equal((await a.type('error')).code, 'bad_item');
    a.send({ t: 'inv_discard', rid: newRid(), slot: 9, n: 1 });
    assert.equal((await a.type('error')).code, 'bad_item');
    a.send({ t: 'inv_discard', rid: newRid(), slot: 0, n: 1 });
    assert.equal((await a.type('error')).code, 'cant_discard', '낚싯대는 버릴 수 없다');
    a.send({ t: 'inv_discard', rid: newRid(), slot: 5, n: 1 });
    assert.equal((await a.type('inventory')).slots[5], null);
  });

  it('서버를 껐다 켜도 같은 uid는 같은 자리·인벤토리·위치를 되찾는다', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-restart-'));
    let s1 = createServer({ port: 0, saveDir: dir, ...FAST });
    const A = uid();
    const B = uid();
    const a = await open(s1);
    const { welcome } = await enter(a, { id: A });
    await goToPond(a);
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    await a.type('fish_bite');
    await sleep(100);
    a.send({ t: 'fish_hook', rid: r, reaction: 100 });
    assert.equal((await a.type('fish_result')).ok, true);
    const b = await open(s1);
    const wb = (await enter(b, { code: welcome.code, id: B })).welcome;
    assert.equal(wb.id, 2);

    await s1.close(); // 종료 시 저장
    assert.ok(readdirSync(dir).includes(`${welcome.code}.json`));

    const s2 = createServer({ port: 0, saveDir: dir, ...FAST });
    const a2 = await open(s2);
    const w2 = (await enter(a2, { code: welcome.code, id: A })).welcome;
    assert.equal(w2.id, 1);
    assert.equal(w2.resumed, false);
    assert.deepEqual(w2.inv.slots[5], { id: 'crucian', n: 1 });
    assert.equal(w2.players.find((p) => p.id === 1).x, AT_POND.x);

    const b2 = await open(s2);
    assert.equal((await enter(b2, { code: welcome.code, id: B })).welcome.id, 2);
    const c2 = await open(s2);
    c2.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: welcome.code });
    assert.equal((await c2.type('error')).code, 'room_full');
    await s2.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('깨진 저장 파일은 .corrupt 로 치워 두고 방이 없는 것으로 처리한다', async () => {
    writeFileSync(path.join(saveDir, 'ABCDEF.json'), '{ not json');
    const a = await open();
    a.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: 'ABCDEF' });
    assert.equal((await a.type('error')).code, 'room_not_found');
    assert.ok(readdirSync(saveDir).some((f) => f.startsWith('ABCDEF.json.corrupt-')));
  });

  it('방 코드로 파일 경로를 조작할 수 없다', async () => {
    const a = await open();
    for (const code of ['../x', '..\\..\\x', 'ABC/DEF', 'abc', '']) {
      a.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code });
      assert.equal((await a.type('error')).code, 'room_not_found', code);
    }
  });

  it('uid 형식이 이상하면 거부', async () => {
    const a = await open();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: '../../etc' });
    assert.equal((await a.type('error')).code, 'bad_message');
    a.send({ t: 'create', v: PROTOCOL_VERSION });
    assert.equal((await a.type('error')).code, 'bad_message');
  });

  it('인벤토리가 가득 차면 던지기 전에 거절한다', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-full-'));
    const s = createServer({ port: 0, saveDir: dir, ...FAST, quickSlots: 2, inventoryCapacity: 1, inventoryStackSize: 1 });
    const a = await open(s);
    await enter(a);
    await goToPond(a);
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    await a.type('fish_bite');
    await sleep(100);
    a.send({ t: 'fish_hook', rid: r, reaction: 100 });
    assert.equal((await a.type('fish_result')).ok, true);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    assert.equal((await a.type('error')).code, 'inventory_full');
    await s.close();
    rmSync(dir, { recursive: true, force: true });
  });
});
