/** 얼굴 꾸미기: 눈·눈동자 색·코·입·피부·머리 모양·머리 색 (data/looks/face_parts.json). 거울 앞에서만 바꿀 수 있다. */

export const FACE_KEYS = ['eyes', 'eye_color', 'nose', 'mouth', 'skin', 'hair', 'hair_color'];

/** face_parts.json → 항목별 id 집합, 자리별 기본 얼굴, 거울 거리. */
export function loadFace(file) {
  const ids = {
    eyes: new Set(file.eyes.map((p) => p.id)),
    eye_color: new Set(file.eye_colors.map((p) => p.id)),
    nose: new Set(file.noses.map((p) => p.id)),
    mouth: new Set(file.mouths.map((p) => p.id)),
    skin: new Set(file.skins.map((p) => p.id)),
    hair: new Set(file.hair_styles.map((p) => p.id)),
    hair_color: new Set(file.hair_colors.map((p) => p.id)),
  };
  const defaults = file.defaults ?? [];
  if (defaults.length === 0) throw new Error('face_parts.json: defaults 가 비었음');
  for (const d of defaults) for (const k of FACE_KEYS) if (!ids[k].has(d[k])) throw new Error(`face default: ${k}=${d[k]} 모름`);
  return { ids, defaults, mirrorRange: file.mirror?.range ?? 2.2 };
}

/** 자리(1, 2 …)의 기본 얼굴. */
export function defaultFace(face, slot) {
  return { ...face.defaults[Math.min(Math.max(slot - 1, 0), face.defaults.length - 1)] };
}

/** 저장 파일의 얼굴: 모르는 id·빠진 항목은 자리 기본값. */
export function sanitizeFace(raw, face, slot) {
  const out = defaultFace(face, slot);
  if (!raw || typeof raw !== 'object') return out;
  for (const k of FACE_KEYS) if (typeof raw[k] === 'string' && face.ids[k].has(raw[k])) out[k] = raw[k];
  return out;
}

/** 요청한 얼굴 (일부 항목만 보내도 된다). 모르는 항목·id 가 하나라도 있으면 null. */
export function applyFaceRequest(current, request, face) {
  if (!request || typeof request !== 'object' || Array.isArray(request)) return null;
  const out = { ...current };
  let any = false;
  for (const [k, v] of Object.entries(request)) {
    if (!FACE_KEYS.includes(k) || typeof v !== 'string' || !face.ids[k].has(v)) return null;
    out[k] = v;
    any = true;
  }
  return any ? out : null;
}

/** 거울 앞인가: 마을에 놓인 거울(village_layout.mirrors) 또는 누군가 놓은 거울 가구. */
export function nearMirror(data, placed, x, z) {
  const range = data.face.mirrorRange + 0.5; // 위치 보고 지연 여유
  for (const m of data.mirrors) if (Math.hypot(x - m.x, z - m.z) <= range) return true;
  for (const f of placed.values()) if (data.items.get(f.item)?.mirror && Math.hypot(x - f.x, z - f.z) <= range) return true;
  return false;
}
