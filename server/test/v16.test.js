// v16: 도감 · 업적 · 칭호 · 생일 · 달력 · 방명록 · 놀러 가기 · 사진.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { DAY_MS, DAY_START_HOUR } from '../src/clock.js';
import { checkAchievements, cleanBirthday, dateOfDay, statValues } from '../src/progress.js';
import { Client, uid } from './helpers.js';

/** 64바이트 넘는 가짜 JPEG (시작 FF D8 · 끝 FF D9). */
const fakeJpeg = (n = 200) => {
  const b = Buffer.alloc(n, 0x42);
  b[0] = 0xff;
  b[1] = 0xd8;
  b[n - 2] = 0xff;
  b[n - 1] = 0xd9;
  return b.toString('base64');
};

describe('v16 규칙', () => {
  it('생일은 그 달에 있는 날만', () => {
    assert.deepEqual(cleanBirthday({ m: 2, d: 29 }), { m: 2, d: 29 });
    assert.equal(cleanBirthday({ m: 4, d: 31 }), null);
    assert.equal(cleanBirthday({ m: 13, d: 1 }), null);
    assert.equal(cleanBirthday({ m: '3', d: 1 }), null);
  });

  it('업적은 목표를 넘을 때 한 번만 · 단계마다', () => {
    const list = { list: [{ id: 'a1', stat: 'fish', goal: 1 }, { id: 'a2', stat: 'fish', goal: 3 }], byId: new Map() };
    const profile = { stats: { fish: 1 }, npcs: {}, dex: { fish: {}, items: [] } };
    assert.deepEqual(checkAchievements(profile, list, statValues(profile), 10), ['a1']);
    assert.deepEqual(checkAchievements(profile, list, statValues(profile), 11), []);
    profile.stats.fish = 5;
    assert.deepEqual(checkAchievements(profile, list, statValues(profile), 12), ['a2']);
    assert.deepEqual(profile.ach.map((a) => a.at), [10, 12]);
  });
});

describe('v16 서버', () => {
  let saveDir;
  let server;
  const clients = [];
  let rid = 0;
  const r = () => `v${++rid}`;
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-v16-'));
    server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', startFriendship: 10, eventForce: '' });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });
  async function enter(code = null, who = uid()) {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: who, code } : { t: 'create', v: PROTOCOL_VERSION, uid: who });
    const w = await c.type('welcome');
    const room = [...server.rooms.rooms.values()].find((x) => x.code === w.code);
    const player = room.players.get(w.id);
    return { c, w, room, player, code: w.code };
  }

  it('업적을 이루면 알림 · 칭호를 달면 친구에게도 보인다 · 못 이룬 칭호는 거절', async () => {
    const a = await enter();
    const bUid = uid();
    const b = await enter(a.code, bUid);
    a.c.send({ t: 'set_title', rid: r(), id: 'fish_1' });
    assert.equal((await a.c.type('error')).code, 'bad_title');
    a.player.profile.stats.fish = 1;
    a.c.send({ t: 'emote_quick', quick: ['hello'] }); // 프로필을 다시 보내게
    const ach = await a.c.type('ach');
    assert.ok(ach.ids.includes('fish_1'));
    const prof = await a.c.next((m) => m.t === 'profile' && m.ach.some((x) => x.id === 'fish_1'));
    assert.equal(prof.stats.fish, 1);
    a.c.send({ t: 'set_title', rid: r(), id: 'fish_1' });
    assert.equal((await a.c.type('title')).title, 'fish_1');
    const seen = await b.c.next((m) => m.t === 'title' && m.id === a.w.id);
    assert.equal(seen.title, 'fish_1');
    // 다시 들어온 사람은 입장 정보에서 본다 (방은 2명).
    b.c.kill();
    const again = await enter(a.code, bUid);
    assert.equal(again.w.players.find((p) => p.id === a.w.id).title, 'fish_1');
  });

  it('생일: 오늘로 정하면 친한 주민이 축하 마을톡 + 선물, 친구에게는 마을 소식 · 한 해에 한 번', async () => {
    const a = await enter();
    const b = await enter(a.code);
    const today = dateOfDay(server.clock.day(), DAY_MS, DAY_START_HOUR);
    a.c.send({ t: 'set_birthday', rid: r(), birthday: { m: today.m, d: today.d } });
    const wish = await a.c.next((m) => m.t === 'msg' && m.th.startsWith('npc:'));
    assert.ok(wish.m.tx.length > 0);
    await a.c.next((m) => m.t === 'inventory');
    const note = await b.c.next((m) => m.t === 'msg' && m.th === 'sys:town' && m.m.tx.includes('생일'));
    assert.ok(note);
    const npcMsgs = Object.keys(a.player.profile.chats).filter((th) => th.startsWith('npc:')).length;
    assert.equal(npcMsgs, server.data.npcs.size, '친한 주민 모두');
    // 다시 정해도 또 받지 않는다.
    a.c.send({ t: 'set_birthday', rid: r(), birthday: { m: today.m, d: today.d } });
    await a.c.type('profile');
    const count = a.player.profile.chats['sys:town'].m.length;
    a.c.send({ t: 'set_birthday', rid: r(), birthday: { m: today.m, d: today.d } });
    await a.c.type('profile');
    assert.equal(a.player.profile.chats['sys:town'].m.length, count);
    a.c.send({ t: 'set_birthday', rid: r(), birthday: { m: 2, d: 30 } });
    assert.equal((await a.c.type('error')).code, 'bad_birthday');
  });

  it('달력: 이레치 날씨(여덟 칸) · 이벤트 · 생일', async () => {
    const a = await enter();
    a.player.profile.birthday = { ...dateOfDay(server.clock.day() + 2, DAY_MS, DAY_START_HOUR) };
    delete a.player.profile.birthday.y;
    delete a.player.profile.birthday.wd;
    a.c.send({ t: 'cal_info' });
    const cal = await a.c.type('cal');
    assert.equal(cal.days.length, 7);
    assert.equal(cal.days[0].day, cal.today);
    for (const d of cal.days) {
      assert.equal(d.w.length, 8);
      assert.ok(d.w.every((w) => w === 'clear'));
      assert.equal(typeof d.ev, 'string');
    }
    assert.deepEqual(cal.days[2].pl, [a.w.id]);
  });

  it('놀러 가기 · 방명록: 주인 있는 집만, 주인에게 알림, 집 안 사람에게 새 목록', async () => {
    const host = await enter();
    const guest = await enter(host.code);
    const unit = server.data.units[0].id;
    guest.c.send({ t: 'home_visit', rid: r(), unit });
    assert.equal((await guest.c.type('error')).code, 'not_visitable');
    host.room.homes[unit] = { owner: host.player.uid, price: 1, day: 0 };
    guest.c.send({ t: 'home_visit', rid: r(), unit });
    const home = await guest.c.next((m) => m.t === 'home' && m.unit === unit);
    assert.deepEqual(home.gb, []);
    assert.equal(guest.player.home, unit);
    await host.c.next((m) => m.t === 'visit' && m.id === guest.w.id);
    await host.c.next((m) => m.t === 'msg' && m.th === 'sys:town' && m.m.tx.includes('놀러'));
    guest.c.send({ t: 'gb_write', rid: r(), tx: '  집이 정말 예뻐요!  ' });
    const gb = await guest.c.type('gb');
    assert.deepEqual(gb.list.map((e) => [e.by, e.tx]), [[guest.w.id, '집이 정말 예뻐요!']]);
    await host.c.next((m) => m.t === 'msg' && m.th === 'sys:town' && m.m.tx.includes('방명록'));
    // 너무 잦으면 거른다.
    guest.c.send({ t: 'gb_write', rid: r(), tx: '또' });
    assert.equal((await guest.c.type('error')).code, 'too_fast');
    assert.equal(guest.player.profile.stats.visit, 1);
    assert.equal(guest.player.profile.stats.guestbook, 1);
    // 저장했다 다시 읽어도 방명록이 남는다.
    const saved = host.room.toSave();
    assert.equal(saved.world.guestbooks[unit].length, 1);
  });

  it('사진: 친구 방으로 보내면 두 사람 대화방에 사진 메시지 · 받아 보기 · JPEG 아니면 거절 · 큰 일반 메시지는 거절', async () => {
    const a = await enter();
    const b = await enter(a.code);
    const th = `pl:${b.w.id}`;
    a.c.send({ t: 'photo_up', rid: r(), th, img: Buffer.from('not a jpeg at all, just text').toString('base64') });
    assert.equal((await a.c.type('error')).code, 'bad_photo');
    a.c.send({ t: 'photo_up', rid: r(), th, img: fakeJpeg(30000), tx: '호숫가에서!' });
    const sent = await a.c.type('photo_sent');
    const got = await b.c.next((m) => m.t === 'msg' && m.m.ph === sent.id);
    assert.equal(got.th, `pl:${a.w.id}`);
    assert.equal(got.m.tx, '호숫가에서!');
    b.c.send({ t: 'photo_get', id: sent.id });
    const ph = await b.c.type('photo');
    assert.equal(Buffer.from(ph.img, 'base64').length, 30000);
    b.c.send({ t: 'photo_get', id: 'pzzzzzz' });
    assert.equal((await b.c.type('error')).code, 'no_photo');
    a.c.send({ t: 'say', tx: 'x'.repeat(4000) });
    const big = await a.c.next((m) => m.t === 'error' && m.msg === 'size');
    assert.equal(big.code, 'bad_message');
  });
});
