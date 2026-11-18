#include "Voice.h"

namespace practice {

namespace IntroText {

juce::String spokenTime (double seconds)
{
    const int s = (int) std::round (seconds);
    const int m = s / 60, r = s % 60;
    if (m == 0) return juce::String (r) + " seconds";
    const juce::String mins = m == 1 ? "1 minute" : juce::String (m) + " minutes";
    return r == 0 ? mins : mins + " " + juce::String (r) + " seconds";
}

std::vector<VoicePart> parts (const Drill& d, int bpm, const SessionSettings& s, bool scored)
{
    std::vector<VoicePart> out { { "say." + d.id, d.say.isNotEmpty() ? d.say : d.name + "." },
                                 { "bpm." + juce::String (bpm), juce::String (bpm) + "." } };
    switch (s.kind)
    {
        case SessionSettings::Kind::cycles:
            out.push_back ({ "cycles." + juce::String (s.cycles), s.cycles == 1 ? juce::String ("1 cycle.") : juce::String (s.cycles) + " cycles." });
            break;
        case SessionSettings::Kind::duration:
            out.push_back ({ "time." + juce::String (s.seconds), spokenTime (s.seconds) + "." });
            break;
        case SessionSettings::Kind::endurance:
            out.push_back (scored ? VoicePart { "endurance", "Endurance." } : VoicePart { "open", "Open." });
            break;
    }
    return out;
}

VoicePart cue (int n)
{
    juce::String word;
    switch (n) { case 0: word = "Rest."; break; case 2: word = "Eighths."; break; case 3: word = "Triplets."; break;
                 case 4: word = "Sixteenths."; break; default: word = juce::String (n) + "."; }
    return { "cue." + juce::String (n), word };
}

VoicePart cue (double bpm) { const int b = (int) bpm; return { "bpm." + juce::String (b), juce::String (b) + "." }; }

} // namespace IntroText

void VoiceLines::load (const juce::File& bundled, const juce::File& cache)
{
    clips.clear(); pack.reset(); version_ = 0;
    for (auto& folder : { bundled, cache })
    {
        auto idx = juce::JSON::parse (folder.getChildFile ("index.json"));
        auto packFile = folder.getChildFile ("pack.bin");
        if (! idx.isObject() || (int) idx.getProperty ("schema", 1) > 1 || ! packFile.existsAsFile()) continue;
        const int v = (int) idx.getProperty ("version", 0);
        if (v <= version_ && ! clips.empty()) continue;
        std::map<juce::String, Clip> found;
        juce::int64 needed = 0;
        if (auto* o = idx["clips"].getDynamicObject())
            for (auto& p : o->getProperties())
            {
                Clip c { (juce::int64) p.value["o"], (int) p.value["n"], p.value["text"].toString() };
                needed = std::max (needed, c.o + c.n);
                found[p.name.toString()] = c;
            }
        if (packFile.getSize() < needed) continue;
        juce::MemoryBlock bytes;
        if (! packFile.loadFileAsData (bytes)) continue;
        clips = std::move (found);
        pack = std::move (bytes);
        version_ = v;
    }
}

bool VoiceLines::has (const std::vector<VoicePart>& parts) const
{
    for (auto& p : parts)
    {
        auto it = clips.find (p.key);
        if (it == clips.end() || it->second.text != p.text || it->second.o + it->second.n > (juce::int64) pack.getSize()) return false;
    }
    return ! parts.empty();
}

std::shared_ptr<SoundBuffer> VoiceLines::line (const AudioEngine& engine, const std::vector<VoicePart>& parts) const
{
    if (! has (parts)) return nullptr;
    auto out = std::make_shared<SoundBuffer>();
    const int gap = (int) (0.08 * engine.sampleRate());
    for (auto& p : parts)
    {
        const auto& c = clips.at (p.key);
        juce::MemoryBlock bytes (static_cast<const char*> (pack.getData()) + c.o, (size_t) c.n);
        auto s = engine.decode (bytes);
        if (! s) return nullptr;
        out->samples.insert (out->samples.end(), s->samples.begin(), s->samples.end());
        out->samples.insert (out->samples.end(), (size_t) gap, 0.0f);
    }
    return out;
}

} // namespace practice
