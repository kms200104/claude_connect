import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createNpcRuntime, stepNpcs, updateApproaches } from '../src/npcs.js';

// v0.11: 친한 주민이 가까이 있는 사람에게 먼저 다가가 말을 건다.
const RULES = { min_friendship: 6, range: 9, stop_distance: 1.5, chance_per_s: 1000, cooldown_ms: 300000, npc_cooldown_ms: 45000, wait_ms: 7000, give_up_ms: 15000 };
const defs = new Map([['morak', { id: 'morak', waypoints: [[0, 0], [10, 0]] }]]);

function run(players, friend, steps = 80) {
  const npcs = createNpcRuntime(defs, 0, () => 0.5);
  const greeted = [];
  const seen = {};
  let now = 0;
  for (let i = 0; i < steps; i++) {
    now += 100;
    updateApproaches(npcs, players, {
      rules: RULES,
      now,
      dtMs: 100,
      random: () => 0,
      mode: 'roam',
      friendOf: () => friend,
      lastApproached: (p) => seen[p.id] ?? -Infinity,
      canBeApproached: (p) => !p.busy,
      onGreet: (n, p) => {
        seen[p.id] = now;
        greeted.push([n.id, p.id, Math.hypot(p.x - n.x, p.z - n.z)]);
      },
    });
    stepNpcs(npcs, { dtMs: 100, now, random: () => 0.5, mode: 'roam', speed: 1.4, idleMinMs: 2500, idleMaxMs: 6000 });
  }
  return { greeted, npc: npcs.get('morak') };
}

describe('주민이 먼저 다가와 말 걸기', () => {
  it('친한 사람에게 걸어가서 옆에 멈추고 한 번만 말을 건다', () => {
    const { greeted, npc } = run([{ id: 1, x: 5, z: 3 }], 10);
    assert.equal(greeted.length, 1);
    assert.ok(greeted[0][2] <= 2.0 && greeted[0][2] >= 1.0, `옆에 멈춤 (${greeted[0][2]})`);
    assert.equal(npc.approaching, null);
  });

  it('친하지 않거나 바쁘거나 멀리 있으면 다가가지 않는다', () => {
    assert.equal(run([{ id: 1, x: 5, z: 3 }], 2).greeted.length, 0);
    assert.equal(run([{ id: 1, x: 5, z: 3, busy: true }], 10).greeted.length, 0);
    assert.equal(run([{ id: 1, x: 40, z: 30 }], 10).greeted.length, 0);
  });
});
