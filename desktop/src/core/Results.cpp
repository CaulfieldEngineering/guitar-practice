#include "Results.h"
#include <algorithm>
#include <ctime>

namespace practice {

juce::String SessionResult::isoDate (juce::Time t)
{
    // UTC, whole seconds, "Z": what Swift's .iso8601 strategy writes and reads.
    const std::time_t s = (std::time_t) (t.toMilliseconds() / 1000);
    std::tm tm {};
   #if JUCE_WINDOWS
    gmtime_s (&tm, &s);
   #else
    gmtime_r (&s, &tm);
   #endif
    char buf[32];
    std::strftime (buf, sizeof (buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return buf;
}

std::optional<juce::Time> SessionResult::parseDate (const juce::String& s)
{
    if (s.length() < 19) return std::nullopt;
    auto t = juce::Time::fromISO8601 (s);
    if (t.toMilliseconds() == 0) return std::nullopt;
    return t;
}

juce::String SessionResult::newID()
{
    return juce::Uuid().toDashedString().toUpperCase();
}

juce::var SessionResult::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("schema", schema);
    o->setProperty ("id", id);
    o->setProperty ("date", isoDate (date));
    o->setProperty ("exerciseID", exerciseID);
    o->setProperty ("exerciseVersion", exerciseVersion);
    o->setProperty ("exerciseName", exerciseName);
    o->setProperty ("mode", mode);
    o->setProperty ("ladderStep", ladderStep);
    o->setProperty ("guided", guided);
    o->setProperty ("startBPM", startBPM);
    o->setProperty ("topBPM", topBPM);
    o->setProperty ("seconds", seconds);
    o->setProperty ("cycles", cycles);
    o->setProperty ("notes", notes);
    o->setProperty ("hits", hits);
    o->setProperty ("missed", missed);
    o->setProperty ("extra", extra);
    o->setProperty ("pct20", pct20);
    o->setProperty ("pct40", pct40);
    o->setProperty ("tightMs", tightMs);
    o->setProperty ("closeMs", closeMs);
    o->setProperty ("meanErrorMs", meanErrorMs);
    o->setProperty ("spreadMs", spreadMs);
    o->setProperty ("toleranceMs", toleranceMs);
    o->setProperty ("targetPercent", targetPercent);
    o->setProperty ("accuracyPercent", accuracyPercent);
    if (sustainedSeconds) o->setProperty ("sustainedSeconds", *sustainedSeconds);
    o->setProperty ("score", score);
    o->setProperty ("passed", passed);
    if (accentsPercent) o->setProperty ("accentsPercent", *accentsPercent);
    if (offsetMs) o->setProperty ("offsetMs", *offsetMs);
    o->setProperty ("appVersion", appVersion);
    if (scoringVersion) o->setProperty ("scoringVersion", *scoringVersion);
    if (fullMs) o->setProperty ("fullMs", *fullMs);
    if (zeroMs) o->setProperty ("zeroMs", *zeroMs);
    if (doubles) o->setProperty ("doubles", *doubles);
    juce::Array<juce::var> offs;
    for (int x : extraOffsetsMs) offs.add (x);
    o->setProperty ("extraOffsetsMs", offs);
    if (device.isNotEmpty()) o->setProperty ("device", device);
    return juce::var (o);
}

static bool isNum (const juce::var& v) { return v.isInt() || v.isInt64() || v.isDouble(); }

std::optional<SessionResult> SessionResult::fromVar (const juce::var& v)
{
    if (! v.isObject() || ! v["id"].isString() || ! v["exerciseID"].isString() || ! v["date"].isString()
        || ! isNum (v["startBPM"]) || ! v["mode"].isString())
        return std::nullopt;
    auto date = parseDate (v["date"].toString());
    if (! date) return std::nullopt;
    SessionResult r;
    auto i = [&] (const char* k, int d) { auto x = v[k]; return isNum (x) ? (int) x : d; };
    auto n = [&] (const char* k, double d) { auto x = v[k]; return isNum (x) ? (double) x : d; };
    r.schema = i ("schema", 1);
    r.id = v["id"].toString();
    r.date = *date;
    r.exerciseID = v["exerciseID"].toString();
    r.exerciseVersion = i ("exerciseVersion", 1);
    r.exerciseName = v["exerciseName"].toString();
    r.mode = v["mode"].toString();
    r.ladderStep = i ("ladderStep", 0);
    r.guided = v["guided"].isBool() ? (bool) v["guided"] : false;
    r.startBPM = i ("startBPM", 0);
    r.topBPM = i ("topBPM", r.startBPM);
    r.seconds = n ("seconds", 0);
    r.cycles = i ("cycles", 0); r.notes = i ("notes", 0); r.hits = i ("hits", 0); r.missed = i ("missed", 0);
    r.extra = i ("extra", 0); r.pct20 = i ("pct20", 0); r.pct40 = i ("pct40", 0);
    r.tightMs = n ("tightMs", 20); r.closeMs = n ("closeMs", 40);
    r.meanErrorMs = n ("meanErrorMs", 0); r.spreadMs = n ("spreadMs", 0); r.toleranceMs = n ("toleranceMs", 0);
    r.targetPercent = i ("targetPercent", 85); r.accuracyPercent = i ("accuracyPercent", 0);
    if (isNum (v["sustainedSeconds"])) r.sustainedSeconds = (double) v["sustainedSeconds"];
    r.score = i ("score", 0);
    r.passed = v["passed"].isBool() ? (bool) v["passed"] : false;
    if (isNum (v["accentsPercent"])) r.accentsPercent = (int) v["accentsPercent"];
    if (isNum (v["offsetMs"])) r.offsetMs = (double) v["offsetMs"];
    r.appVersion = v["appVersion"].toString();
    if (isNum (v["scoringVersion"])) r.scoringVersion = (int) v["scoringVersion"];
    if (isNum (v["fullMs"])) r.fullMs = (double) v["fullMs"];
    if (isNum (v["zeroMs"])) r.zeroMs = (double) v["zeroMs"];
    if (isNum (v["doubles"])) r.doubles = (int) v["doubles"];
    if (auto* a = v["extraOffsetsMs"].getArray()) for (auto& x : *a) if (isNum (x)) r.extraOffsetsMs.push_back ((int) x);
    r.device = v["device"].toString();
    return r;
}

namespace Stats {

std::vector<Best> bests (const std::vector<SessionResult>& results)
{
    std::map<juce::String, Best> map;
    for (auto& r : results)
    {
        if (r.guided) continue;
        const auto key = r.exerciseID + "|" + r.mode + "|" + juce::String (r.startBPM);
        auto it = map.find (key);
        if (it == map.end()) map[key] = { r.exerciseID, r.mode, r.startBPM, r.bestValue(), 1, r.date };
        else { auto& b = it->second; b.value = std::max (b.value, r.bestValue()); b.runs++; if (r.date > b.last) b.last = r.date; }
    }
    std::vector<Best> out;
    for (auto& [k, b] : map) out.push_back (b);
    std::sort (out.begin(), out.end(), [] (const Best& a, const Best& b) {
        if (a.exerciseID != b.exerciseID) return a.exerciseID < b.exerciseID;
        if (a.mode != b.mode) return a.mode < b.mode;
        return a.bpm < b.bpm;
    });
    return out;
}

std::optional<double> best (const std::vector<SessionResult>& results, const juce::String& id, const juce::String& mode, int bpm)
{
    for (auto& b : bests (results)) if (b.exerciseID == id && b.mode == mode && b.bpm == bpm) return b.value;
    return std::nullopt;
}

std::optional<int> learnedTempo (const std::vector<SessionResult>& results, const juce::String& id, int recent, int step)
{
    std::vector<const SessionResult*> solo;
    for (auto& r : results) if (r.exerciseID == id && ! r.guided) solo.push_back (&r);
    std::stable_sort (solo.begin(), solo.end(), [] (auto* a, auto* b) { return a->date > b->date; });
    if ((int) solo.size() > recent) solo.resize ((size_t) recent);
    std::vector<int> passed;
    for (auto* r : solo) if (r->passed) passed.push_back (r->topBPM);
    std::sort (passed.begin(), passed.end(), std::greater<int>());
    if (passed.size() >= 2) return passed[1];
    if (passed.size() == 1) return std::max (20, passed[0] - step);
    return std::nullopt;
}

std::optional<int> fastestPass (const std::vector<SessionResult>& results, const juce::String& id)
{
    std::optional<int> best;
    for (auto& r : results) if (r.exerciseID == id && ! r.guided && r.passed) best = std::max (best.value_or (0), r.topBPM);
    return best;
}

} // namespace Stats

namespace Library {

std::optional<std::vector<Drill>> decodeDrills (const juce::var& file)
{
    if (! file.isObject() || (int) file.getProperty ("schema", 1) > supportedSchema) return std::nullopt;
    auto* list = file["exercises"].getArray();
    if (! list) return std::nullopt;
    std::vector<Drill> out;
    for (auto& e : *list)
        if (auto d = Drill::fromVar (e); d && d->schema <= supportedSchema) out.push_back (*d);
    return out;
}

std::optional<CatalogContents> read (const juce::File& folder)
{
    auto indexFile = folder.getChildFile ("index.json");
    if (! indexFile.existsAsFile()) return std::nullopt;
    auto index = juce::JSON::parse (indexFile);
    if (! index.isObject() || (int) index.getProperty ("schema", 1) > supportedSchema || ! index["files"].isArray()) return std::nullopt;
    CatalogContents c;
    c.version = (int) index.getProperty ("version", 0);
    for (auto& f : *index["files"].getArray())
    {
        const auto path = f["path"].toString(), kind = f["kind"].toString();
        if (path.contains ("..") || path.startsWith ("/")) return std::nullopt;
        auto file = folder.getChildFile (path);
        if (! file.existsAsFile()) continue;
        auto v = juce::JSON::parse (file);
        if (kind == "exercises") { if (auto list = decodeDrills (v)) for (auto& d : *list) c.drills.push_back (d); }
        else if (kind == "zones") { if (auto z = TempoZones::fromVar (v)) c.zones = z; }
        else if (kind == "scoring") { if (auto s = scoringFromVar (v)) c.scoring = s; }
    }
    return c;
}

CatalogContents load (const juce::File& bundled, const juce::File& cached, const juce::File& user)
{
    CatalogContents out;
    std::vector<juce::String> order;
    std::map<juce::String, Drill> byID;
    auto add = [&] (const std::vector<Drill>& list) {
        for (auto& d : list) { if (! byID.count (d.id)) order.push_back (d.id); byID[d.id] = d; }
    };
    for (auto& folder : { bundled, cached })
        if (auto c = read (folder))
        {
            add (c->drills);
            if (c->zones) out.zones = c->zones;
            if (c->scoring) out.scoring = c->scoring;
            out.version = std::max (out.version, c->version);
        }
    if (user.isDirectory())
    {
        auto files = user.findChildFiles (juce::File::findFiles, false, "*.json");
        files.sort();
        for (auto& f : files) if (auto list = decodeDrills (juce::JSON::parse (f))) add (*list);
    }
    for (auto& id : order) if (! byID[id].timedBlocks) out.drills.push_back (byID[id]);
    if (out.drills.empty()) out.drills.push_back (Drill::fallback());
    if (! out.zones) out.zones = TempoZones::standard();
    if (! out.scoring) out.scoring = ScoringConfig {};
    return out;
}

} // namespace Library
} // namespace practice
