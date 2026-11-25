// 2026-11-24: one drill, routines, routine runs, settings, X notes, and old runs still kept.  node --test server/
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from './index.mjs';
import { checkCatalog, isX } from './catalog.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function run(t) {
  const data = fs.mkdtempSync(path.join(os.tmpdir(), 'practice-'));
  const server = http.createServer(createApp({ catalog: path.join(ROOT, 'catalog'), data }));
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => {
    t.after(() => { server.close(); fs.rmSync(data, { recursive: true, force: true }); });
    resolve({ base: `http://127.0.0.1:${server.address().port}`, data });
  }));
}

const result = (over = {}) => ({
  schema: 1, id: '3f1c2a7e-8b0d-4c55-9a51-0d2b9d1e4f10', date: '2026-11-14T20:00:00Z', exerciseID: 'trip16x4', exerciseVersion: 1,
  exerciseName: 'Triplets to sixteenths, 4 and 4', mode: 'cycles', ladderStep: 0, guided: false, startBPM: 90, topBPM: 90,
  seconds: 64, cycles: 8, notes: 224, hits: 220, missed: 4, extra: 1, pct20: 70, pct40: 95, tightMs: 20, closeMs: 40,
  meanErrorMs: 4, spreadMs: 11, toleranceMs: 30, targetPercent: 85, accuracyPercent: 91, score: 88,
  passed: true, appVersion: '0.2.2', ...over,
});
const postJSON = (url, body, method = 'POST') => fetch(url, { method, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }).then((r) => r.json());

test('the drill catalog filter: archived drills are kept in the file but never served', async (t) => {
  const { base } = await run(t);
  const raw = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'exercises', 'right-hand.json'), 'utf8')).exercises;
  assert.equal(raw.length, 9, 'every definition is still in the file');
  assert.deepEqual(raw.filter((e) => !e.archived).map((e) => e.id), ['trip16x4']);
  const served = (await (await fetch(`${base}/catalog/exercises/right-hand.json`)).json()).exercises;
  assert.deepEqual(served.map((e) => e.id), ['trip16x4']);
  assert.equal(served[0].pitch, 'x', 'a rhythm drill: any pitch counts');
  const h = await (await fetch(`${base}/health`)).json();
  assert.equal(h.ok, true);
  assert.equal(h.drills, 1);
  assert.equal(h.archived, 8);
});

test('his runs of an archived drill are kept and still counted', async (t) => {
  const { base } = await run(t);
  const old = result({ id: '11111111-2222-4333-8444-555566667777', exerciseID: 'alt16', exerciseName: 'Alternate picking, sixteenths', topBPM: 140 });
  await postJSON(`${base}/api/sessions`, { sessions: [old] });
  assert.equal((await (await fetch(`${base}/api/sessions?exercise=alt16`)).json()).sessions.length, 1);
  assert.ok((await (await fetch(`${base}/api/stats`)).json()).bests.some((b) => b.exerciseID === 'alt16'));
});

test('X notes: "x" for a fret, a note or a drill is any pitch; a fret that is neither is refused', () => {
  assert.equal(isX({ pitch: 'x' }, { string: 3, fret: 5 }), true);
  assert.equal(isX({}, { string: 3, fret: 'x' }), true);
  assert.equal(isX({}, { x: true, string: 3, fret: 5 }), true);
  assert.equal(isX({}, {}), true, 'a note with no fret is any pitch');
  assert.equal(isX({}, { string: 6, fret: 3 }), false);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'practice-cat-'));
  try {
    fs.mkdirSync(path.join(tmp, 'exercises'));
    fs.writeFileSync(path.join(tmp, 'index.json'), JSON.stringify({ schema: 1, version: 1, files: [{ path: 'exercises/a.json', kind: 'exercises' }] }));
    const drill = (notes) => ({ schema: 1, exercises: [{ id: 'a', name: 'A', tempo: { start: 80 }, notes }] });
    fs.writeFileSync(path.join(tmp, 'exercises', 'a.json'), JSON.stringify(drill([{ at: { beat: 0 }, string: 6, fret: 'x' }, { at: { beat: 1 }, string: 6, fret: 3 }])));
    assert.deepEqual(checkCatalog(tmp).errors, []);
    fs.writeFileSync(path.join(tmp, 'exercises', 'a.json'), JSON.stringify(drill([{ at: { beat: 0 }, string: 6, fret: 'q' }])));
    assert.ok(checkCatalog(tmp).errors.some((e) => e.includes('fret')));
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
});

const routine = (over = {}) => ({
  id: '0b6d7c1e-1234-4abc-8def-0123456789ab', name: 'Evening', updatedAt: '2026-11-24T20:00:00Z',
  blocks: [{ id: 'b1', kind: 'warmup', name: 'Warm-up', seconds: 120, click: true, bpm: 80 },
    { id: 'b2', kind: 'drill', drillID: 'trip16x4', drill: { bpm: 100, session: { kind: 'cycles', cycles: 8 } } }],
  ...over,
});

test('routines: the starter is there until saved over; the newer edit wins; a delete is kept as a tombstone', async (t) => {
  const { base, data } = await run(t);
  let all = (await (await fetch(`${base}/api/routines`)).json()).routines;
  assert.equal(all.length, 1);
  assert.equal(all[0].starter, true);
  all = (await postJSON(`${base}/api/routines`, { routines: [routine()] })).routines;
  assert.equal(all.length, 2);
  all = (await postJSON(`${base}/api/routines`, { routines: [routine({ name: 'Old', updatedAt: '2026-11-24T19:00:00Z' })] })).routines;
  assert.equal(all.find((r) => r.id === routine().id).name, 'Evening', 'an older copy from another device loses');
  all = (await postJSON(`${base}/api/routines`, { routines: [routine({ name: 'Late', updatedAt: '2026-11-24T21:00:00Z' })] })).routines;
  assert.equal(all.find((r) => r.id === routine().id).name, 'Late');
  const starter = all.find((r) => r.starter);
  all = (await postJSON(`${base}/api/routines`, { routines: [{ id: starter.id, deleted: true, updatedAt: '2026-11-24T22:00:00Z' }] })).routines;
  assert.equal(all.find((r) => r.id === starter.id).deleted, true);
  assert.ok(!all.some((r) => r.starter));
  assert.ok(fs.existsSync(path.join(data, 'routines.json')));
  all = (await postJSON(`${base}/api/routines`, { routines: [{ id: 'x' }, { name: 'no id' }] })).routines;
  assert.equal(all.length, 2, 'nonsense is ignored');
});

test('routine runs are kept once, with each block', async (t) => {
  const { base } = await run(t);
  const r = { id: '6a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d', date: '2026-11-24T21:00:00Z', routineID: routine().id, routineName: 'Evening',
    seconds: 600, completed: true, blocks: [{ kind: 'warmup', name: 'Warm-up', seconds: 120 }, { kind: 'drill', name: 'Triplets', seconds: 300, sessionID: '3f1c2a7e-8b0d-4c55-9a51-0d2b9d1e4f10' }] };
  assert.deepEqual((await postJSON(`${base}/api/routine-runs`, { runs: [r, { id: 'bad' }] })).stored, [r.id]);
  await postJSON(`${base}/api/routine-runs`, { runs: [r] });
  const runs = (await (await fetch(`${base}/api/routine-runs`)).json()).runs;
  assert.equal(runs.length, 1);
  assert.equal(runs[0].blocks[1].sessionID, '3f1c2a7e-8b0d-4c55-9a51-0d2b9d1e4f10');
});

test('settings follow him: the tuning saved last wins', async (t) => {
  const { base } = await run(t);
  assert.deepEqual(await (await fetch(`${base}/api/settings`)).json(), {});
  const dropD = { tuning: { preset: 'dropD', strings: [64, 59, 55, 50, 45, 38] }, updatedAt: '2026-11-24T20:00:00Z' };
  assert.deepEqual(await postJSON(`${base}/api/settings`, dropD, 'PUT'), dropD);
  const older = { tuning: { preset: 'standard' }, updatedAt: '2026-11-24T19:00:00Z' };
  assert.deepEqual(await postJSON(`${base}/api/settings`, older, 'PUT'), dropD);
});

test('backward compatible: a 0.2.2 run is still kept, and a run with the new fields too', async (t) => {
  const { base } = await run(t);
  const oldRun = result({ id: '22222222-3333-4444-8555-666677778888' });
  const newRun = result({ id: '33333333-4444-4555-8666-777788889999', mode: 'challenge', tempoMode: 'accuracy',
    tempoChanges: [{ at: 12.5, from: 100, to: 104, kind: 'up' }], breaks: 1, earnedSeconds: 180, elapsedSeconds: 240, bestStreakSeconds: 90 });
  assert.equal((await postJSON(`${base}/api/sessions`, { sessions: [oldRun, newRun] })).stored.length, 2);
  const list = (await (await fetch(`${base}/api/sessions`)).json()).sessions;
  assert.equal(list.find((s) => s.id === newRun.id).tempoChanges[0].to, 104);
  assert.equal((await fetch(`${base}/api/levels`)).status, 200);
  // The old app's catalog routes still answer: the index, every file it names, and the old routines file.
  const idx = await (await fetch(`${base}/catalog/index.json`)).json();
  for (const f of idx.files) assert.equal((await fetch(`${base}/catalog/${f.path}`)).status, 200, f.path);
  assert.ok(idx.files.some((f) => f.kind === 'routines'), 'the old routines file is still listed for 0.2.2');
});
