// The shared scoring vectors are what shared/scoring.mjs says, and the drill server's max rule agrees with them.
// node --test shared/
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from './scoring.mjs';
import { learnedTempo as serverMax } from '../server/store.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const V = JSON.parse(fs.readFileSync(path.join(ROOT, 'shared', 'scoring-vectors.json'), 'utf8'));
const near = (a, b, msg) => assert.ok(Math.abs(a - b) <= V.tolerance, `${msg}: ${a} vs ${b}`);

test('the vectors use the catalog\'s scoring numbers', () => {
  const cat = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'scoring.json'), 'utf8'));
  for (const k of ['fullFraction', 'zeroFraction', 'fullMinMs', 'fullMaxMs', 'zeroMinMs', 'zeroMaxMs', 'extraWeight']) assert.equal(V.config[k], cat[k], k);
});

test('every run scores as the vectors say', () => {
  for (const c of V.score) {
    const notes = c.notes.map(([time, accent, beat]) => ({ time, accent: !!accent, beat }));
    const played = c.played.map(([time, strength]) => ({ time, strength }));
    const r = S.score(notes, played, c.window, c.rule, V.config);
    for (const k of ['score', 'hits', 'missed', 'extra', 'within20', 'within40', 'full', 'accentsLanded', 'accentBeats', 'pct20', 'pct40', 'passed']) assert.equal(r[k], c.expect[k], `${c.name} ${k}`);
    for (const k of ['meanError', 'spread', 'fullMs', 'zeroMs']) near(r[k], c.expect[k], `${c.name} ${k}`);
    assert.equal(S.band(r.spread), c.expect.band);
  }
});

test('doubles, cycle accuracy, credit, calibration, grid and max', () => {
  for (const c of V.doubles) assert.deepEqual(S.dropDoubles(c.picks.map(([time, strength]) => ({ time, strength })), c.within, c.ratio).map((o) => [o.time, o.strength]), c.expect, c.name);
  for (const c of V.accuracy) near(S.accuracy(c.errors, c.gaps, c.extras, V.config), c.expect, 'accuracy');
  for (const c of V.credit) near(S.credit(V.config, c.errorMs, c.gap), c.expect, `credit ${c.gap} ${c.errorMs}`);
  for (const c of V.calibration) {
    const r = S.calibration(c.clicks, c.played);
    if (c.expect === null) { assert.equal(r, null); continue; }
    near(r.offset, c.expect.offset, c.name); assert.equal(r.hits, c.expect.hits);
  }
  for (const c of V.max) {
    assert.equal(S.learnedTempo(c.runs, 'trip16x4'), c.expect, c.name);
    assert.equal(serverMax(c.runs, 'trip16x4')?.max ?? null, c.expect, `server ${c.name}`);
  }
});

test('pitch: X notes score on timing only, pitched notes check the pitch in the tuning', () => {
  for (const c of V.pitch) {
    const r = S.score(c.notes.map(([time, accent, beat, pitch]) => ({ time, accent: !!accent, beat, pitch })),
      c.played.map(([time, strength, pitch]) => ({ time, strength, pitch })), 0.05, S.standardRule, V.config);
    assert.deepEqual({ score: r.score, hits: r.hits, wrongPitch: r.wrongPitch }, c.expect, c.name);
  }
  const x = V.pitch.find((c) => c.name.startsWith('X notes: any'));
  const right = V.pitch.find((c) => c.name === 'pitched: right notes in E standard');
  assert.equal(x.expect.score, right.expect.score, 'an X run with any pitches scores what a right-note run does');
  assert.equal(x.expect.wrongPitch, 0);
  assert.equal(V.pitch.find((c) => c.name.includes('two wrong')).expect.wrongPitch, 2);
  assert.equal(V.pitch.find((c) => c.name.includes('drop D')).expect.wrongPitch, 8);
  assert.equal(S.notePitch([64, 59, 55, 50, 45, 38], 6, 0), 38);
  assert.equal(S.notePitch([64, 59, 55, 50, 45, 40], 6, 'x'), null);
});
