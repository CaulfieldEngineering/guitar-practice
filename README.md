# Practice

Joe's guitar practice iPhone app. Joe, 2026-11-14: "Can you build me an iOS app for guitar practice? Nice clean ui. Basic will just be a metronome. Then some HIIT style cycles where I can program metronome change intervals. Eventually, a way to plug in a guitar and basically play along à la guitar hero to attain a score. But it'll be like speed picking basic practices, not songs." The same day: the play-along now ("Go ahead and build a very basic version of the plugin mode now too"), right-hand exercises first ("alternate picking and speed picking"), a guided and a solo mode ("a midi version to play along to and then nothing to play along to"), the flagship drill ("alternating 4x triplets then 4x 16th notes at a given tempo"; modes by cycles, by time, and "see how long you can sustain XYZ percent accuracy"), a foundation that scales, drills pulled from the mini PC without an app update, stats over Tailscale, and a spoken intro.

Install: Safari (or the Browser) on the iPhone, https://caulfieldengineering.github.io/practice-install/, Install. After that the app updates itself: an Update capsule appears at the top when a newer build is out, and Settings has the row.

**Practice for Windows** (desktop/, since 2026-11-17; Joe: "Can we build a desktop version of the guitar practice app? Let them share drills and stats in a common backend"): the same app on his laptop and the mini PC, built with JUCE for ASIO and WASAPI exclusive. Same drills, same scoring (both apps pass `shared/scoring-vectors.json`), and every run from either app is in both apps' Progress through the drill server. Install from `Dropbox\Apps\Practice`; it updates itself. [desktop/README.md](desktop/README.md).

## 0.3.0 (phone) and 0.2.0 (Windows), 2026-11-24

Joe, 2026-11-24: "Can we completely overhaul and modernize the UI? The premise is great but it looks a little AI slop now. Also, Let's remove all drills for now except for 'Triplets to 16th's, 4+4'. And I want a few additional options including ascending tempo. Then let's build a Routines section where we can interval out warm ups, drills, breaks, etc." Then: ascending tempo "either per loop, or threshold average accuracy sustained per x duration", "a slow down BPM based on average sustained poor accuracy. And a paused break when dropping below even lower threshold accuracy", "Let's also define the guitar's tuning and start using an X where correct note doesn't care", and "some kind of 'Challenge' mode that counts duration but only counts towards the time when the accuracy is above a certain threshold".

- **The look.** Redesigned from a written design pass (docs/design-0.3.md): the system font with monospaced digits (no rounded numerals), left-aligned screens, the system's own navigation bars, forms and lists on the phone, one accent, a beat bar, an accuracy meter with zones. Four tabs on the phone (Metronome, Drills, Routines, Progress; Settings is the gear); a side panel on the desktop.
- **One drill.** Every drill but `trip16x4` is `"archived": true` in `catalog/exercises/right-hand.json`: kept, with his runs, and left out by the drill server (`activeExercises` in `server/catalog.mjs`), the phone (`Library.active`) and the desktop (`Library::active`). Take the flag off and bump `catalog/index.json` to bring one back.
- **Ascending tempo** (`tempoPlan` in a drill's session): per loop (+N every K loops or seconds, to an end tempo, then hold or start again) or by accuracy (speed up at or above a line held for a window, slow down under a lower line, an automatic break with a countdown under a lower one still; the lines kept 5 points apart and a wait after each change). The tempo curve, the breaks and each stretch's accuracy are kept with the run (`tempoChanges`, `tempoSteps`, `breaks`). One reference, `shared/tempo-plan.mjs`, with vectors (`shared/tempo-vectors.json`) every app passes.
- **Challenge** (a kind of run): the clock counts only while the rolling accuracy holds at the line; done at the target, or at the cap. Kept: `earnedSeconds`, `elapsedSeconds`, `bestStreakSeconds`.
- **Options** before Start: count-in bars, accent (beat 1, group starts, off), click sound (Click, Wood block, Beep, Rim) and level, the gap trainer (the click muted every Nth bar), and a tuning for this drill.
- **Tuning** (Settings, Guitar): presets from E standard to 7-string B and Drop A, or custom per string; it follows him through the drill server (`/api/settings`). Tab and note names follow it.
- **X notes.** A note whose pitch does not matter (`"x": true`, `"fret": "x"`, or no fret; a whole drill with `"pitch": "x"`) is drawn as a × and scored on timing only. A note with a string and a fret is checked for pitch in the tuning (a YIN pitch detector on the pick's first 50 ms; the octave and an unknown pitch are not held against him). The triplets drill is all X.
- **Routines.** Blocks in order (warm-up, drill with its own setup, break, open practice, custom), edited, reordered, duplicated; run as a guided session (3, 2, 1 and a chime before each block, Pause, Skip, Back) and kept as one session in Progress with each drill block's run. Shared by both apps through the drill server (`/api/routines`, `/api/routine-runs`). The starter, "Picking session", is in `catalog/starter-routines.json`. The runner's timing is `shared/routine-clock.mjs`, with vectors.
- **Tests.** `npm test` (the server, the catalog filter, routines, settings, the shared vectors), the desktop's `PracticeTests.exe` (the same vectors), and on the phone `ModelCheckTests` (the same checks also run on Windows: `bash scripts/model-check.sh`, with the Swift toolchain).

## What is in it

Two tabs, Metronome and Drills (Joe, 2026-11-14: "intervals and play along can just be combined into Drills since we're covering both audio and no-audio settings"), in the house style (HQ/agent/app-design.md): dark first and light from the same tokens, the studio accent `#6FB7A0`, one primary button per screen. Progress and Settings are line icons at the top of the screen.

- **Metronome.** Big tempo; drag on the number to scrub it (each step ticks), hold the minus or the plus, the slider, or Tap. Time signature (2/4 to 7/4), accent on the one, clicks per beat (quarter, eighth, triplet, sixteenth). The beats of the bar light as they play.
- **Drills.** A table, one line a drill (Joe, on 0.1.6: "the lists still need a big cleanup. Like a table of some kind?"): the name (the drill's `short` name; it takes all the room the other columns leave, 0.1.10), the pattern in a few characters ("3→4", "16", "16·rest"), his max and his best accuracy as two compact columns, and when it was last played as a small line under the name; grouped under small headers by the drill's `category` (Picking, Speed, Accents); sorted as listed, by last played, by max or by name; a search field once there are more than twelve. What a drill is, in words, is on its own screen.
  - **Timed routines are out of the app since 0.1.7** (Joe, 2026-11-14: "Let's omit the timed routines for now and just focus on the drills themselves. We'll build in routines later"). Nothing of his is deleted: the routines saved on the phone stay in `Documents/routines.json`, the starters stay in `catalog/routines/`, and the code is kept, unused: the routine player in `Player`, `Features/Intervals` (the run screen and the editor), and the groundwork for bringing them back as drills made of timed blocks (`Exercise.segments`, the `routine` kind of run, `PlayAlong.setOwnRoutines`), which reads and is unit tested but has never run on a phone. The Drills table leaves out any drill with timed blocks.
  - **Picking drills.** Tapping one opens its own screen: what it is and its pattern, then the setup, then one Start. The setup, top to bottom: the **tempo** (the zones of his max once he has one, each showing its tempos, "Z3 Tempo · 120–135 bpm"; or by hand: drag on the number or hold the minus and plus; the drill's own levels are one menu under it), **Guided or Solo**, the **run** (Cycles, Time or Endurance, and its one amount), the **Audio input** switch, and **Options**, folded until asked for (the ladder, the pass mark, the click, the spoken intro, where the sound goes and the calibration). All of it is remembered per drill.
  - **Audio input** (Joe, 2026-11-14: "Just some kind of toggle for 'audio input', if it's selected, it'll be scored"). On: the guitar comes in through an audio interface (USB-C or Lightning; Joe: "Won't be using the mic"), each pick attack is found and scored against the note the drill asks for, the run is saved, sent to the mini PC and counts toward his max. Off: the input is never opened (no interface needed, no microphone permission asked, Bluetooth headphones stay in their listening mode), nothing is scored, saved or counted; the click, the guide, the kind of run, the spoken intro and the zone tempo all still work, Endurance becomes Open (it runs until he stops it), the ladder climbs every cycle, and the run screen shows only the pattern, the tempo, the cycle and the time. Only the minutes played that way are kept, per drill, on the phone (`UnscoredLog`, shown on Progress), apart from the scores.
  - **Runs.** Guided plays the drill on a real guitar, short muted notes of the FreePats Strat, over the click (the switch from triplets to sixteenths is accented so it is heard; see The guide guitar); Solo is the click only; after a guided run the main button is "Now solo". Runs by **cycles**, by **time**, or **endurance** (keep going until the accuracy over the last N cycles drops under the target; the score is the time held). Any of them can **ladder**: faster after each passed cycle. Live, made to be glanced at: the pattern now ("Triplets", amber the beat before a change), the tempo, the accuracy, the time, the run as scrolling tablature (six string lines; each note is its fret number on its string, scrolling to a fixed line and taking its colour there: teal, soft teal, amber or red; above the strings the rhythm as bars grouped by the beat, with the pick direction over each; the string and fret come from the drill's data, so left-hand drills will show their real notes; a right-hand drill is an open G), an early/late line of the latest picks, the input level. **Pause and Stop are always at the bottom of the run screen, and a tap anywhere pauses** (Joe, on 0.1.6: "can't figure out how to stop it"). Paused, the sound is off and the clock stopped, with Resume and End: Resume goes back to the start of the cycle that was playing, behind a bar of count-in, and that cycle is played again from clean (in a count-in it starts over); the cycles already judged stand, and the run's own clock carries on from there, so a timed run is no longer and no shorter. End keeps what was judged. **Leaving the drill ends it** (Joe, on 0.1.6: "Drills keep running when I leave the drill"): when the drill's screen goes away for any reason, the click, the guide, the voice, the input and the timer stop (`PlayAlong.leave`), and a scored run keeps what was judged. The app has one player (`Player`): starting the metronome ends a drill and starting a drill ends the metronome. When the metronome is ticking and another tab is open, a bar at the top says so, with Stop. After: the accuracy or the time held, every note's timing as a strip, then on the click, on average early or late, spread, missed, extra, accents. **Calibrate** once per setup: play one note on each of twelve clicks; the median offset is kept.
- **Voice** (0.1.8; Joe, 2026-11-14: "can we do a better voice? And simpler voice intro. Don't need to say keep the motions small etc"). Before a drill a recorded voice says a short, plain line: the name and the pattern, the tempo, the goal. "Triplets to sixteenths. Four and four. 120. 8 cycles." Nothing about how to play: coaching is in the drill's description on its screen. Skip it, or hear it again with the speaker button. Optional short cues in a run (the coming switch, a new ladder tempo), only with headphones or an interface, never on the phone's own speaker and microphone. See The recorded voice.
- **Progress** (the chart icon on Drills): per drill, his max, the tempo reached run by run as a small line, the best solo run at each tempo and kind of run, the minutes played with the audio input off; then the latest runs. From the mini PC when it is reachable (every run from every device), otherwise the phone's own copy.

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
  Features/    Metronome, PlayAlong (the Drills list, a drill's setup, the run and result screens, Progress),
               Intervals (a routine's run screen and editor), Settings, Debug (the screens drawn from made-up values
               for the UI test's screenshots; debug builds only)
  Shared/      Theme (the design system's tokens), Components (what the screens are built from), TapTempo
catalog/       the drills and starter routines (data; bundled in the app and served by the drill server)
server/        the drill server (Node, no dependencies) and its tests
```

- **Drills are data, not code.** A versioned JSON schema (below). Notes sit on a beat grid with string, fret, pick direction and accent, so left-hand drills and riffs fit later without a schema change. Tempo rules (start, min, max, the ladder step) and scoring rules (pass mark, tight and close windows, the match window) are per drill. Session defaults and levels are per drill.
- **The engine is behind protocols** (Engine/Protocols.swift): `SoundBank` (the click and guide sounds; a sampled guitar drops in), `OnsetDetecting` (a better detector drops in), `NoteInput` (where played notes come from: `AudioOnsetInput` today, a MIDI guitar later). The audio thread never waits: parameters and the play-along's events cross with a try-lock (`Locked`), and the play-along keeps a second and a half queued ahead.
- **Scoring is separate from the UI**: pure functions over note times and onset times (Scoring.swift, Session.swift), all unit tested. The same rules are in the desktop app (desktop/src/core/Scoring.cpp) and in plain JavaScript (shared/scoring.mjs); all three pass one file of test vectors (shared/scoring-vectors.json, `node scripts/make-scoring-vectors.mjs`), so change a rule in all three together.
- **One store for runs** (SwiftData, `SessionRecord`, the full `SessionResult` as JSON with indexed fields), with a schema version on each result. Progress per drill over time comes from it, or from the server's copy.

### Session modes

`SessionSettings`: `kind` (cycles, duration, endurance), `cycles`, `seconds`, `targetPercent` (the accuracy a cycle passes at, and the one endurance holds to), `windowCycles`, `ladderStep`. (`toleranceMs` is still read, for catalogs and 0.1.5, and no longer used: see Accuracy.) A drill gives the starting values (`session`) and its levels can set them; the player changes them on the screen (kept per drill). A run is built a cycle at a time (`RunBuilder.cycle`), so the next cycle's tempo can follow the last result. The ladder decides from the latest judged cycle, which with short cycles can be the one before last (a cycle is judged a moment after it ends, and the next is queued a second and a half ahead).

## How to add a drill

1. Open (or add) a file in `catalog/exercises/`, shaped `{"schema": 1, "exercises": [...]}`. A drill:

```json
{
  "id": "trip16x4",                      // unique, never reused; results are kept by it
  "version": 1,                          // bump when the drill itself changes
  "name": "Triplets to sixteenths, 4 and 4",
  "detail": "One line under the name.",
  "short": "Trips to 16ths, 4+4",        // optional: the name in the Drills table
  "category": "Speed",                   // the table's section: Picking, Speed, Accents, or a new one
  "say": "Triplets to sixteenths. Four and four.",   // what the voice says first: the name and the pattern, short. The tempo and the goal are added
  "intro": "Only for 0.1.7 and earlier, which speak it.",
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
4. `node scripts/make-voice.mjs` records the new `say` line (a few cents; without it the phone's own voice says it). Then `npm run check` (exits non-zero and says what is wrong) and `npm test`.
5. Commit and push. The drill server reads the folder on every request, so the next pull on the phone (opening Play along, pull to refresh, or Settings, Get drills) has it. The next app build also bundles it as the offline starter set.

A routine is the same in `catalog/routines/` (`{"schema": 1, "routines": [{"name", "intervals": [{"kind": "play"|"rest"|"motion", "seconds", "bpm", "label"}], "rounds", "stepBPM", "beatsPerBar", "subdivision", "countInBeats", "notes", "intro"}]}`); starter routines appear on a phone that has none yet and through Settings, Put back the starter routines.

Rules the app keeps: a file whose `schema` is newer than the app knows is skipped whole; a drill with `"schema": 2` (or anything it cannot read) is skipped alone; the rest load. Ids are unique across files; a later file wins. `Documents/Exercises/*.json` on the phone (same shape) is loaded last, for trying a drill without the server.

## The drill server (mini PC)

`server/index.mjs`, no dependencies, scheduled task **Practice Drill Server** (`scripts/register-task.ps1`, at logon, hidden, restarted on failure, log in `logs/service.log`), on `127.0.0.1:4700` and the tailnet address only (`hosts` in `config.local.json` at the repo root, not in git; `config.example.json` shows its shape) (it waits for the tailnet address if Tailscale is not up yet).

| Route | What |
|---|---|
| `GET /health` | `{ok, catalogVersion, drills, routines, problems, sessions}`; `ok` is false when the catalog has a problem |
| `GET /catalog/index.json`, `GET /catalog/<path>` | the catalog, straight from `catalog/` |
| `POST /api/sessions` | `{sessions: [...]}`; answers `{stored: [ids]}`, the ids it now holds. A run already held is not added again |
| `GET /api/sessions?exercise=<id>` | every run, newest first |
| `GET /api/levels` | his max per drill: `{levels: {<id>: {max, basedOn, passes, rule}}}` |
| `GET /api/stats?exercise=<id>` | `bests` (best solo run per drill, mode and starting tempo: score, or seconds held for endurance) and `progress` (every run in time order) |
| `GET /desktop/latest.json`, `GET /desktop/Practice-Setup-<version>.exe` | the desktop app's updater (from `desktop/release/`, written by `desktop/scripts/build.ps1`) |
| `GET /` | a small page: the drills and the latest runs |

Runs are kept in one place, `data/sessions.jsonl` (one run a line, appended, never rewritten; not in git). The phone queues every run (SwiftData) and sends the queue when it opens, after each run, and from Progress and Settings, until the server answers with the run's id; then it is marked sent. Away from Tailscale everything works from the phone's copy and the last catalog it pulled.

A result (`SessionResult`, schema 1): id, date, exercise id, version and name, mode, ladder step, guided, starting and top tempo, seconds played, cycles, notes, hits, missed, extra, within the tight and close windows, the windows, average error and spread (ms), tolerance and target, accuracy within the tolerance, seconds held (endurance), score, passed, accents, the calibration offset, the app version.

## Tempo zones and his max

Joe, 2026-11-14: "exercises can be chosen the tempo but can also choose to resume at whatever tempo the app has learned I've achieved", then: "I'm thinking like heart rates, there's maximum but then there's percentages of maximum based on what you're expected to sustain".

- **His max on a drill** is learned from his runs: of his last 10 solo runs of it, the ones that passed (the drill's target, e.g. 85% accuracy) give the tempo they reached; the max is the second highest, so one lucky run does not count (with a single pass, that tempo less one ladder step). The drill server works it out (`GET /api/levels`, `learnedTempo` in `server/store.mjs`) so the rule can be tuned without an app update; the phone has the same rule (`Stats.learnedTempo`) for when the mini PC is out of reach. Guided runs never count.
- **Zones** are percentages of that max, in `catalog/zones.json` (tunable like any drill: change it, bump the index version): Z1 Warm-up 60 to 70%, Z2 Cruise 70 to 80%, Z3 Tempo 80 to 90%, Z4 Threshold 90 to 100%, Z5 Max 100 to 105%. Each kind of run suggests one (`suggest`): endurance Z2, cycles and time Z3, a laddered run Z4 (it climbs into Z5, which is where a new max comes from). A run starts at `startAt` within the zone (the middle).
- On a drill's screen, once he has a max: **Zones** (default; the zone chips, and "Z3 Tempo · 80–90% of max 150 → 120–135 bpm") or **Manual** (the tempo by hand). The run screen shows the zone and the percent of max as the tempo climbs. After a run, a higher max is said plainly ("Your max is now 136, up from 132").

## Accuracy

Joe, 2026-11-14, on the "Within 30 ms" row: "The ms accuracy should be part of the algorithm determining percentage accuracy, not a user feature". So there is no timing window to set anywhere. The accuracy is worked out note by note (`ScoringConfig` in `ios/Practice/Scoring/Scoring.swift`):

- A played note earns **credit** from its timing error: all of it inside a tight window, falling smoothly (a cosine) to nothing at a wider one.
- Both windows are a **share of the gap to the nearest neighbouring note**, so they follow the subdivision and the tempo: sixteenths at 160 (94 ms apart) get full credit within 12 ms and nothing from 42 ms; eighths at 80 (375 ms apart) get full credit within 25 ms and nothing from 90 ms. Each window is kept between a floor and a ceiling in milliseconds.
- A **missed** note earns nothing. Each **extra** note counts as one more note that earned nothing.
- **Accuracy** is the credit over the notes asked for plus the extras, as a percentage. It is the run's score, what a cycle is judged on (the ladder, and his max), and what endurance holds to. The endurance target is still his to set, as a percentage.

**What the numbers mean, and one pick heard twice (0.2.2).** Joe, 2026-11-17, on the guitar through the MOMIX-CAB and the Shokz: "I believe I'm playing pretty locked in but I struggled to get above 61% accuracy". His five-minute run said why: on the click within 4 ms on average (the 231 ms calibration was right), a spread of 20 ms, 94% of notes within 40 ms, and 923 extra notes on 1574. Without the extras that run is about 97%. The extras were one pick heard twice, so:

- **A pick heard twice is one note** (`Scoring.addPick`): two onsets closer than the drill's match window (45% of the shortest gap between notes, at most 100 ms), one with under half the other's energy, are one pick, and the stronger is kept. Two picks of like strength are still two notes, so a real extra note still costs. The detector also needs a new attack to rise over 30% of the last one's energy, fading over 40 ms (`OnsetDetector.retriggerRatio`, `envelopeTau`), which a soft note after an accent clears easily. Each result keeps `doubles` (how many were folded) and `extraOffsetsMs` (each extra left, ms from its nearest note) so the next look at his runs sees what they are.
- **The scale against players** (Gaussian timing, no misses or extras, the flagship drill at 90; `TimingFairnessTests`): a spread of 12 ms scores 100, 15 ms about 99, 20 ms about 97, 25 ms about 93, 30 ms about 89, 40 ms about 78, 50 ms about 69. Session players hold 10 to 15 ms, good amateurs 20 to 30, beginners 40 to 60, so the 85 pass mark is a good amateur's, not a virtuoso's. At faster tempos the windows shrink with the gap (sixteenths at 140: 20 ms scores about 85).
- **The result says the timing apart from the score**: "4 ms early · spread 20 ms · Tight" (bands by spread: Locked under 15, Tight under 25, Good under 40, Loose under 60, Rough), what the extra notes cost in points when it is five or more, and the anchors in one line. The average belongs to the calibration, the spread to him.

The numbers are in `catalog/scoring.json` (`fullFraction` 0.12, `zeroFraction` 0.45, `fullMinMs` 12, `fullMaxMs` 25, `zeroMinMs` 35, `zeroMaxMs` 90, `extraWeight` 1), served by the drill server like the zones: change them, bump `catalog/index.json`'s version, `npm run check`, and the phone has them on its next pull, with no app update. The app carries the same numbers as its default (`ScoringConfig.standard`) for before a catalog has been read. A result says how it was judged: `scoringVersion` 2, and `fullMs` and `zeroMs` (the windows, averaged over the run); `accuracyPercent` and `score` are the same number now, and `toleranceMs` carries the full-credit window. Runs from 0.1.5 and before have no `scoringVersion` (their accuracy was the share of notes within a fixed 30 ms).

## The guide guitar

Joe, 2026-11-14: "can we do a better sound for the guided?" The guide is recorded notes of the FreePats Strat, his default guitar since 2026-11-12 (the clean set: a Fender recorded direct and run through its maker's amp and cabinet). It is CC0, public domain, so it ships in the app. `python scripts/make-guitar.py` cuts it into `ios/Practice/Resources/Guitar` (52 notes, 0.9 MB): thirteen pitches from the low E up to the F above the open high E, each as a hard and a soft recording, two takes of each, cut at the pick attack and shaped to a short muted note, mono at 24 kHz.

`Engine/GuitarBank.swift` reads them once. A note of the guide carries its pitch (from the drill's `string` and `fret`; a drill that names no string plays the open G) and its stroke; the bank picks the nearest recording and how much faster or slower to run it to be in tune, the hard recording for an accent and the soft one otherwise, one take for a down stroke and the other for an up stroke. The audio thread plays it sample by sample at that speed (`RenderState`), and a new note damps the one before, as on one string. If the notes are missing from the app the old made-up pluck is used. The amp tone is the one in the recordings; there is no amp model in the app.

## The recorded voice

`node scripts/make-voice.mjs` makes the voice on the mini PC: one clip for each drill's spoken line (the catalog's `say`), every tempo from 40 to 260, 1 to 40 cycles, every length of timed run, "Endurance", "Open" and the cue words, 336 clips in all. The speech is OpenAI's `gpt-4o-mini-tts`, the same service and key HQ's read-aloud uses (`C:\Users\Joe\.keys\openai.txt`), voice `sage`, asked to be calm, neutral and natural; it is paid by use, about a cent and a half a minute of audio, and the whole set is about six minutes, so around ten cents; a later run only makes the clips whose words changed. (Not ElevenLabs: Joe, 2026-11-04, on HQ's voice: "I don't want to use ElevenLabs".) Each clip has its silence trimmed and is a small mono MP3; they are packed end to end into `voice/pack.bin` (2.6 MB) with `voice/index.json` saying where each one is and the words it says.

The app carries the two files, and the drill server serves them (`/voice/index.json`, `/voice/pack.bin`); when the phone pulls the catalog it takes a newer voice too (`Engine/VoiceClips.swift`). A line is said in the recorded voice only when every part of it has a clip that says exactly those words; otherwise the whole line is spoken by the phone's own voice (the one chosen in Settings), so a new drill is never silent and never half in one voice. After adding or rewording a drill's `say`: `node scripts/make-voice.mjs`, `npm test`, commit and push. To change the voice, change `VOICE` in the script and delete `voice/` first.

## The lock screen

`App/NowPlaying.swift` puts what is playing (the drill's name, or Metronome) on the lock screen and in Control Center and takes pause, play and stop from there: pause holds a drill (the metronome stops), play resumes it, stop ends everything. It only works with Settings, Sound, Lock-screen controls switched on (`audio.lockScreen`), which makes the audio session exclusive (`AudioEngine.mixesWithOthers`); see Limits.

## The design system

`ios/Practice/Shared/Theme.swift` holds the tokens and `Components.swift` what is built from them; every screen uses only these.

- **Words** (`Shared/Strings.swift`, `L`): every label, button, message and helper line the app shows is in this one file, to be read through in one sitting (Joe, on 0.1.6: "Weird labels like 'Done, keep this'"). A button is one or two plain words, the standard iOS ones where there is one (Start, Stop, Pause, Resume, End, Done, Next, Skip, Calibrate); no commas or explanations in a button; helper text only where needed, one short line. A result is saved by itself, so its buttons are Again and Done. A drill's name, description and levels come from the catalog; what the voice says is in `Engine/Voice.swift` (`IntroText`).
- **Colour** (`Theme`): dark first, light from the same names. `bg`, `side`, `raised`, `text`, `muted`, `faint`, `line`, `lineStrong`, `hover`; one accent, as a fill (`accent`, `#6FB7A0`) and as text or a glyph (`accentText`, darker in light so it reads on white), `accentSoft` behind a chosen thing; `warn` and `danger` for states only.
- **Space** (`Space`): 4, 8, 12, 16, 20, 24, 32, 40; the page margin is 16; nothing tapped is under 44.
- **Radius** (`Radius`): 6, 8, 10, always continuous; nothing is a capsule. **Control** (`Control`): buttons and rows are 44 high, small square buttons 32.
- **Compact, not big and round** (0.1.9; Joe on 0.1.8: "UI looks much better. Still not a fan of how big and rounded many elements are"). Buttons are standard height with a small radius; the minus and plus are small squares, and a row's stepper is one compact control; a state is a line of text in the accent, not a pill; the only big numbers are the tempo (the metronome, a drill's setup, the run screen's bpm), everything else is in regular sizes. The references are Linear, Things 3 and Apple's Clock and Fitness, and his standing rule against AI design tropes (vault `AI/Memory/Design and style`).
- **Type** (`Typo`): SF Pro text styles, so everything follows Dynamic Type; numbers in SF Pro Rounded with fixed-width digits (`Typo.number` for the big ones, which shrink to fit, `Typo.figure` inside text).
- **Haptics** (`Haptics`, and `.sensoryFeedback`): a tick for each step of a value, a tap for the primary button.
- **Components**: `ScreenHeader` and `NavBar`, `SectionLabel`, `Row`, `StepperRow` (hold to keep stepping; one adjustable value to VoiceOver), `ToggleRow`, `Segmented`, `Disclosure`, `PrimaryButton` (one a screen), `QuietButton`, `TextButton`, `IconButton`, `BarIcon`, `Chip` (a line of text), `BigStat`, `ProgressLine`, `BeatDots`, `TempoDial`, and in the drill screens `ZoneBar`, `PatternStrip`, `LaneView`, `TimingMeter`, `ErrorStrip`, `Sparkline`.
- **The tempo is never set from inside its own change handler** (that recursion crashed 0.1.4): `TempoDial` only calls out, and `Player.setBPM` and `PlayAlong.setBPM` clamp and return early when nothing changes. Settings shows the voices `Voice` read once in the background; it never reads the list itself.
- **Checking a change**: the UI test (`ios/PracticeUITests`) taps through every screen and photographs each one, dark and light, including a run and a result drawn from made-up values (`-screen run`, debug builds only). Look at the `screens` artifact of the run before shipping.

## Latency (Bluetooth headphones included)

Joe, 2026-11-14, on his Shokz open-ear headphones: "Is there a way to remove the latency or compensate so that the analysis is still accurate". The delay cannot be removed, so every pick is scored against when the click was heard (Engine/Latency.swift):

- Output stays on A2DP: the session is `playAndRecord` with `.allowBluetoothA2DP` and never `.allowBluetooth` (hands-free), so turning the input on does not flip the headphones into call mode. The input is always the interface (`preferInterface`: USB, line in or a wired headset input), never the headphones' own; with none plugged in the screen says "Plug in your audio interface" and a run does not start (the phone's microphone only with the testing switch on). If the route is hands-free anyway, the screen says so.
- The estimate is outputLatency (which iOS reports for Bluetooth) + inputLatency + the IO buffer. Calibrate plays twelve clicks; he plays one note on each; picks are moved by the estimate and the median of what is left is the residual. The offset in use is today's estimate plus that residual, so it follows iOS when the reported Bluetooth delay moves.
- Calibrations are kept per route (the input and output ports), applied by themselves when that route is active; a route with none says "New audio setup ... calibrate once". The current offset in ms is on the Play along screen, and each result keeps the offset it used.
- A route change in the middle of a run holds it (0.1.7): the engine stops, the run is paused with "Audio changed to ...", and Resume picks it up on the new route. The setup screen re-reads the route.
- **Where the sound goes when an interface is plugged in** (Joe, 2026-11-14: "I just connected my guitar rig single and lost the headphone out"). iOS sends the sound to a USB interface the moment it is plugged in, along with taking its input, when the interface has an output of its own (most do: a headphone jack). An app can ask for an input (`setPreferredInput`, which Practice does for the interface) but cannot name an output: the only way to send the sound somewhere else is the system's own picker. So the picker (`RoutePicker`, an `AVRoutePickerView`) is on the drill's setup (Audio Route), on the run screen (top right) and in the calibration, and the screens say what iOS chose ("In: iRig · Out: Shokz"). The session is `playAndRecord` with `.allowBluetoothA2DP`, which is what lets Bluetooth headphones be picked as the output while the interface stays the input. When the sound is on the interface, one line says so and what to do (pick the headphones there, or use the interface's headphone out). Whether his interface and his Shokz hold that pairing on his phone is not yet tried; an interface with no output of its own (a USB microphone, say) leaves the sound where it was.
- Spoken cues and the guide notes go to the headphones too.

**The calibration is two steps**, the way a rhythm game does it (Joe, 2026-11-14: "there's a visual component that needs to line up with the audible component plus the guitar pluck. Like the line passing through the center of the screen"). It opens from a drill's Options (Timing, Calibrate), from the note under Audio input when a setup has never been calibrated, and from Settings (Timing).

1. **Sight and sound** (`PlayAlong.startCalibration`, the audio input stays closed). A click plays and marks scroll across a line through the middle of the screen; a slider (5 ms steps, -100 to +300 ms) moves the marks until each crosses the line exactly on the click he hears. That is the **display offset**, kept per output (`DisplayOffsetStore`, keyed by the output half of the route): the lane of every run on that output is drawn that much later (`PlayAlong.laneNow`), so a note reaches the line when it is heard. It moves the picture only, never the scoring.
2. **The guitar** (`PlayAlong.calibrateInput`, the audio input open). The same marks; he picks one note as each of twelve crosses the line. The median of played minus click is the offset every pick is scored with on this route (as before, kept as a residual over iOS's own estimate), and the spread of the notes says how steady it was: the result reads "Calibrated for ...: 182 ms from 12 notes, steady (they varied by 6 ms)", and both are kept on the calibration (`spreadMs`, `hits`).

Two setups, each calibrated once:

- **Interface in, interface out** (headphones on the interface): the lowest delay and the most accurate.
- **Interface in, Shokz out** (Bluetooth A2DP): the delay is larger and measured out. iOS's rule is that the newest route wins, and a USB interface usually takes both input and output when it is plugged in. The speaker button on the Play along screen (the system output picker) moves the output to the Bluetooth headphones while the input stays on the interface; the screen always shows what iOS actually chose ("In: ... Out: ..."). Not yet tried on his phone: if iOS keeps both on the interface with his model, use the interface's headphone out, or connect the Shokz after the interface.

## Audio: picking the input and output (0.2.0)

Settings > Audio, and the Input and Output rows on a drill's screen (Joe, 2026-11-16: "a whole audio test area? to define the input, and the output and check levels etc", "just allow me to pick input and output explicitly"). `Engine/AudioSetup.swift` is the model, `Features/Settings/AudioSettingsView.swift` the screen, `Engine/LevelMeter.swift` the level maths, `Engine/AudioPrefs.swift` what is remembered and the plain-words check.

- **Input**: every input iOS offers (`availableInputs`), and a two-input interface's Input 1, Input 2 and Inputs 1 and 2 as separate lines. The pick is kept (`AudioPrefs.preferredInput`) and asked for again on every route change; per input, the channel, the gain (where iOS allows it) and the mic position are kept and re-applied. The tap listens to inputs 1 and 2 summed unless one is picked (0.1.10 read only the first channel).
- **Output**: the iPhone speaker and every output the phone has used. iOS lets an app switch only to the speaker (`overrideOutputAudioPort`); for any other output picking it opens iOS's own list. When iOS puts the sound or the input somewhere else, one amber line says so and why (`AudioDiagnosis.inputNote`, `outputNote`); a pick is never ignored silently.
- **Record mode on the drill screen**: with Audio Input on, the screen puts the session in play-and-record (measurement mode, A2DP allowed, never hands-free). In playback mode iOS lists no input at all, which is why 0.1.10 read "In: No input" with the interface plugged in.
- **Meter**: peak bar, a peak-hold tick (1.5 s, then falls), a clip light (2 s), and a readout from the loudest peak of the last 3 s: No signal below -50 dBFS, Too quiet below -24, Good, Clipping at -0.2.
- **Test tone** (A 440, -12 dBFS, 1 s) and **Click test** (a bar at 120), at the **App Sounds** level, which is the clicks, guide and voice against the guitar, kept per output.
- **Hear Guitar**: the input mixed into the output through the app, mono, with its own level, per output; off on the phone's speaker and mic. On Bluetooth it is late: listen through the interface's headphone out. On a Bluetooth output it is off whenever the app opens and is never kept (0.2.2; Joe, 2026-11-17: "Definitely don't want to monitor my own guitar because the latency is big but it works for just playing along").
- **Route changes keep the screen**: `AudioEngine.rebuild()` builds a new engine on the new route around the same render state, so the frame clock, the metronome, a run and the calibration carry on; a short notice says what changed (`routeNotice()`); the guitar step of the calibration starts over on the new route. Only a call or an audio reset stops a run. The UI test fakes a route change on each screen (`-debugRoute 1`, debug builds only).
- **The iOS limit**: recording from a USB interface, iOS usually keeps the sound on the interface too and will not send it to Bluetooth (the Shokz). The screen says so; the workaround is a Bluetooth transmitter on the interface's headphone out, paired with the Shokz.

## Building and installing

The same route as the HQ and Browser iPhone apps. `.github/workflows/ios-build.yml` runs on a push touching `ios/`, `catalog/` or itself: XcodeGen makes the project from `ios/project.yml`, the unit tests run on the iPhone simulator and must pass, then on `main` it archives, exports ad hoc, and publishes `app.ipa`, `manifest.plist`, `version.json`, the icon and the install page to the public repo `CaulfieldEngineering/practice-install` (GitHub Pages). The version is the one line in `ios/VERSION` (raise it for each release; on `main` the run stops before building if it is not newer than the published one, since the phone would see no update); the build number is the run number. Other branches build and test only. The UI test's screenshots of every screen, dark and light, are kept with each run as the `screens` artifact.

Signing: Blocks' Apple team, App Store Connect API key (their ids and the key's path are `apple` in `config.local.json`, and the team id is the `IOS_TEAM_ID` secret) and Apple Distribution certificate, with Practice's own App ID `com.caulfieldengineering.practice` and ad-hoc profile `Practice AdHoc`. `node scripts/apple-provision.mjs` makes the App ID and the profile for every registered iPhone (into `C:\Users\Joe\.apple\practice`, never a new certificate); `npm i --no-save libsodium-wrappers && node scripts/apple-secrets.mjs` puts the certificate, its password, the profile, the team and the install repo's deploy key (`C:\Users\Joe\.apple\practice\install_key`) in this repo's Actions secrets. Every year, after Blocks' certificate is renewed, run both again, then the workflow, then reinstall. A new iPhone: register it, then run both again.

The icon is drawn by `python scripts/make-icon.py` (the charcoal and teal of his other icons).

Tests: `ios/PracticeTests` (the sequencers to the frame, block size, drift over ten minutes, routine timelines, the event queue, tap tempo, scoring, matching, calibration, cycles and cues, endurance and the ladder, onset detection on synthetic picking, the catalog and schema decoding, results and the send queue) on the simulator in the workflow; `npm test` (the server: the catalog, serving it, keeping runs once, stats).

## Limits, honestly

- Onset detection is energy based with a high-pass: right for one picked string, muted or open. Chords, legato, heavy distortion with long sustain and noisy rooms will miss or add notes. A spectral-flux or learned detector can drop in behind `OnsetDetecting`.
- The phone's microphone is only a testing stand-in (Settings, "Use the phone's microphone (testing)", off by default). On it, with the phone's speaker, the phone hears its own click and guide notes and the room; the app says so. Bluetooth headphones (his Shokz) are fine: see Latency. If the headphones drop into call mode (hands-free), the app says so; the sound is poor and the delay changes, so reconnect them.
- The ladder's tempo step can lag a cycle behind the result for short cycles (see Session modes).
- Pitch is not checked: a note on the wrong string or fret still counts. Left-hand drills need pitch; the schema already carries string and fret.
- Timed routines are not in the app (see What is in it); they come back later.
- A paused run picks up at the start of the cycle it was in, not at the exact note, so the notes of that cycle are scored once, cleanly.
- Lock-screen controls (Settings, off unless switched on) mean other apps' sound stops while Practice plays: iOS only shows an app on the lock screen and in Control Center, and only sends it pause and stop, when its sound is not mixed with others'. With the switch off the click plays over his music as before, and there is nothing on the lock screen. Not yet tried on his phone.

## Next

- A pitch check (string and fret), so left-hand drills and riffs can be scored; they already show as tablature and play on the guide guitar.
- **Routines, later** (Joe, 2026-11-14): bring the timed routines back as drills whose data has several timed blocks (`segments`: play at a tempo, rest, or a block with no click; `rounds`, `stepBPM`, `pattern`), opening the same setup and run screens, so their play blocks can be guided and scored and use the zones. The schema, the scheduler and the mapping from a saved routine are in the code, unused; what is left is the catalog entries, the list, an editor, and trying it on the phone.
- Agents tuning levels from the runs on the mini PC: see `docs/agents.md`.
