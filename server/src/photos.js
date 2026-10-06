// v16 사진: 휴대폰 카메라로 찍은 사진을 마을톡으로 친구에게 보낸다. 사진은 방 저장 파일과 따로
// <saveDir>/photos/<방 코드>/<id>.jpg 에 두고, 마을톡 메시지에는 id 만 싣는다 (받은 사람이 photo_get 으로 받아 간다).
// 방마다 최근 max_per_room 장까지만 두고 오래된 것부터 지운다. JPEG 만, 크기 상한.
import fs from 'node:fs';
import path from 'node:path';
import { RoomStore } from './persistence.js';

export const PHOTO_RULES = Object.freeze({
  maxBytes: 96 * 1024, // 디코딩한 JPEG 크기
  maxPerRoom: 80,
  gapMs: 4000, // 한 사람이 보내는 간격
  maxSide: 1024,
});
const ID_RE = /^p[0-9a-z]{4,20}$/;

export function createPhotoStore(saveDir) {
  const root = path.join(saveDir, 'photos');

  const dirOf = (code) => (RoomStore.isValidCode(code) ? path.join(root, code) : null);

  /** base64 JPEG 를 검사해 버퍼로 (아니면 null). */
  function decode(b64) {
    if (typeof b64 !== 'string' || b64.length > Math.ceil((PHOTO_RULES.maxBytes * 4) / 3) + 8) return null;
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(b64)) return null;
    const buf = Buffer.from(b64, 'base64');
    if (buf.length < 64 || buf.length > PHOTO_RULES.maxBytes) return null;
    // JPEG 시작(FF D8)과 끝(FF D9).
    if (buf[0] !== 0xff || buf[1] !== 0xd8 || buf[buf.length - 2] !== 0xff || buf[buf.length - 1] !== 0xd9) return null;
    return buf;
  }

  /** 저장하고 방의 사진 목록(room.photos)에 올린다. 넘치면 오래된 것을 지운다. */
  function put(room, buf, by, at) {
    const dir = dirOf(room.code);
    if (!dir) return null;
    room.photoSeq = (room.photoSeq ?? 0) + 1;
    const id = `p${room.photoSeq.toString(36)}${Math.floor(at % 1679616).toString(36).padStart(4, '0')}`;
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, `${id}.jpg`), buf);
    room.photos ??= [];
    room.photos.push({ id, by, at });
    while (room.photos.length > PHOTO_RULES.maxPerRoom) {
      const old = room.photos.shift();
      try {
        fs.unlinkSync(path.join(dir, `${old.id}.jpg`));
      } catch {
        /* 이미 없음 */
      }
    }
    room.saveDirty = true;
    return id;
  }

  /** base64 로 읽기 (없으면 null). */
  function get(room, id) {
    const dir = dirOf(room.code);
    if (!dir || typeof id !== 'string' || !ID_RE.test(id) || !(room.photos ?? []).some((p) => p.id === id)) return null;
    try {
      return fs.readFileSync(path.join(dir, `${id}.jpg`)).toString('base64');
    } catch {
      return null;
    }
  }

  return { decode, put, get };
}

/** 저장 파일의 사진 목록 정리. */
export function sanitizePhotos(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((p) => p && typeof p.id === 'string' && ID_RE.test(p.id) && Number.isInteger(p.by) && Number.isFinite(p.at))
    .slice(-PHOTO_RULES.maxPerRoom)
    .map((p) => ({ id: p.id, by: p.by, at: p.at }));
}
