# Practice: design spec for the overhaul (2026-11-24)

For the builder. House file: `HQ/agent/app-design.md` (binding; where this spec is silent, it decides). iOS first, desktop in section 4. Every label below is final and in sentence case. "Loop" replaces "cycle" everywhere in the UI (Joe's word: "ascend either per loop"). One loop is one pass of the drill's pattern.

## 1. Brief, and what was taken from other apps

**Who and where.** Joe, guitar on his lap, pick in his right hand, phone on a stand or the desk at arm's length; he sets up with one thumb, then reads from about a metre while playing. On the desktop, a mouse before the run and eyes only during it.

**The one thing it is for.** Start a timed, scored picking run fast, and read tempo, beat and accuracy at a glance while both hands are busy.

**What is on it, in order.** The tempo and the beat. Then the accuracy and where the tempo is going next. Then the notes (the lane). Then the controls to stop. Setup, history and settings are quiet and one step away.

Structure taken from, not paint:

| From | What was taken |
|---|---|
| Apple Clock (Timer, Stopwatch) | One huge plain numeral in the system font, nothing around it; two controls at the bottom; no card. |
| Apple Fitness (workout, intervals) | The interval runner: the current block big, "next" small, a 3-2-1 before each block, pause leading to End. A workout is edited as an ordered list of typed blocks (Warm-up, Work, Recovery) with "Add" last. One summary per session. |
| Apple Settings | Every setup screen: inset groups, one label and one control a row, value rows with a chevron to a checkmark list, action rows in the accent last in the group, one helper line at most. |
| Soundbrenner | The beat shown as a row of equal segments across the screen, the accented one marked; tempo changed by holding minus or plus. |
| Pro Metronome | Tempo automation as two plain rules ("+N bpm every K bars"), and the muted-bar trainer as a single choice. |
| Tempo (Frozen Ape) | Setlist as a plain table: name, tempo, length. No artwork. |
| Melodics | Accuracy as one live bar with a mark that moves, and a result that leads with one number and then the detail. |

## 2. Tokens (SwiftUI)

### Colour (`Theme`, light then dark)

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#FFFFFF` | `#1C1C1B` | Flat screens: Metronome, Run, runner, tables, Result |
| `side` | `#F7F7F5` | `#161615` | Behind groups: setup, editors, Settings, choice lists |
| `raised` | `#FFFFFF` | `#262625` | A group, a sheet, the lifted segment. (Dark changes from `#2C2C2A`.) |
| `text` | `#1C1B19` | `#E4E3DF` | |
| `muted` | `#6A6964` | `#A3A29C` | Values, secondary lines |
| `faint` | `#A09F99` | `#6B6A65` | Chevrons, column heads, glyphs only |
| `line` | `#EBEAE6` | `#2B2B29` | Hairlines (1 px at device scale) |
| `lineStrong` | `#DCDBD6` | `#3B3B38` | Tracks, unlit beat segments, lane strings |
| `hover` | `rgba(55,53,47,.055)` | `rgba(255,255,250,.055)` | Quiet button fill |
| `active` | `rgba(55,53,47,.09)` | `rgba(255,255,250,.09)` | Pressed, segmented track |
| `accent` | `#6FB7A0` | `#6FB7A0` | Fills only: primary button, lit beat, switch on, meter mark in the up zone |
| `accentText` | `#2F7F69` | `#7CC4AD` | Accent as text or glyph. Light stays `#2F7F69`, not the house `#3F9A80`, because `#3F9A80` on white is under 4.5:1. |
| `onAccent` | `#10201B` | `#10201B` | |
| `accentSoft` | accent at 14% | accent at 14% | The up zone band, the running bar |
| `warn` | `#A9781C` | `#D9A441` | The down zone, a route note |
| `danger` | `#C4402B` | `#E8796B` | The break zone, Delete, End routine |

Zone colours (the only place four hues meet): up `accent`, hold `lineStrong` (mark in `text`), down `warn`, break `danger`. Bands are the colour at 22% opacity; the mark and the zone word are the full colour.

Groups: `raised`, radius 10, no shadow, no border in dark, a 1 px `line` border in light. `.tint(Theme.accentText)` on the app; switches `.tint(Theme.accent)`.

### Type (`Typo`). System font, default design everywhere. Drop `.rounded` (it is the main thing that reads as generated). Two weights: regular and semibold. Every number uses `.monospacedDigit()`.

| Role | Font |
|---|---|
| `tempoHero` (Metronome, countdowns, break) | `.system(size: 88, weight: .regular, design: .default).monospacedDigit()`, tracking -1, `minimumScaleFactor(0.6)` |
| `tempoRun` (Run screen tempo) | size 64, regular, monospaced digits, tracking -0.5 |
| `tempoSetup` (Drill setup tempo) | size 44, regular, monospaced digits |
| `statLarge` (Result's number) | size 44, semibold, monospaced digits |
| `stat` (accuracy on Run, time left) | `.title2` semibold, monospaced digits |
| `unit` ("bpm" beside a big numeral) | `.body` regular, `muted`, on the numeral's baseline, 6 pt gap |
| `screenTitle` | system inline nav title (17 semibold) |
| `cue` (pattern now, block name) | `.title3` semibold |
| `body`, row label, button | `.body` regular; primary button `.body` semibold |
| `value` | `.body` regular, `muted`, monospaced digits |
| `sub` | `.subheadline` regular |
| `section`, helper, column head | `.footnote` regular, `muted` (column heads `faint`). Sentence case, never capitals, never tracked. |

Fixed sizes only for the four numerals above; all else follows Dynamic Type.

### Spacing, radii, sizes

- `Space`: 2, 4, 6, 8, 12, 16, 24, 32. Remove 20 and 40. Page margin 16. Between groups 24. Between related lines 8 to 12.
- `Radius`: `sm` 4 (segment, beat segment, tag), `md` 6 (button, field), `lg` 10 (group, sheet). Changes from 6, 8, 10. Nothing is a capsule; round only the switch and the status dot.
- Row height 44. Primary button 48 high, full width, only at the bottom of a screen. Icon buttons: 20 pt symbol in a 44 box. Table rows 44, column head row 28.

### Motion and haptics

- State change 120 ms ease; push, sheet, reorder 220 ms ease-out (system defaults are fine). Numerals change with `.contentTransition(.numericText())`. The beat segment lights with no animation (a cut, so it is on the click). Nothing pulses, scales or bounces. With Reduce Motion: no numeric transitions, the lane still scrolls.
- No haptic on beats (it fights the click and the pick).

| Event | Feedback |
|---|---|
| Stepper or tempo step, slider detent, reorder drop, list pick | `.sensoryFeedback(.selection, trigger:)` |
| Start, Pause, Resume, Stop, Skip, Back | `UIImpactFeedbackGenerator(style: .medium)` |
| Tap tempo | `UIImpactFeedbackGenerator(style: .light)` |
| Tempo steps up | `.sensoryFeedback(.increase, trigger: targetBPM)` |
| Tempo steps down | `.sensoryFeedback(.decrease, trigger: targetBPM)` |
| 3, 2, 1 of a countdown | `UIImpactFeedbackGenerator(style: .rigid)`, one each |
| Block ends, auto break begins | `UIImpactFeedbackGenerator(style: .soft)` and the chime |
| Run or routine finished | `UINotificationFeedbackGenerator` `.success` |
| Input lost, route refused | `UINotificationFeedbackGenerator` `.warning` |

Sounds: block chime is two sine notes, 880 Hz then 1320 Hz, 110 ms each, 10 ms fades, 12 dB under the click. Countdown ticks are the click sound, the last one accented.

### Shared components (one shape each, used everywhere)

- `ValueRow`: label left, value right in `muted`, `chevron.right` 13 pt semibold `faint`. Pushes a `ChoiceList` (rows with a `checkmark` in `accentText` on the chosen one) or a detail screen.
- `StepperRow`: label left; right: value in `text` with monospaced digits, then the system `Stepper` look (minus and plus in one 94 by 32 control, radius 6). Hold repeats; after ten repeats the step is 5 times larger.
- `SwitchRow`: system `Toggle`.
- `SegmentedRow`: system `Picker(.segmented)` at the right, sized to its words, two choices only.
- `ActionRow`: `accentText`, left-aligned, last in its group.
- `BeatBar`: one segment per beat across the full width, gap 4, height 6, radius 2, `lineStrong`; the current beat `accent`; the accented beat's segment is 10 high. Replaces `BeatDots`.
- `ProgressLine`: 4 high, radius 2, track `lineStrong`.
- `QuietButton`: 48 high, radius 6, `hover` fill, `text` label with a 17 pt symbol.
- Delete: `Chip`, `BigStat`, the capital `SectionLabel`, `Segmented` (custom), `ScreenHeader`, `NavBar`, `Disclosure`. Use `NavigationStack`, the system bar, `.navigationBarTitleDisplayMode(.inline)` on every screen.

## 3. Screens (iPhone, 390 by 844; check 375 by 667)

### App shell

`TabView`, four tabs, labels with outline symbols: **Metronome** `metronome`, **Drills** `guitars`, **Routines** `list.bullet.rectangle`, **Progress** `chart.xyaxis.line`. Settings is a `gearshape` button at the right of each tab root's bar, opening a sheet with Done. The tab bar hides while a run or a routine is live. When sound is playing from another tab, the existing running bar shows under the nav bar: 44 high, `accentSoft`, a 6 pt dot, "Metronome at 120 bpm" (or "Drill running", "Routine running"), and a text button **Stop**.

### Metronome (flat, `bg`, no scroll)

Top to bottom:
1. Bar: title "Metronome", right `gearshape`.
2. `BeatBar`, 24 below the bar.
3. Tempo block, left-aligned at the margin: the numeral in `tempoHero` with "bpm" as `unit`. At the right edge, level with the numeral's middle: `minus` and `plus` icon buttons (hold repeats). Drag sideways on the numeral changes it; a tap on it opens a number pad.
4. Slider 30 to 300, full width, thin track.
5. Rows, flat with hairlines starting at the label edge:
   - `ValueRow` "Time signature" · "4/4" (2/4 to 7/4)
   - `ValueRow` "Subdivision" · "Quarter" (Quarter, Eighth, Triplet, 16th)
   - `ValueRow` "Accent" · "Beat 1" (Off, Beat 1)
   - `ValueRow` "Click sound" · "Wood block"
6. Bottom, 16 above the tab bar: `QuietButton` **Tap** (`hand.tap`, 96 wide) and the primary **Start** (`play.fill`), which reads **Stop** (`stop.fill`) while running.

### Drills (flat table)

Bar: "Drills", right `gearshape`. Column head row: "Drill", "Max", "Best". Rows 44 high, hairline between:

| Column | Content |
|---|---|
| Drill (takes the rest) | "Triplets to 16ths, 4+4" in `body`; truncates last |
| Max (48, right) | "136" monospaced, `text`; "–" in `faint` when none |
| Best (52, right) | "94%" `muted` |

No section headers while there is one group (a label only with two or more groups). No search field under 12 rows. No sort button under 6 rows. The pattern column and the "last played" line are gone (both are on the drill's screen and in Progress). All other drills are removed from the catalog list; the table code stays. Empty: one muted line, "No drills. Pull down to update".

### Drill setup (grouped, `side`; pushed from the table)

Bar: Back "Drills", title "Triplets to 16ths, 4+4", right `speaker.wave.2` (hear the intro). Start is fixed at the bottom over a hairline; the content scrolls beneath it.

1. Header, not in a group: `PatternStrip` (56 high), then one line in `footnote` `muted`: "4 beats of triplets, then 4 beats of 16ths".
2. Tempo block, same shape as the Metronome's but `tempoSetup`: "120" with "bpm", `minus` and `plus` at the right. One caption under it in `footnote` `muted`: "88% of max 136" (or "No max yet").
3. Group:
   - `ValueRow` "Tempo zone" · "Z3, 120 to 135" (Manual, then each zone; hidden until he has a max)
   - `ValueRow` "Ascending tempo" · "Off" | "+4 every 2 loops to 160" | "By accuracy to 160"
   - `ValueRow` "Length" · "8 loops" | "5 min" | "Hold 90%" | "Until stopped"
4. Group:
   - `SwitchRow` "Audio input" (on: the run is scored)
   - `SwitchRow` "Guide notes" (on: the notes are played for him; replaces Guided and Solo)
   - `ValueRow` "Audio" · "MOMIX-CAB, Shokz" (the existing Audio screen)
   - Helper line under the group only when something is wrong, in `warn`: the existing route note.
5. Group: `ValueRow` "Options" · a summary of what differs from default ("Count-in 2 bars, gaps"), empty when all default.
6. Fixed bottom: primary **Start** (`play.fill`).

**Length** (detail). Checkmark list: "Loops", "Time", "Hold accuracy" (only with audio input), "Until stopped". Under the list, one group for the chosen one: `StepperRow` "Loops" 1 to 100, default 8; or `StepperRow` "Time" 0:30 to 30:00 in 30 second steps, default 5:00; or `StepperRow` "Accuracy" 50 to 100%, default 90%.

**Options** (detail, three groups):
- "Click": `ValueRow` "Click sound" · "Wood block" (Wood block, Beep, Rim, Clave); slider row "Click level" with the value at the right ("80%"); `ValueRow` "Accent" · "Beat 1" (Off, Beat 1, Group starts); `StepperRow` "Count-in" · "1 bar" (0 shows "Off", up to 4); `ValueRow` "Gap trainer" · "Off" (Off, Every 2nd bar, Every 3rd bar, Every 4th bar, Every 8th bar; the click is muted on that bar, the lane keeps scrolling).
- "Scoring" (only with audio input): `StepperRow` "Pass mark" · "85%"; `ValueRow` "Calibration" · "231 ms" (opens Calibration).
- "Voice": `SwitchRow` "Voice intro".
- "Guitar": `ValueRow` "Tuning" · "Default, E standard". Its list is "Default" first (the value from Settings, named beside it in `muted`), then the presets and "Custom" as on the Tuning screen. An override shows in the Options summary on the setup screen ("Drop D"). A Drill block in a routine has the same row in its own Options, so each block can differ.

**Ascending tempo** (detail). First group is the checkmark list: "Off", "Per loop", "By accuracy". Picking "By accuracy" turns Audio input on; the one helper line under the list then reads "Uses audio input".

*Per loop*, one group "Steps":
- `StepperRow` "Start" · "120 bpm" (the same value as the setup tempo)
- `StepperRow` "End" · "160 bpm"
- `StepperRow` "Step" · "+4 bpm" (1 to 20)
- `StepperRow` "Every" · "2 loops" (1 to 16)
- `SegmentedRow` "At the top" · Hold | Restart

*By accuracy*, four groups. Each of the three rules is the same three-part shape, so it reads at a glance; a rule that is off collapses to its switch.
- "Range": `StepperRow` "Start" · "120 bpm"; `StepperRow` "End" · "160 bpm"; `StepperRow` "Step" · "4 bpm"; `SegmentedRow` "At the top" · Hold | Restart.
- "Speed up" (always on): `StepperRow` "At or above" · "90%"; `ValueRow` "For" · "8 loops" (4 loops, 8 loops, 16 loops, 15 seconds, 30 seconds, 1 minute, 2 minutes).
- "Slow down": `SwitchRow` "Slow down" (default on); then `StepperRow` "Below" · "75%"; `ValueRow` "For" · "4 loops" (2 loops, 4 loops, 8 loops, 10 seconds, 20 seconds, 30 seconds); `StepperRow` "Lowest" · "100 bpm" (default Start minus 20; never under it).
- "Break": `SwitchRow` "Auto break" (default on); then `StepperRow` "Below" · "60%"; `ValueRow` "For" · "2 loops" (1 loop, 2 loops, 4 loops, 10 seconds, 20 seconds); `ValueRow` "Break length" · "25 seconds" (20, 25, 30 seconds); `SwitchRow` "Resume one step slower" (default on).
- Last group, "Stability": `ValueRow` "Wait after a change" · "2 loops" (1 loop, 2 loops, 4 loops, 10 seconds, 20 seconds); `ValueRow` "Accuracy over" · "Last 4 loops" (Last 2 loops, Last 4 loops, Last 8 loops).

Rules the controls enforce (no extra rows): "Below" for slow down is clamped to at least 5 points under "At or above"; "Below" for the break at least 5 under slow down. That gap is the hysteresis. After any change of tempo, and after a break, the sustained timers reset and nothing changes for "Wait after a change". The steppers stop at the clamp; no error text.

### Run (flat, `bg`, no bars; full screen)

Left-aligned, 16 margins, top to bottom. Heights are for 844; the lane takes the slack.

1. Top line (44): drill name in `sub` `muted` at the left; the route picker (`airplayaudio`, 44 box) at the right.
2. Cue: the pattern now in `cue` ("Triplets"); at the right on the same baseline, in `sub` `muted`, "16ths in 2 beats". Amber only in the last beat before a change.
3. Tempo row: left, the numeral in `tempoRun` with "bpm". Right-aligned stack in `sub` `muted`, monospaced digits: "Target 160" over "Next 128". With ascending off, the stack is empty. During the count-in the numeral is `muted` and the stack reads "Count-in".
4. `BeatBar`, full width, 8 under the tempo.
5. Step progress (only with ascending on), 16 under: a caption line in `footnote` `muted`, left "Next step" and right the measure, then a `ProgressLine`.
   - Per loop: right text "1 of 2 loops". Fill `accent`.
   - By accuracy, up zone: left "Speeding up", right "5 of 8 loops" (or "0:18 of 0:30"). Fill `accent`.
   - Hold zone: left "Holding", right empty, line empty.
   - Down zone: left "Slowing down", right "2 of 4 loops". Fill `warn`.
   - Break zone: left "Break", right "1 of 2 loops". Fill `danger`.
   - Waiting after a change: left "Settling", line empty.
   - At the top with Hold: left "Top tempo", line full.
6. Accuracy meter (only with audio input), 16 under. Caption line: left "Accuracy" in `footnote` `muted`; right the number in `stat` ("92%") followed by the zone word in `sub` semibold in the zone colour: "Up", "Hold", "Down", "Break". The bar: 12 high, radius 2, full width, scale 50% at the left edge to 100% at the right (lower clamps left). Its background is the four bands, side by side, split at the three thresholds: break band, down band, hold band, up band. A mark, 3 wide and 20 high, radius 1.5, in the zone's full colour, sits at the rolling accuracy and moves with a 120 ms ease. Under the bar's ends, nothing; the thresholds are read from the bands. When ascending is off or per loop, the bar has two bands split at the pass mark (hold colour under it, up colour over it) and no zone word. Before the first loop is judged: the number reads "–" and there is no mark.
7. Lane: `TabLane`, flexible height (min 140, about 200 at 844), a hairline above and below, no fill. The hit line (the calibration line) is one 2 px vertical line in `accent` through the whole lane height, a third of the way from the left. Judged notes take the existing colours.
8. Timing strip: the existing early and late dots, 28 high, "Early" and "Late" in `faint` at its ends. Hidden at 667 height and when unscored.
9. Status line in `sub` `muted`, monospaced: left "Loop 5 of 16", right "2:14 left" (or the elapsed time when open ended).
10. Bottom: two `QuietButton`s of equal width, **Pause** (`pause.fill`) and **Stop** (`stop.fill`). No accent fill on this screen: the accent belongs to the beat and the meter. A tap anywhere above the buttons also pauses; the hint line is removed.

Unscored run (audio input off): items 6 and 8 are absent and the lane grows.

**Notes on the lane.** One glyph size for both kinds: `.callout` semibold, monospaced digits, centred on its string line with a `bg` patch behind it so the line does not run through it.
- The string names at the lane's left edge follow the tuning in use, in `footnote` `faint`, high string on top ("E B G D A D" reads top to bottom for Drop D). A 7-string tuning draws seven lines; the gap shrinks, the lane does not grow.
- A pitched note is its fret number ("0", "5", "12").
- An X note (pitch does not matter, timing only) is "×" (U+00D7) in the same font, on the drill's string. The triplets drill is all ×.
- Before the hit line both are `text`. After it they take one state:

| State | Looks like |
|---|---|
| On the click | `accent` |
| Close | `accent` at 60% |
| Loose | `warn` |
| Missed | `danger` |
| Wrong pitch (pitched notes only; the timing still counts) | The fret number in `danger` inside a 1 px `danger` outline, 20 by 20, radius 4, and the note that was heard ("F#") in `footnote` `danger` directly under it, below the lowest string |

An × can never be wrong pitch. The result's rows gain "Wrong notes" · "2" when the drill has pitched notes.

**Paused.** The run dims to 40%. Over it, left-aligned at the vertical middle: "Paused" in `cue`; one line in `sub` `muted` with the route ("In MOMIX-CAB, out Shokz") or, in `warn`, why it paused ("The interface was unplugged"). Bottom: primary **Resume** (`play.fill`), under it the text button **End** in `danger`.

**Auto break** (replaces the run's content; the top line stays):
- "Break" in `cue`.
- The countdown in `tempoHero`: "0:25".
- One line in `body` `muted`: "Rest your hand".
- One line in `sub` `muted`: "Resumes at 116 bpm".
- A `ProgressLine` draining, fill `lineStrong` over `line` (no red here; the break is calm).
- Bottom: `QuietButton` **Skip** (`forward.end.fill`) and `QuietButton` **Stop** (`stop.fill`).
- The click stops when the break starts; soft haptic and the chime. The last three seconds tick 3, 2, 1 with the numeral showing "3", "2", "1"; then the drill's own count-in and the run goes on. The break counts in the session time and is listed on the result.

### Calibration (two steps, existing flow, restyled)

Bar: Cancel at the left, title "Calibration", right nothing. Under it, left-aligned: "Step 1 of 2" in `footnote` `muted`, then "Line up the marks" in `cue`, then one line in `sub` `muted`: "Move the slider until each mark crosses the line on the click". The sync lane (168 high, hairline above and below) with the line through the centre of the screen, 2 px `accent`, full lane height. Under it: the offset in `stat` ("+35 ms"), `minus`, slider, `plus`. Bottom: primary **Next**. Step 2: "Step 2 of 2", "Play on the line", "Play one note as each mark crosses the line"; a readout row "Heard" · "6 of 8"; bottom: primary **Done**, enabled when enough are heard; under it the text button **Retry**.

### Result (flat; replaces the run)

Bar: title is the drill's name, right **Done**.
1. One line in `sub` `muted`: "Solo, 120 to 148 bpm, 6 min".
2. The number in `statLarge`: "91%" (`accentText` when passed, `text` when not). Beside it on the baseline in `body` `muted`: "accuracy, pass mark 85%". For Hold accuracy: the time held, "held at 90%".
3. One line in `sub` semibold `accentText`, only when true: "New max 148 bpm, up from 144".
4. With ascending tempo: a small table, head "Tempo", "Time", "Accuracy"; one row for each tempo reached ("124", "0:48", "93%"). A break is a row: "Break", "0:25", "–".
5. "Timing per note": the existing error strip, 56 high, "Early" and "Late" at its ends.
6. Rows (label, value): "Timing" · "4 ms early"; "Spread" · "20 ms, tight"; "Extra notes" · "12"; "Missed" · "3"; "Top tempo" · "148 bpm".
7. Fixed bottom: primary **Again** (`arrow.clockwise`). After a guided run it reads **Play solo**.

Removed: the centred layout, the chip, the paragraph of anchors (it moves to a `ValueRow` "About the numbers" at the end of the rows, opening one short text screen).

### Routines (flat table)

Bar: "Routines", right `plus` then `gearshape`. Column head: "Routine", "Blocks", "Time". Row: name; "5" (44, right); "24 min" (64, right). Tap opens the routine. Swipe left: **Delete** (asks once). Swipe right: **Duplicate**. `plus` makes "New routine" with one Warm-up and one Drill block and opens it with the name selected. Empty: "No routines. Tap + to make one".

### Routine (the editor; one screen, always editable)

Bar: Back "Routines", the routine's name as the title (tap the title to rename, inline), right `ellipsis` menu: Rename, Duplicate, Delete.

A flat table of blocks. Head: "Block", "Tempo", "Length". Rows 44:

| Block | Tempo | Length |
|---|---|---|
| Warm-up | 80 | 3:00 |
| Triplets to 16ths, 4+4 | 100 to 140 | 8:00 |
| Break | | 1:00 |
| Triplets to 16ths, 4+4 | 132 | 16 loops |
| Open practice | 90 | 5:00 |

- Tempo 84 wide, Length 72 wide, both right-aligned and monospaced. An ascending drill shows "100 to 140".
- Long-press and drag reorders (`.onMove`, no Edit mode); a selection tick on drop. Swipe left: **Delete**. Swipe right: **Duplicate** (the copy lands under the original).
- Last row: `ActionRow` "Add block", a menu of Warm-up, Drill, Break, Open practice. The new block is appended and its editor opens.
- Under the table, one line in `footnote` `muted`: "5 blocks, about 24 min".
- Fixed bottom: primary **Start** (`play.fill`).

The fourth block type is named "Open practice", not "Free play": Joe, 2026-11-14, "don't call it 'just play' that's lame".

### Block editor (grouped; pushed from a block row)

Bar: Back is the routine's name, title is the block type. Changes save as they are made; no Save button.

- **Warm-up.** Group: field row "Name" · "Warm-up"; `StepperRow` "Length" · "3:00" (0:30 to 30:00, 30 second steps); `SwitchRow` "Click" (on); `StepperRow` "Tempo" · "80 bpm" (shown while Click is on).
- **Drill.** Group one: `ValueRow` "Drill" · "Triplets to 16ths, 4+4". Then the Drill setup's own groups, the same views: the tempo block, "Tempo zone", "Ascending tempo", "Length" (Loops or Time only), "Audio input", "Guide notes", "Options". No Start here.
- **Break.** Group: field row "Name" · "Break"; `StepperRow` "Length" · "1:00" (0:15 to 10:00, 15 second steps). Silent.
- **Open practice.** Group: field row "Name" · "Open practice"; `StepperRow` "Length" · "5:00"; `SwitchRow` "Click" (off); `StepperRow` "Tempo" · "90 bpm" (shown while Click is on).
- Every type ends with a group of two action rows: "Duplicate" in `accentText`, "Delete" in `danger` (asks once).

### Routine runner (full screen, no bars)

One frame for every state, so nothing jumps:
- Top line (44): left "2 of 5" then the routine's name, in `sub` `muted`; right the route picker.
- A segmented `ProgressLine` under it: one segment per block, widths by length, gap 2; done blocks `muted`, the current one filling in `accent`, the rest `lineStrong`.
- Middle: the block's content (below).
- Next-up line (28), above the buttons, in `sub` `muted`: left "Next", then the next block's name in `text`; right its length. On the last block: "Last block".
- Bottom: three controls in a row: icon button `backward.end.fill` (44 box, labelled "Back"), `QuietButton` **Pause** in the middle taking the rest, icon button `forward.end.fill` ("Skip"). Back restarts the current block; twice within two seconds goes to the one before.

**Playing, a Drill block.** The middle is the Run screen's items 2 to 9, unchanged (cue, tempo, beat, step progress, accuracy meter, lane, status line reading "Loop 5 of 16" and the block's "2:14 left"). The run's own Pause and Stop are replaced by the runner's bottom row.

**Playing, Warm-up, Break, Open practice.** Left-aligned: the block's name in `cue`; the time left in `tempoHero` ("2:14"); with Click on, a line "80 bpm" in `stat` and the `BeatBar`; a Break shows only the name and the time.

**Between blocks (auto-advance).** The chime at the end of a block, then three seconds. The middle shows: "Next" in `footnote` `muted`; the next block's name in `cue`; its summary in `sub` `muted` ("100 to 140 bpm, 8:00"); the numeral "3", "2", "1" in `tempoHero`, a tick and a rigid haptic on each. Then the block starts (a Drill block plays its count-in first). Skip during the countdown starts the block at once; Pause holds the countdown.

**Paused.** The middle dims to 40%; "Paused" in `cue` over it. The bottom row becomes: primary **Resume** (`play.fill`), and under it a line of two text buttons, **Restart block** in `text` at the left and **End routine** in `danger` at the right (End asks once: "End the routine? What is done is saved.", buttons End and Cancel).

**Finished.** Chime, success haptic. Bar: the routine's name, right **Done**. Then: one line in `sub` `muted` "5 blocks, 4 played, Nov 24 at 9:10 PM"; the total time in `statLarge` ("24:10") with "total" beside it in `body` `muted`; when any block was scored, the line "Accuracy 91%, top tempo 148 bpm" in `body`; a table, head "Block", "Tempo", "Accuracy": one row per block (unscored blocks show "–", skipped blocks show "Skipped" in `faint`); a scored drill row opens that block's Result. Fixed bottom: primary **Again**. The whole routine is saved as one session.

### Progress (flat; a tab)

Bar: "Progress", right `gearshape`. Under it one status line in `footnote` `muted` with a 6 pt dot, coloured only when wrong: "All devices, updated 9:12 PM" or, with a `warn` dot, "This phone only. The drill server could not be reached".

1. Table "Drills" (the label shows because there are two groups). Head "Drill", "Max", "Best". Row opens **Drill progress**: the max in `statLarge` with "bpm max"; the tempo trend sparkline (56 high, a 1.5 px `accentText` line, no fill, no dots but the last); a table of bests, head "Tempo", "Best", "Date"; a row "Unscored time" · "42 min".
2. Table "Sessions", newest first. Head "Session", "Tempo", "Accuracy". The name cell has the date under it in `footnote` `faint` ("Today 9:10 PM", "Nov 22"). A drill run: "Triplets to 16ths, 4+4", "120 to 148", "91%". A routine: its name, "5 blocks", "91%" or "–". A row opens its Result (drill) or the routine's finished screen (routine), read-only, with Back instead of the bottom button. 30 rows, then an `ActionRow` "Show more".
3. Empty: "No sessions yet. Run a drill and it shows here".

### Settings (sheet, grouped, Done at the right)

- "Audio": `ValueRow` "Audio" · the input's name; `ValueRow` "Calibration" · "231 ms"; `SwitchRow` "Phone microphone".
- "Guitar": `ValueRow` "Tuning" · "E standard".
- "Sound": `ValueRow` "Click sound" · "Wood block"; slider row "Click level" · "80%"; `SwitchRow` "Block chime"; `SwitchRow` "Countdown ticks".
- "Voice": `SwitchRow` "Voice intro"; `SwitchRow` "Voice cues"; `ValueRow` "Voice" · "Ava"; `ActionRow` "Preview".
- "Screen": `SwitchRow` "Keep screen on"; `SwitchRow` "Lock screen controls".
- "Sync": read-only "Drills" · "Updated 2:10 PM"; read-only "Runs waiting" · "0"; `ActionRow` "Sync now".
- "About": read-only "Version" · "0.3.0"; `ActionRow` "Check for updates" (or "Update to 0.3.1").

No footer paragraphs. A group gets a helper line only where a label cannot carry it: under "Audio", "Phone microphone is for testing without an interface". The Advanced fold is removed. The Audio screen keeps its rows and takes the same components; its long check text becomes one line per problem.

**Tuning** (detail, grouped; the same screen for Settings and for an override). One group, a checkmark list; each row is the preset's name with its notes at the right in `muted`, monospaced, low string first:

| Row | Value |
|---|---|
| E standard | E A D G B E |
| Eb standard | Eb Ab Db Gb Bb Eb |
| Drop D | D A D G B E |
| D standard | D G C F A D |
| Drop C | C G C F A D |
| C standard | C F Bb Eb G C |
| B standard | B E A D F# B |
| 7-string B | B E A D G B E |
| Drop A | A E A D G B E |
| Custom | its notes, and a `chevron.right` |

Tapping a preset picks it. Tapping "Custom" picks it and opens **Custom tuning**: a `SegmentedRow` "Strings" · 6 | 7 in its own group; then one group with a `StepperRow` per string, lowest first, labelled "String 6" down to "String 1" (or from "String 7"), the value the note with its octave ("E2"), one semitone a step, an octave and a half either way from standard; then an `ActionRow` "Copy from E standard" (a menu of the presets, to start from one). The note sounds once, quietly, on each step. Flats are written "Eb", sharps "F#"; never the symbols.

## 4. Desktop (JUCE, default window 1100 by 720, minimum 900 by 640)

Same tokens (`Theme.h` already has them; change `raised` dark to `#262625`). 13 px text, 28 px rows and controls, radii 4, 6, 10, Lucide 16 px icons, focus ring 1.5 px `accent`. Numerals: Segoe UI Variable, regular, tabular; hero 72 px, run tempo 56 px, result 36 px.

- **Frame.** Replace the two-segment switch with a left side panel, 176 wide, `side`: rows 28 high with a 16 px icon and a label: Metronome (`timer`), Drills (`guitar`), Routines (`list-ordered`), Progress (`line-chart`); Settings (`settings`) pinned at the bottom. Selected row: `active` fill, radius 6, `text`; others `muted`. The side panel hides during a run. Content area `bg`, padding 24.
- **Metronome.** A column 560 wide at the left of the content: `BeatBar`, the hero numeral with "bpm" and minus and plus (28 px icon buttons), slider, then a form (label column 160, controls on one line): Time signature, Subdivision, Accent, Click sound as dropdowns. Start (accent, 28 high, 120 wide) and Tap (quiet) under the form. Space starts and stops; up and down change the tempo by 1, with Shift by 5.
- **Drills.** A table across the content: head row 28, rows 28, columns Drill (rest), Pattern (120), Max (64, right), Best (64, right), Last played (96, right). Double-click or Enter opens the setup.
- **Drill setup.** Two columns, no scrolling. Left, 560: the pattern strip, the tempo block, then the form with every row from the phone's setup, Length and Ascending tempo as dropdowns whose settings show in place under them (Per loop adds four rows; By accuracy adds the four groups, each with a 12 px `muted` label). Right, 360: "Options" as a second form (Click, Scoring, Voice). Start (accent) at the bottom left of the left column; Enter starts. The three rules each sit on one line on the desktop: "Speed up" · [90%] at or above for [8 loops]; "Slow down" · switch, [75%] below for [4 loops], lowest [100 bpm]; "Break" · switch, [60%] below for [2 loops], [25 seconds], "Resume one step slower" checkbox on the next line.
- **Run.** The whole window, `bg`. A top line 28 high (drill name left, device names right in `muted`). Left column, 320 wide: cue, the tempo numeral with Target and Next under it, `BeatBar`, step progress, the accuracy meter (the same four bands, 12 high), the status line, then Pause and Stop (quiet, 28 high) at the bottom. The rest is the lane, full height between two hairlines, the hit line a third from its left; the timing strip, 28 high, under it. Space pauses, Esc stops (asks nothing; the run is saved).
- **Auto break, countdowns, paused.** The left column's content swaps as on the phone; the lane stays drawn at 40%.
- **Result.** Left column 320: the summary line, the number, the new max line, the rows, Again (accent) and Done (quiet). Right: the tempo table when ascending, and the error strip full width.
- **Routines.** Master and detail. Left, 280: the routines table (Routine, Time) with a `plus` icon button in its head row. Right: the chosen routine: its name at 15 px semibold (double-click renames), the blocks table (Block, Tempo, Length; drag a row to reorder; on hover, 16 px `copy` and `trash-2` icons with tooltips; Ctrl+D duplicates, Delete deletes), an "Add block" text button under it opening a menu, "5 blocks, about 24 min" in `muted`, and Start (accent) at the bottom right. Selecting a block opens its editor as a 320 panel at the right of the blocks table (the table narrows; nothing scrolls sideways); the panel is a form with the same rows as the phone's block editor.
- **Routine runner.** The Run layout. The left column gains, at its top, "2 of 5" with the routine's name and the segmented progress line, and at its bottom the next-up line and the row Back, Pause, Skip. Left and right arrow keys are Back and Skip.
- **Progress.** Two tables side by side: Drills (360 wide) and Sessions (the rest; columns Session, Date, Device, Tempo, Accuracy). Selecting a row shows its detail in place of the Drills table, with a Back text button.
- **Settings.** A form 560 wide: the phone's groups as labelled sections; Audio keeps its own screen. Tuning is a dropdown of the presets and "Custom"; choosing Custom shows, under it, a Strings switch (6 or 7) and one row of six or seven note dropdowns, low string at the left, 64 wide each. The drill's Options form has the same dropdown with "Default" first.
- **Lane.** The phone's glyphs and states at 13 px semibold; × for X notes; the wrong-pitch outline 18 by 18 with the heard note under the lowest string at 11 px.

## 5. What reads as generated in the current UI, and what replaces it

| Now | Replace with |
|---|---|
| SF Rounded for every number (`Typo.number`, `Typo.figure`) | The default system design, regular weight, monospaced digits |
| `Chip` ("Solo · Z3 Tempo · 88% of max") floating at the top of Run, Result and Calibration | A plain muted line, left-aligned |
| Everything centred on Run, Result, Calibration, Paused | Left-aligned on the 16 margin; numbers right-aligned in their columns |
| Three `BigStat` tiles in a row (number over a tiny label) | One tempo numeral; accuracy lives in the meter's caption; time in the status line |
| `SectionLabel` in tracked capitals over every block ("GUIDE", "RUN") | Sentence-case footnote labels, only on screens with two or more groups |
| Custom `Segmented` with three and four segments (Run kind, Subdivision) | Value rows to a checkmark list; the system segmented control only for two choices |
| Custom `ScreenHeader` and `NavBar` | The system navigation bar, inline titles |
| Setup as loose stacked blocks, each with its own helper paragraph (guided help, mode line, ladder help) | Inset groups of single-line rows; summaries in the row's value; at most one helper line |
| A zone bar, a dial, a levels menu, two segmented controls and a disclosure on one screen | One tempo block, three value rows, two switches, one Options row |
| Inline `Disclosure` ("Options") that pushes the Start button around | A value row to an Options screen; Start fixed at the bottom |
| "Ladder" as a stepper buried in Options | "Ascending tempo", on the surface, with its own screen |
| Menus with `chevron.up.chevron.down` in the accent for some rows, steppers and toggles of other shapes for others | One `ValueRow`, one `StepperRow`, one `SwitchRow` |
| `BeatDots`: small round dots, centred | `BeatBar`: full-width segments on the margins |
| Radii 6, 8, 10 with filled `hover` panels around controls | 4, 6, 10; fills only for groups and buttons |
| Primary and quiet buttons with an icon on every one, including Done and Next | Icons only on transport buttons (Start, Pause, Stop, Skip, Back, Again) |
| "Tap anywhere to pause" hint line under the buttons | Removed; the gesture stays |
| The paused card with a centred help paragraph | "Paused", one line, Resume, End |
| Result: three centred captions, including the paragraph of anchors ("session players 10 to 15 ms...") | Rows with values; the anchors on their own short screen |
| Drill table with a pattern glyph column, a "last played" second line and kind headers for one drill | Three columns, one line a row, no header until there are two groups |
| Progress and Settings as icons crowding the Drills header | Progress is a tab; Settings is one gear, in the same place on every tab |
| Progress as a stack of per-drill panels with a sparkline each | Two tables; the sparkline one tap in |
| Settings footers that are paragraphs; an Advanced fold holding one switch | One helper line at most; the switch joins the Audio group |
| Words: "Cycles", "Endurance", "Open", "Ladder", "Solo/Guided", "Display Sync", "Input" as a step name | "Loops", "Hold accuracy", "Until stopped", "Ascending tempo", "Guide notes", "Line up the marks", "Play on the line" |
| Amber used for the count-in clock and for cues as well as for warnings | Amber only for the down zone, the beat before a pattern change, and a route problem |
