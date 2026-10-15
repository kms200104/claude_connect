// v0.28.2 게이트 안 던전 (서버 권위, 그림은 클라이언트 game/hunter/dungeon_field.gd):
// 게이트에 들어가면 도시 밖 먼 곳의 별도 공간(무너진 지하철역 · 이끼 낀 동굴)으로 옮겨 가 그 안에서 웨이브 · 우두머리와 싸운다.
// 던전 자리는 게이트 자리(spots) 순서마다 하나 — data/hunter/hunter.json gates.dungeon (x0 + i × dx, z0).
// 판정은 사각형 바닥 · 기둥(원) · 잔해(사각형)만 (물리 없음). 클라이언트 core/types/hunter_rules.gd 와 같은 계산.

/** 그 게이트 자리의 던전 가운데 (월드 좌표). */
export function dungeonOrigin(G, spotId) {
  const D = G?.dungeon;
  if (!D) return null;
  const i = G.spots.findIndex((s) => s.id === spotId);
  if (i < 0) return null;
  return { x: D.x0 + i * D.dx, z: D.z0 };
}

/** (x, z) 가 어느 던전 영역 안이면 { spot, o } (영역 = 가장 큰 지도 반 너비 + 여유), 아니면 null. */
export function dungeonAt(G, x, z) {
  const D = G?.dungeon;
  if (!D) return null;
  if (Math.abs(z - D.z0) > D.dx * 0.5) return null;
  const i = Math.round((x - D.x0) / D.dx);
  if (i < 0 || i >= G.spots.length) return null;
  return { spot: G.spots[i].id, o: { x: D.x0 + i * D.dx, z: D.z0 } };
}

/** 그 지도에서 서 있을 수 있는 곳 (로컬 좌표, 벽 · 기둥 · 잔해에서 pad 만큼 떨어져). */
export function dungeonStandLocal(map, lx, lz, pad = 0.35) {
  if (Math.abs(lx) > map.w / 2 - pad || Math.abs(lz) > map.d / 2 - pad) return false;
  for (const [px, pz, r] of map.pillars ?? []) if (Math.hypot(lx - px, lz - pz) < r + pad) return false;
  for (const [rx, rz, w, d] of map.rubble ?? []) if (Math.abs(lx - rx) < w / 2 + pad && Math.abs(lz - rz) < d / 2 + pad) return false;
  return true;
}
