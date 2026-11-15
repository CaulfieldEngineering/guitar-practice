// Makes the recorded voice for Practice: short clips for each drill's spoken line, every tempo, the goals and the
// few cue words, in one calm voice, packed into voice/pack.bin with voice/index.json beside it. The drill server
// serves the two files (/voice/index.json, /voice/pack.bin) and the app also carries them, so the voice works before
// the phone has reached the mini PC; the phone's own voice is the fallback for anything with no clip.
//
// Joe, 2026-11-14: "can we do a better voice? And simpler voice intro. Don't need to say keep the motions small".
//
//   node scripts/make-voice.mjs            make what is missing (a clip is kept while its words are the same)
//   node scripts/make-voice.mjs --list     say what would be made, and make nothing
//
// The speech is OpenAI's gpt-4o-mini-tts (the same service and key as HQ's read-aloud, C:\Users\Joe\.keys\openai.txt),
// paid by use: a clip is about a second, the whole set a few minutes of audio, a few cents. To change the voice, change
// VOICE below and delete voice/ first, so every clip is made again in the new one.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'voice');
const KEY_FILE = path.join(os.homedir(), '.keys', 'openai.txt');
const MODEL = 'gpt-4o-mini-tts';
const VOICE = 'sage';
const STYLE = 'Calm, neutral and natural, like a studio engineer quietly reading a cue. An even, unhurried pace. No excitement, no sales voice, and the last word falls, it does not rise.';

/** "30 seconds", "1 minute", "2 minutes 30 seconds": the same words the app says (IntroText.spokenTime). */
function spokenTime(seconds) {
  const m = Math.floor(seconds / 60), r = seconds % 60;
  if (m === 0) return `${r} seconds`;
  const mins = m === 1 ? '1 minute' : `${m} minutes`;
  return r === 0 ? mins : `${mins} ${r} seconds`;
}

/** Every clip wanted: key -> the words. The keys are the ones the app asks for (IntroText.parts). */
function wanted() {
  const clips = {};
  const index = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', 'index.json'), 'utf8'));
  for (const f of index.files.filter((x) => x.kind === 'exercises')) {
    const doc = JSON.parse(fs.readFileSync(path.join(ROOT, 'catalog', f.path), 'utf8'));
    for (const e of doc.exercises ?? []) {
      const say = (e.say || `${e.name}.`).trim();
      clips[`say.${e.id}`] = say;
    }
  }
  for (let bpm = 40; bpm <= 260; bpm += 1) clips[`bpm.${bpm}`] = `${bpm}.`;
  for (let n = 1; n <= 40; n += 1) clips[`cycles.${n}`] = n === 1 ? '1 cycle.' : `${n} cycles.`;
  for (let s = 30; s <= 1800; s += 30) clips[`time.${s}`] = `${spokenTime(s)}.`;
  clips.endurance = 'Endurance.';
  clips.open = 'Open.';
  clips['cue.2'] = 'Eighths.';
  clips['cue.3'] = 'Triplets.';
  clips['cue.4'] = 'Sixteenths.';
  clips['cue.0'] = 'Rest.';
  return clips;
}

async function speak(key, text) {
  const res = await fetch('https://api.openai.com/v1/audio/speech', {
    method: 'POST',
    headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
    body: JSON.stringify({ model: MODEL, voice: VOICE, input: text, instructions: STYLE, response_format: 'mp3' }),
  });
  if (!res.ok) throw new Error(`speech said ${res.status}: ${(await res.text().catch(() => '')).slice(0, 200)}`);
  return small(Buffer.from(await res.arrayBuffer()));
}

/** The clip with the silence at both ends taken off, as a small mono MP3 (ffmpeg), so the whole set is a few MB. */
function small(mp3) {
  const trim = 'silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse';
  const r = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', 'pipe:0', '-af', trim, '-ac', '1', '-ar', '24000', '-b:a', '40k', '-f', 'mp3', 'pipe:1'],
    { input: mp3, maxBuffer: 16 * 1024 * 1024 });
  if (r.status !== 0 || !r.stdout?.length) throw new Error(`ffmpeg: ${String(r.stderr || r.error || '').slice(0, 200)}`);
  return r.stdout;
}

const want = wanted();
const indexFile = path.join(OUT, 'index.json');
const packFile = path.join(OUT, 'pack.bin');
let old = { version: 0, clips: {} };
let oldPack = Buffer.alloc(0);
if (fs.existsSync(indexFile) && fs.existsSync(packFile)) {
  old = JSON.parse(fs.readFileSync(indexFile, 'utf8'));
  oldPack = fs.readFileSync(packFile);
}
const sameVoice = old.voice === VOICE && old.model === MODEL;
const keep = {};
const make = [];
for (const [k, text] of Object.entries(want)) {
  const o = old.clips?.[k];
  if (sameVoice && o && o.text === text && o.o + o.n <= oldPack.length) keep[k] = oldPack.subarray(o.o, o.o + o.n);
  else make.push(k);
}
console.log(`${Object.keys(want).length} clips wanted, ${Object.keys(keep).length} kept, ${make.length} to make`);
if (process.argv.includes('--list')) {
  for (const k of make.slice(0, 40)) console.log(' ', k, JSON.stringify(want[k]));
  process.exit(0);
}

const gone = Object.keys(old.clips ?? {}).some((k) => !(k in want));
if (!make.length && !gone) { console.log('nothing to do'); process.exit(0); }
const key = make.length ? fs.readFileSync(KEY_FILE, 'utf8').trim() : '';
let failed = 0;
// A few at a time, each tried up to three times.
const queue = [...make];
async function worker() {
  for (;;) {
    const k = queue.shift();
    if (!k) return;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try { keep[k] = await speak(key, want[k]); break; } catch (e) {
        if (attempt === 3) { failed += 1; console.error('failed', k, String(e.message || e)); } else await new Promise((r) => setTimeout(r, 1500 * attempt));
      }
    }
    const left = queue.length;
    if (left % 25 === 0) console.log(`${left} left`);
  }
}
await Promise.all(Array.from({ length: 4 }, worker));

fs.mkdirSync(OUT, { recursive: true });
const clips = {};
const parts = [];
let offset = 0;
for (const k of Object.keys(want)) {
  const data = keep[k];
  if (!data) continue;
  clips[k] = { o: offset, n: data.length, text: want[k] };
  parts.push(data);
  offset += data.length;
}
fs.writeFileSync(packFile, Buffer.concat(parts));
fs.writeFileSync(indexFile, JSON.stringify({ schema: 1, version: (old.version || 0) + 1, model: MODEL, voice: VOICE, bytes: offset, clips }) + '\n');
console.log(`voice ${(old.version || 0) + 1}: ${Object.keys(clips).length} clips, ${(offset / 1024 / 1024).toFixed(2)} MB${failed ? `, ${failed} failed (run again)` : ''}`);
process.exit(failed ? 1 : 0);
