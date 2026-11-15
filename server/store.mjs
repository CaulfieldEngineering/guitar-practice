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

const bestValue = (s) => (s.mode === 'endurance' ? s.sustainedSeconds || 0 : s.score || 0);

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

/** Every run in time order, trimmed to what a progress chart needs. */
export function progress(list) {
  return [...list].sort((a, b) => String(a.date).localeCompare(String(b.date))).map((s) => ({
    date: s.date, exerciseID: s.exerciseID, exerciseVersion: s.exerciseVersion, mode: s.mode, guided: !!s.guided,
    startBPM: s.startBPM, topBPM: s.topBPM, score: s.score, accuracyPercent: s.accuracyPercent,
    sustainedSeconds: s.sustainedSeconds ?? null, meanErrorMs: s.meanErrorMs, spreadMs: s.spreadMs,
  }));
}
