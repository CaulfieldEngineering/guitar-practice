// Makes shared/tempo-vectors.json: ascending-tempo inputs and the answers every app must give (the iPhone app's
// TempoPlanTests, the desktop app's tests, npm test). Run it after changing a rule in shared/tempo-plan.mjs,
// TempoPlan.swift and TempoPlan.cpp together:  node scripts/make-tempo-vectors.mjs
//
// Every input is written out in full: the plan, the tempos, and for the accuracy cases each loop's accuracy, length
// and the tempo it was played at (one loop behind the decisions, as in the apps, where the next loop is queued
// before the last is judged).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as T from '../shared/tempo-plan.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// perLoop: the tempo of each loop.
const perLoop = [];
const addPerLoop = (name, plan, start, top, loops) => {
  const p = T.normalize({ ...plan, mode: 'perLoop' });
  perLoop.push({ name, plan: p, start, top, loops, expect: loops.map(([k, e]) => T.perLoopBPM(p, start, top, k, e)) });
};
const ks = (n, secs) => Array.from({ length: n }, (_, k) => [k, k * secs]);
addPerLoop('every 2 loops, hold at the top', { step: 4, every: 2, atTop: 'hold' }, 100, 112, ks(12, 2.4));
addPerLoop('every loop, restart at the top', { step: 5, every: 1, atTop: 'restart' }, 90, 100, ks(9, 2.6));
addPerLoop('every 10 seconds', { step: 3, every: 10, everyUnit: 'seconds' }, 80, 200, ks(14, 2.9));
addPerLoop('a step past the top lands on the top', { step: 7, every: 1 }, 100, 110, ks(5, 2));
addPerLoop('top at the start', { step: 4, every: 1 }, 120, 120, ks(4, 2));

// accuracy: each loop's accuracy, its length, the tempo it was played at, and what the governor did.
const governor = [];
function addGovernor(name, plan, start, top, floor, accuracies, secondsAt = (bpm) => (8 * 60) / bpm) {
  const p = T.normalize({ ...plan, mode: 'accuracy' });
  const g = new T.Governor(p, start, top, floor);
  const loops = [];
  const expect = [];
  let queued = start;                     // the tempo the loop being judged was played at (one behind)
  for (const a of accuracies) {
    const bpm = queued;
    const seconds = Math.round(secondsAt(bpm) * 1e6) / 1e6;
    queued = g.target;                    // the next loop was queued before this one was judged
    const c = g.judge(a, seconds, bpm);
    loops.push([a, seconds, bpm]);
    expect.push({ change: c, target: g.target, progress: Math.round(g.progress() * 1e6) / 1e6, zone: T.zoneOf(p, a) });
  }
  governor.push({ name, plan: p, start, top, floor, loops, expect });
}
const steady = (n, a) => Array(n).fill(a);
addGovernor('up after 4 loops at 90 or more, then again', { upPercent: 90, upWindow: 4, step: 4 }, 100, 140, 100, steady(14, 0.93));
addGovernor('hold between the thresholds', { upPercent: 90, downPercent: 75, upWindow: 3, downWindow: 3 }, 100, 140, 96, steady(10, 0.82));
addGovernor('down when under 75 for 3 loops, not under the floor',
  { upPercent: 90, downPercent: 75, upWindow: 3, downWindow: 3, step: 4 }, 112, 140, 104, steady(16, 0.6));
addGovernor('break under 50 for 2 loops, a step slower after',
  { breakOn: true, breakPercent: 50, breakWindow: 2, downWindow: 4, step: 4, slowerAfterBreak: true }, 120, 160, 100, [0.9, 0.4, 0.3, 0.92, 0.95]);
addGovernor('break, same tempo after', { breakOn: true, breakPercent: 50, breakWindow: 2, slowerAfterBreak: false }, 120, 160, 100, [0.3, 0.2, 0.6]);
addGovernor('hysteresis: near the up line it does not flip',
  { upPercent: 90, downPercent: 75, upWindow: 2, downWindow: 2, cooldownLoops: 1 }, 100, 140, 92, [0.91, 0.91, 0.89, 0.88, 0.9, 0.91, 0.89, 0.9]);
addGovernor('cooldown: 2 loops after a change are not counted',
  { upPercent: 90, upWindow: 1, cooldownLoops: 2, step: 2 }, 100, 140, 100, steady(10, 0.95));
addGovernor('windows in seconds', { windowUnit: 'seconds', upPercent: 85, upWindow: 10, downWindow: 10, step: 5 }, 100, 140, 100,
  steady(12, 0.9));
addGovernor('thresholds too close are pulled apart', { upPercent: 80, downPercent: 79, breakOn: true, breakPercent: 78, upWindow: 2, downWindow: 2, breakWindow: 2 },
  100, 140, 90, [0.76, 0.76, 0.76, 0.74, 0.7, 0.69]);
addGovernor('holds at the top', { upPercent: 90, upWindow: 1, cooldownLoops: 0, step: 10 }, 100, 120, 100, steady(6, 0.99));
addGovernor('a down is the average over its whole window', { downPercent: 75, downWindow: 4, upWindow: 4 }, 120, 140, 100, [0.5, 0.5, 0.5, 0.95, 0.5, 0.5]);

const zones = [];
for (const plan of [{}, { breakOn: true }, { downOn: false }, { downOn: false, breakOn: true }]) {
  const p = T.normalize({ ...plan, mode: 'accuracy' });
  for (const a of [1, 0.9, 0.89, 0.75, 0.74, 0.5, 0.49, 0]) zones.push({ plan: p, accuracy: a, expect: T.zoneOf(p, a) });
}

const bounds = [
  [{ endBPM: 0, minBPM: 0 }, 100, { min: 40, max: 200 }],
  [{ endBPM: 150, minBPM: 0 }, 100, { min: 40, max: 200 }],
  [{ endBPM: 250, minBPM: 80 }, 100, { min: 40, max: 200 }],
  [{ endBPM: 90, minBPM: 120 }, 100, { min: 40, max: 200 }],
  [{ endBPM: 0, minBPM: 20 }, 100, { min: 40, max: 200 }],
].map(([plan, start, rule]) => { const p = T.normalize(plan); return { plan: p, start, rule, expect: T.bounds(p, start, rule) }; });

const out = { comment: 'Made by scripts/make-tempo-vectors.mjs from shared/tempo-plan.mjs. Do not edit by hand.', perLoop, governor, zones, bounds };
fs.writeFileSync(path.join(ROOT, 'shared', 'tempo-vectors.json'), JSON.stringify(out, null, 1) + '\n');
console.log(`shared/tempo-vectors.json: ${perLoop.length} per-loop, ${governor.length} governor, ${zones.length} zone, ${bounds.length} bounds cases`);

// Challenge: each loop's accuracy and length, and the clock after it.
const challenge = [];
function addChallenge(name, opts, loops) {
  const c = new T.ChallengeClock(opts);
  const expect = loops.map(([a, s]) => ({ result: c.judge(a, s), earned: c.earned, elapsed: c.elapsed, inZone: c.inZone,
    bestStreak: c.bestStreak, share: Math.round(c.share * 1e6) / 1e6 }));
  challenge.push({ name, opts, loops, expect });
}
addChallenge('earns only in the zone, pauses under it', { targetSeconds: 20, percent: 90, window: 1 },
  [[0.95, 4], [0.95, 4], [0.8, 4], [0.85, 4], [0.92, 4], [0.97, 4], [0.99, 4], [0.99, 4]]);
addChallenge('the rolling window smooths one bad loop', { targetSeconds: 12, percent: 90, window: 2 },
  [[0.96, 3], [0.86, 3], [0.96, 3], [0.6, 3], [0.6, 3], [0.97, 3], [0.97, 3], [0.97, 3], [0.97, 3]]);
addChallenge('the cap ends it before the target', { targetSeconds: 60, percent: 90, window: 1, capSeconds: 15 },
  [[0.95, 5], [0.5, 5], [0.95, 5], [0.95, 5]]);
addChallenge('best streak is the longest run in the zone', { targetSeconds: 100, percent: 85, window: 1 },
  [[0.9, 2], [0.9, 2], [0.8, 2], [0.9, 2], [0.9, 2], [0.9, 2], [0.7, 2]]);
const vec = JSON.parse(fs.readFileSync(path.join(ROOT, 'shared', 'tempo-vectors.json'), 'utf8'));
vec.challenge = challenge;
fs.writeFileSync(path.join(ROOT, 'shared', 'tempo-vectors.json'), JSON.stringify(vec, null, 1) + '\n');
console.log(`and ${challenge.length} challenge cases`);
