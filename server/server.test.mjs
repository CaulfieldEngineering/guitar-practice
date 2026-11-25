// node --test server/
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from './index.mjs';
import { checkCatalog } from './catalog.mjs';

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
  exerciseName: 'Triplets to sixteenths, 4 and 4', mode: 'endurance', ladderStep: 0, guided: false, startBPM: 90, topBPM: 90,
  seconds: 64, cycles: 8, notes: 224, hits: 220, missed: 4, extra: 1, pct20: 70, pct40: 95, tightMs: 20, closeMs: 40,
  meanErrorMs: 4, spreadMs: 11, toleranceMs: 30, targetPercent: 85, accuracyPercent: 91, sustainedSeconds: 56, score: 88,
  passed: true, appVersion: '0.1.1', ...over,
});

test('the repo catalog is valid', () => {
  const c = checkCatalog(path.join(ROOT, 'catalog'));
  assert.deepEqual(c.errors, []);
  assert.equal(c.drills, 1);
  assert.equal(c.archived, 8);
  assert.equal(c.list[0].id, 'trip16x4');
  assert.equal(c.starters.length, 1);
});

test('the scoring numbers are in the catalog, and nonsense is refused', () => {
  const idx = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'index.json'), 'utf8'));
  assert.ok(idx.files.some((f) => f.kind === 'scoring' && f.path === 'scoring.json'));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'practice-cat-'));
  try {
    fs.writeFileSync(path.join(tmp, 'index.json'), JSON.stringify({ schema: 1, version: 1, files: [{ path: 'scoring.json', kind: 'scoring' }] }));
    fs.writeFileSync(path.join(tmp, 'scoring.json'), JSON.stringify({ schema: 1, fullFraction: 0.5, zeroFraction: 0.2 }));
    assert.ok(checkCatalog(tmp).errors.some((e) => e.includes('zeroFraction')));
    fs.writeFileSync(path.join(tmp, 'scoring.json'), JSON.stringify({ schema: 1, fullMaxMs: 20 }));
    assert.deepEqual(checkCatalog(tmp).errors, []);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
});

test('serves the catalog and refuses paths outside it', async (t) => {
  const { base } = await run(t);
  const idx = await (await fetch(`${base}/catalog/index.json`)).json();
  assert.equal(idx.schema, 1);
  for (const f of idx.files) assert.equal((await fetch(`${base}/catalog/${f.path}`)).status, 200);
  assert.equal((await fetch(`${base}/catalog/..%2Fpackage.json`)).status, 404);
  const h = await (await fetch(`${base}/health`)).json();
  assert.equal(h.ok, true);
});

test('serves the recorded voice, whole', async (t) => {
  const { base } = await run(t);
  const idx = await (await fetch(`${base}/voice/index.json`)).json();
  assert.ok(idx.version >= 1);
  assert.ok(idx.clips['say.trip16x4'] && idx.clips['bpm.120'] && idx.clips['cycles.8'] && idx.clips.endurance && idx.clips['cue.3']);
  const pack = Buffer.from(await (await fetch(`${base}/voice/pack.bin`)).arrayBuffer());
  const needed = Math.max(...Object.values(idx.clips).map((c) => c.o + c.n));
  assert.equal(pack.length, needed);
  // Every drill in the catalog has its line recorded, in the words the catalog has now.
  const drills = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'exercises', 'right-hand.json'), 'utf8')).exercises;
  for (const d of drills) assert.equal(idx.clips[`say.${d.id}`]?.text, d.say || `${d.name}.`, d.id);
  assert.equal((await fetch(`${base}/voice/other.bin`)).status, 404);
});

test('keeps each run once and acknowledges it', async (t) => {
  const { base, data } = await run(t);
  const post = (sessions) => fetch(`${base}/api/sessions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sessions }) }).then((r) => r.json());
  const a = result();
  const b = result({ id: '9a7b6c5d-1111-4222-8333-944455556666', mode: 'cycles', score: 92, sustainedSeconds: null });
  assert.deepEqual((await post([a])).stored, [a.id]);
  assert.deepEqual((await post([a, b, { id: 'nope' }])).stored, [a.id, b.id]);
  const lines = fs.readFileSync(path.join(data, 'sessions.jsonl'), 'utf8').trim().split('\n');
  assert.equal(lines.length, 2);
  const list = (await (await fetch(`${base}/api/sessions?exercise=trip16x4`)).json()).sessions;
  assert.equal(list.length, 2);
  const stats = await (await fetch(`${base}/api/stats`)).json();
  assert.deepEqual(stats.bests.map((x) => [x.mode, x.best]), [['cycles', 92], ['endurance', 56]]);
  assert.equal(stats.progress.length, 2);
});

test('his level: the second best pass of the last ten solo runs', async (t) => {
  const { base } = await run(t);
  const id = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
  const day = (n) => `2026-11-${String(n).padStart(2, '0')}T20:00:00Z`;
  const runs = [
    result({ id: id(1), date: day(1), mode: 'cycles', topBPM: 140, passed: true }),   // old: outside the last ten
    ...Array.from({ length: 9 }, (_, i) => result({ id: id(10 + i), date: day(2 + i), mode: 'cycles', topBPM: 100 + i, passed: i % 2 === 0 })),
    result({ id: id(30), date: day(20), mode: 'cycles', topBPM: 130, passed: true }),  // one lucky run
    result({ id: id(31), date: day(21), mode: 'cycles', topBPM: 150, passed: true, guided: true }), // guided: not counted
  ];
  await fetch(`${base}/api/sessions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sessions: runs }) });
  const { levels } = await (await fetch(`${base}/api/levels`)).json();
  assert.equal(levels.trip16x4.max, 108);
});

test('serves the desktop updater from its releases folder, and nothing else from there', async (t) => {
  const data = fs.mkdtempSync(path.join(os.tmpdir(), 'practice-'));
  const releases = path.join(data, 'releases');
  fs.mkdirSync(releases);
  fs.writeFileSync(path.join(releases, 'latest.json'), JSON.stringify({ version: '0.1.1', file: 'Practice-Setup-0.1.1.exe' }));
  fs.writeFileSync(path.join(releases, 'Practice-Setup-0.1.1.exe'), 'MZ');
  fs.writeFileSync(path.join(releases, 'secret.txt'), 'no');
  const server = http.createServer(createApp({ catalog: path.join(ROOT, 'catalog'), data, releases }));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); fs.rmSync(data, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await (await fetch(`${base}/desktop/latest.json`)).json()).version, '0.1.1');
  assert.equal(await (await fetch(`${base}/desktop/Practice-Setup-0.1.1.exe`)).text(), 'MZ');
  assert.equal((await fetch(`${base}/desktop/secret.txt`)).status, 404);
  assert.equal((await fetch(`${base}/desktop/..%2Fsessions.jsonl`)).status, 404);
});

test('a run from the desktop app (with its device name) is kept and listed with the phone runs', async (t) => {
  const { base } = await run(t);
  const phone = result();
  const desktop = result({ id: '7d2e4c1a-1111-4c55-9a51-0d2b9d1e4f10', device: 'JPC', appVersion: '0.1.0', date: '2026-11-17T23:00:00Z' });
  await fetch(`${base}/api/sessions`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ sessions: [phone, desktop] }) });
  const list = (await (await fetch(`${base}/api/sessions`)).json()).sessions;
  assert.equal(list.length, 2);
  assert.equal(list[0].device, 'JPC');
});
