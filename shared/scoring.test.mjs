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
