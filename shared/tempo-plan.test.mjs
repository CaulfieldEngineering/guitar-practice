// The ascending-tempo vectors are what shared/tempo-plan.mjs says, and the rules hold: node --test shared/
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as T from './tempo-plan.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const V = JSON.parse(fs.readFileSync(path.join(ROOT, 'shared', 'tempo-vectors.json'), 'utf8'));

test('per loop: every tempo as the vectors say', () => {
  for (const c of V.perLoop) assert.deepEqual(c.loops.map(([k, e]) => T.perLoopBPM(c.plan, c.start, c.top, k, e)), c.expect, c.name);
});

test('accuracy-gated: every decision as the vectors say', () => {
  for (const c of V.governor) {
    const g = new T.Governor(c.plan, c.start, c.top, c.floor);
    c.loops.forEach(([a, s, bpm], i) => {
      const ch = g.judge(a, s, bpm);
      assert.deepEqual(ch, c.expect[i].change, `${c.name} loop ${i}`);
      assert.equal(g.target, c.expect[i].target, `${c.name} loop ${i} target`);
      assert.ok(Math.abs(g.progress() - c.expect[i].progress) < 1e-6, `${c.name} loop ${i} progress`);
      assert.equal(T.zoneOf(c.plan, a), c.expect[i].zone, `${c.name} loop ${i} zone`);
    });
  }
  for (const c of V.zones) assert.equal(T.zoneOf(c.plan, c.accuracy), c.expect);
  for (const c of V.bounds) assert.deepEqual(T.bounds(c.plan, c.start, c.rule), c.expect);
});

const run = (plan, start, top, floor, accs) => {
  const g = new T.Governor(plan, start, top, floor);
  let queued = start;
  return accs.map((a) => { const bpm = queued; queued = g.target; return g.judge(a, 3, bpm); }).filter(Boolean);
};

test('up, down and break each happen, and only past their own threshold for their own window', () => {
  const p = { mode: 'accuracy', upPercent: 90, upWindow: 3, downPercent: 75, downWindow: 3, breakOn: true, breakPercent: 50, breakWindow: 2 };
  assert.deepEqual(run(p, 100, 140, 90, [0.95, 0.95, 0.95]).map((c) => c.kind), ['up']);
  assert.deepEqual(run(p, 100, 140, 90, [0.95, 0.95]), []);
  assert.deepEqual(run(p, 100, 140, 90, [0.6, 0.6, 0.6]).map((c) => c.kind), ['down']);
  assert.deepEqual(run(p, 100, 140, 90, [0.3, 0.3]).map((c) => c.kind), ['break']);
  assert.deepEqual(run(p, 100, 140, 100, [0.6, 0.6, 0.6, 0.6]), [], 'never under the floor');
});

test('hysteresis: the thresholds are kept apart and a loop between them holds', () => {
  const n = T.normalize({ upPercent: 80, downPercent: 82, breakOn: true, breakPercent: 90 });
  assert.ok(n.downPercent <= n.upPercent - 5 && n.breakPercent <= n.downPercent - 5);
  const p = { mode: 'accuracy', upPercent: 90, upWindow: 1, downPercent: 75, downWindow: 1, cooldownLoops: 0 };
  // Alternating just under and just over a band edge never goes down after an up.
  const kinds = run(p, 100, 200, 90, [0.91, 0.91, 0.89, 0.8, 0.89, 0.8]).map((c) => c.kind);
  assert.ok(!kinds.includes('down'), kinds.join());
});

test('cooldown: after a change no loop counts until it has passed, and loops at the old tempo never count', () => {
  const g = new T.Governor({ mode: 'accuracy', upPercent: 90, upWindow: 1, cooldownLoops: 2 }, 100, 200, 100);
  assert.equal(g.judge(0.95, 3, 100)?.kind, 'up');
  assert.equal(g.judge(0.95, 3, 100), null, 'still at the old tempo');
  assert.equal(g.judge(0.95, 3, 104), null, 'cooldown 1');
  assert.equal(g.judge(0.95, 3, 104), null, 'cooldown 2');
  assert.equal(g.judge(0.95, 3, 104)?.kind, 'up');
});

test('challenge: the clock runs only while the accuracy holds, as the vectors say', () => {
  for (const c of V.challenge) {
    const k = new T.ChallengeClock(c.opts);
    c.loops.forEach(([a, s], i) => {
      const r = k.judge(a, s);
      const e = c.expect[i];
      assert.deepEqual({ result: r, earned: k.earned, elapsed: k.elapsed, inZone: k.inZone, bestStreak: k.bestStreak,
        share: Math.round(k.share * 1e6) / 1e6 }, e, `${c.name} loop ${i}`);
    });
  }
});

test('challenge: under the threshold nothing is earned, and it ends exactly at the target', () => {
  const k = new T.ChallengeClock({ targetSeconds: 10, percent: 90, window: 1 });
  assert.equal(k.judge(0.89, 4), 'held');
  assert.equal(k.earned, 0);
  assert.equal(k.judge(0.9, 4), 'earned');
  assert.equal(k.judge(0.95, 4), 'earned');
  assert.equal(k.judge(0.95, 4), 'done');
  assert.equal(k.earned, 10, 'never past the target');
  assert.equal(k.elapsed, 16);
});
