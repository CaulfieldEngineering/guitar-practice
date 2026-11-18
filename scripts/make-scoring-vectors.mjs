// Makes shared/scoring-vectors.json: inputs and the answers every app must give (the iPhone app's
// ScoringVectorTests, the desktop app's tests, npm test). Run it after changing a scoring rule in shared/scoring.mjs,
// Scoring.swift and Scoring.cpp together:  node scripts/make-scoring-vectors.mjs
//
// Inputs are written out in full (note times, picks, strengths), so no app needs this script's random numbers.
// Picks are made with whole-ish times and strengths that are exact in 32-bit floats (1, 0.5, 0.25, 2), and no case
// sits on a rounding edge, so a 64-bit and a 32-bit strength give the same answer.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from '../shared/scoring.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'scoring.json'), 'utf8'));
const config = { ...S.standardConfig, ...catalog };
const drills = Object.fromEntries(JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'exercises', 'right-hand.json'), 'utf8'))
  .exercises.map((e) => [e.id, e]));

// A small seeded generator (mulberry32) and a Gaussian from it.
function rng(seed) {
  let a = seed >>> 0;
  const next = () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const gauss = () => { const u = Math.max(1e-12, next()), v = next(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); };
  return { next, gauss };
}
const q = (x) => Math.round(x * 1e6) / 1e6;   // microsecond times: short in the file, exact enough

function specsOf(d) {
  if (d.groups) return { specs: S.expand(d.groups, d.accent === 'first'), cycleBeats: d.groups.length };
  const specs = [...d.notes].sort((a, b) => (a.at.beat + (a.at.step ?? 0) / (a.at.of ?? 1)) - (b.at.beat + (b.at.step ?? 0) / (b.at.of ?? 1)));
  const last = Math.floor(specs[specs.length - 1].at.beat + (specs[specs.length - 1].at.step ?? 0) / (specs[specs.length - 1].at.of ?? 1)) + 1;
  return { specs, cycleBeats: d.cycleBeats ?? last };
}

const scoreCases = [];
function scoreCase(name, drillID, bpm, seconds, { seed, mean = 0, spread = 15, miss = 0, extra = 0, doubles = 0, accentBoost = 2 }) {
  const d = drills[drillID];
  const { specs, cycleBeats } = specsOf(d);
  const notes = S.runNotes(specs, cycleBeats, bpm, 0.5, seconds).map((n) => ({ ...n, time: q(n.time) }));
  const r = rng(seed);
  let played = [];
  for (const n of notes) {
    if (r.next() < miss) continue;
    const err = (mean + spread * r.gauss()) / 1000;
    played.push({ time: q(n.time + err), strength: n.accent ? accentBoost : 1 });
    if (r.next() < doubles) played.push({ time: q(n.time + err + 0.012 + 0.01 * r.next()), strength: 0.25 });
  }
  for (let k = 0; k < Math.round(extra * notes.length); k++) {
    const t = notes[0].time + r.next() * (notes[notes.length - 1].time - notes[0].time);
    played.push({ time: q(t), strength: 1 });
  }
  played.sort((a, b) => a.time - b.time);
  const window = d.scoring?.windowMs ? d.scoring.windowMs / 1000 : S.matchWindow(S.shortestGap(specs, cycleBeats, bpm));
  const rule = { ...S.standardRule, ...(d.scoring || {}) };
  const res = S.score(notes, played, window, rule, config);
  scoreCases.push({
    name, drill: drillID, bpm, window, rule: { passMark: rule.passMark, tightMs: rule.tightMs, closeMs: rule.closeMs },
    notes: notes.map((n) => [n.time, n.accent ? 1 : 0, n.beat]),
    played: played.map((p) => [p.time, p.strength]),
    expect: {
      score: res.score, expected: res.expected, hits: res.hits, missed: res.missed, extra: res.extra,
      within20: res.within20, within40: res.within40, full: res.full, pct20: res.pct20, pct40: res.pct40, passed: res.passed,
      meanError: res.meanError, spread: res.spread, fullMs: res.fullMs, zeroMs: res.zeroMs,
      accentsLanded: res.accentsLanded, accentBeats: res.accentBeats,
      errors: res.errors, extraOffsets: res.extraOffsets, band: S.band(res.spread),
    },
  });
}

scoreCase('flagship at 90, tight player', 'trip16x4', 90, 16, { seed: 1, spread: 12 });
scoreCase('flagship at 90, good amateur', 'trip16x4', 90, 16, { seed: 2, spread: 25 });
scoreCase('flagship at 120, loose, late', 'trip16x4', 120, 16, { seed: 3, mean: 18, spread: 40, miss: 0.05 });
scoreCase('eighths at 80, early', 'alt8', 80, 12, { seed: 4, mean: -10, spread: 15 });
scoreCase('sixteenths at 160, extras', 'alt16', 160, 8, { seed: 5, spread: 10, extra: 0.1 });
scoreCase('triplets at 100, misses', 'alt3', 100, 10, { seed: 6, spread: 20, miss: 0.2 });
scoreCase('threes to fours at 80', '3to4', 80, 12, { seed: 7, spread: 18 });
scoreCase('speed bursts at 110 (rest bars)', 'burst', 110, 17.5, { seed: 8, spread: 14, extra: 0.03 });
scoreCase('accent sixteenths, accents land', 'accent16', 80, 9, { seed: 9, spread: 12, accentBoost: 2 });
scoreCase('accent triplets, accents flat', 'accent3', 90, 9, { seed: 10, spread: 12, accentBoost: 1 });
scoreCase('gallop at 100', 'gallop', 100, 10, { seed: 11, spread: 16 });
scoreCase('beginner at 70', 'alt16', 70, 10, { seed: 12, spread: 55, miss: 0.1, extra: 0.05 });
scoreCase('nothing played', 'alt8', 100, 4, { seed: 13, miss: 1 });

// Picks heard twice, folded (Scoring.addPick / dropDoubles).
const doubleCases = [];
function doubleCase(name, picks, within, ratio = 0.5) {
  doubleCases.push({ name, within, ratio, picks, expect: S.dropDoubles(picks.map(([time, strength]) => ({ time, strength })), within, ratio).map((o) => [o.time, o.strength]) });
}
doubleCase('a weak echo after a pick goes', [[1, 1], [1.015, 0.25], [1.2, 1], [1.214, 0.25]], 0.045);
doubleCase('two picks of like strength stay', [[1, 1], [1.02, 1], [1.04, 0.5]], 0.045);
doubleCase('a strong second keeps the second', [[1, 0.25], [1.01, 1], [1.3, 1]], 0.045);
doubleCase('far apart are two notes', [[1, 1], [1.1, 0.25], [1.2, 0.25]], 0.045);
{
  const r = rng(99); const picks = []; let t = 0.5;
  for (let i = 0; i < 60; i++) { t += 0.09 + 0.02 * r.next(); picks.push([q(t), 1]); if (r.next() < 0.4) picks.push([q(t + 0.008 + 0.02 * r.next()), r.next() < 0.5 ? 0.25 : 0.5]); }
  doubleCase('a run of sixteenths with echoes', picks, 0.042);
}

// Per-cycle accuracy (Scoring.accuracy), what the ladder and endurance judge.
const accuracyCases = [];
{
  const r = rng(21);
  for (let k = 0; k < 8; k++) {
    const n = 4 + Math.floor(r.next() * 28);
    const gapS = [0.094, 0.125, 0.167, 0.25, 0.375][k % 5];
    const errors = Array.from({ length: n }, () => (r.next() < 0.1 ? null : q((30 * r.gauss())) ));
    const gl = Array.from({ length: n }, () => gapS);
    const extras = Math.floor(r.next() * 3);
    accuracyCases.push({ errors, gaps: gl, extras, expect: S.accuracy(errors, gl, extras, config) });
  }
  accuracyCases.push({ errors: [], gaps: [], extras: 0, expect: 1 });
}

// Credit for one note (the cosine fall-off), across gaps and errors.
const creditCases = [];
for (const gap of [0.05, 0.094, 0.125, 0.2, 0.375, 0.75]) {
  for (const e of [0, 5, 11.9, 12.5, 18, 25, 30, 41, 60, 95, -22]) {
    const w = S.windows(config, gap);
    creditCases.push({ gap, errorMs: e, fullMs: w.full, zeroMs: w.zero, expect: S.credit(config, e, gap) });
  }
}

// The calibration (median of played minus click).
const calibrationCases = [];
{
  const r = rng(31);
  const clicks = Array.from({ length: 12 }, (_, i) => q(1 + i * 0.75));
  const played = clicks.map((c) => q(c + 0.182 + 0.006 * r.gauss())).filter((_, i) => i !== 4);
  calibrationCases.push({ name: 'steady, one missed', clicks, played, expect: S.calibration(clicks, played) });
  const few = clicks.slice(0, 4).map((c) => c + 0.1);
  calibrationCases.push({ name: 'too few', clicks, played: few, expect: null });
  const even = clicks.slice(0, 10).map((c, i) => q(c + 0.05 + (i % 2 ? 0.004 : -0.004)));
  calibrationCases.push({ name: 'even count', clicks, played: even, expect: S.calibration(clicks, even) });
}

// The grid: note times of a run, the shortest gap and the match window, for every catalog drill.
const gridCases = [];
for (const [id, d] of Object.entries(drills)) {
  const { specs, cycleBeats } = specsOf(d);
  for (const bpm of [d.tempo.start, 137]) {
    const sg = S.shortestGap(specs, cycleBeats, bpm);
    const notes = S.runNotes(specs, cycleBeats, bpm, 1.25, 6.3);
    gridCases.push({ drill: id, bpm, start: 1.25, seconds: 6.3, shortestGap: sg, window: S.matchWindow(sg),
      times: notes.map((n) => n.time), accents: notes.map((n) => (n.accent ? 1 : 0)), beats: notes.map((n) => n.beat) });
  }
}

// His max on a drill (rule 1).
const maxCases = [];
{
  const run = (date, topBPM, passed, guided = false, exerciseID = 'trip16x4') => ({ date, topBPM, passed, guided, exerciseID });
  maxCases.push({ name: 'second highest pass', runs: [run('2026-11-10T10:00:00Z', 120, true), run('2026-11-11T10:00:00Z', 132, true), run('2026-11-12T10:00:00Z', 128, true), run('2026-11-13T10:00:00Z', 140, false)], expect: 128 });
  maxCases.push({ name: 'one pass less a step', runs: [run('2026-11-10T10:00:00Z', 120, true), run('2026-11-11T10:00:00Z', 150, false)], expect: 116 });
  maxCases.push({ name: 'guided never counts', runs: [run('2026-11-10T10:00:00Z', 160, true, true), run('2026-11-11T10:00:00Z', 170, true, true)], expect: null });
  const many = Array.from({ length: 14 }, (_, i) => run(`2026-11-${String(i + 1).padStart(2, '0')}T10:00:00Z`, 100 + i * 3, i % 3 !== 0));
  maxCases.push({ name: 'only the last ten count', runs: many, expect: S.learnedTempo(many, 'trip16x4') });
  for (const c of maxCases) if (S.learnedTempo(c.runs, 'trip16x4') !== c.expect) throw new Error(`max case ${c.name}`);
}

const out = {
  about: 'Shared scoring test vectors. Every app (iPhone: ios/PracticeTests/ScoringVectorTests.swift; desktop: desktop/tests; npm test) must give these answers. Made by scripts/make-scoring-vectors.mjs from shared/scoring.mjs with the numbers in catalog/scoring.json. Times in seconds, errors in ms; notes are [time, accent, beat], picks [time, strength].',
  config, tolerance: 1e-6,
  score: scoreCases, doubles: doubleCases, accuracy: accuracyCases, credit: creditCases, calibration: calibrationCases,
  grid: gridCases, max: maxCases,
};
const file = path.join(ROOT, 'shared', 'scoring-vectors.json');
fs.writeFileSync(file, JSON.stringify(out, null, 0).replace(/\{"name"/g, '\n{"name"') + '\n');
console.log(`wrote ${path.relative(ROOT, file)}: ${scoreCases.length} runs (scores ${scoreCases.map((c) => c.expect.score).join(', ')}), ${doubleCases.length} double cases, ${accuracyCases.length} cycle accuracies, ${creditCases.length} credits, ${calibrationCases.length} calibrations, ${gridCases.length} grids, ${maxCases.length} max cases`);
