// 나무 상태(서버 권위). 다 자란 나무(grown)를 도끼로 찍을 때마다 목재 1개, chopsToFell 번째에 쓰러져 그루터기(stump)가 된다.
// 그루터기는 다음 날 묘목(sapling), 그다음 날 다 자란 나무가 된다. 하루가 바뀌면 덜 찍힌 나무의 찍힌 횟수도 회복된다.
// state: { s: 'grown' | 'stump' | 'sapling', c: 오늘 찍힌 횟수, d: c를 센 날짜, f: 쓰러진 날짜 }

export const TreeStage = Object.freeze({ grown: 'grown', stump: 'stump', sapling: 'sapling' });

export function newTreeState() {
  return { s: TreeStage.grown, c: 0, d: 0, f: 0 };
}

/** 날짜가 지난 만큼 자라게 한다. 바뀌었으면 true. */
export function refreshTree(state, today) {
  const before = `${state.s}/${state.c}`;
  if (state.s !== TreeStage.grown) {
    if (today >= state.f + 2) Object.assign(state, { s: TreeStage.grown, c: 0, d: today });
    else if (today >= state.f + 1) state.s = TreeStage.sapling;
  } else if (state.c > 0 && state.d !== today) {
    state.c = 0;
    state.d = today;
  }
  return before !== `${state.s}/${state.c}`;
}

/** 한 번 찍는다. 다 자란 나무가 아니면 null, 아니면 { felled } */
export function chopTree(state, today, chopsToFell) {
  refreshTree(state, today);
  if (state.s !== TreeStage.grown) return null;
  state.c += 1;
  state.d = today;
  if (state.c >= chopsToFell) {
    Object.assign(state, { s: TreeStage.stump, c: 0, f: today });
    return { felled: true };
  }
  return { felled: false };
}

/** 저장 파일 → 데이터에 있는 나무만, 모르는 값은 기본값으로. */
export function sanitizeTrees(raw, defs) {
  const out = new Map();
  for (const id of defs.keys()) {
    const r = raw && typeof raw === 'object' ? raw[id] : null;
    const st = newTreeState();
    if (r && Object.values(TreeStage).includes(r.s)) {
      st.s = r.s;
      st.c = Number.isInteger(r.c) && r.c >= 0 ? r.c : 0;
      st.d = Number.isInteger(r.d) ? r.d : 0;
      st.f = Number.isInteger(r.f) ? r.f : 0;
    }
    out.set(id, st);
  }
  return out;
}

export function treeWire(id, st) {
  return { id, s: st.s, c: st.c };
}
