#include "Model.h"
#include <algorithm>
#include <cmath>
#include <set>

namespace practice {

juce::String formatClock (double seconds)
{
    const int s = std::max (0, (int) std::round (seconds));
    return juce::String (s / 60) + ":" + juce::String (s % 60).paddedLeft ('0', 2);
}

static juce::var sessionVar (const SessionSettings& s) { return s.toVar(); }

Model::Model (AppPaths p, bool offline)
    : paths (std::move (p)),
      settings (paths.data.getChildFile ("settings.json")),
      history (paths.data.getChildFile ("runs.json"))
{
    engine.setResources (paths.guitar());
    reloadCatalog();
    voice.load (paths.voiceBundled(), paths.voiceCache());

    drillID = settings.get ("drill").toString();
    if (std::none_of (drills.begin(), drills.end(), [this] (const Drill& d) { return d.id == drillID; })) drillID = drills.front().id;
    loadDrillSettings();
    metroBPM = settings.getInt ("metro.bpm", 100);
    metroBeats = settings.getInt ("metro.beats", 4);
    metroSub = settings.getInt ("metro.sub", 1);
    metroAccent = settings.getBool ("metro.accent", true);
    gridClicks = settings.getBool ("click", true);
    voiceCues = settings.getBool ("voiceCues", false);
    engine.clickGain = (float) settings.getDouble ("clickGain", 1.0);
    engine.guitarGain = (float) settings.getDouble ("guitarGain", 0.7);
    engine.hearGuitar = false;   // never kept on: monitoring is off until he turns it on (latency)

    auto backend = std::make_unique<JuceDeviceBackend>();
    auto* raw = backend.get();
    deviceController = std::make_unique<DeviceController> (std::move (backend), &engine);
    raw->onDeviceListChanged = [this] { deviceController->rescan(); };
    deviceController->onChange = [this] {
        juce::MessageManager::callAsync ([this] { device = deviceController->state(); deviceChanged(); });
    };
    engine.onDeviceError = [this] (juce::String) { juce::MessageManager::callAsync ([this] { deviceController->rescan(); }); };
    deviceSetup = DeviceSetup::fromVar (settings.get ("device"));
    deviceController->start();
    if (deviceSetup.type.isNotEmpty()) deviceController->request (deviceSetup);
    else deviceController->rescan();

    sync = std::make_unique<SyncWorker> (history, [this] { return settings.serverBase(); }, paths, appVersion());
    sync->catalogVersion = [this] { return catalogVersion; };
    sync->voiceVersion = [this] { return voice.version(); };
    syncState = sync->snapshot();
    sync->onChange = [this] {
        juce::MessageManager::callAsync ([this] {
            syncState = sync->snapshot();
            if (syncState.catalogChanged) { reloadCatalog(); catalogNote = "Drills updated"; }
            else if (syncState.reachable == false) catalogNote = "Offline. Using saved drills.";
            else if (syncState.catalog == DrillServer::Pull::invalid) catalogNote = "Couldn't read drills. Using saved drills.";
            else catalogNote = {};
            if (syncState.voiceChanged) voice.load (paths.voiceBundled(), paths.voiceCache());
            maybeDownloadUpdate();
            sendChangeMessage();
        });
    };
    if (! offline) sync->start (30000);
    startTimerHz (60);
}

Model::~Model()
{
    stopTimer();
    sync.reset();
    deviceController.reset();
    settings.save();
}

juce::String Model::computerName() const { return juce::SystemStats::getComputerName(); }

// ---------------------------------------------------------------- catalog

void Model::reloadCatalog()
{
    auto c = Library::load (paths.catalogBundled(), paths.catalogCache(), paths.catalogUser());
    drills = c.drills;
    zones = c.zones.value_or (TempoZones::standard());
    scoring = c.scoring.value_or (ScoringConfig {});
    auto cached = Library::read (paths.catalogCache());
    auto bundled = Library::read (paths.catalogBundled());
    catalogVersion = std::max (cached ? cached->version : 0, bundled ? bundled->version : 0);
}

const Drill& Model::drill() const
{
    for (auto& d : drills) if (d.id == drillID) return d;
    return drills.front();
}

void Model::select (const juce::String& id)
{
    if (id == drillID || phase != Phase::ready) return;
    drillID = id;
    settings.set ("drill", id);
    message = {};
    loadDrillSettings();
    sendChangeMessage();
}

void Model::loadDrillSettings()
{
    loading = true;
    const auto& d = drill();
    auto v = settings.get ("drill." + d.id);
    bpm = v.hasProperty ("bpm") ? (int) v["bpm"] : d.tempo.start;
    session = v.hasProperty ("session") ? SessionSettings::fromVar (v["session"], d.session) : d.session;
    guided = v.hasProperty ("guided") ? (bool) v["guided"] : true;
    intro = v.hasProperty ("intro") ? (bool) v["intro"] : true;
    resume = v.hasProperty ("resume") ? (bool) v["resume"] : true;
    audioInput = v.hasProperty ("audioInput") ? (bool) v["audioInput"] : true;
    zoneChoice = v["zone"].toString();
    loading = false;
}

void Model::saveDrillSettings()
{
    if (loading) return;
    auto* o = new juce::DynamicObject();
    o->setProperty ("bpm", bpm);
    o->setProperty ("session", sessionVar (session));
    o->setProperty ("guided", guided);
    o->setProperty ("intro", intro);
    o->setProperty ("resume", resume);
    o->setProperty ("audioInput", audioInput);
    o->setProperty ("zone", zoneChoice);
    settings.set ("drill." + drill().id, juce::var (o));
    sendChangeMessage();
}

void Model::setBPM (int v)
{
    const auto& t = drill().tempo;
    v = juce::jlimit (t.min, t.max, v);
    if (v == bpm) return;
    bpm = v;
    saveDrillSettings();
}
void Model::nudgeTempo (int v) { if (resume) resume = false; setBPM (v); saveDrillSettings(); }
void Model::chooseZone (const juce::String& id) { zoneChoice = id; resume = true; saveDrillSettings(); }
void Model::setManual (bool manual) { resume = ! manual; saveDrillSettings(); }
void Model::apply (const Level& l) { resume = false; setBPM (l.bpm); if (l.session) session = *l.session; saveDrillSettings(); }
void Model::setSession (const SessionSettings& s) { session = s; saveDrillSettings(); }
void Model::setGuided (bool g) { guided = g; saveDrillSettings(); }
void Model::setIntro (bool on) { intro = on; saveDrillSettings(); }
void Model::setAudioInput (bool on) { audioInput = on; message = {}; saveDrillSettings(); }
void Model::setGridClicks (bool on) { gridClicks = on; settings.set ("click", on); sendChangeMessage(); }
void Model::setVoiceCues (bool on) { voiceCues = on; settings.set ("voiceCues", on); sendChangeMessage(); }

std::optional<int> Model::level (const juce::String& idIn) const
{
    const auto id = idIn.isNotEmpty() ? idIn : drill().id;
    auto it = syncState.levels.find (id);
    if (it != syncState.levels.end()) return it->second;
    int step = 4;
    for (auto& d : drills) if (d.id == id) step = d.tempo.stepOnPass;
    return Stats::learnedTempo (allRuns(), id, 10, step);
}

const TempoZones::Zone* Model::activeZone() const
{
    if (zoneChoice.isNotEmpty()) if (auto* z = zones.zone (zoneChoice)) return z;
    return zones.suggested (session);
}

juce::String Model::zoneLine() const
{
    auto m = level();
    auto* z = activeZone();
    if (! m || ! z) return {};
    auto r = TempoZones::range (*z, *m);
    return z->name + " " + z->title + juce::String (juce::CharPointer_UTF8 (" \xc2\xb7 ")) + juce::String ((int) z->low)
         + juce::String (juce::CharPointer_UTF8 ("\xe2\x80\x93")) + juce::String ((int) z->high) + "% of max " + juce::String (*m)
         + juce::String (juce::CharPointer_UTF8 (" \xe2\x86\x92 ")) + juce::String (r.first) + juce::String (juce::CharPointer_UTF8 ("\xe2\x80\x93"))
         + juce::String (r.second) + " bpm";
}

int Model::startTempo() const
{
    if (resume)
        if (auto m = level())
            if (auto* z = activeZone())
                return juce::jlimit (drill().tempo.min, drill().tempo.max, zones.start (*z, *m));
    return bpm;
}

// ---------------------------------------------------------------- devices

void Model::pickDevice (const DeviceSetup& s)
{
    deviceSetup = s;
    settings.set ("device", s.toVar());
    deviceController->request (s);   // never waits
    sendChangeMessage();
}

void Model::deviceChanged()
{
    // First start with nothing picked: the lowest-latency kind there is. A real ASIO driver first, then WASAPI in
    // exclusive mode, which falls back to shared mode by itself if the device refuses it.
    if (deviceSetup.type.isEmpty() && ! device.lists.empty() && ! device.busy)
    {
        DeviceSetup s;
        auto asio = device.lists.find ("ASIO");
        if (asio != device.lists.end())
            for (auto& n : asio->second.outputs)
                if (! n.containsIgnoreCase ("ASIO4ALL") && ! n.containsIgnoreCase ("Generic") && ! n.containsIgnoreCase ("FL Studio")
                    && ! n.containsIgnoreCase ("Realtek") && ! n.containsIgnoreCase ("built-in")) { s = { "ASIO", n, n, -1 }; break; }
        if (s.type.isEmpty())
        {
            auto ex = device.lists.find ("Windows Audio (Exclusive Mode)");
            if (ex != device.lists.end() && ! ex->second.outputs.isEmpty())
                s = { ex->first, ex->second.inputs.isEmpty() ? juce::String() : ex->second.inputs[0], ex->second.outputs[0], -1 };
        }
        if (s.type.isEmpty())
        {
            auto sh = device.lists.find ("Windows Audio");
            if (sh != device.lists.end() && ! sh->second.outputs.isEmpty())
                s = { sh->first, sh->second.inputs.isEmpty() ? juce::String() : sh->second.inputs[0], sh->second.outputs[0], -1 };
        }
        if (s.type.isNotEmpty()) pickDevice (s);
    }
    else if (! device.busy && ! device.open && device.opened == deviceSetup && deviceSetup.type == "Windows Audio (Exclusive Mode)"
             && ! settings.getBool ("device.explicit", false))
    {
        auto s = deviceSetup;
        s.type = "Windows Audio";
        message = "Exclusive mode was refused by the device; using shared mode.";
        pickDevice (s);
    }
    // A device change in the middle of a run holds it; Resume picks it up on the new device.
    const auto key = device.open ? device.opened.routeKey() : juce::String();
    if (key != lastOpenedKey)
    {
        if ((phase == Phase::running || phase == Phase::calibrating) && lastOpenedKey.isNotEmpty())
        {
            if (phase == Phase::running) { pause(); message = "Audio changed to " + routeName() + ". Resume when ready."; }
            else { stopRunAudio(); phase = Phase::ready; message = "Audio changed. Calibrate again on " + routeName() + "."; }
        }
        lastOpenedKey = key;
    }
    sendChangeMessage();
}

juce::String Model::routeName() const
{
    if (! device.open) return "No audio device";
    const auto& s = device.opened;
    if (s.input.isEmpty() || s.input == s.output) return s.output;
    return s.input + " in, " + s.output + " out";
}

bool Model::hasInput() const { return selfTestNoInput || (device.open && device.info.inputChannels > 0 && engine.inputChannelCount() > 0); }

void Model::debugPick (double planSeconds, float strength)
{
    const double sr = engine.sampleRate();
    engine.injectOnset ({ planSeconds + (double) origin / sr + shift(), strength });
}

double Model::latencyEstimate() const
{
    const auto& i = device.info;
    if (! device.open || i.sampleRate <= 0) return 0;
    return (double) (std::max (0, i.inputLatency) + std::max (0, i.outputLatency) + std::max (0, i.bufferSize)) / i.sampleRate;
}

std::optional<Calibration> Model::calibration() const
{
    return device.open ? settings.calibration (device.opened.routeKey()) : std::nullopt;
}

double Model::currentOffset() const
{
    auto c = calibration();
    return latencyEstimate() + (c ? c->residual : 0.0);
}

double Model::displayOffset() const { return settings.displayOffset (device.opened.outputKey()); }

void Model::setDisplayOffset (double s)
{
    settings.setDisplayOffset (device.opened.outputKey(), s);
    sendChangeMessage();
}

void Model::setMeterListening (bool on) { meterListening = on; }

void Model::testTone()
{
    toneBuffer = engine.makeTone (440, 1.0, -12);
    AudioEngine::Event e;
    e.frame = engine.framePosition() + (juce::int64) (0.05 * engine.sampleRate());
    e.buffer = toneBuffer.get();
    engine.push ({ e });
}

void Model::clickTest()
{
    std::vector<AudioEngine::Event> ev;
    const auto f0 = engine.framePosition() + (juce::int64) (0.05 * engine.sampleRate());
    for (int i = 0; i < 4; ++i)
    {
        AudioEngine::Event e;
        e.frame = f0 + (juce::int64) (i * 0.5 * engine.sampleRate());
        e.kind = i == 0 ? ClickKind::accent : ClickKind::beat;
        ev.push_back (e);
    }
    engine.push (ev);
}

void Model::setHearGuitar (bool on) { engine.hearGuitar = on; sendChangeMessage(); }

void Model::setSoundsGain (float g)
{
    engine.soundsGain = g;
    auto all = settings.get ("soundsGain");
    if (! all.isObject()) all = juce::var (new juce::DynamicObject());
    all.getDynamicObject()->setProperty (device.opened.outputKey(), g);
    settings.set ("soundsGain", all);
    sendChangeMessage();
}

float Model::soundsGain() const { return engine.soundsGain.load(); }

// ---------------------------------------------------------------- metronome

void Model::toggleMetronome()
{
    if (engine.metronomeRunning()) { engine.stopMetronome(); sendChangeMessage(); return; }
    if (phase != Phase::ready && phase != Phase::result) leave();   // one player: the metronome ends a drill
    engine.startMetronome (metroBPM, metroBeats, metroSub, metroAccent);
    sendChangeMessage();
}

void Model::setMetroBPM (int v)
{
    v = juce::jlimit (20, 400, v);
    if (v == metroBPM) return;
    metroBPM = v;
    settings.set ("metro.bpm", v);
    engine.setMetronome (metroBPM, metroBeats, metroSub, metroAccent);
    sendChangeMessage();
}
void Model::setMetroBeats (int b) { metroBeats = juce::jlimit (2, 7, b); settings.set ("metro.beats", metroBeats); engine.setMetronome (metroBPM, metroBeats, metroSub, metroAccent); sendChangeMessage(); }
void Model::setMetroSub (int s) { metroSub = juce::jlimit (1, 4, s); settings.set ("metro.sub", metroSub); engine.setMetronome (metroBPM, metroBeats, metroSub, metroAccent); sendChangeMessage(); }
void Model::setMetroAccent (bool a) { metroAccent = a; settings.set ("metro.accent", a); engine.setMetronome (metroBPM, metroBeats, metroSub, metroAccent); sendChangeMessage(); }

void Model::tap()
{
    const double t = juce::Time::getMillisecondCounterHiRes() / 1000.0;
    if (! taps.empty() && t - taps.back() > 2.0) taps.clear();
    taps.push_back (t);
    if (taps.size() > 5) taps.erase (taps.begin());
    if (taps.size() >= 2) setMetroBPM ((int) std::round (60.0 * (double) (taps.size() - 1) / (taps.back() - taps.front())));
}

// ---------------------------------------------------------------- the run

void Model::start() { begin (false); }
void Model::calibrate() { begin (true); }
void Model::nowSolo() { guided = false; saveDrillSettings(); start(); }
void Model::clearResult() { score.reset(); saved.reset(); unscored.reset(); phase = Phase::ready; sendChangeMessage(); }

bool Model::inputReady()
{
    if (! device.open) { message = "No audio device. Pick one in Audio settings."; return false; }
    if (! hasInput()) { message = "Pick an audio input to score."; return false; }
    return true;
}

void Model::begin (bool calibrating)
{
    message = {};
    const bool scored = audioInput || calibrating;
    if (scored && ! inputReady()) { sendChangeMessage(); return; }
    if (! device.open) { message = "No audio device. Pick one in Audio settings."; sendChangeMessage(); return; }
    if (engine.metronomeRunning()) engine.stopMetronome();
    if (! calibrating && intro)
    {
        auto parts = IntroText::parts (drill(), startTempo(), session, scored);
        introLine = voice.line (engine, parts);
        if (introLine)
        {
            AudioEngine::Event e;
            e.frame = engine.framePosition() + (juce::int64) (0.05 * engine.sampleRate());
            e.buffer = introLine.get();
            engine.push ({ e });
            introDeadline = juce::Time::getMillisecondCounterHiRes() + 1000.0 * ((double) introLine->samples.size() / engine.sampleRate() + 0.4);
            phase = Phase::intro;
            sendChangeMessage();
            return;
        }
    }
    launch (calibrating);
}

void Model::skipIntro()
{
    if (phase != Phase::intro) return;
    engine.stopVoices();
    introLine.reset();
    launch (false);
}

void Model::repeatIntro()
{
    auto line = voice.line (engine, IntroText::parts (drill(), startTempo(), session, audioInput));
    if (! line) return;
    voiceKeep.push_back (line);
    if (voiceKeep.size() > 4) voiceKeep.erase (voiceKeep.begin());
    AudioEngine::Event e;
    e.frame = engine.framePosition() + (juce::int64) (0.05 * engine.sampleRate());
    e.buffer = line.get();
    engine.push ({ e });
}

void Model::pushEvents (const std::vector<TimedEvent>& list)
{
    std::vector<AudioEngine::Event> ev;
    ev.reserve (list.size());
    for (auto& t : list)
    {
        if (! gridClicks && phase != Phase::calibrating && phase != Phase::syncing
            && (t.kind == ClickKind::accent || t.kind == ClickKind::beat)) continue;
        const auto frame = engine.frameAt (origin, t.time);
        if (t.pitch >= 0) { ev.push_back (engine.guideEvent (frame, t.pitch, t.kind == ClickKind::pluckAccent, t.up)); continue; }
        AudioEngine::Event e;
        e.frame = frame;
        e.kind = t.kind;
        ev.push_back (e);
    }
    engine.push (ev);
}

void Model::launch (bool calibrating)
{
    lastCueBeat = -1; lastCueBPM = 0;
    runDrill_ = drill();
    runSettings = session;
    runGuided = guided && ! calibrating;
    runScored = audioInput || calibrating;
    lastRunWasGuided = runGuided;
    lastRunWasScored = runScored;
    const double startBPM = calibrating ? 80.0 : (double) startTempo();
    levelUp.reset();
    runZoneMax = calibrating ? 0 : level().value_or (0);
    now = 0;
    currentBPM = startBPM;
    topBPM = (int) startBPM;
    slots.clear(); noteStart.clear(); notes.clear(); states.clear(); played.clear(); doubles = 0; errors.clear(); gaps.clear(); usedPlayed.clear();
    accuracies.clear(); lastPassed = runScored ? std::optional<bool>() : std::optional<bool> (true);
    rolling.reset(); lastCycleAccuracy.reset(); sustained = 0;
    score.reset(); saved.reset(); unscored.reset(); newBest = false;
    doneScheduling = false;
    plannedEnd.reset();
    const int beats = runDrill_.beatsPerBar;
    auto counted = RunBuilder::countIn (beats, startBPM);
    countInEnd = counted.end;
    countInUntil = counted.end;
    introEvents = counted.events;
    scheduledUntil = counted.end;

    engine.clearAll();
    origin = engine.framePosition() + (juce::int64) (0.12 * engine.sampleRate());
    runDevice = device.opened;
    phase = calibrating ? Phase::calibrating : Phase::running;
    std::vector<TimedEvent> first = counted.events;
    if (calibrating)
    {
        calibrationClicks.clear();
        for (int i = 0; i < calibrationCount; ++i) calibrationClicks.push_back (counted.end + i * 60.0 / startBPM);
        for (double t : calibrationClicks) { Note n; n.time = t; notes.push_back (n); }
        states.assign (notes.size(), NoteState::waiting);
        gaps = Scoring::gaps (calibrationClicks);
        plannedEnd = counted.end + calibrationCount * 60.0 / startBPM;
        for (int i = 0; i < calibrationCount; ++i)
            first.push_back ({ calibrationClicks[(size_t) i], i % beats == 0 ? ClickKind::accent : ClickKind::beat, i % beats });
        first.push_back ({ *plannedEnd + 0.05, ClickKind::done });
        doneScheduling = true;
    }
    else
    {
        switch (runSettings.kind)
        {
            case SessionSettings::Kind::duration: plannedEnd = counted.end + runSettings.seconds; break;
            default: plannedEnd.reset(); break;
        }
    }
    pushEvents (first);
    engine.setListening (runScored);
    engine.drainOnsets();
    if (! calibrating) scheduleAhead();
    sendChangeMessage();
}

void Model::scheduleAhead()
{
    bool added = false;
    while (! doneScheduling && scheduledUntil < now + 1.5)
    {
        const size_t k = slots.size();
        bool stopNow = false;
        switch (runSettings.kind)
        {
            case SessionSettings::Kind::cycles: stopNow = (int) k >= std::max (1, runSettings.cycles); break;
            case SessionSettings::Kind::duration: stopNow = scheduledUntil >= plannedEnd.value_or (0) - 1e-6; break;
            case SessionSettings::Kind::endurance: stopNow = scheduledUntil - countInEnd >= SessionSettings::enduranceCap; break;
        }
        if (stopNow)
        {
            doneScheduling = true;
            plannedEnd = scheduledUntil;
            pushEvents ({ { scheduledUntil + 0.05, ClickKind::done } });
            break;
        }
        const double bpmNow = k == 0 ? currentBPM
            : RunBuilder::nextBPM (slots[k - 1].bpm, lastPassed, runSettings.ladderStep, runDrill_.tempo.max);
        std::optional<double> limit;
        if (runSettings.kind == SessionSettings::Kind::duration) limit = plannedEnd;
        auto slot = RunBuilder::cycle (runDrill_, (int) k, scheduledUntil, bpmNow, runGuided, limit);
        slots.push_back (slot);
        noteStart.push_back ((int) notes.size());
        notes.insert (notes.end(), slot.notes.begin(), slot.notes.end());
        states.insert (states.end(), slot.notes.size(), NoteState::waiting);
        added = true;
        scheduledUntil = slot.end();
        if (slot.duration <= 1e-6) { doneScheduling = true; plannedEnd = scheduledUntil; break; }
        pushEvents (slot.events);
    }
    if (added)
    {
        std::vector<double> t;
        for (auto& n : notes) t.push_back (n.time);
        gaps = Scoring::gaps (t);
    }
}

double Model::window() const
{
    if (phase == Phase::calibrating) return 0.25;
    double fastest = currentBPM;
    for (auto& s : slots) fastest = std::max (fastest, s.bpm);
    return runDrill_.window (fastest);
}

double Model::shift() const { return phase == Phase::calibrating ? latencyEstimate() : currentOffset(); }

const CycleSlot* Model::currentSlot() const
{
    const CycleSlot* found = nullptr;
    for (auto& s : slots) if (s.start <= now) found = &s;
    return found;
}

std::optional<int> Model::cycleNumber() const
{
    if (auto* s = currentSlot()) return s->index + 1;
    return std::nullopt;
}

std::vector<double> Model::recentErrors() const
{
    std::vector<double> out;
    for (int i = (int) std::min (errors.size(), notes.size()) - 1; i >= 0 && out.size() < 12; --i)
        if (notes[(size_t) i].time <= now + 0.2 && errors[(size_t) i]) out.push_back (*errors[(size_t) i]);
    std::reverse (out.begin(), out.end());
    return out;
}

double Model::timingSpanMs() const { return scoring.windows (gaps.empty() ? 0.25 : gaps.back()).zero; }

std::optional<Model::GroupCue> Model::groupCue() const
{
    auto* s = currentSlot();
    if (phase != Phase::running || ! s || now >= s->end()) return std::nullopt;
    auto sizes = runDrill_.groupSizes();
    if (sizes.size() <= 1 || std::set<int> (sizes.begin(), sizes.end()).size() <= 1) return std::nullopt;
    const double beat = 60 / s->bpm;
    const int local = juce::jlimit (0, (int) sizes.size() - 1, (int) ((now - s->start) / beat));
    int k = 1;
    while (k < (int) sizes.size() && sizes[(size_t) ((local + k) % (int) sizes.size())] == sizes[(size_t) local]) ++k;
    return GroupCue { sizes[(size_t) local], sizes[(size_t) ((local + k) % (int) sizes.size())], k };
}

void Model::speakCues()
{
    if (! voiceCues || phase != Phase::running) return;
    auto* s = currentSlot();
    if (! s) return;
    auto say = [this] (VoicePart p) {
        auto line = voice.line (engine, { p });
        if (! line) return;
        voiceKeep.push_back (line);
        if (voiceKeep.size() > 6) voiceKeep.erase (voiceKeep.begin());
        AudioEngine::Event e;
        e.frame = engine.framePosition() + (juce::int64) (0.02 * engine.sampleRate());
        e.buffer = line.get();
        e.gain = 0.8f;
        engine.push ({ e });
    };
    if (s->bpm != lastCueBPM)
    {
        if (lastCueBPM > 0) say (IntroText::cue (s->bpm));
        lastCueBPM = s->bpm;
        return;
    }
    auto cue = groupCue();
    if (! cue || cue->beatsUntil != 1) return;
    const int beatIndex = (int) ((now - countInEnd) / (60 / s->bpm));
    if (beatIndex == lastCueBeat) return;
    lastCueBeat = beatIndex;
    say (IntroText::cue (cue->next));
}

void Model::timerCallback()
{
    if (phase == Phase::intro)
    {
        const bool done = ! introLine || ! introLine->playing.load();
        if ((done && juce::Time::getMillisecondCounterHiRes() > introDeadline - 300) || juce::Time::getMillisecondCounterHiRes() > introDeadline + 2000)
        {
            introLine.reset();
            launch (false);
        }
        return;
    }
    if (phase == Phase::running || phase == Phase::calibrating || phase == Phase::syncing)
    {
        frame();
        sendChangeMessage();
        return;
    }
    // the Audio screen's meter
    engine.setListening (false);
    if (meterListening || engine.metronomeRunning()) sendChangeMessage();
}

void Model::frame()
{
    if (! engine.running())
    {
        if (phase == Phase::running) { pause(); message = "The audio device stopped. Resume when it is back."; }
        else if (phase != Phase::paused) { stopRunAudio(); phase = Phase::ready; }
        return;
    }
    const double sr = engine.sampleRate();
    now = (engine.nowFrames() - (double) origin) / sr;
    if (phase == Phase::syncing)
    {
        if (plannedEnd && now > *plannedEnd + 0.4) endSync();
        return;
    }
    if (runScored)
    {
        const double within = window();
        const double base = (double) origin / sr + shift();
        for (auto& o : engine.drainOnsets())
            if (o.time > 0 && ! Scoring::addPick ({ o.time - base, o.strength }, played, within)) ++doubles;
    }
    if (phase == Phase::running) scheduleAhead();
    if (auto* s = currentSlot())
    {
        currentBPM = s->bpm;
        if (! runScored) topBPM = std::max (topBPM, (int) s->bpm);
    }
    if (runScored)
    {
        updateStates();
        if (phase == Phase::running) evaluateCycles();
        if (phase != Phase::running && phase != Phase::calibrating) return;
    }
    if (phase == Phase::running) speakCues();
    if (doneScheduling && plannedEnd && now > *plannedEnd + 0.4)
    {
        if (runScored) finish (false); else finishUnscored();
    }
}

void Model::updateStates()
{
    const double w = window();
    std::vector<double> exp, pl;
    for (auto& n : notes) exp.push_back (n.time);
    for (auto& p : played) pl.push_back (p.time);
    auto m = Scoring::match (exp, pl, w);
    usedPlayed.assign (played.size(), 0);
    errors.assign (notes.size(), std::nullopt);
    for (size_t i = 0; i < m.size(); ++i)
    {
        if (m[i])
        {
            usedPlayed[(size_t) *m[i]] = 1;
            errors[i] = (pl[(size_t) *m[i]] - exp[i]) * 1000;
            const double c = scoring.credit (*errors[i], i < gaps.size() ? gaps[i] : 1.0);
            states[i] = c >= 0.999 ? NoteState::tight : (c >= 0.5 ? NoteState::close : NoteState::loose);
        }
        else
            states[i] = notes[i].time + w < now ? NoteState::missed : NoteState::waiting;
    }
}

int Model::noteEnd (size_t i) const
{
    if (i + 1 < noteStart.size()) return noteStart[i + 1];
    return (int) notes.size();
}

void Model::evaluateCycles()
{
    const double w = window();
    while (accuracies.size() < slots.size())
    {
        const size_t k = accuracies.size();
        const auto& s = slots[k];
        if (! (now > s.end() + w + 0.05)) break;
        const int lo = noteStart[k], hi = noteEnd (k);
        if (hi > (int) errors.size() || hi > (int) gaps.size()) break;
        if (hi == lo) { accuracies.push_back (1); continue; }
        int extras = 0;
        for (size_t j = 0; j < played.size(); ++j)
            if (! usedPlayed[j] && played[j].time >= s.start - w / 2 && played[j].time < s.end() - w / 2) ++extras;
        const double acc = Scoring::accuracy (errors, gaps, (size_t) lo, (size_t) hi, extras, scoring);
        accuracies.push_back (acc);
        lastCycleAccuracy = acc;
        const bool passed = acc * 100 >= runSettings.targetPercent;
        lastPassed = passed;
        if (passed) topBPM = std::max (topBPM, (int) s.bpm);
        std::vector<int> counts;
        for (size_t i = 0; i < accuracies.size(); ++i) counts.push_back (noteEnd (i) - noteStart[i]);
        auto r = RunBuilder::rolling (accuracies, counts, runSettings.windowCycles);
        rolling = r ? r : std::optional<double> (accuracies.back());
        if (runSettings.kind == SessionSettings::Kind::endurance)
        {
            if (r)
            {
                if (*r * 100 >= runSettings.targetPercent) sustained = s.end() - countInEnd;
                else { finish (false); return; }
            }
            else if (passed) sustained = s.end() - countInEnd;
        }
    }
}

void Model::stopRunAudio()
{
    engine.clearAll();
    engine.setListening (false);
}

void Model::finishUnscored()
{
    stopRunAudio();
    const double end = std::min (now, plannedEnd.value_or (now));
    const double seconds = std::max (0.0, end - countInEnd);
    if (seconds < 1) { phase = Phase::ready; sendChangeMessage(); return; }
    int done = 0;
    for (auto& s : slots) if (s.end() <= now + 0.05) ++done;
    const int first = slots.empty() ? bpm : (int) slots.front().bpm;
    unscored = UnscoredRun { seconds, first, std::max (topBPM, first), done };
    settings.addUnscored (runDrill_.id, seconds);
    score.reset(); saved.reset();
    phase = Phase::result;
    sendChangeMessage();
}

void Model::finish (bool stoppedEarly)
{
    const bool wasCalibrating = phase == Phase::calibrating;
    const bool wasPaused = phase == Phase::paused;
    if (! wasPaused)
    {
        const double sr = engine.sampleRate(), within = window();
        const double base = (double) origin / sr + shift();
        for (auto& o : engine.drainOnsets())
            if (o.time > 0 && ! Scoring::addPick ({ o.time - base, o.strength }, played, within)) ++doubles;
    }
    stopRunAudio();
    if (wasCalibrating)
    {
        std::vector<double> pl;
        for (auto& p : played) pl.push_back (p.time);
        if (auto found = Scoring::calibration (calibrationClicks, pl))
        {
            Calibration c;
            c.residual = found->offset;
            c.measured = latencyEstimate() + found->offset;
            c.routeName = routeName();
            c.date = juce::Time::getCurrentTime();
            c.spreadMs = found->spread * 1000;
            c.hits = found->hits;
            settings.setCalibration (runDevice.routeKey(), c);
            message = "Calibrated for " + routeName() + ": " + juce::String ((int) std::round (c.measured * 1000)) + " ms from "
                    + juce::String (found->hits) + " notes, " + (*c.spreadMs < 15 ? "steady" : "uneven") + " (they varied by "
                    + juce::String ((int) std::round (*c.spreadMs)) + " ms)";
        }
        else
            message = "Not enough notes. Try again.";
        phase = Phase::ready;
        sendChangeMessage();
        return;
    }
    const bool isEndurance = runSettings.kind == SessionSettings::Kind::endurance;
    const size_t judged = isEndurance || stoppedEarly ? accuracies.size() : slots.size();
    const size_t upto = judged < noteStart.size() ? (size_t) noteStart[judged] : notes.size();
    std::vector<Note> counted (notes.begin(), notes.begin() + (long) std::min (upto, notes.size()));
    auto r = Scoring::score (counted, played, window(), runDrill_.scoring, scoring);
    score = r;
    double playedSeconds = 0;
    if (judged > 0) playedSeconds = slots[std::min (judged, slots.size()) - 1].end() - countInEnd;
    const int startBPM = slots.empty() ? bpm : (int) slots.front().bpm;
    SessionResult s;
    s.id = SessionResult::newID();
    s.date = juce::Time::getCurrentTime();
    s.exerciseID = runDrill_.id;
    s.exerciseVersion = runDrill_.version;
    s.exerciseName = runDrill_.name;
    s.mode = SessionSettings::kindName (runSettings.kind);
    s.ladderStep = runSettings.ladderStep;
    s.guided = runGuided;
    s.startBPM = startBPM;
    s.topBPM = topBPM;
    s.seconds = playedSeconds;
    s.cycles = (int) judged;
    s.notes = r.expected; s.hits = r.hits; s.missed = r.missed; s.extra = r.extra;
    s.pct20 = r.pct20(); s.pct40 = r.pct40();
    s.tightMs = runDrill_.scoring.tightMs; s.closeMs = runDrill_.scoring.closeMs;
    s.meanErrorMs = r.meanError; s.spreadMs = r.spread; s.toleranceMs = r.fullMs;
    s.targetPercent = runSettings.targetPercent;
    s.accuracyPercent = r.score;
    if (isEndurance) s.sustainedSeconds = sustained;
    s.score = r.score;
    s.passed = isEndurance ? sustained > 0 : r.passed();
    if (r.accentBeats && *r.accentBeats > 0) s.accentsPercent = (int) std::round (100.0 * r.accentsLanded.value_or (0) / *r.accentBeats);
    s.offsetMs = currentOffset() * 1000;
    s.appVersion = "desktop " + appVersion();
    s.scoringVersion = 2;
    s.fullMs = r.fullMs; s.zeroMs = r.zeroMs;
    s.doubles = doubles;
    for (size_t i = 0; i < r.extraOffsets.size() && i < 400; ++i) s.extraOffsetsMs.push_back ((int) std::round (r.extraOffsets[i]));
    s.device = computerName();

    newBest = false;
    auto before = allRuns();
    if (! runGuided) if (auto prev = Stats::best (before, s.exerciseID, s.mode, s.startBPM)) newBest = s.bestValue() > *prev;
    const auto levelBefore = level (s.exerciseID);
    if (r.expected > 0) history.add (s);
    if (auto after = level (s.exerciseID); after && *after > levelBefore.value_or (0) && ! runGuided)
        levelUp = std::make_pair (levelBefore.value_or (0), *after);
    sync->kick();
    saved = s;
    phase = Phase::result;
    sendChangeMessage();
}

void Model::stop()
{
    if (phase == Phase::intro) { engine.stopVoices(); introLine.reset(); phase = Phase::ready; sendChangeMessage(); return; }
    if (phase == Phase::syncing) { endSync(); return; }
    if (phase == Phase::running || phase == Phase::paused) { endRun(); return; }
    if (phase != Phase::calibrating) return;
    stopRunAudio();
    phase = Phase::ready;
    sendChangeMessage();
}

void Model::pause()
{
    if (phase != Phase::running) return;
    pausedAt = now;
    stopRunAudio();
    engine.drainOnsets();
    phase = Phase::paused;
    sendChangeMessage();
}

void Model::resumeRun()
{
    if (phase != Phase::paused) return;
    message = {};
    if (runScored && ! inputReady()) { sendChangeMessage(); return; }
    if (! device.open) { message = "No audio device. Pick one in Audio settings."; sendChangeMessage(); return; }
    const int beats = std::max (1, runDrill_.beatsPerBar);
    double from = pausedAt, floor = pausedAt;
    std::vector<TimedEvent> lead;
    const CycleSlot* in = nullptr;
    for (auto& s : slots) if (s.start <= pausedAt) in = &s;
    if (pausedAt < countInEnd)
    {
        from = 0; floor = 0; lead = introEvents; countInUntil = countInEnd;
    }
    else if (in && pausedAt < in->end() && ! in->notes.empty())
    {
        const double beat = 60 / std::max (1.0, in->bpm);
        from = in->start - beats * beat;
        floor = in->start;
        for (int i = 0; i < beats; ++i) lead.push_back ({ from + i * beat, ClickKind::countIn, i });
        const double cut = in->start - 0.02;
        played.erase (std::remove_if (played.begin(), played.end(), [cut] (const Onset& o) { return o.time >= cut; }), played.end());
        countInUntil = in->start;
    }
    std::vector<TimedEvent> events = lead;
    for (auto& s : slots) for (auto& e : s.events) if (e.time >= floor - 1e-6) events.push_back (e);
    if (doneScheduling) events.push_back ({ plannedEnd.value_or (scheduledUntil) + 0.05, ClickKind::done });
    engine.clearAll();
    origin = engine.framePosition() + (juce::int64) (0.12 * engine.sampleRate()) - (juce::int64) std::llround (from * engine.sampleRate());
    runDevice = device.opened;
    now = from;
    phase = Phase::running;
    pushEvents (events);
    engine.setListening (runScored);
    engine.drainOnsets();
    sendChangeMessage();
}

void Model::endRun()
{
    if (phase != Phase::running && phase != Phase::paused) return;
    if (! runScored) { finishUnscored(); return; }
    if (! accuracies.empty()) { finish (true); return; }
    stopRunAudio();
    phase = Phase::ready;
    sendChangeMessage();
}

void Model::leave()
{
    switch (phase)
    {
        case Phase::intro: case Phase::syncing: case Phase::calibrating: stop(); break;
        case Phase::running: case Phase::paused: endRun(); break;
        default: break;
    }
    engine.stopVoices();
    if (phase == Phase::result) clearResult();
}

void Model::startCalibration()
{
    if (phase != Phase::ready) return;
    if (! device.open) { message = "No audio device. Pick one in Audio settings."; sendChangeMessage(); return; }
    if (engine.metronomeRunning()) engine.stopMetronome();
    message = {};
    runDrill_ = drill();
    runSettings = session;
    runGuided = false; runScored = false;
    const double tempo = 80;
    currentBPM = tempo;
    slots.clear(); noteStart.clear(); played.clear(); doubles = 0; errors.clear(); gaps.clear(); usedPlayed.clear();
    accuracies.clear(); lastPassed.reset(); rolling.reset(); lastCycleAccuracy.reset(); sustained = 0;
    score.reset(); saved.reset(); unscored.reset(); newBest = false;
    countInEnd = 0; countInUntil = 0;
    const double beat = 60 / tempo;
    std::vector<TimedEvent> ev;
    notes.clear();
    for (int i = 0; i < 400; ++i)
    {
        const double t = 0.6 + i * beat;
        Note n; n.time = t; notes.push_back (n);
        ev.push_back ({ t, i % 4 == 0 ? ClickKind::accent : ClickKind::beat, i % 4 });
    }
    states.assign (notes.size(), NoteState::waiting);
    plannedEnd = notes.back().time + beat;
    doneScheduling = true;
    engine.clearAll();
    origin = engine.framePosition() + (juce::int64) (0.12 * engine.sampleRate());
    runDevice = device.opened;
    now = 0;
    phase = Phase::syncing;
    pushEvents (ev);
    sendChangeMessage();
}

void Model::endSync()
{
    stopRunAudio();
    phase = Phase::ready;
    sendChangeMessage();
}

void Model::calibrateInput()
{
    if (phase == Phase::syncing) endSync();
    calibrate();
}

// ---------------------------------------------------------------- progress, sync, updates

std::vector<SessionResult> Model::allRuns() const
{
    std::map<juce::String, SessionResult> byID;
    for (auto& r : syncState.serverRuns) byID[r.id.toLowerCase()] = r;
    for (auto& r : history.results()) byID[r.id.toLowerCase()] = r;
    std::vector<SessionResult> out;
    for (auto& [k, r] : byID) out.push_back (r);
    std::stable_sort (out.begin(), out.end(), [] (auto& a, auto& b) { return a.date > b.date; });
    return out;
}

void Model::syncNow() { sync->kick(); }

void Model::maybeDownloadUpdate()
{
    if (! syncState.update.isObject() || updateDownloading) return;
    const auto version = syncState.update["version"].toString();
    const auto file = syncState.update["file"].toString();
    if (version.isEmpty() || ! file.matchesWildcard ("Practice-Setup-*.exe", true) || version == updateVersion) return;
    updateDownloading = true;
    const auto url = settings.serverBase() + "/desktop/" + file;
    const auto dest = juce::File::getSpecialLocation (juce::File::tempDirectory).getChildFile (file);
    juce::Thread::launch ([this, url, dest, version] {
        const bool ok = DrillServer::download (url, dest, 60000);
        juce::MessageManager::callAsync ([this, ok, dest, version] {
            updateDownloading = false;
            if (ok) { updateFile = dest; updateVersion = version; }
            sendChangeMessage();
        });
    });
    sendChangeMessage();
}

void Model::installUpdate()
{
    if (! updateFile.existsAsFile()) return;
    leave();
    if (updateFile.startAsProcess ("/S /UPDATE")) juce::JUCEApplicationBase::quit();
}

// ---------------------------------------------------------------- made-up states for the screenshots

void Model::debugSeed (int which)
{
    phase = Phase::ready; message = {}; score.reset(); saved.reset(); unscored.reset(); levelUp.reset(); newBest = false;
    notes.clear(); states.clear(); errors.clear(); slots.clear(); noteStart.clear(); played.clear();
    if (which == 0) return;
    for (auto& d : drills) if (d.id == "trip16x4") runDrill_ = d;
    if (which == 4)
    {
        phase = Phase::syncing;
        for (int i = 0; i < 40; ++i) { Note n; n.time = 0.6 + i * 0.75; notes.push_back (n); }
        states.assign (notes.size(), NoteState::waiting);
        now = 4.1;
        return;
    }
    runSettings = runDrill_.session;
    runSettings.kind = SessionSettings::Kind::endurance;
    lastRunWasGuided = false; lastRunWasScored = true;
    runZoneMax = 150;
    const double bpmNow = 128;
    countInEnd = 60.0 / bpmNow * 4; countInUntil = countInEnd;
    juce::Random rnd (7);
    for (int k = 0; k < 6; ++k)
    {
        auto slot = RunBuilder::cycle (runDrill_, k, countInEnd + k * runDrill_.cycleBeats * 60.0 / bpmNow, bpmNow, false);
        noteStart.push_back ((int) notes.size());
        notes.insert (notes.end(), slot.notes.begin(), slot.notes.end());
        slots.push_back (slot);
    }
    states.assign (notes.size(), NoteState::waiting);
    now = slots[3].start + 1.2;
    currentBPM = bpmNow;
    std::vector<Onset> pl;
    for (auto& n : notes)
        if (n.time < now + 0.05)
        {
            const double e = rnd.nextFloat() < 0.04 ? 1.0 : (rnd.nextFloat() - 0.5) * 0.045 + 0.004;
            if (e < 0.5) pl.push_back ({ n.time + e, 1.0f });
        }
    played = pl;
    gaps.clear();
    { std::vector<double> t; for (auto& n : notes) t.push_back (n.time); gaps = Scoring::gaps (t); }
    if (which == 3)
    {
        std::vector<Note> counted;
        for (auto& n : notes) if (n.time < now) counted.push_back (n);
        auto r = Scoring::score (counted, played, runDrill_.window (bpmNow), runDrill_.scoring, scoring);
        score = r;
        SessionResult s;
        s.id = SessionResult::newID(); s.date = juce::Time::getCurrentTime(); s.exerciseID = runDrill_.id; s.exerciseName = runDrill_.name;
        s.mode = "endurance"; s.startBPM = 128; s.topBPM = 136; s.seconds = 96; s.cycles = 8; s.targetPercent = 85;
        s.sustainedSeconds = 72; s.score = r.score; s.accuracyPercent = r.score; s.passed = true;
        saved = s;
        newBest = true;
        levelUp = std::make_pair (132, 136);
        phase = Phase::result;
        return;
    }
    updateStates();
    rolling = 0.91; sustained = 72;
    phase = which == 2 ? Phase::paused : Phase::running;
}

} // namespace practice
