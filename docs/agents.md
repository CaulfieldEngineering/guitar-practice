# For agents: adding drills to Practice, and reading Joe's runs

Joe, 2026-11-14: "Let new drills and levels be added without an iOS update. Let the drill data be stored on mini pc and pulled into the app." And: "Stats over Tailscale too."

## Add a drill or a level (no app build needed)

1. Edit `catalog/exercises/*.json` (a new file also goes in `catalog/index.json` `files`). The shape, both the `groups` shorthand and the full `notes` form, is in README.md, "How to add a drill". A level is an entry in a drill's `levels`: `{"name": "Level 5", "bpm": 110, "session": {"kind": "endurance", "targetPercent": 85, "toleranceMs": 30}}`.
2. Give every drill a `say`: the name and the pattern, short and plain ("Triplets to sixteenths. Four and four."); the voice adds the tempo and the goal. No coaching in it (Joe, 2026-11-14: "Don't need to say keep the motions small etc"): how to play goes in `detail`, which the drill's screen shows. Also a `short` name and a `category` for the Drills table. Then `node scripts/make-voice.mjs` records the line (README.md, "The recorded voice"). Right-hand drills first (Joe: "The first games can be right hand exercises"); his source is the vault page `Databases/Training Vault/Perfect Picking Course.md`; use its names. A left-hand drill gives each note its `string` and `fret`: it shows as tablature and plays on the guide guitar (it is not yet scored for pitch).
3. Never reuse or rename an `id`: results are kept by it. Raise the drill's own `version` when its notes change.
4. Raise `version` in `catalog/index.json` by one. The phone only pulls a catalog with a higher number.
5. `npm run check` and `npm test` in this repo; both must pass. Commit and push.
6. The drill server serves the folder as it is on disk (no restart). Check with `curl http://127.0.0.1:4700/health` (`ok: true`, the new `catalogVersion`).

## Tune how accuracy is judged (no app build needed)

The timing windows are not a setting in the app (Joe, 2026-11-14: "The ms accuracy should be part of the algorithm determining percentage accuracy, not a user feature"). They are numbers in `catalog/scoring.json`, explained in README.md, "Accuracy": full credit within `fullFraction` of the gap between notes, none from `zeroFraction`, each kept between its Min and Max in ms; `extraWeight` is what an extra note costs. To tune: change the numbers, raise `version` in `catalog/index.json`, `npm run check` and `npm test`, commit and push. After changing `server/catalog.mjs` itself, restart the scheduled task "Practice Drill Server" so `/health` checks with the new code.

Runs with the audio input off are not runs: nothing about them reaches the server, and they never count toward his max. Only the minutes are kept, on the phone.

## Read his runs

- `GET http://127.0.0.1:4700/api/stats` (`?exercise=<id>`): bests per drill, mode and starting tempo, and every run in time order. `GET /api/sessions` gives the full results. The file is `data/sessions.jsonl` in this repo folder on the mini PC (one run a line; never edit it by hand).
- Tuning: when his solo runs at a level pass comfortably several times (score at or over the pass mark, or endurance held past a few minutes), the next level can start higher; when they fail, the level is too high. Add or change levels in the catalog as above. Practices are not targets for Joe: never turn this into a streak or a count to report at him (HQ CLAUDE.md, "Practices, not outcomes"). Mention progress only when he asks or it serves what he is working on.

## The pieces

- App: `ios/` (README.md has the architecture). Install page https://caulfieldengineering.github.io/practice-install/.
- Server: `server/index.mjs`, scheduled task "Practice Drill Server", port 4700 on 127.0.0.1 and DRILL_SERVER_HOST. Log: `logs/service.log`.
- Vault: Apps row `Apps/List/Practice.md`, Systems row `AI/Systems/Practice drill server.md`, the line on `AI/Memory/Small apps.md`.
