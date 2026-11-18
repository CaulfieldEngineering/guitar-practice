# Practice for Windows

The guitar practice app on the computer. Joe, 2026-11-17, about 11:15 PM: "Can we build a desktop version of the guitar practice app? Let them share drills and stats in a common backend".

Same app as the phone: the Metronome, the Drills table and a drill's setup (zones of his max or a tempo by hand, Guided or Solo, Cycles, Time or Endurance, the ladder, the Audio input switch), the run as scrolling tablature with play-along scoring, the result, the two-step calibration (the Guitar Hero line, then the guitar), Progress, and Settings with the Audio section. Same drills, same scoring, same runs: both apps read the drill server on the mini PC, and every run from either one is in both apps' Progress.

Install: `Dropbox\Apps\Practice\Practice-Setup-<version>.exe` (for this user only, no administrator rights; Start menu and desktop shortcut). After that it updates itself: Settings, About, and an **Update to x** link in the top bar once a newer build has downloaded.

## Why JUCE (and not a web or Electron app)

The core of this app is timing: the click has to sound at an exact sample, and a pick has to be timed against when the click was heard. On Windows that means the audio interface's ASIO driver or WASAPI in exclusive mode, which go straight to the device with buffers of a few milliseconds. A browser (and so Electron) only reaches the shared Windows mixer through Web Audio: on top of the device's own delay it adds the mixer's (typically 10 to 30 ms), cannot open ASIO at all, and runs the audio graph beside a JavaScript UI thread. JUCE is native C++, opens ASIO and WASAPI exclusive directly, renders sample-accurately in the device's own callback, and is what Duet's engine and our plug-ins are already built with (the same JUCE 7.0.12 and ASIO SDK checkouts beside the repo). So the desktop app is JUCE; the phone stays SwiftUI; what they share is data (the catalog, the scoring numbers, the runs) and one set of test vectors, not code.

## Audio

- **Device types**: ASIO (his interface's own driver, the lowest delay), Windows Audio (Exclusive Mode) and Windows Audio (shared). On first start it picks a real ASIO driver if there is one, else WASAPI exclusive, and falls back to shared by itself if the device refuses exclusive mode (one line says so). Settings, Audio: device type, input, input channel (1, 2, or both summed, as on the phone), output, buffer size.
- **Picking a device never freezes** (the phone froze in 0.2.0: three listeners each asked iOS again on every change; 0.2.1 coalesced them). Every device call here (scanning, loading an ASIO driver, starting WASAPI exclusive) runs on one worker thread that owns the devices (`src/engine/DeviceController`). The screen only posts the newest pick and reads a snapshot: a pick never waits, picks made while one is opening are dropped, the newest wins. A plugged or unplugged device rescans on the same thread. The stress test fires 400 picks against a slow fake driver and 30 against the real Windows devices; none may take over 5 ms.
- **Monitoring is off by default** and never kept on: Hear Guitar in Settings mixes the input into the output with its own level (Joe, 2026-11-17: "Definitely don't want to monitor my own guitar because the latency is big").
- **Latency**: the offset taken off every pick is the drivers' own figures (input + output latency + one buffer) plus what the calibration measured on top, kept per pair of devices (`in:<type>/<input>|out:<type>/<output>`), as the phone keeps it per route. Settings shows the breakdown and the total.
- **Calibration**, two steps as on the phone: Display sync (marks cross a line in the middle; a slider moves them until each crosses on the click; kept per output; moves the picture only) and Input (play one note as each of twelve marks crosses; the median of played minus click is the residual; the spread says how steady).
- A device change in the middle of a run holds it (paused, one line saying what changed); Resume picks it up on the new device.

## Scoring: the same as the phone, proven by one set of vectors

`src/core/Scoring.cpp` is the phone's `Scoring.swift` line for line (the credit windows as a share of the gap to the nearest note, the cosine fall-off, extras counting as notes that earned nothing, a pick heard twice folded into one, the band words, the calibration), `src/core/OnsetDetector.cpp` is its detector in the same 32-bit floats, and `src/core/Drill.cpp` its drill grid and run builder. The numbers are `catalog/scoring.json`, served by the drill server to both.

The proof is `shared/scoring-vectors.json`: thirteen whole runs (from a tight player at 90 to a beginner at 70, extras, misses, accents, rest bars), pick-folding cases, per-cycle accuracies, credits across gaps, calibrations, every catalog drill's grid at two tempos and the max rule, with the answers. Made by `node scripts/make-scoring-vectors.mjs` from `shared/scoring.mjs` (the rules once more in plain JavaScript). Three suites read the same file and must agree to a millionth: the desktop tests, the iPhone app's `ScoringVectorTests` (in CI on every push), and `npm test`. **Change a rule in all three together, make the vectors again, and all three suites must pass.**

## The common backend

The drill server (`server/index.mjs`, http://DRILL_SERVER_HOST:4700) is the source of the drills, the scoring numbers and the voice for both apps, and the store of every run (`data/sessions.jsonl`). The desktop app (`src/app/Sync`, a worker thread, every 30 seconds and right after a run):

- sends each run it made until the server answers with its id (`POST /api/sessions`); away from the server they wait in `%APPDATA%\Practice\runs.json` and go at the next sync,
- reads every run from every device (`GET /api/sessions`) and his max per drill (`GET /api/levels`); the last copy is kept for Progress offline,
- pulls a newer catalog or voice, swapping it in whole only when every file read,
- asks whether a newer desktop build is out (`GET /desktop/latest.json`) and downloads it (`GET /desktop/Practice-Setup-<version>.exe`).

Runs go out in the phone's exact shape (`SessionResult`, schema 1, dates with whole seconds, upper-case ids), plus `device` (the computer's name), which the phone ignores and Progress shows as Where. New on the server for the desktop: only the two `/desktop/` routes, served from `desktop/release/` (not in git).

## Building, testing, releasing

On the mini PC (Visual Studio 2022 Build Tools, CMake, JUCE 7.0.12 and the ASIO SDK beside the repo, as for Duet):

```
powershell -NoProfile -File desktop\scripts\build.ps1
```

builds Release, runs the desktop tests and `npm test` (any failure stops it), draws every screen dark and light at 1100 by 720 and 1280 by 800 into `logs\desktop-screens-<version>` (`Practice.exe --screens <folder>`), makes the installer with NSIS (the copy electron-builder keeps in `%LOCALAPPDATA%\electron-builder\Cache`), and publishes it to `desktop\release\` (what the updater is served) and `Dropbox\Apps\Practice\` (the newest only). Raise `desktop/VERSION` for each release.

Tests (`desktop/tests/Tests.cpp`, `PracticeTests.exe`): scoring parity with the shared vectors; the onset detector on synthetic picking; device picks under stress (fake and real devices); sync with the real drill server on a scratch port and data folder (runs made offline wait, go once the server is up, are kept once, a phone-shaped run shows in the desktop's list, every stored run carries every key the phone's decoder needs, the update check and download). `Practice.exe --selftest <report>` drives the real app on the real device: the metronome, an unscored run to its end, pause and resume, a scored run with picks injected where there is no input, 40 device picks in a row while idle.

## The code

```
desktop/
  src/core/     Scoring, OnsetDetector, Drill (the schema, zones, the run builder), Results (SessionResult, Stats, the catalog reader)
  src/engine/   AudioEngine (the callback: events at frames, the metronome, the guide guitar, picks, the meter, Hear Guitar),
                DeviceController (the device worker; ASIO and WASAPI through JUCE)
  src/app/      Model (the play-along ported from PlayAlongModel.swift, the calibration, the metronome, updates),
                Store (settings, calibrations, the run queue), Sync (the drill server), Voice (the recorded intro)
  src/ui/       Theme (the house tokens, Lucide icons), Widgets, Screens, RunScreens, SettingsScreens, MainComponent
  tests/        Tests.cpp, serve.mjs (a scratch drill server for the sync test)
  installer/    Practice.nsi
  scripts/      build.ps1, make-ico.py
```

## Not done, honestly

- macOS: JUCE builds it (CoreAudio is wired in DeviceController), but there is no Mac here to build or sign it.
- Lock-screen controls and the phone's own fallback voice have no Windows counterpart: a line without a recorded clip is not spoken.
- Timed routines are out of the desktop app as they are out of the phone (Joe, 2026-11-14: "Let's omit the timed routines for now").
- The installer is not code-signed, so a copy downloaded through a browser gets a SmartScreen prompt; copied over Dropbox or the updater it does not.
