// The desktop app's tests (desktop/scripts/build.ps1 runs them; exit code 0 means all passed):
//   1. Scoring parity: every case in shared/scoring-vectors.json, the same file the iPhone app's
//      ScoringVectorTests and `npm test` read, so the phone and the computer score a run the same.
//   2. The onset detector on synthetic picking (the iPhone app's OnsetTests, ported).
//   3. Device picks under stress: hundreds of picks fired from the "UI thread" against a slow fake device; no pick
//      may wait, the newest pick must be the one open at the end, and the ones in between are coalesced. Then the
//      same against the real Windows devices when there are any.
//   4. Sync with the drill server: the real server (server/index.mjs) on a scratch port and data folder; runs made
//      offline wait in the queue, go when the server is up, are kept once, and come back in every app's list.
#include <JuceHeader.h>
#include "../src/core/Scoring.h"
#include "../src/core/Drill.h"
#include "../src/core/OnsetDetector.h"
#include "../src/core/Results.h"
#include "../src/engine/DeviceController.h"
#include "../src/engine/AudioEngine.h"
#include "../src/app/Store.h"
#include "../src/app/Sync.h"
#include <atomic>
#include <cmath>
#include <iostream>

using namespace practice;

static int failures = 0, checks = 0;
#define CHECK(cond, what) do { ++checks; if (! (cond)) { ++failures; std::cout << "  FAIL " << (what) << "  (" << #cond << ")\n"; } } while (0)
static bool near (double a, double b, double tol) { return std::abs (a - b) <= tol; }
static juce::File repo() { return juce::File (PRACTICE_REPO); }
static double num (const juce::var& v) { return (double) v; }

// ---------------------------------------------------------------- 1. scoring parity

static void scoringParity()
{
    std::cout << "Scoring parity with shared/scoring-vectors.json\n";
    auto V = juce::JSON::parse (repo().getChildFile ("shared/scoring-vectors.json"));
    CHECK (V.isObject(), "the vectors file reads");
    const double tol = num (V["tolerance"]);
    auto config = scoringFromVar (V["config"]);
    CHECK (config.has_value(), "the config reads");
    if (! config) return;
    // the catalog's numbers are the vectors' numbers
    auto cat = scoringFromVar (juce::JSON::parse (repo().getChildFile ("catalog/scoring.json")));
    CHECK (cat && cat->fullFraction == config->fullFraction && cat->zeroMaxMs == config->zeroMaxMs, "catalog/scoring.json matches the vectors");

    int runs = 0;
    for (auto& c : *V["score"].getArray())
    {
        const auto name = c["name"].toString().toStdString();
        std::vector<Note> notes;
        for (auto& n : *c["notes"].getArray()) { Note x; x.time = num (n[0]); x.accent = num (n[1]) != 0; x.beat = (int) n[2]; notes.push_back (x); }
        std::vector<Onset> played;
        for (auto& p : *c["played"].getArray()) played.push_back ({ num (p[0]), (float) num (p[1]) });
        ScoringRule rule;
        rule.passMark = (int) c["rule"]["passMark"];
        rule.tightMs = num (c["rule"]["tightMs"]);
        rule.closeMs = num (c["rule"]["closeMs"]);
        auto r = Scoring::score (notes, played, num (c["window"]), rule, *config);
        auto e = c["expect"];
        auto optEq = [] (std::optional<int> a, const juce::var& b) { return b.isVoid() ? ! a : (a && *a == (int) b); };
        CHECK (r.score == (int) e["score"], name + " score " + std::to_string (r.score) + " vs " + e["score"].toString().toStdString());
        CHECK (r.expected == (int) e["expected"] && r.hits == (int) e["hits"] && r.missed == (int) e["missed"] && r.extra == (int) e["extra"], name + " counts");
        CHECK (r.within20 == (int) e["within20"] && r.within40 == (int) e["within40"] && r.full == (int) e["full"], name + " windows");
        CHECK (r.pct20() == (int) e["pct20"] && r.pct40() == (int) e["pct40"] && r.passed() == (bool) e["passed"], name + " percentages");
        CHECK (optEq (r.accentsLanded, e["accentsLanded"]) && optEq (r.accentBeats, e["accentBeats"]), name + " accents");
        CHECK (near (r.meanError, num (e["meanError"]), tol) && near (r.spread, num (e["spread"]), tol), name + " mean and spread");
        CHECK (near (r.fullMs, num (e["fullMs"]), tol) && near (r.zeroMs, num (e["zeroMs"]), tol), name + " judged windows");
        CHECK (Scoring::band (r.spread) == e["band"].toString().toStdString(), name + " band");
        auto* errs = e["errors"].getArray();
        bool errorsOk = errs && errs->size() == (int) r.errors.size();
        for (int k = 0; errorsOk && k < errs->size(); ++k)
            errorsOk = (*errs)[k].isVoid() ? ! r.errors[(size_t) k] : (r.errors[(size_t) k] && near (*r.errors[(size_t) k], num ((*errs)[k]), tol));
        CHECK (errorsOk, name + " every note's error");
        auto* extras = e["extraOffsets"].getArray();
        bool extrasOk = extras && extras->size() == (int) r.extraOffsets.size();
        for (int k = 0; extrasOk && k < extras->size(); ++k) extrasOk = near (r.extraOffsets[(size_t) k], num ((*extras)[k]), tol);
        CHECK (extrasOk, name + " extra offsets");
        ++runs;
    }
    for (auto& c : *V["doubles"].getArray())
    {
        std::vector<Onset> picks;
        for (auto& p : *c["picks"].getArray()) picks.push_back ({ num (p[0]), (float) num (p[1]) });
        auto kept = Scoring::dropDoubles (picks, num (c["within"]), (float) num (c["ratio"]));
        auto* want = c["expect"].getArray();
        bool ok = want && want->size() == (int) kept.size();
        for (int k = 0; ok && k < want->size(); ++k) ok = near (kept[(size_t) k].time, num ((*want)[k][0]), tol) && near (kept[(size_t) k].strength, num ((*want)[k][1]), tol);
        CHECK (ok, "doubles: " + c["name"].toString().toStdString());
    }
    for (auto& c : *V["accuracy"].getArray())
    {
        std::vector<std::optional<double>> errors;
        std::vector<double> gaps;
        for (auto& x : *c["errors"].getArray()) errors.push_back (x.isVoid() ? std::nullopt : std::optional<double> (num (x)));
        for (auto& x : *c["gaps"].getArray()) gaps.push_back (num (x));
        const double a = Scoring::accuracy (errors, gaps, 0, errors.size(), (int) c["extras"], *config);
        CHECK (near (a, num (c["expect"]), tol), "cycle accuracy");
    }
    for (auto& c : *V["credit"].getArray())
    {
        auto w = config->windows (num (c["gap"]));
        CHECK (near (w.full, num (c["fullMs"]), tol) && near (w.zero, num (c["zeroMs"]), tol), "windows at a gap");
        CHECK (near (config->credit (num (c["errorMs"]), num (c["gap"])), num (c["expect"]), tol), "credit");
    }
    for (auto& c : *V["calibration"].getArray())
    {
        std::vector<double> clicks, played;
        for (auto& x : *c["clicks"].getArray()) clicks.push_back (num (x));
        for (auto& x : *c["played"].getArray()) played.push_back (num (x));
        auto r = Scoring::calibration (clicks, played);
        if (c["expect"].isVoid()) CHECK (! r, "calibration: " + c["name"].toString().toStdString());
        else CHECK (r && near (r->offset, num (c["expect"]["offset"]), tol) && near (r->spread, num (c["expect"]["spread"]), tol)
                    && r->hits == (int) c["expect"]["hits"], "calibration: " + c["name"].toString().toStdString());
    }
    auto drills = Library::decodeDrills (juce::JSON::parse (repo().getChildFile ("catalog/exercises/right-hand.json")));
    CHECK (drills && drills->size() >= 9, "the catalog's drills decode");
    for (auto& c : *V["grid"].getArray())
    {
        const auto id = c["drill"].toString();
        const Drill* d = nullptr;
        for (auto& x : *drills) if (x.id == id) d = &x;
        CHECK (d != nullptr, ("grid drill " + id).toStdString());
        if (! d) continue;
        const double bpm = num (c["bpm"]);
        CHECK (near (d->shortestGap (bpm), num (c["shortestGap"]), tol) && near (d->window (bpm), num (c["window"]), tol), ("grid gap " + id).toStdString());
        auto notes = d->runNotes (bpm, num (c["start"]), num (c["seconds"]));
        auto* times = c["times"].getArray();
        bool ok = times && times->size() == (int) notes.size();
        for (int k = 0; ok && k < times->size(); ++k)
            ok = near (notes[(size_t) k].time, num ((*times)[k]), tol) && notes[(size_t) k].accent == (num (c["accents"][k]) != 0)
              && notes[(size_t) k].beat == (int) c["beats"][k];
        CHECK (ok, ("grid notes " + id + " at " + juce::String (bpm)).toStdString());
    }
    for (auto& c : *V["max"].getArray())
    {
        std::vector<SessionResult> list;
        for (auto& r : *c["runs"].getArray())
        {
            SessionResult s;
            s.exerciseID = r["exerciseID"].toString();
            s.date = *SessionResult::parseDate (r["date"].toString());
            s.topBPM = (int) r["topBPM"]; s.passed = (bool) r["passed"]; s.guided = (bool) r["guided"];
            list.push_back (s);
        }
        auto m = Stats::learnedTempo (list, "trip16x4");
        CHECK (c["expect"].isVoid() ? ! m : (m && *m == (int) c["expect"]), "max: " + c["name"].toString().toStdString());
    }
    std::cout << "  " << runs << " runs and every other case checked\n";
}

// ---------------------------------------------------------------- 2. the detector

static std::vector<float> picking (double sr, double seconds, const std::vector<double>& times, float amp = 0.5f)
{
    uint32_t seed = 7;
    auto rnd = [&] { seed = seed * 1664525u + 1013904223u; return (float) (int32_t) seed / (float) INT32_MAX; };
    std::vector<float> x ((size_t) (sr * seconds));
    for (auto& v : x) v = rnd() * 0.002f;
    for (double t : times)
    {
        const int start = (int) (t * sr);
        for (int k = 0; k < (int) (0.08 * sr) && start + k < (int) x.size(); ++k)
            x[(size_t) (start + k)] += amp * rnd() * (float) std::exp (-(double) k / sr * 40);
    }
    return x;
}

static void detector()
{
    std::cout << "Onset detector\n";
    const double sr = 48000;
    std::vector<double> times;
    for (double t = 0.5; t < 4.0; t += 0.125) times.push_back (t);
    auto x = picking (sr, 4.2, times);
    OnsetDetector d (sr);
    std::vector<Onset> found;
    for (size_t i = 0; i < x.size(); i += 4800)
    {
        const int n = (int) std::min<size_t> (4800, x.size() - i);
        d.process (x.data() + i, n, (double) i / sr, [&] (const Onset& o) { found.push_back (o); });
    }
    Onset last;
    if (d.flush (last)) found.push_back (last);
    CHECK (found.size() == times.size(), "finds every pick (" + std::to_string (found.size()) + " of " + std::to_string (times.size()) + ")");
    bool close = found.size() == times.size();
    for (size_t k = 0; close && k < times.size(); ++k) close = near (found[k].time, times[k], 0.002);
    CHECK (close, "each within 2 ms");

    OnsetDetector q (44100);
    auto silence = picking (44100, 3, {});
    auto none = q.process (silence, 0);
    CHECK (none.empty() && ! q.flush (last), "silence and noise give nothing");

    OnsetDetector a (sr), b (sr);
    auto oa = a.process (picking (sr, 1, { 0.2 }, 0.8f), 0); if (a.flush (last)) oa.push_back (last);
    auto ob = b.process (picking (sr, 1, { 0.2 }, 0.2f), 0); if (b.flush (last)) ob.push_back (last);
    CHECK (! oa.empty() && ! ob.empty() && oa[0].strength > ob[0].strength * 4, "accents are stronger");
}

// ---------------------------------------------------------------- 3. device picks under stress

class SlowFakeBackend : public DeviceBackend {
public:
    std::atomic<int> opens { 0 };
    juce::String lastOpened;
    juce::StringArray types() override { return { "Fake" }; }
    DeviceLists scan (const juce::String&) override
    {
        juce::Thread::sleep (150);
        DeviceLists l;
        for (int i = 0; i < 6; ++i) { l.inputs.add ("In " + juce::String (i)); l.outputs.add ("Out " + juce::String (i)); }
        return l;
    }
    OpenResult open (const DeviceSetup& s, juce::AudioIODeviceCallback*) override
    {
        juce::Thread::sleep (120);   // an ASIO driver taking its time
        ++opens;
        lastOpened = s.output;
        OpenResult r; r.ok = true; r.sampleRate = 48000; r.bufferSize = 128;
        return r;
    }
    void close() override { juce::Thread::sleep (30); }
};

static void deviceStress()
{
    std::cout << "Device picks under stress\n";
    auto backend = std::make_unique<SlowFakeBackend>();
    auto* fake = backend.get();
    DeviceController dc (std::move (backend), nullptr);
    std::atomic<int> changes { 0 };
    dc.onChange = [&] { ++changes; };
    dc.start();
    double worst = 0;
    const int picks = 400;
    DeviceSetup last;
    for (int i = 0; i < picks; ++i)
    {
        DeviceSetup s { "Fake", "In " + juce::String (i % 6), "Out " + juce::String (i % 6), i % 3 - 1 };
        const double t0 = juce::Time::getMillisecondCounterHiRes();
        dc.request (s);
        auto st = dc.state();   // what the screen reads on every repaint
        juce::ignoreUnused (st);
        worst = std::max (worst, juce::Time::getMillisecondCounterHiRes() - t0);
        last = s;
        if (i % 20 == 0) dc.rescan();
        juce::Thread::sleep (i % 7 == 0 ? 3 : 0);
    }
    CHECK (worst < 5.0, "no pick waits (worst " + std::to_string (worst) + " ms)");
    // wait for the worker to settle, never on the picks themselves
    for (int k = 0; k < 400 && dc.state().busy; ++k) juce::Thread::sleep (10);
    auto st = dc.state();
    CHECK (! st.busy && st.open, "settles open");
    CHECK (st.opened == last, "the newest pick is the one open (" + st.opened.output.toStdString() + ")");
    CHECK (fake->opens.load() < picks / 4, "picks in between are coalesced (" + std::to_string (fake->opens.load()) + " opens for " + std::to_string (picks) + " picks)");
    CHECK (st.requests == picks, "every pick was taken");
    CHECK (st.lists.count ("Fake") && st.lists["Fake"].inputs.size() == 6, "scans in the background");

    // The real Windows devices: open the default output a few times, quickly, through the same controller.
    AudioEngine engine;
    DeviceController real (std::make_unique<JuceDeviceBackend>(), &engine);
    real.start();
    real.rescan();
    for (int k = 0; k < 200 && (real.state().busy || real.state().types.isEmpty()); ++k) juce::Thread::sleep (10);
    auto rs = real.state();
    juce::String type = "Windows Audio";
    auto it = rs.lists.find (type);
    if (it == rs.lists.end() || it->second.outputs.isEmpty())
    {
        std::cout << "  (no Windows audio output on this computer: the real-device part is skipped)\n";
        return;
    }
    worst = 0;
    for (int i = 0; i < 30; ++i)
    {
        DeviceSetup s { i % 2 ? juce::String ("Windows Audio (Exclusive Mode)") : type, "", it->second.outputs[i % it->second.outputs.size()], -1 };
        const double t0 = juce::Time::getMillisecondCounterHiRes();
        real.request (s);
        worst = std::max (worst, juce::Time::getMillisecondCounterHiRes() - t0);
    }
    DeviceSetup final { type, "", it->second.outputs[0], -1 };
    real.request (final);
    for (int k = 0; k < 1000 && real.state().busy; ++k) juce::Thread::sleep (10);
    rs = real.state();
    CHECK (worst < 5.0, "real devices: no pick waits (worst " + std::to_string (worst) + " ms)");
    CHECK (! rs.busy && rs.opened == final, "real devices: the newest pick is the one open");
    std::cout << "  real device: " << (rs.open ? "open, " : "not open, ") << rs.opened.output << " at " << rs.info.sampleRate
              << " Hz, buffer " << rs.info.bufferSize << (rs.error.isNotEmpty() ? (" (" + rs.error + ")") : juce::String()) << "\n";
    real.closeDevice();
}

// ---------------------------------------------------------------- 4. sync with the drill server

static SessionResult makeRun (const juce::String& drill, int bpm, bool passed)
{
    SessionResult r;
    r.id = SessionResult::newID();
    r.date = juce::Time::getCurrentTime();
    r.exerciseID = drill; r.exerciseName = drill; r.mode = "cycles";
    r.startBPM = bpm; r.topBPM = bpm; r.seconds = 32; r.cycles = 4; r.notes = 112; r.hits = 110; r.missed = 2;
    r.score = passed ? 91 : 70; r.accuracyPercent = r.score; r.passed = passed; r.appVersion = PRACTICE_VERSION;
    r.scoringVersion = 2; r.fullMs = 18; r.zeroMs = 60; r.doubles = 1; r.extraOffsetsMs = { -22, 31 }; r.device = "TEST";
    return r;
}

static void syncTests()
{
    std::cout << "Sync with the drill server\n";
    // results in the phone's shape
    auto r = makeRun ("trip16x4", 120, true);
    const auto json = juce::JSON::toString (r.toVar(), true);
    const auto sent = juce::JSON::parse (json)["date"].toString();
    CHECK (sent.length() == 20 && sent.endsWith ("Z") && sent[10] == 'T' && ! sent.contains ("."),
           "dates go out with whole seconds, as the phone reads them (" + sent.toStdString() + ")");
    auto back = SessionResult::fromVar (juce::JSON::parse (json));
    CHECK (back && back->id == r.id && back->score == r.score && back->extraOffsetsMs.size() == 2, "a result round-trips");
    CHECK (r.id == r.id.toUpperCase() && r.id.length() == 36, "ids are upper-case UUIDs, like the phone's");

    auto scratch = juce::File::getSpecialLocation (juce::File::tempDirectory).getChildFile ("practice-sync-" + juce::Uuid().toDashedString());
    scratch.createDirectory();
    AppPaths paths; paths.data = scratch.getChildFile ("app"); paths.data.createDirectory(); paths.resources = repo();
    History history (paths.data.getChildFile ("runs.json"));
    const int port = 47000 + juce::Random::getSystemRandom().nextInt (900);
    const juce::String base = "http://127.0.0.1:" + juce::String (port);
    SyncWorker sync (history, [base] { return base; }, paths, "0.0.1");
    sync.catalogVersion = [] { return 0; };
    sync.voiceVersion = [] { return 999; };

    // offline: two runs wait in the queue
    history.add (makeRun ("trip16x4", 116, true));
    history.add (makeRun ("trip16x4", 124, true));
    sync.runOnceForTest();
    CHECK (sync.snapshot().reachable == false, "offline is offline");
    CHECK (history.pendingCount() == 2, "offline runs wait in the queue");

    // the server comes up
    auto data = scratch.getChildFile ("server");
    data.createDirectory();
    juce::ChildProcess server;
    const bool started = server.start (juce::StringArray { "node", repo().getChildFile ("desktop/tests/serve.mjs").getFullPathName(), juce::String (port), data.getFullPathName() });
    CHECK (started, "the drill server starts (node on the PATH)");
    if (! started) return;
    for (int k = 0; k < 100 && ! DrillServer::get (base + "/health", 500).ok(); ++k) juce::Thread::sleep (50);

    sync.runOnceForTest();
    auto snap = sync.snapshot();
    CHECK (snap.reachable == true, "reaches the server");
    CHECK (history.pendingCount() == 0, "the queue empties once the server holds the runs");
    CHECK (snap.serverRuns.size() == 2, "the server's list has them (" + std::to_string (snap.serverRuns.size()) + ")");
    CHECK (snap.levels.count ("trip16x4") && snap.levels["trip16x4"] == 116, "his max comes back from the server");
    CHECK (snap.catalog == DrillServer::Pull::updated && paths.catalogCache().getChildFile ("index.json").existsAsFile(), "the catalog is pulled when newer");

    // a run made "on the phone" appears in the desktop's list; sending the same run twice keeps it once
    auto phone = makeRun ("alt16", 140, true);
    phone.device = {};
    CHECK (DrillServer::send (base, { phone }).contains (phone.id), "a phone-shaped run is taken");
    auto again = DrillServer::send (base, { phone });
    sync.runOnceForTest();
    snap = sync.snapshot();
    CHECK (again.contains (phone.id) && snap.serverRuns.size() == 3, "a run is kept once, and the phone's run is in the desktop's list");
    bool hasDevice = false;
    for (auto& s : snap.serverRuns) hasDevice |= s.device == "TEST";
    CHECK (hasDevice, "the desktop's runs say which computer they came from");

    // the server's own file: every run in the phone's shape (the phone's decoder needs these keys)
    auto lines = juce::StringArray::fromLines (data.getChildFile ("sessions.jsonl").loadFileAsString());
    lines.removeEmptyStrings();
    bool phoneShape = lines.size() == 3;
    for (auto& l : lines)
    {
        auto v = juce::JSON::parse (l);
        for (auto key : { "id", "date", "exerciseID", "exerciseVersion", "exerciseName", "mode", "ladderStep", "guided", "startBPM", "topBPM",
                          "seconds", "cycles", "notes", "hits", "missed", "extra", "pct20", "pct40", "tightMs", "closeMs", "meanErrorMs",
                          "spreadMs", "toleranceMs", "targetPercent", "accuracyPercent", "score", "passed", "appVersion" })
            phoneShape &= v.hasProperty (key);
    }
    CHECK (phoneShape, "every stored run carries every key the phone's SessionResult needs");

    // the update check
    auto releases = data.getChildFile ("releases");
    releases.createDirectory();
    releases.getChildFile ("latest.json").replaceWithText ("{\"version\":\"9.9.9\",\"file\":\"Practice-Setup-9.9.9.exe\"}");
    releases.getChildFile ("Practice-Setup-9.9.9.exe").replaceWithText ("not really an installer");
    sync.runOnceForTest();
    snap = sync.snapshot();
    CHECK (snap.update["version"].toString() == "9.9.9", "a newer desktop build is seen");
    auto dl = scratch.getChildFile ("dl.exe");
    CHECK (DrillServer::download (base + "/desktop/Practice-Setup-9.9.9.exe", dl) && dl.getSize() > 0, "the installer downloads");

    server.kill();
    scratch.deleteRecursively();
}

int main()
{
    juce::ScopedJuceInitialiser_GUI init;   // the real-device part needs the message manager
    scoringParity();
    detector();
    deviceStress();
    syncTests();
    std::cout << "\n" << (checks - failures) << " of " << checks << " checks passed" << (failures ? ", FAILED\n" : "\n");
    return failures ? 1 : 0;
}
