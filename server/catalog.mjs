// Checks the drill catalog the way the app reads it: node server/catalog.mjs (prints problems, exits 1 on any).
// Run it after adding or changing a drill, before bumping the index's version.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const SUPPORTED_SCHEMA = 1;
const KINDS = new Set(['cycles', 'duration', 'endurance', 'challenge']);

/** Whether a note's pitch does not matter ("x"): timing only. True for a drill marked `"pitch": "x"`, a note with
 * `"x": true` or `"fret": "x"`, and any note that names no fret (the groups shorthand). */
export function isX(drill, note) {
  if (drill?.pitch === 'x' || note?.x === true || note?.fret === 'x' || note?.fret === 'X') return true;
  return !(Number.isInteger(note?.fret) && Number.isInteger(note?.string));
}

/** The drills a file serves: everything but the archived ones (kept in the file, with his runs, to come back). */
export const activeExercises = (list) => (list ?? []).filter((e) => !e?.archived);

function checkExercise(e, where, errors) {
  const at = `${where} ${e?.id ?? '(no id)'}`;
  if (!e || typeof e.id !== 'string' || !e.id) errors.push(`${where}: an exercise without an id`);
  if (typeof e?.name !== 'string' || !e.name) errors.push(`${at}: no name`);
  if (!e?.tempo || !Number.isInteger(e.tempo.start)) errors.push(`${at}: tempo.start is needed (a whole bpm)`);
  const hasNotes = Array.isArray(e?.notes) && e.notes.length > 0;
  const hasGroups = Array.isArray(e?.groups) && e.groups.length > 0;
  if (!hasNotes && !hasGroups) errors.push(`${at}: needs "groups" or "notes"`);
  if (hasGroups && !e.groups.every((n) => Number.isInteger(n) && n >= 0 && n <= 12)) errors.push(`${at}: groups are whole numbers of notes per beat, 0 to 12`);
  if (hasNotes) {
    for (const n of e.notes) {
      const a = n?.at;
      if (!a || !Number.isInteger(a.beat) || a.beat < 0) { errors.push(`${at}: a note without at.beat`); break; }
      const of = a.of ?? 1, step = a.step ?? 0;
      if (!Number.isInteger(of) || of < 1 || !Number.isInteger(step) || step < 0 || step >= of) { errors.push(`${at}: a note's step must be 0 to of-1`); break; }
      if (n.pick && !['down', 'up'].includes(n.pick)) { errors.push(`${at}: pick is "down" or "up"`); break; }
      if (n.string != null && !(Number.isInteger(n.string) && n.string >= 1 && n.string <= 7)) { errors.push(`${at}: string is 1 (high E) to 7`); break; }
      if (n.fret != null && !(n.fret === 'x' || n.fret === 'X' || (Number.isInteger(n.fret) && n.fret >= 0 && n.fret <= 24))) { errors.push(`${at}: fret is 0 to 24, or "x" (any pitch)`); break; }
      if (n.x != null && typeof n.x !== 'boolean') { errors.push(`${at}: x is true or false`); break; }
    }
    if (e.cycleBeats != null && !(Number.isInteger(e.cycleBeats) && e.cycleBeats >= 1)) errors.push(`${at}: cycleBeats is a whole number of beats`);
  }
  if (e?.pitch != null && e.pitch !== 'x') errors.push(`${at}: pitch is "x" (timing only) or left out`);
  if (e?.archived != null && typeof e.archived !== 'boolean') errors.push(`${at}: archived is true or false`);
  if (e?.session?.kind && !KINDS.has(e.session.kind)) errors.push(`${at}: session.kind is cycles, duration, endurance or challenge`);
  for (const l of e?.levels ?? []) {
    if (typeof l?.name !== 'string' || !Number.isInteger(l?.bpm)) errors.push(`${at}: each level needs a name and a bpm`);
    if (l?.session?.kind && !KINDS.has(l.session.kind)) errors.push(`${at}: level ${l.name}: session.kind is cycles, duration or endurance`);
  }
}

const BLOCKS = new Set(['warmup', 'drill', 'rest', 'free', 'custom']);

/** A routine of the Routines section (since 2026-11-24): named blocks in order. */
export function checkPracticeRoutine(r, where, errors, drillIDs) {
  const at = `${where} ${r?.name ?? '(no name)'}`;
  if (typeof r?.id !== 'string' || !r.id) errors.push(`${where}: a routine without an id`);
  if (typeof r?.name !== 'string' || !r.name) errors.push(`${at}: no name`);
  if (!Array.isArray(r?.blocks) || !r.blocks.length) { errors.push(`${at}: no blocks`); return; }
  for (const b of r.blocks) {
    if (!BLOCKS.has(b?.kind)) { errors.push(`${at}: a block's kind is warmup, drill, rest, free or custom`); break; }
    if (b.kind === 'drill') {
      // A drill block runs as the drill's own run (its session: loops, time, hold accuracy or challenge).
      if (drillIDs && !drillIDs.has(b.drillID)) { errors.push(`${at}: drill ${b.drillID} is not an active drill`); break; }
      if (b.drill?.session?.kind && !KINDS.has(b.drill.session.kind)) { errors.push(`${at}: a drill block's session.kind is cycles, duration, endurance or challenge`); break; }
    } else if (!Number.isInteger(b.seconds) || b.seconds <= 0) { errors.push(`${at}: each block needs seconds above 0`); break; }
  }
}

function checkRoutine(r, where, errors) {
  const at = `${where} ${r?.name ?? '(no name)'}`;
  if (typeof r?.name !== 'string' || !r.name) errors.push(`${where}: a routine without a name`);
  if (!Array.isArray(r?.intervals) || !r.intervals.length) errors.push(`${at}: no intervals`);
  for (const i of r?.intervals ?? []) {
    if (!['play', 'rest', 'motion'].includes(i?.kind)) { errors.push(`${at}: interval kind is play, rest or motion`); break; }
    if (!Number.isInteger(i?.seconds) || i.seconds <= 0) { errors.push(`${at}: interval seconds must be a whole number above 0`); break; }
  }
}

/** Reads and checks the catalog folder. */
export function checkCatalog(folder) {
  const errors = [];
  const list = [];
  let version = 0, routines = 0, archived = 0;
  const starters = [];
  let index;
  try {
    index = JSON.parse(fs.readFileSync(path.join(folder, 'index.json'), 'utf8'));
  } catch (e) {
    return { version: 0, drills: 0, routines: 0, list, errors: [`index.json: ${e.message}`] };
  }
  version = index.version;
  if (!Number.isInteger(index.version)) errors.push('index.json: version must be a whole number');
  if (index.schema > SUPPORTED_SCHEMA) errors.push(`index.json: schema ${index.schema} is newer than ${SUPPORTED_SCHEMA}`);
  const ids = new Map();
  for (const f of index.files ?? []) {
    if (typeof f.path !== 'string' || f.path.includes('..') || path.isAbsolute(f.path)) { errors.push(`index.json: bad path ${f.path}`); continue; }
    let doc;
    try { doc = JSON.parse(fs.readFileSync(path.join(folder, f.path), 'utf8')); } catch (e) { errors.push(`${f.path}: ${e.message}`); continue; }
    if (!Number.isInteger(doc.schema)) errors.push(`${f.path}: schema is missing`);
    if (f.kind === 'exercises') {
      for (const e of doc.exercises ?? []) {
        checkExercise(e, f.path, errors);
        if (e?.id) {
          if (ids.has(e.id)) errors.push(`${f.path}: id ${e.id} is also in ${ids.get(e.id)}`);
          ids.set(e.id, f.path);
          if (e.archived) archived += 1; else list.push({ id: e.id, name: e.name, version: e.version });
        }
      }
    } else if (f.kind === 'zones') {
      const zs = doc.zones ?? [];
      if (!zs.length) errors.push(`${f.path}: no zones`);
      for (const z of zs) {
        if (typeof z?.id !== 'string' || !Number.isFinite(z?.low) || !Number.isFinite(z?.high) || z.low >= z.high) {
          errors.push(`${f.path}: each zone needs an id and low < high (percent of max)`); break;
        }
      }
      for (const [mode, id] of Object.entries(doc.suggest ?? {})) {
        if (!zs.some((z) => z.id === id)) errors.push(`${f.path}: suggest.${mode} names ${id}, which is not a zone`);
      }
    } else if (f.kind === 'scoring') {
      // How timing becomes accuracy (the app's ScoringConfig): every number optional, but sensible when given.
      const num = (k) => doc[k] == null || (Number.isFinite(doc[k]) && doc[k] >= 0);
      for (const k of ['fullFraction', 'zeroFraction', 'fullMinMs', 'fullMaxMs', 'zeroMinMs', 'zeroMaxMs', 'extraWeight']) {
        if (!num(k)) errors.push(`${f.path}: ${k} must be a number, 0 or more`);
      }
      const v = { fullFraction: 0.12, zeroFraction: 0.45, fullMinMs: 12, fullMaxMs: 25, zeroMinMs: 35, zeroMaxMs: 90, ...doc };
      if (!(v.fullFraction > 0 && v.zeroFraction > v.fullFraction)) errors.push(`${f.path}: zeroFraction must be above fullFraction, both above 0`);
      if (!(v.fullMinMs > 0 && v.fullMaxMs >= v.fullMinMs)) errors.push(`${f.path}: fullMinMs must be above 0 and no more than fullMaxMs`);
      if (!(v.zeroMinMs > 0 && v.zeroMaxMs >= v.zeroMinMs)) errors.push(`${f.path}: zeroMinMs must be above 0 and no more than zeroMaxMs`);
    } else if (f.kind === 'routines') {
      for (const r of doc.routines ?? []) { checkRoutine(r, f.path, errors); routines += 1; }
    } else if (f.kind === 'starter-routines') {
      for (const r of doc.routines ?? []) starters.push([r, f.path]);
    } else errors.push(`index.json: ${f.path} has kind ${f.kind} (exercises, routines, starter-routines, zones or scoring)`);
  }
  const active = new Set(list.map((d) => d.id));
  for (const [r, where] of starters) checkPracticeRoutine(r, where, errors, active);
  // Every JSON file in the folder should be in the index, or the app never sees it.
  const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((x) => x.isDirectory() ? walk(path.join(d, x.name)) : [path.join(d, x.name)]);
  const listed = new Set((index.files ?? []).map((f) => path.normalize(f.path)));
  for (const file of walk(folder)) {
    const rel = path.normalize(path.relative(folder, file));
    if (rel.endsWith('.json') && rel !== 'index.json' && !listed.has(rel)) errors.push(`${rel.replace(/\\/g, '/')} is not in index.json`);
  }
  return { version, drills: list.length, archived, routines, starters: starters.map(([r]) => r), list, errors };
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const folder = process.argv[2] || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'catalog');
  const r = checkCatalog(folder);
  console.log(`catalog ${r.version}: ${r.drills} drills (${r.archived} archived), ${r.starters.length} starter routines`);
  for (const e of r.errors) console.log('problem:', e);
  process.exit(r.errors.length ? 1 : 0);
}
