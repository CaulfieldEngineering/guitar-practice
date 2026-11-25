#include "Routines.h"
#include "Sync.h"
#include "../core/Results.h"

namespace practice {

static juce::String isoMs (juce::Time t)
{
    auto s = SessionResult::isoDate (t);   // UTC, whole seconds, "...Z"
    return s.dropLastCharacters (1) + "." + juce::String (t.getMilliseconds()).paddedLeft ('0', 3) + "Z";
}

static juce::Time parseTime (const juce::String& s)
{
    auto t = juce::Time::fromISO8601 (s);
    if (t.toMilliseconds() != 0) return t;
    if (auto p = SessionResult::parseDate (s)) return *p;
    return juce::Time (0);
}

static int intOr (const juce::var& v, const char* k, int d) { auto x = v[k]; return x.isInt() || x.isInt64() || x.isDouble() ? (int) x : d; }

// ---- DrillSetup ----

juce::var DrillSetup::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("bpm", bpm);
    o->setProperty ("guided", guided);
    o->setProperty ("audioInput", audioInput);
    o->setProperty ("session", session.toVar());
    return juce::var (o);
}

DrillSetup DrillSetup::fromVar (const juce::var& v)
{
    DrillSetup d;
    d.bpm = intOr (v, "bpm", 100);
    d.guided = v["guided"].isBool() && (bool) v["guided"];
    d.audioInput = v["audioInput"].isBool() ? (bool) v["audioInput"] : true;
    d.session = SessionSettings::fromVar (v["session"]);
    return d;
}

// ---- RoutineBlock ----

juce::String RoutineBlock::kindName (Kind k)
{
    switch (k) { case Kind::warmup: return "warmup"; case Kind::drill: return "drill"; case Kind::rest: return "rest"; case Kind::free: return "free"; case Kind::custom: return "custom"; }
    return "custom";
}

juce::String RoutineBlock::kindTitle (Kind k)
{
    switch (k) { case Kind::warmup: return "Warm-up"; case Kind::drill: return "Drill"; case Kind::rest: return "Break"; case Kind::free: return "Open practice"; case Kind::custom: return "Block"; }
    return "Block";
}

juce::String RoutineBlock::title (const std::vector<Drill>& drills) const
{
    if (name.isNotEmpty()) return name;
    if (kind == Kind::drill)
    {
        for (auto& d : drills) if (d.id == drillID) return d.tableName();
        return "Drill";
    }
    return kindTitle (kind);
}

double RoutineBlock::estimate (const std::vector<Drill>& drills) const
{
    if (kind != Kind::drill || ! drill) return seconds;
    const auto& s = drill->session;
    switch (s.kind)
    {
        case SessionSettings::Kind::duration: return s.seconds;
        case SessionSettings::Kind::challenge: return s.capSeconds > 0 ? std::min (s.capSeconds, s.seconds * 3 / 2) : s.seconds * 3 / 2;
        case SessionSettings::Kind::endurance: return 300;
        case SessionSettings::Kind::cycles:
        {
            int beats = 8;
            for (auto& d : drills) if (d.id == drillID) beats = d.cycleBeats;
            return std::max (1, s.cycles) * beats * 60.0 / std::max (1, drill->bpm);
        }
    }
    return seconds;
}

juce::var RoutineBlock::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("id", id);
    o->setProperty ("kind", kindName (kind));
    o->setProperty ("name", name);
    o->setProperty ("seconds", seconds);
    o->setProperty ("click", click);
    o->setProperty ("bpm", bpm);
    if (drillID.isNotEmpty()) o->setProperty ("drillID", drillID);
    if (drill) o->setProperty ("drill", drill->toVar());
    return juce::var (o);
}

RoutineBlock RoutineBlock::fromVar (const juce::var& v)
{
    RoutineBlock b;
    if (v["id"].isString()) b.id = v["id"].toString();
    const auto k = v["kind"].toString();
    b.kind = k == "drill" ? Kind::drill : k == "rest" ? Kind::rest : k == "free" ? Kind::free : k == "warmup" ? Kind::warmup : Kind::custom;
    b.name = v["name"].toString();
    b.seconds = intOr (v, "seconds", 180);
    b.click = v["click"].isBool() && (bool) v["click"];
    b.bpm = intOr (v, "bpm", 80);
    b.drillID = v["drillID"].toString();
    if (v["drill"].isObject()) b.drill = DrillSetup::fromVar (v["drill"]);
    return b;
}

RoutineBlock RoutineBlock::make (Kind k, const std::vector<Drill>& drills)
{
    RoutineBlock b;
    b.kind = k;
    switch (k)
    {
        case Kind::warmup: b.seconds = 180; b.click = true; b.bpm = 80; break;
        case Kind::rest: b.seconds = 60; break;
        case Kind::free: b.seconds = 300; b.bpm = 90; break;
        case Kind::custom: b.seconds = 120; break;
        case Kind::drill:
            if (! drills.empty())
            {
                b.drillID = drills.front().id;
                DrillSetup d;
                d.bpm = drills.front().tempo.start;
                d.session.kind = SessionSettings::Kind::duration;
                d.session.seconds = 300;
                b.drill = d;
            }
            break;
    }
    return b;
}

// ---- PracticeRoutine ----

double PracticeRoutine::estimate (const std::vector<Drill>& drills) const
{
    double t = 0;
    for (auto& b : blocks) t += b.estimate (drills) + RoutineClock::countdownSeconds;
    return t;
}

PracticeRoutine PracticeRoutine::duplicate() const
{
    auto r = *this;
    r.id = juce::Uuid().toDashedString();
    r.name = name + " copy";
    r.starter = false;
    r.updatedAt = juce::Time::getCurrentTime();
    for (auto& b : r.blocks) b.id = juce::Uuid().toDashedString();
    return r;
}

juce::var PracticeRoutine::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("id", id);
    o->setProperty ("updatedAt", isoMs (updatedAt));
    if (deleted) { o->setProperty ("deleted", true); return juce::var (o); }
    o->setProperty ("name", name);
    juce::Array<juce::var> a;
    for (auto& b : blocks) a.add (b.toVar());
    o->setProperty ("blocks", a);
    return juce::var (o);
}

std::optional<PracticeRoutine> PracticeRoutine::fromVar (const juce::var& v)
{
    if (! v.isObject() || ! v["id"].isString()) return std::nullopt;
    PracticeRoutine r;
    r.id = v["id"].toString().toLowerCase();
    r.updatedAt = parseTime (v["updatedAt"].toString());
    r.deleted = v["deleted"].isBool() && (bool) v["deleted"];
    r.starter = v["starter"].isBool() && (bool) v["starter"];
    r.name = v["name"].toString();
    if (auto* a = v["blocks"].getArray()) for (auto& b : *a) r.blocks.push_back (RoutineBlock::fromVar (b));
    return r;
}

std::vector<PracticeRoutine> PracticeRoutine::merge (const std::vector<PracticeRoutine>& a, const std::vector<PracticeRoutine>& b)
{
    std::vector<PracticeRoutine> out;
    auto add = [&] (const PracticeRoutine& r) {
        for (auto& x : out)
            if (x.id == r.id)
            {
                if (r.updatedAt > x.updatedAt || (r.updatedAt == x.updatedAt && x.starter && ! r.starter)) x = r;
                return;
            }
        out.push_back (r);
    };
    for (auto& r : a) add (r);
    for (auto& r : b) add (r);
    return out;
}

// ---- RoutineRunRecord ----

juce::var RoutineRunRecord::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("schema", 1);
    o->setProperty ("id", id);
    o->setProperty ("date", SessionResult::isoDate (date));
    o->setProperty ("routineID", routineID);
    o->setProperty ("routineName", routineName);
    o->setProperty ("seconds", seconds);
    o->setProperty ("completed", completed);
    if (device.isNotEmpty()) o->setProperty ("device", device);
    if (appVersion.isNotEmpty()) o->setProperty ("appVersion", appVersion);
    juce::Array<juce::var> a;
    for (auto& b : blocks)
    {
        auto* x = new juce::DynamicObject();
        x->setProperty ("kind", b.kind); x->setProperty ("name", b.name); x->setProperty ("seconds", b.seconds);
        x->setProperty ("skipped", b.skipped);
        if (b.sessionID.isNotEmpty()) x->setProperty ("sessionID", b.sessionID);
        if (b.accuracy) x->setProperty ("accuracy", *b.accuracy);
        if (b.startBPM) x->setProperty ("startBPM", *b.startBPM);
        if (b.topBPM) x->setProperty ("topBPM", *b.topBPM);
        a.add (juce::var (x));
    }
    o->setProperty ("blocks", a);
    return juce::var (o);
}

std::optional<RoutineRunRecord> RoutineRunRecord::fromVar (const juce::var& v)
{
    if (! v.isObject() || ! v["id"].isString() || ! v["routineName"].isString()) return std::nullopt;
    RoutineRunRecord r;
    r.id = v["id"].toString();
    r.date = parseTime (v["date"].toString());
    r.routineID = v["routineID"].toString();
    r.routineName = v["routineName"].toString();
    r.device = v["device"].toString();
    r.appVersion = v["appVersion"].toString();
    r.seconds = (double) v["seconds"];
    r.completed = v["completed"].isBool() && (bool) v["completed"];
    if (auto* a = v["blocks"].getArray())
        for (auto& x : *a)
        {
            Block b;
            b.kind = x["kind"].toString(); b.name = x["name"].toString(); b.seconds = (double) x["seconds"];
            b.skipped = x["skipped"].isBool() && (bool) x["skipped"];
            b.sessionID = x["sessionID"].toString();
            if (! x["accuracy"].isVoid()) b.accuracy = (int) x["accuracy"];
            if (! x["startBPM"].isVoid()) b.startBPM = (int) x["startBPM"];
            if (! x["topBPM"].isVoid()) b.topBPM = (int) x["topBPM"];
            r.blocks.push_back (b);
        }
    return r;
}

// ---- RoutineStore ----

RoutineStore::RoutineStore (juce::File data, juce::File bundledCatalog)
    : file (data.getChildFile ("routines.json")), runsFile (data.getChildFile ("routine-runs.json")), bundled (bundledCatalog)
{
    auto v = juce::JSON::parse (file);
    if (auto* a = v["routines"].getArray()) for (auto& x : *a) if (auto r = PracticeRoutine::fromVar (x)) all.push_back (*r);
    if (auto* d = v["dirty"].getArray()) for (auto& x : *d) dirty.insert (x.toString());
    std::vector<PracticeRoutine> starters;
    auto s = juce::JSON::parse (bundled.getChildFile ("starter-routines.json"));
    if (auto* a = s["routines"].getArray()) for (auto& x : *a) if (auto r = PracticeRoutine::fromVar (x)) { r->starter = true; starters.push_back (*r); }
    all = PracticeRoutine::merge (starters, all);
    auto rv = juce::JSON::parse (runsFile);
    if (auto* a = rv["runs"].getArray()) for (auto& x : *a) if (auto r = RoutineRunRecord::fromVar (x)) runList.push_back (*r);
    if (auto* a = rv["sent"].getArray()) for (auto& x : *a) sent.insert (x.toString());
}

void RoutineStore::persist() const
{
    file.getParentDirectory().createDirectory();
    juce::Array<juce::var> a, d;
    for (auto& r : all) if (! r.starter) a.add (r.toVar());
    for (auto& x : dirty) d.add (x);
    auto* o = new juce::DynamicObject();
    o->setProperty ("routines", a);
    o->setProperty ("dirty", d);
    file.replaceWithText (juce::JSON::toString (juce::var (o)));
    juce::Array<juce::var> ra, sa;
    for (auto& r : runList) ra.add (r.toVar());
    for (auto& x : sent) sa.add (x);
    auto* ro = new juce::DynamicObject();
    ro->setProperty ("runs", ra);
    ro->setProperty ("sent", sa);
    runsFile.replaceWithText (juce::JSON::toString (juce::var (ro)));
}

std::vector<PracticeRoutine> RoutineStore::routines() const
{
    std::lock_guard<std::mutex> g (lock);
    std::vector<PracticeRoutine> out;
    for (auto& r : all) if (! r.deleted) out.push_back (r);
    return out;
}

std::optional<PracticeRoutine> RoutineStore::routine (const juce::String& id) const
{
    std::lock_guard<std::mutex> g (lock);
    for (auto& r : all) if (r.id == id && ! r.deleted) return r;
    return std::nullopt;
}

void RoutineStore::save (PracticeRoutine r)
{
    std::lock_guard<std::mutex> g (lock);
    r.updatedAt = juce::Time::getCurrentTime();
    r.starter = false;
    bool found = false;
    for (auto& x : all) if (x.id == r.id) { x = r; found = true; }
    if (! found) all.push_back (r);
    dirty.insert (r.id);
    persist();
}

void RoutineStore::remove (const juce::String& id)
{
    std::lock_guard<std::mutex> g (lock);
    for (auto& x : all)
        if (x.id == id) { x.deleted = true; x.starter = false; x.updatedAt = juce::Time::getCurrentTime(); dirty.insert (id); }
    persist();
}

std::optional<PracticeRoutine> RoutineStore::duplicate (const juce::String& id)
{
    auto r = routine (id);
    if (! r) return std::nullopt;
    auto c = r->duplicate();
    save (c);
    return c;
}

PracticeRoutine RoutineStore::newRoutine (const std::vector<Drill>& drills)
{
    PracticeRoutine r;
    r.name = "New routine";
    r.blocks = { RoutineBlock::make (RoutineBlock::Kind::warmup, drills), RoutineBlock::make (RoutineBlock::Kind::drill, drills) };
    save (r);
    return r;
}

void RoutineStore::addRun (const RoutineRunRecord& r)
{
    std::lock_guard<std::mutex> g (lock);
    runList.insert (runList.begin(), r);
    persist();
}

std::vector<RoutineRunRecord> RoutineStore::runs() const
{
    std::lock_guard<std::mutex> g (lock);
    return runList;
}

bool RoutineStore::sync (const juce::String& base)
{
    std::vector<PracticeRoutine> changed;
    std::vector<RoutineRunRecord> unsent;
    {
        std::lock_guard<std::mutex> g (lock);
        for (auto& r : all) if (dirty.count (r.id)) changed.push_back (r);
        for (auto& r : runList) if (! sent.count (r.id)) unsent.push_back (r);
    }
    juce::Array<juce::var> a;
    for (auto& r : changed) a.add (r.toVar());
    auto* o = new juce::DynamicObject();
    o->setProperty ("routines", a);
    auto res = DrillServer::post (base + "/api/routines", juce::JSON::toString (juce::var (o), true));
    if (! res.ok()) return false;
    std::vector<PracticeRoutine> remote;
    if (auto* list = juce::JSON::parse (res.body)["routines"].getArray())
        for (auto& x : *list) if (auto r = PracticeRoutine::fromVar (x)) remote.push_back (*r);
    juce::StringArray stored;
    if (! unsent.empty())
    {
        juce::Array<juce::var> ra;
        for (auto& r : unsent) ra.add (r.toVar());
        auto* ro = new juce::DynamicObject();
        ro->setProperty ("runs", ra);
        auto rr = DrillServer::post (base + "/api/routine-runs", juce::JSON::toString (juce::var (ro), true));
        if (rr.ok()) if (auto* ids = juce::JSON::parse (rr.body)["stored"].getArray()) for (auto& x : *ids) stored.add (x.toString());
    }
    std::vector<RoutineRunRecord> theirs;
    auto got = DrillServer::get (base + "/api/routine-runs");
    if (got.ok()) if (auto* list = juce::JSON::parse (got.body)["runs"].getArray())
        for (auto& x : *list) if (auto r = RoutineRunRecord::fromVar (x)) theirs.push_back (*r);
    std::lock_guard<std::mutex> g (lock);
    all = PracticeRoutine::merge (all, remote);
    for (auto& r : changed) dirty.erase (r.id);
    for (auto& s : stored) sent.insert (s);
    for (auto& t : theirs)
    {
        sent.insert (t.id);
        bool have = false;
        for (auto& r : runList) if (r.id.equalsIgnoreCase (t.id)) have = true;
        if (! have) runList.push_back (t);
    }
    std::sort (runList.begin(), runList.end(), [] (const RoutineRunRecord& x, const RoutineRunRecord& y) { return x.date > y.date; });
    synced = juce::Time::getCurrentTime();
    persist();
    return true;
}

} // namespace practice
