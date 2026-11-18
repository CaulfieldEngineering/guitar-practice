#pragma once
// The recorded voice (voice/index.json and voice/pack.bin, made by scripts/make-voice.mjs on the mini PC): the same
// clips the phone plays, read from the program's own copy or a newer one pulled from the drill server. A line is
// said only when every part of it has a clip saying exactly those words (as on the phone); otherwise nothing is said,
// since Windows has no voice of the phone's quality to fall back on.
#include "../engine/AudioEngine.h"

namespace practice {

struct VoicePart { juce::String key, text; };

namespace IntroText {
    /// "Triplets to sixteenths. Four and four." "120." "8 cycles."
    std::vector<VoicePart> parts (const Drill& d, int bpm, const SessionSettings& s, bool scored);
    VoicePart cue (int notesPerBeat);
    VoicePart cue (double bpm);
    juce::String spokenTime (double seconds);
}

class VoiceLines {
public:
    void load (const juce::File& bundled, const juce::File& cache);
    int version() const { return version_; }
    bool has (const std::vector<VoicePart>& parts) const;
    /// The whole line as one sound at the engine's rate, or null when a part has no clip.
    std::shared_ptr<SoundBuffer> line (const AudioEngine& engine, const std::vector<VoicePart>& parts) const;
private:
    struct Clip { juce::int64 o = 0; int n = 0; juce::String text; };
    std::map<juce::String, Clip> clips;
    juce::MemoryBlock pack;
    int version_ = 0;
};

} // namespace practice
