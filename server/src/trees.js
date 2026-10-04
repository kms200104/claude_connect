// 나무 상태(서버 권위). 다 자란 나무(grown)를 도끼로 찍을 때마다 목재 1개, chopsToFell 번째에 쓰러져 그루터기(stump)가 된다.
// 그루터기는 게임 시간으로 regrow_minutes 만큼씩 지나면 묘목(sapling) → 어린 나무(young) → 다 자란 나무로 다시 자란다.
// 씨앗을 심은 나무는 새싹(sprout)부터 시작해 같은 단계를 거친다. 하루가 바뀌면 덜 찍힌 나무의 찍힌 횟수도 회복된다.
// state: { s: 단계, c: 오늘 찍힌 횟수, d: c를 센 날짜, t: 지금 단계가 시작된 게임 시각(ms) }

export const TreeStage = Object.freeze({ grown: 'grown', stump: 'stump', sprout: 'sprout', sapling: 'sapling', young: 'young' });

const MINUTE_MS = 60000;
const NEXT = { stump: 'sapling', sprout: 'sapling', sapling: 'young', young: 'grown' };

export function newTreeState(stage = TreeStage.grown, t = 0) {
  return { s: stage, c: 0, d: 0, t };
}

/**
 * 시간이 지난 만큼 자라게 한다. 바뀌었으면 true.
 * minutes: 단계별 머무는 시간(게임 분) { stump, sprout, sapling, young }, scale: 테스트용 배율 (작을수록 빨리 자란다).
 */
export function refreshTree(state, today, nowMs, minutes, scale = 1) {
  const before = `${state.s}/${state.c}`;
  let guard = 0;
  while (state.s !== TreeStage.grown && guard++ < 8) {
    const stay = (minutes[state.s] ?? 10) * MINUTE_MS * scale;
    if (nowMs - state.t < stay) break;
    state.t += stay;
    state.s = NEXT[state.s] ?? TreeStage.grown;
    if (state.s === TreeStage.grown) {
      state.c = 0;
      state.d = today;
    }
  }
  if (state.s === TreeStage.grown && state.c > 0 && state.d !== today) {
    state.c = 0;
    state.d = today;
  }
  return before !== `${state.s}/${state.c}`;
}

/** 한 번 찍는다. 다 자란 나무가 아니면 null, 아니면 { felled } */
export function chopTree(state, today, nowMs, chopsToFell) {
  if (state.s !== TreeStage.grown) return null;
  state.c += 1;
  state.d = today;
  if (state.c >= chopsToFell) {
    Object.assign(state, { s: TreeStage.stump, c: 0, t: nowMs });
    return { felled: true };
  }
  return { felled: false };
}

function sanitizeState(r) {
  const st = newTreeState();
  if (r && Object.values(TreeStage).includes(r.s)) {
    st.s = r.s;
    st.c = Number.isInteger(r.c) && r.c >= 0 ? r.c : 0;
    st.d = Number.isInteger(r.d) ? r.d : 0;
    // 옛 저장 파일(날짜 단위 f)에는 t 가 없다 → 0 이면 다음 틱에 바로 다 자란다.
    st.t = Number.isFinite(r.t) ? r.t : 0;
  }
  return st;
}

/** 저장 파일 → 데이터에 있는 나무만, 모르는 값은 기본값으로. */
export function sanitizeTrees(raw, defs) {
  const out = new Map();
  for (const id of defs.keys()) out.set(id, sanitizeState(raw && typeof raw === 'object' ? raw[id] : null));
  return out;
}

/** 저장 파일 → 심은 나무 { id, kind, x, z, by } 와 상태. 모양이 맞고 나무 종류를 아는 것만. */
export function sanitizePlanted(raw, kinds, limit) {
  const defs = new Map();
  const states = new Map();
  if (!Array.isArray(raw)) return { defs, states };
  for (const p of raw.slice(0, limit)) {
    if (!p || typeof p.id !== 'string' || !/^p\d+$/.test(p.id) || !kinds.includes(p.kind)) continue;
    if (!Number.isFinite(p.x) || !Number.isFinite(p.z)) continue;
    defs.set(p.id, { id: p.id, kind: p.kind, x: p.x, z: p.z, by: Number.isInteger(p.by) ? p.by : 0, planted: true });
    states.set(p.id, sanitizeState(p.st));
  }
  return { defs, states };
}

/** 방송용. 심은 나무는 자리와 종류도 함께 보낸다. */
export function treeWire(id, st, def = null) {
  const wire = { id, s: st.s, c: st.c };
  if (def?.planted) Object.assign(wire, { k: def.kind, x: def.x, z: def.z });
  return wire;
}
