# Practice

Joe's guitar practice iPhone app. Joe, 2026-11-14: "Can you build me an iOS app for guitar practice? Nice clean ui. Basic will just be a metronome. Then some HIIT style cycles where I can program metronome change intervals. Eventually, a way to plug in a guitar and basically play along à la guitar hero to attain a score. But it'll be like speed picking basic practices, not songs." The same day: the play-along now ("Go ahead and build a very basic version of the plugin mode now too"), right-hand exercises first ("alternate picking and speed picking"), a guided and a solo mode ("a midi version to play along to and then nothing to play along to"), the flagship drill ("alternating 4x triplets then 4x 16th notes at a given tempo"; modes by cycles, by time, and "see how long you can sustain XYZ percent accuracy"), a foundation that scales, drills pulled from the mini PC without an app update, stats over Tailscale, and a spoken intro.

Install: Safari (or the Browser) on the iPhone, https://caulfieldengineering.github.io/practice-install/, Install. After that the app updates itself: an Update capsule appears at the top when a newer build is out, and Settings has the row.

## What is in it

Three tabs, in the house style (HQ/agent/app-design.md): dark and light from the same tokens, the studio accent `#6FB7A0`, one primary button per screen.

- **Metronome.** Big tempo; drag on it, the minus and plus, the slider, or Tap. Time signature (2/4 to 7/4), accent on the one, clicks per beat (quarter, eighth, triplet, sixteenth). The beats of the bar light as they play.
- **Intervals** (HIIT routines). A routine is a list of intervals (Play at a tempo, Rest, or a timed block with no click), repeated N rounds, every play interval X bpm faster each round, with a count-in. A bell starts each play interval, a lower bell each rest, and the last bar of a rest counts in the next tempo. The running screen shows what to do now, the time left (huge), the tempo, the round, and what is next; skip back and forward; pause and resume; start over. Routines are saved on the phone. Starters from his Perfect Picking Course page (vault, Training Vault): Starting Protocol, 3's to 4's (sets up 6 bpm, breaking point, prior max), Speed ladder, Bursts, Cruise speed.
- **Play along.** The guitar comes in through an audio interface (USB-C or Lightning; Joe, 2026-11-14: "Won't be using the mic"), each pick attack is found and scored against the note the drill asks for. Guided plays the drill as a muted guitar pluck over the click (the switch from triplets to sixteenths is accented so it is heard); Solo is the click only; after a guided run the main button is "Now solo". Runs by **cycles**, by **time**, or **endurance** (keep going until fewer than the target share of notes land within the tolerance over the last N cycles; the score is the time held). Any of them can **ladder**: faster after each passed cycle. Live: the lane (notes scroll to the hit line and light teal, soft teal, amber or red; the pick direction under each), the rolling accuracy, a big "Triplets / Sixteenths" cue that turns amber the beat before a change, the input level. After: the score or time held, within 20, 40 and the set tolerance, missed, extra, on average ahead or behind, spread, accents, and every note's error as a strip. **Calibrate** once per setup: play one note on each of eight clicks; the median offset is kept.
- **Voice.** Before a drill or routine, the phone's own best voice (Premium, then Enhanced, then standard; pick another in Settings) says what it is, the tempo and the goal, then the count starts. Skip it, or hear it again with the speaker button. Optional short cues: "Rest. Next, 140." in routines; the coming switch and a new ladder tempo in the play-along (only with headphones or an interface, never on the phone's own speaker and microphone, where it would hear itself). Better voices: iPhone Settings, Accessibility, Spoken Content, Voices, English.
- **Progress** (the chart icon on Play along): the best solo run at each tempo, per drill and kind of run, and the latest runs; from the mini PC when it is reachable (every run from every device), otherwise the phone's own copy.

Timing: the click is rendered sample by sample inside the audio engine from a sequencer working in audio frames (never a UI timer), so it is exact to the frame and does not drift. It plays alongside other apps (mixWithOthers) and keeps going with the screen locked (the audio background mode).

## The architecture

```
ios/Practice/
  App/         PracticeApp (the scene, the shared objects), Player (one player: metronome, routine or play-along)
  Engine/      AudioEngine (AVAudioEngine, one source node, the input tap), Sequencer (Free, Routine, EventQueue),
               ClickSounds, OnsetDetector, Voice (speech), Protocols (the seams below)
  Scoring/     Scoring (match, score, calibrate), Session (session modes, RunBuilder: a run a cycle at a time)
  Library/     Exercise (the drill schema), Routine (routines and their timeline), Catalog (loading, the drill server)
  Persistence/ History (SwiftData: every run, the send queue, Stats), Stores (routines, the updater)
  Features/    Metronome, Intervals, PlayAlong, Settings: the screens, one folder each
  Shared/      Theme (the house style), TapTempo
catalog/       the drills and starter routines (data; bundled in the app and served by the drill server)
server/        the drill server (Node, no dependencies) and its tests
```

- **Drills are data, not code.** A versioned JSON schema (below). Notes sit on a beat grid with string, fret, pick direction and accent, so left-hand drills and riffs fit later without a schema change. Tempo rules (start, min, max, the ladder step) and scoring rules (pass mark, tight and close windows, the match window) are per drill. Session defaults and levels are per drill.
- **The engine is behind protocols** (Engine/Protocols.swift): `SoundBank` (the click and guide sounds; a sampled guitar drops in), `OnsetDetecting` (a better detector drops in), `NoteInput` (where played notes come from: `AudioOnsetInput` today, a MIDI guitar later). The audio thread never waits: parameters and the play-along's events cross with a try-lock (`Locked`), and the play-along keeps a second and a half queued ahead.
- **Scoring is separate from the UI**: pure functions over note times and onset times (Scoring.swift, Session.swift), all unit tested.
- **One store for runs** (SwiftData, `SessionRecord`, the full `SessionResult` as JSON with indexed fields), with a schema version on each result. Progress per drill over time comes from it, or from the server's copy.

### Session modes

`SessionSettings`: `kind` (cycles, duration, endurance), `cycles`, `seconds`, `targetPercent`, `toleranceMs`, `windowCycles`, `ladderStep`. A drill gives the starting values (`session`) and its levels can set them; the player changes them on the screen (kept per drill). A run is built a cycle at a time (`RunBuilder.cycle`), so the next cycle's tempo can follow the last result. The ladder decides from the latest judged cycle, which with short cycles can be the one before last (a cycle is judged a moment after it ends, and the next is queued a second and a half ahead).

## How to add a drill

1. Open (or add) a file in `catalog/exercises/`, shaped `{"schema": 1, "exercises": [...]}`. A drill:

```json
{
  "id": "trip16x4",                      // unique, never reused; results are kept by it
  "version": 1,                          // bump when the drill itself changes
  "name": "Triplets to sixteenths, 4 and 4",
  "detail": "One line under the name.",
  "intro": "What the voice says first. The tempo and the goal are added to it.",
  "groups": [3, 3, 3, 3, 4, 4, 4, 4],    // shorthand: notes per beat, 0 is a beat of rest; alternate picking from a downstroke
  "accent": "first",                     // shorthand only, optional: accent the first note of each beat
  "tempo": { "start": 80, "min": 40, "max": 200, "stepOnPass": 4 },
  "scoring": { "passMark": 85, "tightMs": 20, "closeMs": 40 },          // optional; windowMs optional
  "session": { "kind": "endurance", "targetPercent": 85, "toleranceMs": 30, "windowCycles": 2 },   // optional
  "levels": [ { "name": "Level 1", "bpm": 70, "session": { "kind": "cycles", "cycles": 4 } } ]       // optional
}
```

   Or the full form instead of `groups`: `"cycleBeats": 1, "notes": [{"at": {"beat": 0, "step": 0, "of": 4}, "pick": "down", "accent": true, "string": 3, "fret": 5}, ...]` (`step` of `of` within the beat, so triplets are exact; `string` 1 is high E; `string` and `fret` optional). `gallop` in `right-hand.json` is a worked example.
2. A new file goes into `catalog/index.json`'s `files` as `{"path": "exercises/<file>.json", "kind": "exercises"}`.
3. Raise `version` in `catalog/index.json` by one. The phone fetches the catalog only when this number is higher than the one it has.
4. `npm run check` (exits non-zero and says what is wrong), then `npm test`.
5. Commit and push. The drill server reads the folder on every request, so the next pull on the phone (opening Play along, pull to refresh, or Settings, Get drills) has it. The next app build also bundles it as the offline starter set.

A routine is the same in `catalog/routines/` (`{"schema": 1, "routines": [{"name", "intervals": [{"kind": "play"|"rest"|"motion", "seconds", "bpm", "label"}], "rounds", "stepBPM", "beatsPerBar", "subdivision", "countInBeats", "notes", "intro"}]}`); starter routines appear on a phone that has none yet and through Settings, Put back the starter routines.

Rules the app keeps: a file whose `schema` is newer than the app knows is skipped whole; a drill with `"schema": 2` (or anything it cannot read) is skipped alone; the rest load. Ids are unique across files; a later file wins. `Documents/Exercises/*.json` on the phone (same shape) is loaded last, for trying a drill without the server.

## The drill server (mini PC)

`server/index.mjs`, no dependencies, scheduled task **Practice Drill Server** (`scripts/register-task.ps1`, at logon, hidden, restarted on failure, log in `logs/service.log`), on `127.0.0.1:4700` and the tailnet address `DRILL_SERVER_HOST:4700` only (it waits for the tailnet address if Tailscale is not up yet).

| Route | What |
|---|---|
| `GET /health` | `{ok, catalogVersion, drills, routines, problems, sessions}`; `ok` is false when the catalog has a problem |
| `GET /catalog/index.json`, `GET /catalog/<path>` | the catalog, straight from `catalog/` |
| `POST /api/sessions` | `{sessions: [...]}`; answers `{stored: [ids]}`, the ids it now holds. A run already held is not added again |
| `GET /api/sessions?exercise=<id>` | every run, newest first |
| `GET /api/stats?exercise=<id>` | `bests` (best solo run per drill, mode and starting tempo: score, or seconds held for endurance) and `progress` (every run in time order) |
| `GET /` | a small page: the drills and the latest runs |

Runs are kept in one place, `data/sessions.jsonl` (one run a line, appended, never rewritten; not in git). The phone queues every run (SwiftData) and sends the queue when it opens, after each run, and from Progress and Settings, until the server answers with the run's id; then it is marked sent. Away from Tailscale everything works from the phone's copy and the last catalog it pulled.

A result (`SessionResult`, schema 1): id, date, exercise id, version and name, mode, ladder step, guided, starting and top tempo, seconds played, cycles, notes, hits, missed, extra, within the tight and close windows, the windows, average error and spread (ms), tolerance and target, accuracy within the tolerance, seconds held (endurance), score, passed, accents, the calibration offset, the app version.

## Latency (Bluetooth headphones included)

Joe, 2026-11-14, on his Shokz open-ear headphones: "Is there a way to remove the latency or compensate so that the analysis is still accurate". The delay cannot be removed, so every pick is scored against when the click was heard (Engine/Latency.swift):

- Output stays on A2DP: the session is `playAndRecord` with `.allowBluetoothA2DP` and never `.allowBluetooth` (hands-free), so turning the input on does not flip the headphones into call mode. The input is always the interface (`preferInterface`: USB, line in or a wired headset input), never the headphones' own; with none plugged in the screen says "Plug in your audio interface" and a run does not start (the phone's microphone only with the testing switch on). If the route is hands-free anyway, the screen says so.
- The estimate is outputLatency (which iOS reports for Bluetooth) + inputLatency + the IO buffer. Calibrate plays twelve clicks; he plays one note on each; picks are moved by the estimate and the median of what is left is the residual. The offset in use is today's estimate plus that residual, so it follows iOS when the reported Bluetooth delay moves.
- Calibrations are kept per route (the input and output ports), applied by themselves when that route is active; a route with none says "New audio setup ... calibrate once". The current offset in ms is on the Play along screen, and each result keeps the offset it used.
- A route change in the middle of a run stops it (the engine restarts on the new route) and says why; the setup screen re-reads the route.
- Spoken cues and the guide notes go to the headphones too.

Two setups, each calibrated once:

- **Interface in, interface out** (headphones on the interface): the lowest delay and the most accurate.
- **Interface in, Shokz out** (Bluetooth A2DP): the delay is larger and measured out. iOS's rule is that the newest route wins, and a USB interface usually takes both input and output when it is plugged in. The speaker button on the Play along screen (the system output picker) moves the output to the Bluetooth headphones while the input stays on the interface; the screen always shows what iOS actually chose ("In: ... Out: ..."). Not yet tried on his phone: if iOS keeps both on the interface with his model, use the interface's headphone out, or connect the Shokz after the interface.

## Building and installing

The same route as the HQ and Browser iPhone apps. `.github/workflows/ios-build.yml` runs on a push touching `ios/`, `catalog/` or itself: XcodeGen makes the project from `ios/project.yml`, the unit tests run on the iPhone simulator and must pass, then on `main` it archives, exports ad hoc, and publishes `app.ipa`, `manifest.plist`, `version.json`, the icon and the install page to the public repo `CaulfieldEngineering/practice-install` (GitHub Pages). Versions are `0.1.<run number>`. Other branches build and test only.

Signing: Blocks' Apple team (`APPLE_TEAM_ID_REDACTED`), App Store Connect API key and Apple Distribution certificate, with Practice's own App ID `com.caulfieldengineering.practice` and ad-hoc profile `Practice AdHoc`. `node scripts/apple-provision.mjs` makes the App ID and the profile for every registered iPhone (into `C:\Users\Joe\.apple\practice`, never a new certificate); `npm i --no-save libsodium-wrappers && node scripts/apple-secrets.mjs` puts the certificate, its password, the profile, the team and the install repo's deploy key (`C:\Users\Joe\.apple\practice\install_key`) in this repo's Actions secrets. Every year, after Blocks' certificate is renewed, run both again, then the workflow, then reinstall. A new iPhone: register it, then run both again.

The icon is drawn by `python scripts/make-icon.py` (the charcoal and teal of his other icons).

Tests: `ios/PracticeTests` (the sequencers to the frame, block size, drift over ten minutes, routine timelines, the event queue, tap tempo, scoring, matching, calibration, cycles and cues, endurance and the ladder, onset detection on synthetic picking, the catalog and schema decoding, results and the send queue) on the simulator in the workflow; `npm test` (the server: the catalog, serving it, keeping runs once, stats).

## Limits, honestly

- Onset detection is energy based with a high-pass: right for one picked string, muted or open. Chords, legato, heavy distortion with long sustain and noisy rooms will miss or add notes. A spectral-flux or learned detector can drop in behind `OnsetDetecting`.
- The phone's microphone is only a testing stand-in (Settings, "Use the phone's microphone (testing)", off by default). On it, with the phone's speaker, the phone hears its own click and guide notes and the room; the app says so. Bluetooth headphones (his Shokz) are fine: see Latency. If the headphones drop into call mode (hands-free), the app says so; the sound is poor and the delay changes, so reconnect them.
- The guide sound is a synthesized muted pluck, not a sampled guitar (`SoundBank` is the place for one).
- The ladder's tempo step can lag a cycle behind the result for short cycles (see Session modes).
- Pitch is not checked: a note on the wrong string or fret still counts. Left-hand drills need pitch; the schema already carries string and fret.
- Play-along runs on its own tab, not inside an Intervals routine yet.

## Next

- A sampled guide guitar and a pitch check (string and fret), so left-hand drills and riffs can be scored.
- Play-along inside a routine's play intervals.
- A progress chart from `/api/stats` (the data is there).
- Agents tuning levels from the runs on the mini PC: see `docs/agents.md`.
