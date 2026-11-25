// The routine runner's clock, in one plain reference, the same as the iPhone app's (ios/Practice/Library/RoutineClock.swift)
// and the desktop app's (desktop/src/core/RoutineClock.cpp). Joe, 2026-11-24: "let's build a Routines section where
// we can interval out warm ups, drills, breaks, etc."
//
// A routine is blocks in order. Before each block a short countdown (3 seconds, a tick each second, a chime as the
// block starts). A block with seconds ends by itself when they have run; a block without (a drill by reps) ends when
// the app says it is done. Pause holds the clock (in a countdown too), Skip ends the block now and moves on, Back
// starts the block again, or, in its first 3 seconds or in a countdown, goes to the block before.
// Time is passed in (seconds, any clock), so the rules are tested without waiting.
//
// Change a rule here, in RoutineClock.swift and RoutineClock.cpp together, then `node scripts/make-routine-vectors.mjs`.

export const COUNTDOWN = 3;
export const BACK_GRACE = 3;

export class RoutineClock {
  /** blocks: [{seconds}] with seconds null for a block that ends itself. */
  constructor(blocks, countdown = COUNTDOWN) {
    this.blocks = blocks.map((b) => ({ seconds: b.seconds ?? null }));
    this.countdown = countdown;
    this.phase = 'idle';          // idle, countdown, block, paused, done
    this.index = 0;
    this.since = 0;               // when the phase (or the stretch since a resume) started
    this.used = 0;                // seconds of the phase already run before `since`
    this.held = null;             // the phase paused
    this.log = blocks.map(() => ({ seconds: 0, skipped: false, done: false }));
  }

  start(t) { if (this.phase === 'idle') this.enterCountdown(0, t); return this.tick(t); }

  enterCountdown(i, t) {
    if (i >= this.blocks.length) { this.phase = 'done'; this.index = this.blocks.length; return; }
    this.phase = 'countdown'; this.index = i; this.since = t; this.used = 0;
  }

  run(t) { return this.used + Math.max(0, t - this.since); }

  /** Moves the clock to t; returns what happened, in order: ['start', i], ['end', i], ['done']. */
  tick(t) {
    const events = [];
    for (let guard = 0; guard < 64; guard++) {
      if (this.phase === 'countdown' && this.run(t) >= this.countdown - 1e-9) {
        const at = this.since + (this.countdown - this.used);
        this.phase = 'block'; this.since = at; this.used = 0;
        events.push(['start', this.index]);
        continue;
      }
      if (this.phase === 'block') {
        const s = this.blocks[this.index].seconds;
        if (s != null && this.run(t) >= s - 1e-9) {
          const at = this.since + (s - this.used);
          this.log[this.index].seconds = round(this.log[this.index].seconds + s);
          this.log[this.index].done = true;
          events.push(['end', this.index]);
          this.enterCountdown(this.index + 1, at);
          if (this.phase === 'done') events.push(['done']);
          continue;
        }
      }
      break;
    }
    return events;
  }

  pause(t) {
    this.tick(t);
    if (this.phase !== 'countdown' && this.phase !== 'block') return;
    this.used = this.run(t); this.held = this.phase; this.phase = 'paused';
  }

  resume(t) {
    if (this.phase !== 'paused') return [];
    this.phase = this.held; this.held = null; this.since = t;
    return this.tick(t);
  }

  /** Ends the block now (a skipped one keeps the seconds it ran) and moves on. In a countdown, skips the countdown. */
  skip(t) {
    this.tick(t);
    const phase = this.phase === 'paused' ? this.held : this.phase;
    if (phase === 'countdown') { this.phase = 'block'; this.since = t; this.used = 0; this.held = null; return [['start', this.index]]; }
    if (phase !== 'block') return [];
    return this.finishBlock(t, true);
  }

  /** A block that ends itself (a drill by reps) has finished. */
  blockDone(t) {
    this.tick(t);
    if (this.phase !== 'block' && !(this.phase === 'paused' && this.held === 'block')) return [];
    return this.finishBlock(t, false);
  }

  finishBlock(t, skipped) {
    const ran = this.phase === 'paused' ? this.used : this.run(t);
    const i = this.index;
    this.log[i].seconds = round(this.log[i].seconds + ran);
    this.log[i].skipped = skipped; this.log[i].done = !skipped;
    this.held = null;
    const events = [['end', i]];
    this.enterCountdown(i + 1, t);
    if (this.phase === 'done') events.push(['done']);
    return events;
  }

  /** Starts the block again, or in its first seconds (or in a countdown) goes to the one before. */
  back(t) {
    this.tick(t);
    const phase = this.phase === 'paused' ? this.held : this.phase;
    if (phase !== 'countdown' && phase !== 'block' && this.phase !== 'done') return;
    const ran = this.phase === 'paused' ? this.used : (this.phase === 'done' ? 0 : this.run(t));
    let i = this.index;
    if (this.phase === 'done') i = this.blocks.length - 1;
    else if (phase === 'countdown' || ran < BACK_GRACE) i = Math.max(0, i - 1);
    if (phase === 'block' && this.phase !== 'done') this.log[this.index].seconds = round(this.log[this.index].seconds + ran);
    this.held = null;
    this.enterCountdown(i, t);
  }

  /** What the screen shows at t (without moving the clock). */
  state(t) {
    const phase = this.phase === 'paused' ? this.held : this.phase;
    const ran = this.phase === 'paused' ? this.used : this.run(t);
    const b = this.blocks[this.index];
    let left = null;
    if (phase === 'countdown') left = Math.max(0, this.countdown - ran);
    else if (phase === 'block' && b && b.seconds != null) left = Math.max(0, b.seconds - ran);
    return { phase: this.phase, index: this.index, left: left === null ? null : round(left), paused: this.phase === 'paused',
      countdownTick: phase === 'countdown' ? Math.ceil(Math.max(0, this.countdown - ran) - 1e-9) : null };
  }

  /** Seconds left in the whole routine at t, counting blocks that end themselves at their estimate. */
  remaining(t, estimates = []) {
    const s = this.state(t);
    if (this.phase === 'done') return 0;
    let total = s.left ?? (estimates[this.index] ?? 0);
    if ((this.phase === 'paused' ? this.held : this.phase) === 'countdown') total += this.blocks[this.index].seconds ?? estimates[this.index] ?? 0;
    for (let i = this.index + 1; i < this.blocks.length; i++) total += this.countdown + (this.blocks[i].seconds ?? estimates[i] ?? 0);
    return round(total);
  }
}

const round = (x) => Math.round(x * 1e6) / 1e6;
