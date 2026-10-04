import fs from 'node:fs';
import path from 'node:path';
import { ROOM_CODE_ALPHABET, ROOM_CODE_LENGTH } from './protocol.js';

export const SAVE_SCHEMA_VERSION = 5;

const CODE_RE = new RegExp(`^[${ROOM_CODE_ALPHABET}]{${ROOM_CODE_LENGTH}}$`);

/**
 * 방(마을) 하나 = JSON 파일 하나. 방 코드가 파일 이름이라 코드 형식을 먼저 검사해서 경로 조작을 막는다.
 * 쓰기는 임시 파일에 쓴 뒤 rename 하는 원자적 방식이고, 방마다 쓰기를 직렬화한다.
 */
export class RoomStore {
  constructor(dir, { logger = console } = {}) {
    this.dir = dir;
    this.logger = logger;
    this.queues = new Map(); // code -> Promise (진행 중인 쓰기)
    fs.mkdirSync(dir, { recursive: true });
  }

  static isValidCode(code) {
    return typeof code === 'string' && CODE_RE.test(code);
  }

  fileFor(code) {
    return path.join(this.dir, `${code}.json`);
  }

  exists(code) {
    return RoomStore.isValidCode(code) && fs.existsSync(this.fileFor(code));
  }

  /** 없거나 깨졌으면 null. 깨진 파일은 .corrupt-<시각> 으로 치워 둔다(데이터 보존). */
  load(code) {
    if (!RoomStore.isValidCode(code)) return null;
    const file = this.fileFor(code);
    let text;
    try {
      text = fs.readFileSync(file, 'utf8');
    } catch {
      return null;
    }
    try {
      const data = JSON.parse(text);
      if (!data || typeof data !== 'object' || data.code !== code || typeof data.profiles !== 'object') throw new Error('bad shape');
      if (data.schema > SAVE_SCHEMA_VERSION) throw new Error(`newer schema ${data.schema}`);
      return data;
    } catch (err) {
      const backup = `${file}.corrupt-${Date.now()}`;
      try {
        fs.renameSync(file, backup);
      } catch {
        /* ignore */
      }
      this.logger.error?.(`[store] ${code}.json 을 읽을 수 없어 ${path.basename(backup)} 로 옮김: ${err.message}`);
      return null;
    }
  }

  /** 직렬화는 호출 시점에 해서 이후 변경이 섞이지 않게 하고, 쓰기만 비동기로 한다. */
  save(code, data) {
    const text = JSON.stringify(data, null, 2);
    const file = this.fileFor(code);
    const prev = this.queues.get(code) ?? Promise.resolve();
    const next = prev
      .then(async () => {
        const tmp = `${file}.tmp`;
        await fs.promises.writeFile(tmp, text);
        await fs.promises.rename(tmp, file);
      })
      .catch((err) => this.logger.error?.(`[store] ${code} 저장 실패: ${err.message}`));
    this.queues.set(code, next);
    return next;
  }

  async idle() {
    await Promise.all([...this.queues.values()]);
  }
}
