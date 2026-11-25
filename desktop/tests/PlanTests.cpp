// 0.3.0's model on the desktop, against the same shared vectors as the phone and npm test:
//   shared/tempo-vectors.json     ascending tempo (per loop, by accuracy: up, down, break, hysteresis, cooldown), Challenge
//   shared/routine-vectors.json   the routine runner's clock (countdowns, auto-advance, pause, skip, back, drills by reps)
//   shared/scoring-vectors.json   pitch: X notes on timing only, pitched notes checked in the tuning
// plus the drill catalog filter, X notes in drill definitions, the click options and the pitch detector.
#include <JuceHeader.h>
#include "../src/core/Scoring.h"
#include "../src/core/Drill.h"
#include "../src/core/TempoPlan.h"
#include "../src/core/RoutineClock.h"
#include "../src/core/PitchDetector.h"
#include "../src/core/Results.h"
#include <cmath>
#include <iostream>

using namespace practice;

extern int planFailures, planChecks;
int planFailures = 0, planChecks = 0;
#define PCHECK(cond, what) do { ++planChecks; if (! (cond)) { ++planFailures; std::cout << "  FAIL " << (what) << "  (" << #cond << ")\n"; } } while (0)
static bool pnear (double a, double b, double tol = 1e-6) { return std::abs (a - b) <= tol; }
static juce::File prepo() { return juce::File (PRACTICE_REPO); }
static juce::var vec (const char* name) { return juce::JSON::parse (prepo().getChildFile (juce::String ("shared/") + name)); }

static void tempoVectors()
{
    std::cout << "Ascending tempo and Challenge with shared/tempo-vectors.json\n";
    auto V = vec ("tempo-vectors.json");
    int n = 0;
    for (auto& c : *V["perLoop"].getArray())
    {
        auto p = TempoPlan::fromVar (c["plan"]);
        auto* loops = c["loops"].getArray();
        auto* want = c["expect"].getArray();
        for (int i = 0; i < loops->size(); ++i)
        {
            auto l = (*loops)[i];
            const int got = p.perLoopBPM ((int) c["start"], (int) c["top"], (int) l[0], (double) l[1]);
            PCHECK (got == (int) (*want)[i], (c["name"].toString() + " loop " + juce::String (i)).toStdString());
        }
        ++n;
    }
    for (auto& c : *V["governor"].getArray())
    {
        auto p = TempoPlan::fromVar (c["plan"]);
        TempoGovernor g (p, (int) c["start"], (int) c["top"], (int) c["floor"]);
        auto* loops = c["loops"].getArray();
        auto* want = c["expect"].getArray();
        for (int i = 0; i < loops->size(); ++i)
        {
            auto l = (*loops)[i];
            auto ch = g.judge ((double) l[0], (double) l[1], (int) l[2]);
            auto e = (*want)[i];
            const auto what = (c["name"].toString() + " loop " + juce::String (i)).toStdString();
            if (e["change"].isObject())
                PCHECK (ch && TempoChange::kindName (ch->kind) == e["change"]["kind"].toString() && ch->from == (int) e["change"]["from"]
                        && ch->to == (int) e["change"]["to"], what + " change");
            else
                PCHECK (! ch, what + " no change");
            PCHECK (g.target() == (int) e["target"], what + " target");
            PCHECK (pnear (g.progress(), (double) e["progress"]), what + " progress");
            PCHECK (TempoPlan::zoneName (p.normalized().zone ((double) l[0])) == e["zone"].toString(), what + " zone");
        }
        ++n;
    }
    for (auto& c : *V["zones"].getArray())
        PCHECK (TempoPlan::zoneName (TempoPlan::fromVar (c["plan"]).zone ((double) c["accuracy"])) == c["expect"].toString(), "zone");
    for (auto& c : *V["bounds"].getArray())
    {
        auto b = TempoPlan::fromVar (c["plan"]).bounds ((int) c["start"], (int) c["rule"]["min"], (int) c["rule"]["max"]);
        PCHECK (b.top == (int) c["expect"]["top"] && b.floor == (int) c["expect"]["floor"], "bounds");
    }
    for (auto& c : *V["challenge"].getArray())
    {
        auto o = c["opts"];
        ChallengeClock k ((double) o["targetSeconds"], (int) o["percent"], (int) o["window"], (double) o.getProperty ("capSeconds", 0));
        auto* loops = c["loops"].getArray();
        auto* want = c["expect"].getArray();
        for (int i = 0; i < loops->size(); ++i)
        {
            auto r = k.judge ((double) (*loops)[i][0], (double) (*loops)[i][1]);
            auto e = (*want)[i];
            const juce::String rs = r == ChallengeClock::Result::earned ? "earned" : r == ChallengeClock::Result::held ? "held" : "done";
            const auto what = (c["name"].toString() + " loop " + juce::String (i)).toStdString();
            PCHECK (rs == e["result"].toString(), what + " result");
            PCHECK (pnear (k.earned, (double) e["earned"]) && pnear (k.elapsed, (double) e["elapsed"]) && pnear (k.bestStreak, (double) e["bestStreak"]), what + " clock");
            PCHECK (k.inZone == (bool) e["inZone"], what + " in zone");
            PCHECK (pnear (std::round (k.share() * 1e6) / 1e6, (double) e["share"]), what + " share");
        }
        ++n;
    }
    // The hysteresis: thresholds too close are pulled apart.
    TempoPlan p; p.upPercent = 80; p.downPercent = 82; p.breakOn = true; p.breakPercent = 90;
    auto q = p.normalized();
    PCHECK (q.downPercent <= q.upPercent - 5 && q.breakPercent <= q.downPercent - 5, "hysteresis kept");
    // The tempo curve as stretches.
    auto steps = TempoStep::from ({ { 100, 4, 0.9 }, { 100, 4, 0.8 }, { 104, 4, 0.5 } }, { { 2, 25 } });
    PCHECK (steps.size() == 3 && steps[0].bpm == 100 && steps[0].accuracy == 85 && steps[1].accuracy == 50 && steps[2].rest, "tempo steps");
    std::cout << "  " << n << " cases\n";
}

static void routineVectors()
{
    std::cout << "The routine clock with shared/routine-vectors.json\n";
    auto V = vec ("routine-vectors.json");
    int n = 0;
    for (auto& c : *V["cases"].getArray())
    {
        std::vector<std::optional<double>> blocks;
        for (auto& b : *c["blocks"].getArray()) blocks.push_back (b["seconds"].isVoid() ? std::nullopt : std::optional<double> ((double) b["seconds"]));
        std::vector<double> est;
        if (auto* a = c["estimates"].getArray()) for (auto& x : *a) est.push_back ((double) x);
        RoutineClock k (blocks);
        auto* steps = c["steps"].getArray();
        auto* want = c["expect"].getArray();
        for (int i = 0; i < steps->size(); ++i)
        {
            const double t = (double) (*steps)[i][0];
            const auto a = (*steps)[i][1].toString();
            std::vector<RoutineClock::Event> ev;
            if (a == "start") ev = k.start (t);
            else if (a == "tick") ev = k.tick (t);
            else if (a == "pause") k.pause (t);
            else if (a == "resume") ev = k.resume (t);
            else if (a == "skip") ev = k.skip (t);
            else if (a == "back") k.back (t);
            else if (a == "blockDone") ev = k.blockDone (t);
            auto e = (*want)[i];
            std::vector<RoutineClock::Event> wantEv;
            for (auto& x : *e["events"].getArray())
            {
                const auto kind = x[0].toString();
                wantEv.push_back ({ kind == "start" ? RoutineClock::Event::Kind::start : kind == "end" ? RoutineClock::Event::Kind::end
                                    : RoutineClock::Event::Kind::done, kind == "done" ? 0 : (int) x[1] });
            }
            const auto what = (c["name"].toString() + " step " + juce::String (i)).toStdString();
            PCHECK (ev == wantEv, what + " events");
            auto s = k.state (t);
            auto ws = e["state"];
            static const char* names[] = { "idle", "countdown", "block", "paused", "done" };
            PCHECK (juce::String (names[(int) s.phase]) == ws["phase"].toString() && s.index == (int) ws["index"], what + " phase");
            PCHECK (ws["left"].isVoid() ? ! s.left : (s.left && pnear (*s.left, (double) ws["left"])), what + " left");
            PCHECK (s.paused == (bool) ws["paused"], what + " paused");
            PCHECK (ws["countdownTick"].isVoid() ? ! s.countdownTick : (s.countdownTick && *s.countdownTick == (int) ws["countdownTick"]), what + " tick");
            PCHECK (pnear (k.remaining (t, est), (double) e["remaining"]), what + " remaining");
        }
        auto* log = c["log"].getArray();
        for (int i = 0; i < log->size(); ++i)
        {
            auto l = (*log)[i];
            PCHECK (pnear (k.log()[(size_t) i].seconds, (double) l["seconds"]) && k.log()[(size_t) i].skipped == (bool) l["skipped"]
                    && k.log()[(size_t) i].done == (bool) l["done"], (c["name"].toString() + " log").toStdString());
        }
        ++n;
    }
    std::cout << "  " << n << " cases\n";
}

static void pitchAndCatalog()
{
    std::cout << "X notes, pitch, the catalog filter, click options, the pitch detector\n";
    auto V = vec ("scoring-vectors.json");
    ScoringConfig cfg;
    auto c0 = V["config"];
    cfg.fullFraction = (double) c0["fullFraction"]; cfg.zeroFraction = (double) c0["zeroFraction"];
    cfg.fullMinMs = (double) c0["fullMinMs"]; cfg.fullMaxMs = (double) c0["fullMaxMs"];
    cfg.zeroMinMs = (double) c0["zeroMinMs"]; cfg.zeroMaxMs = (double) c0["zeroMaxMs"]; cfg.extraWeight = (double) c0["extraWeight"];
    for (auto& c : *V["pitch"].getArray())
    {
        std::vector<Note> notes;
        for (auto& n : *c["notes"].getArray())
        {
            Note x; x.time = (double) n[0]; x.accent = (int) n[1] != 0; x.beat = (int) n[2];
            if (! n[3].isVoid()) x.pitch = (int) n[3];
            notes.push_back (x);
        }
        std::vector<Onset> played;
        for (auto& p : *c["played"].getArray())
        {
            Onset o; o.time = (double) p[0]; o.strength = (float) (double) p[1];
            if (! p[2].isVoid()) o.pitch = (double) p[2];
            played.push_back (o);
        }
        auto r = Scoring::score (notes, played, 0.05, {}, cfg);
        auto e = c["expect"];
        PCHECK (r.score == (int) e["score"] && r.hits == (int) e["hits"] && r.wrongPitch == (int) e["wrongPitch"], c["name"].toString().toStdString());
    }
    PCHECK (Scoring::pitchMatches (std::nullopt, 52.3) && Scoring::pitchMatches (43, std::nullopt), "X and unknown");
    PCHECK (! Scoring::pitchMatches (43, 44.0) && Scoring::pitchMatches (43, 55.2), "semitone wrong, octave right");

    // The catalog filter: only the triplets drill is offered; every drill is still in the file.
    auto file = juce::JSON::parse (prepo().getChildFile ("catalog/exercises/right-hand.json"));
    auto offered = Library::decodeDrills (file);
    auto all = Library::decodeDrills (file, true);
    PCHECK (offered && offered->size() == 1 && (*offered)[0].id == "trip16x4", "only the triplets drill is offered");
    PCHECK (all && all->size() == 9, "every drill is still defined");
    PCHECK (offered && (*offered)[0].pitchFree, "the triplets drill is all X notes");
    auto loaded = Library::load (prepo().getChildFile ("catalog"), juce::File(), juce::File());
    PCHECK (loaded.drills.size() == 1, "the catalog loads one drill");

    // X notes in a drill definition, pitches in a tuning.
    auto d = Drill::fromVar (juce::JSON::parse (R"({"id":"t","name":"T","tempo":{"start":80},"notes":[
        {"at":{"beat":0},"string":6,"fret":"x"},{"at":{"beat":1},"string":6,"fret":3,"x":true},{"at":{"beat":2}},{"at":{"beat":3},"string":6,"fret":3}]})"));
    PCHECK (d && d->notes.size() == 4 && d->notes[0].x && d->notes[1].x && d->notes[2].x && ! d->notes[3].x, "X notes decode");
    PCHECK (d && d->hasPitchedNotes(), "a fretted note asks for a pitch");
    if (d)
    {
        RunBuilder::ClickOptions o;
        o.tuning = *Tuning::preset ("dropD");
        auto slot = RunBuilder::cycle (*d, 0, 0, 60, false, {}, o);
        PCHECK (! slot.notes[0].pitch && slot.notes[3].pitch == 41, "pitches in drop D");
    }
    PCHECK (Tuning::preset ("dropD")->lowToHigh() == "D A D G B E" && Tuning::preset ("seven")->strings.size() == 7, "tunings");

    // Click options: the accent and the gap trainer.
    auto ex = Drill::fallback();
    auto accents = [&] (SessionSettings::Accent a) {
        RunBuilder::ClickOptions o; o.accent = a;
        std::vector<int> out;
        for (auto& e : RunBuilder::cycle (ex, 0, 0, 60, false, {}, o).events) if (e.kind == ClickKind::accent) out.push_back ((int) std::round (e.time));
        return out;
    };
    PCHECK (accents (SessionSettings::Accent::one) == std::vector<int> ({ 0, 4 }), "accent on beat 1");
    PCHECK (accents (SessionSettings::Accent::groups) == std::vector<int> ({ 0, 4 }), "accent at the group starts");
    PCHECK (accents (SessionSettings::Accent::off).empty(), "no accent");
    RunBuilder::ClickOptions gap; gap.gapEvery = 2;
    auto g = RunBuilder::cycle (ex, 0, 0, 60, true, {}, gap);
    int clicks = 0; bool guideInGap = false;
    for (auto& e : g.events)
    {
        if ((e.kind == ClickKind::accent || e.kind == ClickKind::beat) && e.time < 4) ++clicks;
        if ((e.kind == ClickKind::accent || e.kind == ClickKind::beat || e.kind == ClickKind::pluck || e.kind == ClickKind::pluckAccent) && e.time >= 4) guideInGap = true;
    }
    PCHECK (clicks == 4 && ! guideInGap && g.notes.size() == 28, "the gap trainer mutes every 2nd bar, the notes stay");
    auto old = SessionSettings::fromVar (juce::JSON::parse (R"({"kind":"endurance","ladderStep":4})"));
    PCHECK (old.ladderStep == 4 && old.tempoPlan.mode == TempoPlan::Mode::off && old.countInBars == 1, "0.2 settings read");
    auto round = SessionSettings::fromVar (old.toVar());
    PCHECK (round == old, "settings round-trip");

    // The pitch detector.
    PitchDetector det;
    for (auto [hz, midi] : { std::pair<double, double> { 82.41, 40 }, { 55.0, 33 }, { 196.0, 55 }, { 329.63, 64 } })
    {
        std::vector<float> x ((size_t) det.needed() + 64);
        for (size_t i = 0; i < x.size(); ++i)
        {
            const double t = (double) i / det.sampleRate;
            x[i] = (float) (0.3 * (std::sin (2 * juce::MathConstants<double>::pi * hz * t) + 0.5 * std::sin (4 * juce::MathConstants<double>::pi * hz * t)
                                   + 0.25 * std::sin (6 * juce::MathConstants<double>::pi * hz * t)) * std::exp (-t * 3));
        }
        auto m = det.midi (x.data(), (int) x.size());
        PCHECK (m && std::abs (*m - midi) < 0.3, "pitch of " + std::to_string (hz));
    }
    std::vector<float> silence ((size_t) det.needed(), 0.0f);
    PCHECK (! det.midi (silence.data(), (int) silence.size()), "silence has no pitch");
}

void planTests()
{
    tempoVectors();
    routineVectors();
    pitchAndCatalog();
}
