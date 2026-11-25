// Ascending tempo, in one plain reference, line for line the same as the iPhone app's (ios/Practice/Scoring/TempoPlan.swift)
// and the desktop app's (desktop/src/core/TempoPlan.cpp). Joe, 2026-11-24: "perhaps we can have it ascend either per
// loop, or threshold average accuracy sustained per x duration", then: "Similarly, a slow down BPM based on average
// sustained poor accuracy. And a paused break when dropping below even lower threshold accuracy".
//
// Two ways up:
//   perLoop   +step every `every` loops (or seconds), to the top; then hold there or start again from the bottom.
//   accuracy  three thresholds, each over its own sustained window of the latest loops played at the tempo now:
//             up    the average is at or above upPercent for upWindow    -> +step (never past the top)
//             down  the average is under downPercent for downWindow      -> -step (never under the floor)
//             break the average is under breakPercent for breakWindow    -> the drill stops for breakSeconds, then
//                   goes on (a step slower when slowerAfterBreak)
//   No ping-pong: the thresholds are kept apart (hysteresis: down at least 5 under up, break at least 5 under down),
//   after any change the windows start empty, the next `cooldownLoops` loops are not counted, and loops still played
//   at the old tempo (the next is queued before the last is judged) are not counted either.
//
// Change a rule here, in TempoPlan.swift and TempoPlan.cpp together, then `node scripts/make-tempo-vectors.mjs`; the
// three test suites read shared/tempo-vectors.json.

export const defaultPlan = Object.freeze({
  mode: 'off',            // off, perLoop, accuracy
  endBPM: 0,              // the top; 0 is the drill's max tempo
  step: 4,
  every: 2, everyUnit: 'loops',          // perLoop: loops or seconds
  atTop: 'hold',          // perLoop: hold, or restart from the start tempo
  windowUnit: 'loops',    // accuracy: the windows are in loops or seconds
  upPercent: 90, upWindow: 4,
  downOn: true, downPercent: 75, downWindow: 4,
  breakOn: false, breakPercent: 50, breakWindow: 4, breakSeconds: 25, slowerAfterBreak: true,
  cooldownLoops: 1,
  minBPM: 0,              // the floor; 0 is the start tempo
});

/** The plan with every number in range and the thresholds kept apart. */
export function normalize(p) {
  const n = { ...defaultPlan, ...p };
  n.step = clamp(Math.round(n.step), 1, 40);
  n.every = clamp(Math.round(n.every), 1, 600);
  n.upPercent = clamp(Math.round(n.upPercent), 10, 100);
  n.downPercent = clamp(Math.round(n.downPercent), 5, n.upPercent - 5);
  n.breakPercent = clamp(Math.round(n.breakPercent), 0, n.downOn ? n.downPercent - 5 : n.upPercent - 10);
  for (const k of ['upWindow', 'downWindow', 'breakWindow']) n[k] = clamp(Math.round(n[k]), 1, 600);
  n.breakSeconds = clamp(Math.round(n.breakSeconds), 5, 300);
  n.cooldownLoops = clamp(Math.round(n.cooldownLoops), 0, 16);
  return n;
}

const clamp = (x, lo, hi) => Math.min(Math.max(x, lo), Math.max(lo, hi));

/** The top and the floor of a run that starts at `start` on a drill whose tempo rule is `rule` ({min, max}). */
export function bounds(p, start, rule) {
  const top = p.endBPM > 0 ? Math.min(p.endBPM, rule.max) : rule.max;
  const floor = p.minBPM > 0 ? Math.max(rule.min, Math.min(p.minBPM, start)) : start;
  return { top: Math.max(top, start), floor };
}

/** perLoop: the tempo of loop `k` (from 0), which starts `elapsed` seconds into the run. */
export function perLoopBPM(p, start, top, k, elapsed) {
  const steps = p.everyUnit === 'seconds' ? Math.floor((elapsed + 1e-9) / p.every) : Math.floor(k / p.every);
  if (top <= start) return start;
  const levels = Math.ceil((top - start) / p.step) + 1;      // start, start+step, ... top
  const i = p.atTop === 'restart' ? steps % levels : Math.min(steps, levels - 1);
  return Math.min(top, start + i * p.step);
}

/** Where the accuracy sits against the plan, for the meter: up, hold, down or break. */
export function zoneOf(p, accuracy) {
  const pct = accuracy * 100;
  if (pct >= p.upPercent) return 'up';
  if (p.downOn && pct >= p.downPercent) return 'hold';
  if (!p.downOn && (!p.breakOn || pct >= p.breakPercent)) return 'hold';
  if (p.breakOn && pct < p.breakPercent) return 'break';
  return 'down';
}

/**
 * accuracy: judges each loop as it is scored. `judge` returns null or a change {kind: up|down|break, from, to}. On a
 * break, `to` is the tempo the drill goes on at after the break.
 */
export class Governor {
  constructor(plan, start, top, floor) {
    this.p = normalize(plan);
    this.target = start; this.top = top; this.floor = floor;
    this.loops = [];        // {accuracy, seconds} since the last change, at the target
    this.cooldown = 0;
  }

  /** The average over the latest loops covering `n` loops (or seconds); null until they do. */
  average(n) {
    let covered = 0, credit = 0, weight = 0, count = 0;
    for (let i = this.loops.length - 1; i >= 0; i--) {
      const l = this.loops[i];
      covered += this.p.windowUnit === 'seconds' ? l.seconds : 1;
      credit += l.accuracy * l.seconds; weight += l.seconds; count += 1;
      if (covered >= n - 1e-9) return weight > 0 ? credit / weight : 0;
    }
    return null;
  }

  /** How far toward the next step up, 0 to 1: the share of the up window already held at or above the threshold. */
  progress() {
    const n = this.p.upWindow;
    if (this.target >= this.top) return 0;
    let covered = 0, credit = 0, weight = 0;
    for (let i = this.loops.length - 1; i >= 0 && covered < n - 1e-9; i--) {
      const l = this.loops[i];
      covered += this.p.windowUnit === 'seconds' ? l.seconds : 1;
      credit += l.accuracy * l.seconds; weight += l.seconds;
    }
    if (!weight || (credit / weight) * 100 < this.p.upPercent) return 0;
    return Math.min(1, covered / n);
  }

  judge(accuracy, seconds, bpm) {
    if (Math.round(bpm) !== this.target) return null;          // queued before the last change: not counted
    if (this.cooldown > 0) { this.cooldown -= 1; return null; }
    this.loops.push({ accuracy, seconds });
    const p = this.p;
    const from = this.target;
    let change = null;
    const b = p.breakOn ? this.average(p.breakWindow) : null;
    const d = p.downOn ? this.average(p.downWindow) : null;
    const u = this.average(p.upWindow);
    if (b !== null && b * 100 < p.breakPercent) {
      const to = p.slowerAfterBreak ? Math.max(this.floor, from - p.step) : from;
      change = { kind: 'break', from, to };
    } else if (d !== null && d * 100 < p.downPercent && from > this.floor) {
      change = { kind: 'down', from, to: Math.max(this.floor, from - p.step) };
    } else if (u !== null && u * 100 >= p.upPercent && from < this.top) {
      change = { kind: 'up', from, to: Math.min(this.top, from + p.step) };
    }
    if (change) {
      this.target = change.to;
      this.loops = [];
      this.cooldown = p.cooldownLoops;
    }
    return change;
  }
}

/**
 * Challenge (Joe, 2026-11-24: "some kind of 'Challenge' mode that counts duration but only counts towards the time
 * when the accuracy is above a certain threshold"). The drill keeps playing; each loop as it is scored adds its
 * length to the earned time when the rolling accuracy (over the latest `window` loops) is at or above the threshold.
 * Done when the earned time reaches the target, or when the elapsed time reaches the cap (0 is no cap).
 */
export class ChallengeClock {
  constructor({ targetSeconds = 300, percent = 90, window = 2, capSeconds = 0 } = {}) {
    this.target = targetSeconds; this.percent = percent; this.window = Math.max(1, window); this.cap = capSeconds;
    this.earned = 0; this.elapsed = 0; this.streak = 0; this.bestStreak = 0; this.inZone = false;
    this.loops = [];
  }

  /** One scored loop. Returns 'earned', 'held' (under the threshold) or 'done'. */
  judge(accuracy, seconds) {
    if (this.done) return 'done';
    this.loops.push({ accuracy, seconds });
    const w = this.loops.slice(-this.window);
    let credit = 0, weight = 0;
    for (const l of w) { credit += l.accuracy * l.seconds; weight += l.seconds; }
    const rolling = weight > 0 ? credit / weight : 0;
    this.elapsed = round(this.elapsed + seconds);
    this.inZone = rolling * 100 >= this.percent - 1e-9;
    if (this.inZone) {
      this.earned = round(Math.min(this.target, this.earned + seconds));
      this.streak = round(this.streak + seconds);
      this.bestStreak = Math.max(this.bestStreak, this.streak);
    } else {
      this.streak = 0;
    }
    return this.done ? 'done' : this.inZone ? 'earned' : 'held';
  }

  get done() { return this.earned >= this.target - 1e-9 || (this.cap > 0 && this.elapsed >= this.cap - 1e-9); }
  /** The share of the elapsed time that was earned, 0 to 1. */
  get share() { return this.elapsed > 0 ? this.earned / this.elapsed : 0; }
}

const round = (x) => Math.round(x * 1e6) / 1e6;
