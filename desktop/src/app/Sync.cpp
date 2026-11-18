#include "Sync.h"

namespace practice {

namespace DrillServer {

Response get (const juce::String& url, int timeoutMs)
{
    Response r;
    auto opts = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inAddress)
                    .withConnectionTimeoutMs (timeoutMs).withStatusCode (&r.status).withNumRedirectsToFollow (2);
    if (auto s = juce::URL (url).createInputStream (opts)) r.body = s->readEntireStreamAsString();
    return r;
}

Response post (const juce::String& url, const juce::String& json, int timeoutMs)
{
    Response r;
    auto opts = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inPostData)
                    .withConnectionTimeoutMs (timeoutMs).withStatusCode (&r.status)
                    .withExtraHeaders ("Content-Type: application/json");
    if (auto s = juce::URL (url).withPOSTData (json).createInputStream (opts)) r.body = s->readEntireStreamAsString();
    return r;
}

bool download (const juce::String& url, const juce::File& to, int timeoutMs)
{
    int status = 0;
    auto opts = juce::URL::InputStreamOptions (juce::URL::ParameterHandling::inAddress)
                    .withConnectionTimeoutMs (timeoutMs).withStatusCode (&status);
    auto s = juce::URL (url).createInputStream (opts);
    if (! s || status != 200) return false;
    to.getParentDirectory().createDirectory();
    auto tmp = to.getSiblingFile (to.getFileName() + ".part");
    tmp.deleteFile();
    {
        juce::FileOutputStream out (tmp);
        if (! out.openedOk() || out.writeFromInputStream (*s, -1) <= 0) return false;
    }
    return tmp.moveFileTo (to);
}

juce::StringArray send (const juce::String& base, const std::vector<SessionResult>& runs)
{
    juce::StringArray stored;
    if (runs.empty()) return stored;
    juce::Array<juce::var> list;
    for (auto& r : runs) list.add (r.toVar());
    auto* o = new juce::DynamicObject();
    o->setProperty ("sessions", list);
    auto res = post (base + "/api/sessions", juce::JSON::toString (juce::var (o), true));
    if (! res.ok()) return stored;
    auto v = juce::JSON::parse (res.body);
    if (auto* ids = v["stored"].getArray()) for (auto& id : *ids) stored.add (id.toString());
    return stored;
}

std::optional<std::vector<SessionResult>> sessions (const juce::String& base)
{
    auto res = get (base + "/api/sessions");
    if (! res.ok()) return std::nullopt;
    auto v = juce::JSON::parse (res.body);
    auto* list = v["sessions"].getArray();
    if (! list) return std::nullopt;
    std::vector<SessionResult> out;
    for (auto& s : *list) if (auto r = SessionResult::fromVar (s)) out.push_back (*r);
    return out;
}

std::optional<std::map<juce::String, int>> levels (const juce::String& base)
{
    auto res = get (base + "/api/levels");
    if (! res.ok()) return std::nullopt;
    auto v = juce::JSON::parse (res.body);
    auto* obj = v["levels"].getDynamicObject();
    if (! obj) return std::nullopt;
    std::map<juce::String, int> out;
    for (auto& p : obj->getProperties())
    {
        auto m = p.value.getProperty ("max", p.value.getProperty ("bpm", juce::var()));
        if (m.isInt() || m.isDouble() || m.isInt64()) out[p.name.toString()] = (int) m;
    }
    return out;
}

Pull pullCatalog (const juce::String& base, const juce::File& cache, int have)
{
    auto idx = get (base + "/catalog/index.json");
    if (! idx.ok()) return Pull::unreachable;
    auto index = juce::JSON::parse (idx.body);
    if (! index.isObject() || (int) index.getProperty ("schema", 1) > Library::supportedSchema || ! index["files"].isArray()) return Pull::invalid;
    const int version = (int) index.getProperty ("version", 0);
    if (version <= have) return Pull::upToDate;
    auto tmp = cache.getSiblingFile ("catalog-" + juce::Uuid().toDashedString());
    tmp.createDirectory();
    tmp.getChildFile ("index.json").replaceWithText (idx.body);
    for (auto& f : *index["files"].getArray())
    {
        const auto path = f["path"].toString(), kind = f["kind"].toString();
        if (path.contains ("..") || path.startsWith ("/")) { tmp.deleteRecursively(); return Pull::invalid; }
        auto r = get (base + "/catalog/" + path);
        if (! r.ok()) { tmp.deleteRecursively(); return Pull::unreachable; }
        auto v = juce::JSON::parse (r.body);
        const bool good = kind == "exercises" ? Library::decodeDrills (v).has_value()
                        : kind == "zones" ? TempoZones::fromVar (v).has_value()
                        : kind == "scoring" ? scoringFromVar (v).has_value() : true;
        if (! good) { tmp.deleteRecursively(); return Pull::invalid; }
        auto dest = tmp.getChildFile (path);
        dest.getParentDirectory().createDirectory();
        dest.replaceWithText (r.body);
    }
    cache.deleteRecursively();
    return tmp.moveFileTo (cache) ? Pull::updated : Pull::invalid;
}

bool pullVoice (const juce::String& base, const juce::File& cache, int have)
{
    auto idx = get (base + "/voice/index.json", 5000);
    if (! idx.ok()) return false;
    auto v = juce::JSON::parse (idx.body);
    if ((int) v.getProperty ("schema", 1) > 1 || (int) v.getProperty ("version", 0) <= have) return false;
    auto pack = cache.getChildFile ("pack.bin.new");
    if (! download (base + "/voice/pack.bin", pack, 30000)) return false;
    cache.createDirectory();
    pack.moveFileTo (cache.getChildFile ("pack.bin"));
    return cache.getChildFile ("index.json").replaceWithText (idx.body);
}

} // namespace DrillServer

bool versionNewer (const juce::String& a, const juce::String& b)
{
    auto pa = juce::StringArray::fromTokens (a, ".", ""), pb = juce::StringArray::fromTokens (b, ".", "");
    for (int i = 0; i < std::max (pa.size(), pb.size()); ++i)
    {
        const int x = pa[i].getIntValue(), y = pb[i].getIntValue();
        if (x != y) return x > y;
    }
    return false;
}

SyncWorker::SyncWorker (History& h, std::function<juce::String()> b, AppPaths p, juce::String v)
    : juce::Thread ("Practice sync"), history (h), base (std::move (b)), paths (std::move (p)), appVersion (std::move (v))
{
    // The server's copy from the last time it was reached, for Progress before the first sync.
    auto cached = juce::JSON::parse (paths.data.getChildFile ("server-runs.json"));
    if (auto* a = cached.getArray()) for (auto& s : *a) if (auto r = SessionResult::fromVar (s)) snap.serverRuns.push_back (*r);
    auto lv = juce::JSON::parse (paths.data.getChildFile ("levels.json"));
    if (auto* o = lv.getDynamicObject()) for (auto& kv : o->getProperties()) snap.levels[kv.name.toString()] = (int) kv.value;
    snap.pending = history.pendingCount();
}

SyncWorker::~SyncWorker() { signalThreadShouldExit(); notify(); stopThread (15000); }

void SyncWorker::start (int intervalMs) { interval = intervalMs; startThread(); }
void SyncWorker::kick() { notify(); }

SyncWorker::Snapshot SyncWorker::snapshot() const
{
    std::lock_guard<std::mutex> g (lock);
    return snap;
}

void SyncWorker::runOnceForTest() { pass(); }

void SyncWorker::run()
{
    while (! threadShouldExit())
    {
        pass();
        if (onChange) onChange();
        wait (interval);
    }
}

void SyncWorker::pass()
{
    const auto b = base();
    bool reached = false;
    // 1. the queue
    auto list = history.pending();
    bool sendFailed = false;
    for (size_t i = 0; i < list.size(); i += 50)
    {
        std::vector<SessionResult> chunk (list.begin() + (long) i, list.begin() + (long) std::min (list.size(), i + 50));
        auto stored = DrillServer::send (b, chunk);
        if (stored.isEmpty()) { sendFailed = true; break; }
        history.markUploaded (stored);
        reached = true;
    }
    // 2. every run from every device, and his max per drill
    auto runs = sendFailed ? std::nullopt : DrillServer::sessions (b);
    auto lv = runs ? DrillServer::levels (b) : std::nullopt;
    if (runs)
    {
        reached = true;
        juce::Array<juce::var> a;
        for (auto& r : *runs) a.add (r.toVar());
        paths.data.getChildFile ("server-runs.json").replaceWithText (juce::JSON::toString (juce::var (a), true));
    }
    if (lv)
    {
        auto* o = new juce::DynamicObject();
        for (auto& [k, v] : *lv) o->setProperty (k, v);
        paths.data.getChildFile ("levels.json").replaceWithText (juce::JSON::toString (juce::var (o), true));
    }
    // 3. the catalog and the voice
    auto pull = reached ? DrillServer::pullCatalog (b, paths.catalogCache(), catalogVersion ? catalogVersion() : 0) : DrillServer::Pull::unreachable;
    const bool voice = reached && DrillServer::pullVoice (b, paths.voiceCache(), voiceVersion ? voiceVersion() : 0);
    // 4. a newer desktop build
    juce::var update;
    if (reached)
    {
        auto u = DrillServer::get (b + "/desktop/latest.json", 4000);
        auto v = juce::JSON::parse (u.body);
        if (u.ok() && v["version"].isString() && versionNewer (v["version"].toString(), appVersion)) update = v;
    }
    std::lock_guard<std::mutex> g (lock);
    snap.reachable = reached;
    if (reached) snap.lastSync = juce::Time::getCurrentTime();
    if (runs) snap.serverRuns = *runs;
    if (lv) snap.levels = *lv;
    snap.pending = history.pendingCount();
    snap.catalog = pull;
    snap.catalogChanged = pull == DrillServer::Pull::updated;
    snap.voiceChanged = voice;
    snap.update = update;
}

} // namespace practice
