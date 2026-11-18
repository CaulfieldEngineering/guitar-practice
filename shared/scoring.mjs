// The scoring rules in one plain reference, line for line the same as the iPhone app's
// (ios/Practice/Scoring/Scoring.swift, Library/Exercise.swift, Persistence/History.swift Stats.learnedTempo) and the
// desktop app's (desktop/src/core/Scoring.cpp). It exists to make the shared test vectors
// (shared/scoring-vectors.json, scripts/make-scoring-vectors.mjs): every app must give the same answers to them, so
// a run scores the same on the phone and on the computer. The numbers themselves live in catalog/scoring.json, which
// the drill server serves to both apps.
//
// Change a rule here, in Scoring.swift and in Scoring.cpp together, then `node scripts/make-scoring-vectors.mjs`; the
// three test suites (npm test, the iOS unit tests, the desktop tests) all read the new vectors.

export const standardConfig = Object.freeze({
  schema: 1, fullFraction: 0.12, zeroFraction: 0.45, fullMinMs: 12, fullMaxMs: 25, zeroMinMs: 35, zeroMaxMs: 90, extraWeight: 1,
});
export const standardRule = Object.freeze({ passMark: 85, tightMs: 20, closeMs: 40, windowMs: null });

/** The two windows (ms) for a note whose nearest neighbour is `gap` seconds away. */
export function windows(config, gap) {
  const ms = Math.max(0, gap) * 1000;
  const full = Math.min(config.fullMaxMs, Math.max(config.fullMinMs, config.fullFraction * ms));
  const zero = Math.min(config.zeroMaxMs, Math.max(config.zeroMinMs, config.zeroFraction * ms));
  return { full, zero: Math.max(zero, full + 1) };
}

/** Credit 0..1 for one played note. */
export function credit(config, errorMs, gap) {
  const w = windows(config, gap);
  const a = Math.abs(errorMs);
  if (a <= w.full) return 1;
  if (a >= w.zero) return 0;
  const x = (a - w.full) / (w.zero - w.full);
  return 0.5 * (1 + Math.cos(Math.PI * x));
}

/** The matching window around a note (seconds). */
export const matchWindow = (shortestGap) => Math.min(0.100, Math.max(0.030, shortestGap * 0.45));

/** Each expected note's played index (or null), nearest pairs first; ties by note, then by played index. */
export function match(expected, played, window) {
  const pairs = [];
  let j0 = 0;
  for (let i = 0; i < expected.length; i++) {
    const t = expected[i];
    while (j0 < played.length && played[j0] < t - window) j0++;
    let j = j0;
    while (j < played.length && played[j] <= t + window) { pairs.push([Math.abs(played[j] - t), i, j]); j++; }
  }
  pairs.sort((a, b) => (a[0] !== b[0] ? a[0] - b[0] : a[1] !== b[1] ? a[1] - b[1] : a[2] - b[2]));
  const out = new Array(expected.length).fill(null);
  const used = new Set();
  for (const [, e, p] of pairs) if (out[e] === null && !used.has(p)) { out[e] = p; used.add(p); }
  return out;
}

export function gaps(times) {
  const out = new Array(times.length).fill(1);
  if (times.length <= 1) return out;
  for (let i = 0; i < times.length; i++) {
    let g = Number.MAX_VALUE;
    if (i > 0) g = Math.min(g, times[i] - times[i - 1]);
    if (i + 1 < times.length) g = Math.min(g, times[i + 1] - times[i]);
    out[i] = Math.max(0.001, g);
  }
  return out;
}

/** A cycle's accuracy 0..1 (errors: ms or null per note; gaps per note). */
export function accuracy(errors, gapList, extras, config) {
  if (!errors.length) return 1;
  let c = 0;
  for (let i = 0; i < errors.length; i++) if (errors[i] !== null) c += credit(config, errors[i], gapList[i]);
  const count = errors.length + config.extraWeight * Math.max(0, extras);
  return count > 0 ? Math.min(1, c / count) : 1;
}

const roundHalfAway = (x) => (x < 0 ? -Math.round(-x) : Math.round(x));

/** Scores a run. notes: [{time, accent, beat}], played: [{time, strength}] (calibration applied). */
export function score(notes, played, window, rule = standardRule, config = standardConfig) {
  const exp = notes.map((n) => n.time);
  const times = played.map((p) => p.time);
  const m = match(exp, times, window);
  const gap = gaps(exp);
  const errors = [];
  let hits = 0, w20 = 0, w40 = 0, full = 0, cr = 0, fullSum = 0, zeroSum = 0;
  const matched = [];
  for (let i = 0; i < m.length; i++) {
    const w = windows(config, gap[i]);
    fullSum += w.full; zeroSum += w.zero;
    const j = m[i];
    if (j === null) { errors.push(null); continue; }
    const ms = (times[j] - exp[i]) * 1000;
    errors.push(ms); matched.push(ms); hits++;
    const a = Math.abs(ms);
    const c = credit(config, ms, gap[i]);
    cr += c;
    if (c >= 0.999) full++;
    if (a <= rule.tightMs) w20++;
    if (a <= rule.closeMs) w40++;
  }
  let extra = 0;
  const extraOffsets = [];
  if (exp.length) {
    const first = exp[0], last = exp[exp.length - 1];
    const used = new Set(m.filter((x) => x !== null));
    for (let j = 0; j < times.length; j++) {
      const t = times[j];
      if (used.has(j) || t < first - window || t > last + window) continue;
      extra++;
      let near = exp[0];
      for (const e of exp) if (Math.abs(e - t) < Math.abs(near - t)) near = e;
      extraOffsets.push((t - near) * 1000);
    }
  }
  const mean = matched.length ? matched.reduce((s, x) => s + x, 0) / matched.length : 0;
  const spread = matched.length < 2 ? 0 : Math.sqrt(matched.reduce((s, x) => s + (x - mean) * (x - mean), 0) / (matched.length - 1));

  let accentsLanded = null, accentBeats = null;
  if (notes.some((n) => n.accent)) {
    let l = 0, b = 0;
    const byBeat = new Map();
    for (let i = 0; i < m.length; i++) {
      const j = m[i];
      if (j === null) continue;
      if (!byBeat.has(notes[i].beat)) byBeat.set(notes[i].beat, []);
      byBeat.get(notes[i].beat).push([notes[i].accent, played[j].strength]);
    }
    for (const list of byBeat.values()) {
      const acc = list.find((x) => x[0]);
      if (!acc) continue;
      const others = list.filter((x) => !x[0]).map((x) => x[1]);
      if (!others.length) continue;
      b++;
      if (acc[1] > 1.4 * (others.reduce((s, x) => s + x, 0) / others.length)) l++;
    }
    accentsLanded = l; accentBeats = b;
  }
  const n = exp.length;
  const count = n + config.extraWeight * extra;
  const s = !n || count <= 0 ? 0 : roundHalfAway((100 * cr) / count);
  const pct = (k) => (n > 0 ? roundHalfAway((100 * k) / n) : 0);
  return {
    expected: n, hits, within20: w20, within40: w40, missed: n - hits, extra, errors, meanError: mean, spread,
    accentsLanded, accentBeats, score: Math.min(100, Math.max(0, s)), passMark: rule.passMark, full,
    fullMs: n ? fullSum / n : 0, zeroMs: n ? zeroSum / n : 0, extraOffsets,
    pct20: pct(w20), pct40: pct(w40), passed: Math.min(100, Math.max(0, s)) >= rule.passMark,
  };
}

/** Adds a pick unless it is the same pick heard twice. Returns [list, kept]. */
export function addPick(o, played, within, ratio = 0.5) {
  const last = played[played.length - 1];
  if (!last || !(o.time - last.time < within) || !(o.time >= last.time)) { played.push(o); return true; }
  if (o.strength < last.strength * ratio) return false;
  if (last.strength < o.strength * ratio) { played[played.length - 1] = o; return false; }
  played.push(o); return true;
}

export function dropDoubles(list, within, ratio = 0.5) {
  const out = [];
  for (const o of list) addPick(o, out, within, ratio);
  return out;
}

export function band(spreadMs) {
  if (spreadMs < 15) return 'Locked';
  if (spreadMs < 25) return 'Tight';
  if (spreadMs < 40) return 'Good';
  if (spreadMs < 60) return 'Loose';
  return 'Rough';
}

export function calibration(clicks, played) {
  const m = match(clicks, played, 0.25);
  const d = [];
  m.forEach((j, i) => { if (j !== null) d.push(played[j] - clicks[i]); });
  d.sort((a, b) => a - b);
  if (d.length < 5) return null;
  const median = d.length % 2 === 1 ? d[(d.length - 1) / 2] : (d[d.length / 2 - 1] + d[d.length / 2]) / 2;
  const mean = d.reduce((s, x) => s + x, 0) / d.length;
  const spread = Math.sqrt(d.reduce((s, x) => s + (x - mean) * (x - mean), 0) / (d.length - 1));
  return { offset: median, spread, hits: d.length };
}

// ---- the drill grid (Exercise.expand, notes, shortestGap) ----

export function expand(groups, accentFirst) {
  const out = [];
  let down = true;
  groups.forEach((n, b) => {
    for (let k = 0; k < n; k++) {
      out.push({ at: { beat: b, step: k, of: n }, pick: down ? 'down' : 'up', accent: accentFirst && k === 0 });
      down = !down;
    }
  });
  return out;
}

const beatsOf = (at) => at.beat + (at.step ?? 0) / Math.max(1, at.of ?? 1);

export function runNotes(specs, cycleBeats, bpm, start, seconds) {
  const beat = 60 / Math.max(1, bpm);
  const totalBeats = seconds / beat;
  const out = [];
  if (!specs.length) return out;
  for (let cycle = 0; cycle * cycleBeats < totalBeats - 1e-9; cycle++) {
    for (const n of specs) {
      const b = cycle * cycleBeats + beatsOf(n.at);
      if (b >= totalBeats - 1e-9) break;
      out.push({ time: start + b * beat, accent: !!n.accent, beat: cycle * cycleBeats + n.at.beat });
    }
  }
  return out;
}

export function shortestGap(specs, cycleBeats, bpm) {
  const beat = 60 / Math.max(1, bpm);
  const pos = specs.map((n) => beatsOf(n.at));
  if (pos.length <= 1) return beat * cycleBeats;
  let g = cycleBeats - pos[pos.length - 1] + pos[0];
  for (let i = 1; i < pos.length; i++) g = Math.min(g, pos[i] - pos[i - 1]);
  return Math.max(1e-3, g) * beat;
}

/** His max on a drill (rule 1, the same as server/store.mjs learnedTempo and Stats.learnedTempo). */
export function learnedTempo(runs, exerciseID, recent = 10, step = 4) {
  const solo = runs.filter((s) => s.exerciseID === exerciseID && !s.guided)
    .sort((a, b) => String(b.date).localeCompare(String(a.date))).slice(0, recent);
  const passed = solo.filter((s) => s.passed).map((s) => s.topBPM).sort((a, b) => b - a);
  if (passed.length >= 2) return passed[1];
  if (passed.length === 1) return Math.max(20, passed[0] - step);
  return null;
}
