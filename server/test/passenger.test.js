// v0.27 동승: 친구가 운전하는 차량의 빈자리에 타고, 운전자를 따라가고, 자리가 차면 거절, 운전자가 내리면 같이 내린다.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { Client, sleep, uid } from './helpers.js';

describe('v0.27 동승', () => {
  let server;
  let saveDir;
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    await server?.close();
    if (saveDir) rmSync(saveDir, { recursive: true, force: true });
  });
  const ask = async (c, msg, ms = 3000) => {
    const rid = `ps-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const join = async (code = '') => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    return { c, w };
  };
  const moveTo = async (c, p, v = 0) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: v, vz: 0 });
    await sleep(120);
  };

  it('ATV 뒷자리에 타고 · 운전자를 따라가고 · 운전자가 내리면 같이 내린다', async () => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-ps-'));
    server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', startSol: 30000000, vehicleEtaMs: 200, moveSlackMeters: 0.5 });
    const { c: a, w } = await join();
    const { c: b } = await join(w.code);
    const room = [...server.rooms.rooms.values()][0];
    const [pa, pb] = [...room.players.values()];
    const spot = { x: -150, z: 140 };
    for (const [c, dx] of [[a, 0], [b, 1.5]]) await moveTo(c, { x: spot.x + dx, z: spot.z });
    const v = (await ask(a, { t: 'veh_buy', model: 'car_atv' })).v;
    await ask(a, { t: 'veh_call', v, x: spot.x, z: spot.z, yaw: 0 });
    await sleep(300);
    assert.equal((await ask(b, { t: 'veh_board', p: pa.id })).code, 'bad_vehicle', '아직 아무도 운전하지 않는다');
    assert.equal((await ask(a, { t: 'veh_ride', v })).t, 'veh_ride');
    const seat = await ask(b, { t: 'veh_board', p: pa.id });
    assert.equal(seat.t, 'veh_seat');
    assert.equal(seat.d, pa.id);
    assert.equal(seat.s, 0);
    assert.deepEqual(seat.seat, [0.0, 0.88, 0.62]);
    const seen = await a.next((m) => m.t === 'seat' && m.id === pb.id, 2000);
    assert.equal(seen.d, pa.id);
    assert.equal((await ask(b, { t: 'veh_board', p: pa.id })).code, 'cant_ride', '이미 탔다');
    // 운전자가 달리면 동승자 이동은 차 빠르기로 받아 준다 (걷기 빠르기 검사가 아니다).
    for (let i = 1; i <= 5; i++) {
      a.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z - i * 1.2, yaw: 0, vx: 0, vz: -10 });
      b.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z - i * 1.2 + 0.6, yaw: 0, vx: 0, vz: -10 });
      await sleep(100);
    }
    await sleep(150);
    assert.ok(Math.hypot(pb.x - pa.x, pb.z - pa.z) < 1.0, '운전자를 따라 왔다');
    // 운전자에게서 멀리 가면 운전자 자리로 고친다.
    b.send({ t: 'move', x: spot.x + 20, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    assert.ok(Math.hypot(pb.x - pa.x, pb.z - pa.z) < 0.5, '운전자 자리로 고쳤다');
    const snap = await a.next((m) => m.t === 'snap' && m.p.some((p) => p.id === pb.id && p.seat), 2000);
    assert.equal(snap.p.find((p) => p.id === pb.id).seat.d, pa.id);
    // 운전자가 내리면 같이 내린다.
    await ask(a, { t: 'veh_ride', v: '' });
    const off = await b.next((m) => m.t === 'seat' && m.id === pb.id && m.d === 0, 2000);
    assert.equal(off.s, -1);
    assert.equal(pb.passenger, null);
  });
});
