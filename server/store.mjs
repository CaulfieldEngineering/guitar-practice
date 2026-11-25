// Where the runs are kept: one JSON object a line in data/sessions.jsonl, appended, never rewritten. An id already
// held is not added again, so the phone can send the same run as often as it likes until it hears back.
import fs from 'node:fs';
import path from 'node:path';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function valid(s) {
  return s && typeof s === 'object' && typeof s.id === 'string' && UUID.test(s.id) && typeof s.exerciseID === 'string'
    && typeof s.date === 'string' && !Number.isNaN(Date.parse(s.date)) && Number.isFinite(s.startBPM) && typeof s.mode === 'string';
}

export function createStore(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const byId = new Map();
  if (fs.existsSync(file)) {
    for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { const s = JSON.parse(line); if (valid(s)) byId.set(s.id.toLowerCase(), s); } catch { /* a torn last line */ }
    }
  }
  return {
    all: () => [...byId.values()],
    /** Adds the valid runs not yet held. Returns the ids now held of those sent, and how many were new. */
    add(list) {
      const held = [];
      const fresh = [];
      for (const s of list) {
        if (!valid(s)) continue;
        const id = s.id.toLowerCase();
        if (!byId.has(id)) { const rec = { ...s, receivedAt: new Date().toISOString() }; byId.set(id, rec); fresh.push(rec); }
        held.push(s.id);
      }
      if (fresh.length) fs.appendFileSync(file, fresh.map((s) => JSON.stringify(s)).join('\n') + '\n');
      return { held, added: fresh.length };
    },
  };
}

const bestValue = (s) => (s.mode === 'endurance' ? s.sustainedSeconds || 0 : s.mode === 'challenge' ? s.earnedSeconds || 0 : s.score || 0);

/** The best solo run for each exercise, kind of run and starting tempo (guided runs are not bests). */
export function bests(list) {
  const map = new Map();
  for (const s of list) {
    if (s.guided) continue;
    const key = `${s.exerciseID}|${s.mode}|${s.startBPM}`;
    const b = map.get(key) || { exerciseID: s.exerciseID, mode: s.mode, bpm: s.startBPM, best: 0, runs: 0, last: s.date };
    b.best = Math.max(b.best, bestValue(s));
    b.runs += 1;
    if (String(s.date) > String(b.last)) b.last = s.date;
    map.set(key, b);
  }
  return [...map.values()].sort((a, b) => a.exerciseID.localeCompare(b.exerciseID) || a.mode.localeCompare(b.mode) || a.bpm - b.bpm);
}

/**
 * His max on a drill, as in heart-rate zones (rule 1; the app has the same rule as a fallback, Stats.learnedTempo): the
 * fastest he passes at the target accuracy, robust over recent runs. The last 10 solo runs
 * of the drill; those that passed give the tempo they reached; the level is the second highest, so one lucky run does
 * not count. With a single pass, that tempo less one ladder step (4). Tune it here; the app takes the server's answer.
 */
export function learnedTempo(list, exerciseID, { recent = 10, step = 4 } = {}) {
  const solo = list.filter((s) => s.exerciseID === exerciseID && !s.guided)
    .sort((a, b) => String(b.date).localeCompare(String(a.date))).slice(0, recent);
  const passed = solo.filter((s) => s.passed).map((s) => s.topBPM).sort((a, b) => b - a);
  const max = passed.length >= 2 ? passed[1] : passed.length === 1 ? Math.max(20, passed[0] - step) : null;
  if (max == null) return null;
  return { max, bpm: max, basedOn: solo.length, passes: passed.length, rule: 1 };
  return null;
}

export function levels(list) {
  const out = {};
  for (const id of new Set(list.map((s) => s.exerciseID))) {
    const l = learnedTempo(list, id);
    if (l) out[id] = l;
  }
  return out;
}

/** Every run in time order, trimmed to what a progress chart needs. */
export function progress(list) {
  return [...list].sort((a, b) => String(a.date).localeCompare(String(b.date))).map((s) => ({
    date: s.date, exerciseID: s.exerciseID, exerciseVersion: s.exerciseVersion, mode: s.mode, guided: !!s.guided,
    startBPM: s.startBPM, topBPM: s.topBPM, score: s.score, accuracyPercent: s.accuracyPercent,
    sustainedSeconds: s.sustainedSeconds ?? null, meanErrorMs: s.meanErrorMs, spreadMs: s.spreadMs,
  }));
}
