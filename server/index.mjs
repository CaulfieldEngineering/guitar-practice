// The drill server: serves the drill catalog (catalog/) to the Practice iPhone app and keeps every run the app sends.
// Mini PC, scheduled task "Practice Drill Server", tailnet and loopback only, port 4700 (scripts/register-task.ps1).
//
//   GET  /health                      {ok, catalogVersion, drills, sessions}
//   GET  /catalog/index.json          the catalog's index; GET /catalog/<path> for each file it names
//   POST /api/sessions                {sessions: [SessionResult]} -> {stored: [ids held now]}; an id already held is kept once
//   GET  /api/sessions[?exercise=id]  {sessions: [...]}, newest first
//   GET  /api/stats[?exercise=id]     {bests: [{exerciseID, mode, bpm, best, runs, last}], progress: [...]}
//   GET  /api/levels                  {levels: {<exercise id>: {max, basedOn, passes, rule}}}: his max per drill (zones are % of it)
//   GET  /voice/index.json, /voice/pack.bin   the recorded voice (scripts/make-voice.mjs)
//   GET  /desktop/latest.json, /desktop/Practice-Setup-<version>.exe   the desktop app's updater (desktop/scripts/build.ps1)
//   GET  /api/routines                {routines: [...]}: his routines (deleted ones as tombstones) and the starters
//   POST /api/routines                {routines: [...]} -> {routines: every one}; the newer updatedAt wins, per routine
//   POST /api/routine-runs            {runs: [...]} -> {stored: [ids held now]}; GET /api/routine-runs, newest first
//   GET  /api/settings, PUT /api/settings   {tuning, updatedAt}: what follows him from device to device; the newer wins
//   GET  /                            a small page: the drills and the latest runs
//
// The catalog's drill files are served without their archived drills ("archived": true; Joe, 2026-11-24: "Let's
// remove all drills for now except for Triplets to 16th's, 4+4"), so every app, old or new, lists only the rest.
//
// Runs are kept in one place, data/sessions.jsonl (one JSON object a line, never rewritten, only appended).
// No dependencies; node server/index.mjs. Port and addresses: PRACTICE_PORT, PRACTICE_HOSTS (comma separated); without
// PRACTICE_HOSTS, "hosts" in config.local.json at the repo root (not in git; config.example.json shows it), else loopback.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkCatalog, activeExercises } from './catalog.mjs';
import { createRoutineStore } from './routines.mjs';
import { createStore, bests, progress, levels } from './store.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CATALOG = process.env.PRACTICE_CATALOG || path.join(ROOT, 'catalog');
const DATA = process.env.PRACTICE_DATA || path.join(ROOT, 'data');
const VOICE = process.env.PRACTICE_VOICE || path.join(ROOT, 'voice');
// The desktop app's newest installer and its latest.json (desktop/scripts/build.ps1 writes them here; not in git).
const RELEASES = process.env.PRACTICE_RELEASES || path.join(ROOT, 'desktop', 'release');
const PORT = Number(process.env.PRACTICE_PORT || 4700);
const localConfig = () => {
  try {
    return JSON.parse(fs.readFileSync(path.join(ROOT, 'config.local.json'), 'utf8'));
  } catch {
    return {};
  }
};
const HOSTS = String(process.env.PRACTICE_HOSTS || localConfig().hosts || '127.0.0.1').split(',').map((h) => h.trim()).filter(Boolean);

export function createApp({ catalog = CATALOG, data = DATA, voice = VOICE, releases = RELEASES } = {}) {
  const store = createStore(path.join(data, 'sessions.jsonl'));
  const routines = createRoutineStore(data, () => checkCatalog(catalog).starters);

  const send = (res, status, body, type = 'application/json; charset=utf-8') => {
    const text = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
    res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' });
    res.end(text);
  };

  const readBody = (req) => new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > 5 * 1024 * 1024) { reject(new Error('too large')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });

  return async (req, res) => {
    const url = new URL(req.url, 'http://x');
    const p = decodeURIComponent(url.pathname);
    try {
      if (req.method === 'GET' && p === '/health') {
        const c = checkCatalog(catalog);
        return send(res, 200, { ok: c.errors.length === 0, catalogVersion: c.version, drills: c.drills, archived: c.archived,
          routines: c.routines, savedRoutines: routines.all().filter((r) => !r.deleted).length, problems: c.errors,
          sessions: store.all().length, routineRuns: routines.runs().length });
      }
      if (req.method === 'GET' && p.startsWith('/catalog/')) {
        const rel = p.slice('/catalog/'.length);
        const file = path.resolve(catalog, rel);
        if (!file.startsWith(path.resolve(catalog) + path.sep) || !rel.endsWith('.json') || !fs.existsSync(file)) return send(res, 404, { error: 'not found' });
        const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
        if (Array.isArray(doc.exercises)) doc.exercises = activeExercises(doc.exercises);
        return send(res, 200, doc);
      }
      // The recorded voice (scripts/make-voice.mjs): the index and the pack of clips, as they are on disk.
      if (req.method === 'GET' && (p === '/voice/index.json' || p === '/voice/pack.bin')) {
        const file = path.join(voice, p.slice('/voice/'.length));
        if (!fs.existsSync(file)) return send(res, 404, { error: 'not found' });
        return send(res, 200, fs.readFileSync(file), p.endsWith('.json') ? 'application/json; charset=utf-8' : 'application/octet-stream');
      }
      // The desktop app asks every 30 seconds whether a newer build is out, and downloads it from here.
      if (req.method === 'GET' && p.startsWith('/desktop/')) {
        const name = p.slice('/desktop/'.length);
        if (!/^(latest\.json|Practice-Setup-\d+\.\d+\.\d+\.exe)$/.test(name)) return send(res, 404, { error: 'not found' });
        const file = path.join(releases, name);
        if (!fs.existsSync(file)) return send(res, 404, { error: 'not found' });
        return send(res, 200, fs.readFileSync(file), name.endsWith('.json') ? 'application/json; charset=utf-8' : 'application/octet-stream');
      }
      if (req.method === 'POST' && p === '/api/sessions') {
        let body;
        try { body = JSON.parse(await readBody(req)); } catch { return send(res, 400, { error: 'not JSON' }); }
        const list = Array.isArray(body?.sessions) ? body.sessions : [];
        const stored = store.add(list);
        if (stored.added) console.log(new Date().toISOString(), `stored ${stored.added} run(s)`);
        return send(res, 200, { stored: stored.held });
      }
      if (req.method === 'GET' && p === '/api/sessions') {
        const ex = url.searchParams.get('exercise');
        const list = store.all().filter((s) => !ex || s.exerciseID === ex).sort((a, b) => String(b.date).localeCompare(String(a.date)));
        return send(res, 200, { sessions: list });
      }
      if (req.method === 'GET' && p === '/api/stats') {
        const ex = url.searchParams.get('exercise');
        const list = store.all().filter((s) => !ex || s.exerciseID === ex);
        return send(res, 200, { bests: bests(list), progress: progress(list) });
      }
      if (req.method === 'GET' && p === '/api/levels') return send(res, 200, { levels: levels(store.all()) });
      if (p === '/api/routines' && (req.method === 'GET' || req.method === 'POST')) {
        if (req.method === 'POST') {
          let body;
          try { body = JSON.parse(await readBody(req)); } catch { return send(res, 400, { error: 'not JSON' }); }
          const changed = routines.save(Array.isArray(body?.routines) ? body.routines : []);
          if (changed) console.log(new Date().toISOString(), `saved ${changed} routine(s)`);
        }
        return send(res, 200, { routines: routines.all() });
      }
      if (req.method === 'POST' && p === '/api/routine-runs') {
        let body;
        try { body = JSON.parse(await readBody(req)); } catch { return send(res, 400, { error: 'not JSON' }); }
        const r = routines.addRuns(Array.isArray(body?.runs) ? body.runs : []);
        if (r.added) console.log(new Date().toISOString(), `stored ${r.added} routine run(s)`);
        return send(res, 200, { stored: r.held });
      }
      if (req.method === 'GET' && p === '/api/routine-runs') {
        return send(res, 200, { runs: routines.runs().sort((a, b) => String(b.date).localeCompare(String(a.date))) });
      }
      if (p === '/api/settings' && (req.method === 'GET' || req.method === 'PUT' || req.method === 'POST')) {
        if (req.method !== 'GET') {
          let body;
          try { body = JSON.parse(await readBody(req)); } catch { return send(res, 400, { error: 'not JSON' }); }
          return send(res, 200, routines.saveSettings(body));
        }
        return send(res, 200, routines.settings());
      }
      if (req.method === 'GET' && (p === '/' || p === '/index.html')) return send(res, 200, page(catalog, store, routines), 'text/html; charset=utf-8');
      return send(res, 404, { error: 'not found' });
    } catch (e) {
      console.error(new Date().toISOString(), e);
      return send(res, 500, { error: String(e.message || e) });
    }
  };
}

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const clock = (s) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, '0')}`;

function page(catalog, store, routineStore) {
  const c = checkCatalog(catalog);
  const runs = store.all().sort((a, b) => String(b.date).localeCompare(String(a.date))).slice(0, 30);
  const rows = runs.map((r) => `<tr><td>${esc(new Date(r.date).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' }))}</td><td>${esc(r.exerciseName)}</td>
    <td class="n">${r.startBPM}${r.topBPM > r.startBPM ? ` to ${r.topBPM}` : ''}</td><td>${esc(r.mode)}${r.guided ? ', guided' : ''}</td>
    <td class="n">${r.mode === 'endurance' ? clock(r.sustainedSeconds || 0) : r.score}</td><td class="n">${r.accuracyPercent}%</td></tr>`).join('');
  const drills = c.list.map((d) => `<li>${esc(d.name)} <span class="m">${esc(d.id)}, v${d.version ?? 1}</span></li>`).join('');
  const saved = routineStore.all().filter((r) => !r.deleted).map((r) => `<li>${esc(r.name)} <span class="m">${r.blocks.length} blocks${r.starter ? ', starter' : ''}</span></li>`).join('');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Practice drills</title><style>
:root{color-scheme:light dark;--bg:light-dark(#fff,#1c1c1b);--text:light-dark(#1c1b19,#e4e3df);--muted:light-dark(#6a6964,#a3a29c);--line:light-dark(#ebeae6,#2b2b29);--accent:#6FB7A0}
body{margin:0;padding:24px 16px;background:var(--bg);color:var(--text);font:13px/1.5 -apple-system,'Segoe UI',Inter,sans-serif}
main{max-width:860px;margin:0 auto}h1{font-size:15px;margin:0 0 4px}h2{font-size:12px;font-weight:600;color:var(--muted);margin:24px 0 8px}
.m{color:var(--muted)}ul{padding-left:18px;margin:0}table{width:100%;border-collapse:collapse}td{padding:6px 8px 6px 0;border-bottom:1px solid var(--line)}.n{text-align:right;font-variant-numeric:tabular-nums}
</style></head><body><main><h1>Practice drills</h1><div class="m">Catalog ${c.version}, ${c.drills} drills${c.errors.length ? `; problems: ${esc(c.errors.join('; '))}` : ''}. ${store.all().length} runs kept.</div>
<h2>Drills</h2><ul>${drills}</ul><div class="m">${c.archived} archived.</div><h2>Routines</h2><ul>${saved}</ul><h2>Latest runs</h2>${rows ? `<table>${rows}</table>` : '<div class="m">No runs yet.</div>'}</main></body></html>`;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const app = createApp();
  const c = checkCatalog(CATALOG);
  console.log(new Date().toISOString(), `drill server: catalog ${c.version}, ${c.drills} drills${c.errors.length ? ', problems: ' + c.errors.join('; ') : ''}`);
  for (const host of HOSTS) {
    const listen = () => {
      const s = http.createServer(app);
      s.on('error', (e) => {
        // The tailnet address is not there until Tailscale is up: try again in a minute.
        console.error(new Date().toISOString(), `listen ${host}:${PORT}: ${e.code}; trying again in 60 s`);
        setTimeout(listen, 60_000);
      });
      s.listen(PORT, host, () => console.log(new Date().toISOString(), `listening on http://${host}:${PORT}`));
    };
    listen();
  }
}
