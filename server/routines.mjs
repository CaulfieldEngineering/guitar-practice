// What the phone and the computer share besides runs (since 2026-11-24): his routines, the routines he has run, and
// his settings that follow him (the guitar's tuning).
//
//   data/routines.json        {routines: [...]}: each routine whole, by id; the newer `updatedAt` wins; a deleted one
//                             stays as {id, deleted: true, updatedAt} so a device that still has it lets it go
//   data/routine-runs.jsonl   one routine run a line, appended, never rewritten; an id already held is kept once
//   data/settings.json        {tuning, updatedAt}: the newer wins
//
// The starter routines are in catalog/starter-routines.json: they are listed until a routine of the same id is saved
// (changed or deleted), which then stands for it.
import fs from 'node:fs';
import path from 'node:path';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const time = (x) => { const t = Date.parse(x ?? ''); return Number.isNaN(t) ? 0 : t; };

function readJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function writeJSON(file, value) {
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 1) + '\n');
  fs.renameSync(tmp, file);
}

export function validRoutine(r) {
  if (!r || typeof r !== 'object' || typeof r.id !== 'string' || !UUID.test(r.id) || !time(r.updatedAt)) return false;
  if (r.deleted) return true;
  return typeof r.name === 'string' && Array.isArray(r.blocks) && r.blocks.every((b) => b && typeof b.kind === 'string');
}

export function createRoutineStore(dataDir, starters = () => []) {
  fs.mkdirSync(dataDir, { recursive: true });
  const file = path.join(dataDir, 'routines.json');
  const held = new Map((readJSON(file, { routines: [] }).routines ?? []).filter(validRoutine).map((r) => [r.id.toLowerCase(), r]));

  const runsFile = path.join(dataDir, 'routine-runs.jsonl');
  const runs = new Map();
  if (fs.existsSync(runsFile)) {
    for (const line of fs.readFileSync(runsFile, 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { const r = JSON.parse(line); if (validRun(r)) runs.set(r.id.toLowerCase(), r); } catch { /* a torn last line */ }
    }
  }

  const settingsFile = path.join(dataDir, 'settings.json');
  let settings = readJSON(settingsFile, {});

  return {
    /** Every routine: his, then the starters he has not saved over. Deleted ones are included (`deleted: true`). */
    all() {
      const out = [...held.values()];
      for (const s of starters()) if (!held.has(String(s.id).toLowerCase())) out.push({ ...s, starter: true });
      return out;
    },
    /** Saves each routine sent that is newer than the one held. Returns how many changed. */
    save(list) {
      let changed = 0;
      for (const r of list ?? []) {
        if (!validRoutine(r)) continue;
        const id = r.id.toLowerCase();
        const have = held.get(id);
        if (have && time(have.updatedAt) >= time(r.updatedAt)) continue;
        const { starter, ...rest } = r;
        held.set(id, rest);
        changed += 1;
      }
      if (changed) writeJSON(file, { routines: [...held.values()] });
      return changed;
    },
    runs: () => [...runs.values()],
    addRuns(list) {
      const ids = [];
      const fresh = [];
      for (const r of list ?? []) {
        if (!validRun(r)) continue;
        const id = r.id.toLowerCase();
        if (!runs.has(id)) { const rec = { ...r, receivedAt: new Date().toISOString() }; runs.set(id, rec); fresh.push(rec); }
        ids.push(r.id);
      }
      if (fresh.length) fs.appendFileSync(runsFile, fresh.map((r) => JSON.stringify(r)).join('\n') + '\n');
      return { held: ids, added: fresh.length };
    },
    settings: () => settings,
    /** Keeps the settings sent when they are newer than the ones held; answers with what is held now. */
    saveSettings(s) {
      if (s && typeof s === 'object' && time(s.updatedAt) > time(settings.updatedAt)) {
        settings = { ...s };
        writeJSON(settingsFile, settings);
      }
      return settings;
    },
  };
}

export function validRun(r) {
  return r && typeof r === 'object' && typeof r.id === 'string' && UUID.test(r.id) && typeof r.date === 'string'
    && !Number.isNaN(Date.parse(r.date)) && typeof r.routineName === 'string' && Array.isArray(r.blocks);
}
