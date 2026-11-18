#include "Store.h"
#include <algorithm>

namespace practice {

juce::File AppPaths::guitar() const
{
    auto f = resources.getChildFile ("guitar");
    return f.isDirectory() ? f : resources.getChildFile ("ios/Practice/Resources/Guitar");
}

AppPaths AppPaths::find (const juce::File& dataOverride)
{
    AppPaths p;
    p.data = dataOverride != juce::File() ? dataOverride
           : juce::File::getSpecialLocation (juce::File::userApplicationDataDirectory).getChildFile ("Practice");
    p.data.createDirectory();
    // Installed: resources\ beside the program. A build in the repo: walk up to the folder holding catalog\.
    auto exe = juce::File::getSpecialLocation (juce::File::currentExecutableFile).getParentDirectory();
    if (exe.getChildFile ("resources/catalog/index.json").existsAsFile()) { p.resources = exe.getChildFile ("resources"); return p; }
    for (auto d = exe; d.getParentDirectory() != d; d = d.getParentDirectory())
        if (d.getChildFile ("catalog/index.json").existsAsFile() && d.getChildFile ("server").isDirectory()) { p.resources = d; return p; }
    p.resources = exe.getChildFile ("resources");
    return p;
}

// ---- settings ----

Settings::Settings (const juce::File& f) : file (f)
{
    root = juce::JSON::parse (file);
    if (! root.isObject()) root = juce::var (new juce::DynamicObject());
}

Settings::~Settings() { save(); }

juce::var Settings::get (const juce::String& key, const juce::var& dflt) const
{
    return root.hasProperty (key) ? root[juce::Identifier (key)] : dflt;
}

void Settings::set (const juce::String& key, const juce::var& value)
{
    root.getDynamicObject()->setProperty (key, value);
    dirty = true;
    save();
}

int Settings::getInt (const juce::String& key, int dflt) const { auto v = get (key); return v.isVoid() ? dflt : (int) v; }
bool Settings::getBool (const juce::String& key, bool dflt) const { auto v = get (key); return v.isVoid() ? dflt : (bool) v; }
double Settings::getDouble (const juce::String& key, double dflt) const { auto v = get (key); return v.isVoid() ? dflt : (double) v; }

void Settings::save()
{
    if (! dirty) return;
    auto tmp = file.getSiblingFile (file.getFileName() + ".tmp");
    if (tmp.replaceWithText (juce::JSON::toString (root))) tmp.moveFileTo (file);
    dirty = false;
}

std::optional<Calibration> Settings::calibration (const juce::String& key) const
{
    auto all = get ("calibrations");
    auto v = all[juce::Identifier (key)];
    if (! v.isObject()) return std::nullopt;
    Calibration c;
    c.residual = (double) v["residual"];
    c.measured = (double) v["measured"];
    c.routeName = v["routeName"].toString();
    if (auto d = SessionResult::parseDate (v["date"].toString())) c.date = *d;
    if (! v["spreadMs"].isVoid()) c.spreadMs = (double) v["spreadMs"];
    if (! v["hits"].isVoid()) c.hits = (int) v["hits"];
    return c;
}

void Settings::setCalibration (const juce::String& key, const Calibration& c)
{
    auto all = get ("calibrations");
    if (! all.isObject()) all = juce::var (new juce::DynamicObject());
    auto* o = new juce::DynamicObject();
    o->setProperty ("residual", c.residual);
    o->setProperty ("measured", c.measured);
    o->setProperty ("routeName", c.routeName);
    o->setProperty ("date", SessionResult::isoDate (c.date));
    if (c.spreadMs) o->setProperty ("spreadMs", *c.spreadMs);
    if (c.hits) o->setProperty ("hits", *c.hits);
    all.getDynamicObject()->setProperty (key, juce::var (o));
    set ("calibrations", all);
}

double Settings::displayOffset (const juce::String& key) const
{
    auto v = get ("displayOffsets")[juce::Identifier (key)];
    return v.isVoid() ? 0.0 : (double) v;
}

void Settings::setDisplayOffset (const juce::String& key, double seconds)
{
    auto all = get ("displayOffsets");
    if (! all.isObject()) all = juce::var (new juce::DynamicObject());
    all.getDynamicObject()->setProperty (key, juce::jlimit (-0.1, 0.3, seconds));
    set ("displayOffsets", all);
}

double Settings::unscoredSeconds (const juce::String& drill) const
{
    auto v = get ("unscored")[juce::Identifier (drill)];
    return v.isVoid() ? 0.0 : (double) v;
}

void Settings::addUnscored (const juce::String& drill, double seconds)
{
    auto all = get ("unscored");
    if (! all.isObject()) all = juce::var (new juce::DynamicObject());
    all.getDynamicObject()->setProperty (drill, unscoredSeconds (drill) + seconds);
    set ("unscored", all);
}

juce::String Settings::serverBase() const
{
    auto s = get ("server").toString();
    return s.isNotEmpty() ? s.trimCharactersAtEnd ("/") : juce::String ("http://DRILL_SERVER_HOST:4700");
}

// ---- history and the send queue ----

History::History (const juce::File& f) : file (f)
{
    auto v = juce::JSON::parse (file);
    if (auto* a = v.getArray())
        for (auto& e : *a)
            if (auto r = SessionResult::fromVar (e["result"])) entries.push_back ({ *r, (bool) e.getProperty ("uploaded", false) });
}

void History::save() const
{
    juce::Array<juce::var> list;
    for (auto& e : entries)
    {
        auto* o = new juce::DynamicObject();
        o->setProperty ("result", e.result.toVar());
        o->setProperty ("uploaded", e.uploaded);
        list.add (juce::var (o));
    }
    auto tmp = file.getSiblingFile (file.getFileName() + ".tmp");
    if (tmp.replaceWithText (juce::JSON::toString (juce::var (list), true))) tmp.moveFileTo (file);
}

void History::add (const SessionResult& r)
{
    std::lock_guard<std::mutex> g (lock);
    entries.push_back ({ r, false });
    save();
}

std::vector<SessionResult> History::results() const
{
    std::lock_guard<std::mutex> g (lock);
    std::vector<SessionResult> out;
    for (auto& e : entries) out.push_back (e.result);
    std::stable_sort (out.begin(), out.end(), [] (auto& a, auto& b) { return a.date > b.date; });
    return out;
}

std::vector<SessionResult> History::pending() const
{
    std::lock_guard<std::mutex> g (lock);
    std::vector<SessionResult> out;
    for (auto& e : entries) if (! e.uploaded) out.push_back (e.result);
    return out;
}

int History::pendingCount() const
{
    std::lock_guard<std::mutex> g (lock);
    return (int) std::count_if (entries.begin(), entries.end(), [] (auto& e) { return ! e.uploaded; });
}

void History::markUploaded (const juce::StringArray& ids)
{
    if (ids.isEmpty()) return;
    std::lock_guard<std::mutex> g (lock);
    bool changed = false;
    for (auto& e : entries)
        if (! e.uploaded && ids.contains (e.result.id, true)) { e.uploaded = true; changed = true; }
    if (changed) save();
}

} // namespace practice
