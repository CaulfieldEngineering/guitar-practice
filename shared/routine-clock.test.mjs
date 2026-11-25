// The routine clock gives the answers in shared/routine-vectors.json, and its timing rules hold: node --test shared/
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { RoutineClock } from './routine-clock.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const V = JSON.parse(fs.readFileSync(path.join(ROOT, 'shared', 'routine-vectors.json'), 'utf8'));

test('every script as the vectors say', () => {
  for (const c of V.cases) {
    const k = new RoutineClock(c.blocks);
    c.steps.forEach(([t, a], i) => {
      const ev = a === 'start' ? k.start(t) : a === 'tick' ? k.tick(t) : a === 'resume' ? k.resume(t) : a === 'skip' ? k.skip(t)
        : a === 'blockDone' ? k.blockDone(t) : (k[a](t), []);
      assert.deepEqual(ev, c.expect[i].events, `${c.name} step ${i}`);
      assert.deepEqual(k.state(t), c.expect[i].state, `${c.name} step ${i} state`);
      assert.equal(k.remaining(t, c.estimates), c.expect[i].remaining, `${c.name} step ${i} remaining`);
    });
    assert.deepEqual(k.log, c.log, c.name);
  }
});

test('timing: a 60 s block starts 3 s in, ends at 63, and the next countdown starts there exactly', () => {
  const k = new RoutineClock([{ seconds: 60 }, { seconds: 30 }]);
  k.start(0);
  assert.deepEqual(k.tick(2.999), []);
  assert.deepEqual(k.tick(3), [['start', 0]]);
  assert.equal(k.state(33).left, 30);
  assert.deepEqual(k.tick(63.5), [['end', 0]]);
  assert.equal(k.state(63.5).left, 2.5, 'the countdown started at 63, not at the late tick');
  assert.deepEqual(k.tick(66), [['start', 1]]);
  assert.deepEqual(k.tick(96), [['end', 1], ['done']]);
  assert.deepEqual(k.log.map((l) => l.seconds), [60, 30]);
});

test('a pause adds nothing to the block and nothing is lost', () => {
  const k = new RoutineClock([{ seconds: 10 }]);
  k.start(0); k.tick(3); k.pause(5); k.resume(500);
  assert.equal(k.state(500).left, 8);
  assert.deepEqual(k.tick(508), [['end', 0], ['done']]);
  assert.equal(k.log[0].seconds, 10);
});

test('the countdown ticks 3, 2, 1', () => {
  const k = new RoutineClock([{ seconds: 5 }]);
  k.start(0);
  assert.deepEqual([0, 1, 2, 2.9].map((t) => k.state(t).countdownTick), [3, 2, 1, 1]);
});
