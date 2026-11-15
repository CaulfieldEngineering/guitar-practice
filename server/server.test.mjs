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
  assert.ok(c.drills >= 9);
  assert.equal(c.list[0].id, 'trip16x4');
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
