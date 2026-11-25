// Makes shared/routine-vectors.json: scripts of what the player does at what second, and what the routine clock must
// say after each step (the iPhone app's RoutineClockTests, the desktop tests, npm test). Run it after changing a rule
// in shared/routine-clock.mjs, RoutineClock.swift and RoutineClock.cpp together:  node scripts/make-routine-vectors.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { RoutineClock } from '../shared/routine-clock.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cases = [];
function add(name, blocks, steps, estimates = []) {
  const c = new RoutineClock(blocks);
  const expect = steps.map(([t, action]) => {
    let events = [];
    if (action === 'start') events = c.start(t);
    else if (action === 'tick') events = c.tick(t);
    else if (action === 'pause') c.pause(t);
    else if (action === 'resume') events = c.resume(t);
    else if (action === 'skip') events = c.skip(t);
    else if (action === 'back') c.back(t);
    else if (action === 'blockDone') events = c.blockDone(t);
    return { events, state: c.state(t), remaining: c.remaining(t, estimates) };
  });
  cases.push({ name, blocks, steps, estimates, expect, log: c.log });
}
const warm = { seconds: 60 }, drill = { seconds: null }, rest = { seconds: 30 }, free = { seconds: 120 };
add('runs straight through, countdown before each block', [warm, rest, free],
  [[0, 'start'], [1, 'tick'], [2.5, 'tick'], [3, 'tick'], [62.9, 'tick'], [63, 'tick'], [65, 'tick'], [66, 'tick'], [96, 'tick'], [99, 'tick'], [219, 'tick'], [220, 'tick']]);
add('a late tick catches up on every change it missed', [warm, rest, free], [[0, 'start'], [200, 'tick'], [300, 'tick']]);
add('pause holds the block and the countdown', [warm, rest],
  [[0, 'start'], [1, 'pause'], [50, 'resume'], [52, 'tick'], [62, 'pause'], [100, 'tick'], [100, 'resume'], [150, 'tick'], [153, 'tick']]);
add('skip ends a block now and keeps what it ran', [warm, rest, free],
  [[0, 'start'], [20, 'skip'], [21, 'tick'], [23, 'tick'], [30, 'skip'], [30, 'skip'], [40, 'tick']]);
add('a drill by reps ends when it says so', [warm, drill, rest],
  [[0, 'start'], [63, 'tick'], [66, 'tick'], [200, 'tick'], [210, 'blockDone'], [213, 'tick'], [243, 'tick']], [0, 96, 0]);
add('back: early goes to the block before, later starts it again', [warm, rest, free],
  [[0, 'start'], [63, 'tick'], [65, 'tick'], [67, 'back'], [70, 'tick'], [100, 'back'], [103, 'tick'], [104, 'back'], [107, 'tick']]);
add('pause in a drill by reps, then it finishes', [warm, drill], [[0, 'start'], [63, 'tick'], [70, 'pause'], [90, 'blockDone'], [90, 'tick']], [0, 50]);
add('skip a countdown', [warm, rest], [[0, 'start'], [1, 'skip'], [61, 'tick'], [62, 'tick']]);
fs.writeFileSync(path.join(ROOT, 'shared', 'routine-vectors.json'),
  JSON.stringify({ comment: 'Made by scripts/make-routine-vectors.mjs from shared/routine-clock.mjs. Do not edit by hand.', cases }, null, 1) + '\n');
console.log(`shared/routine-vectors.json: ${cases.length} cases`);
