#pragma once
// The audio engine: one callback that renders every sound sample by sample from events placed at exact frames (the
// click is never timed by a UI timer), runs the free metronome, finds pick attacks in the input (OnsetDetector) and
// hands them to the UI through a lock-free queue, measures the input level, and mixes the guitar into the output
// only when Hear Guitar is on (off by default). Nothing in the callback allocates, locks or waits.
//
// The clock is the frame count since the engine first started. A run keeps its own origin frame; a pick found at
// engine frame f is at (f - origin) / sampleRate seconds on the run's clock, before the latency offset is taken off.
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include "../core/Drill.h"
#include "../core/OnsetDetector.h"
#include <array>
#include <atomic>
#include <memory>

namespace practice {

/// A sound already decoded at the engine's rate (a spoken line, the test tone). Kept alive by the UI side until the
/// engine says it is done with it.
struct SoundBuffer {
    std::vector<float> samples;
    std::atomic<bool> playing { false };
};

/// The guide guitar: the FreePats Strat's short muted notes (ios/Practice/Resources/Guitar, public domain), read once.
class GuitarBank {
public:
    static const std::array<int, 13> pitches;
    bool load (const juce::File& folder);
    bool loaded() const { return ! samples.empty(); }
    /// Which recording plays a note, and how much faster it runs (at the bank's own rate) to be in tune.
    std::pair<int, double> lookup (int pitch, bool accent, bool up) const;
    std::vector<std::vector<float>> samples;   // four to a pitch: soft 1, soft 2, hard 1, hard 2
    double sampleRate = 24000;
};

class AudioEngine : public juce::AudioIODeviceCallback {
public:
    AudioEngine();
    ~AudioEngine() override;

    // ---- set up from the message thread ----
    void setResources (const juce::File& guitarFolder);
    double sampleRate() const { return rate.load(); }
    bool running() const { return started.load(); }
    /// Frames rendered since the engine first started, smoothed to the moment of asking (for drawing).
    double nowFrames() const;
    juce::int64 framePosition() const { return framePos.load(); }
    int inputChannelCount() const { return inputChannels.load(); }

    // ---- the run's events (play-along, calibration) ----
    struct Event {
        juce::int64 frame = 0;
        ClickKind kind = ClickKind::beat;
        int sample = -1;      // a guide note: the guitar bank's recording
        double step = 1;      // how fast it runs (bank rate over engine rate already applied)
        SoundBuffer* buffer = nullptr;   // a voice line or the test tone
        float gain = 1;
        int gen = 0;          // set by push(): events from before a clearAll() are dropped
    };
    /// Queues events (any order within one call); false when the queue is full (it holds seconds of a run).
    bool push (const std::vector<Event>& events);
    /// Drops every queued event and stops every sound (the next callback).
    void clearAll();
    /// The frame a time `seconds` after `originFrame` falls on.
    juce::int64 frameAt (juce::int64 originFrame, double seconds) const;
    Event guideEvent (juce::int64 frame, int pitch, bool accent, bool up) const;

    // ---- the free metronome ----
    void startMetronome (double bpm, int beatsPerBar, int subdivision, bool accent);
    void setMetronome (double bpm, int beatsPerBar, int subdivision, bool accent);
    void stopMetronome();
    bool metronomeRunning() const { return metroOn.load(); }
    /// The beat of the bar that is sounding now (-1 when stopped).
    int metronomeBeat() const;

    // ---- input ----
    /// Picks found since the last call, in engine seconds (frame / rate).
    std::vector<Onset> drainOnsets();
    void setListening (bool on);   // the detector runs only while a scored run or the calibration needs it
    /// The self-test only (--selftest), on a computer with no input: a pick as if the detector had found it.
    void injectOnset (const Onset& o);
    std::atomic<bool> testPicks { false };   // the self-test: the detector is off and picks are injected instead
    float inputPeak() const { return peak.load(); }   // the loudest sample of the latest block, 0..1
    std::atomic<bool> hearGuitar { false };
    std::atomic<float> guitarGain { 0.7f };
    std::atomic<float> soundsGain { 0.8f };   // clicks, guide and voice
    std::atomic<float> clickGain { 1.0f };
    /// The metronome's click sound (0.3.0); a run's events carry their own.
    std::atomic<int> metroSound { 0 };
    /// The input just heard, for telling a pick's pitch (a drill with pitched notes): copies the samples from engine
    /// frame `from` into `out` when they are all there and not yet overwritten.
    bool readInput (juce::int64 from, int count, float* out) const;
    juce::int64 inputFrames() const { return historyEnd.load(); }

    // ---- sounds made in code ----
    std::vector<float> makeClick (ClickKind kind) const;
    std::shared_ptr<SoundBuffer> makeTone (double hz, double seconds, float dbfs) const;
    /// Decodes MP3 or WAV bytes to a sound at the engine's rate (message thread).
    std::shared_ptr<SoundBuffer> decode (const juce::MemoryBlock& bytes) const;
    void stopVoices();

    std::function<void (juce::String)> onDeviceError;   // from the audio thread's caller; hop to the UI yourself

    // juce::AudioIODeviceCallback
    void audioDeviceIOCallbackWithContext (const float* const* in, int numIn, float* const* out, int numOut,
                                           int numSamples, const juce::AudioIODeviceCallbackContext&) override;
    void audioDeviceAboutToStart (juce::AudioIODevice* device) override;
    void audioDeviceStopped() override;
    void audioDeviceError (const juce::String& message) override;

    GuitarBank guitar;

private:
    struct Voice {
        const float* data = nullptr;
        int length = 0;
        double pos = 0, step = 1;
        float gain = 1;
        int startOffset = 0;      // frames into the current block before it starts
        int release = -1;         // frames left of a fade, -1 for none
        bool pluck = false;
        SoundBuffer* buffer = nullptr;
        bool active = false;
    };
    void startVoice (const float* data, int length, double step, float gain, int offset, bool pluck, SoundBuffer* buf);
    void render (float* mono, int n);
    void buildSounds (double sr);

    std::atomic<double> rate { 48000 };
    std::atomic<bool> started { false };
    std::atomic<juce::int64> framePos { 0 };
    std::atomic<double> lastCallbackMs { 0 };
    std::atomic<int> blockSize { 512 };
    std::atomic<int> inputChannels { 0 };

    // events: a lock-free queue from the message thread, then a sorted list on the audio thread
    juce::AbstractFifo fifo { 16384 };
    std::vector<Event> fifoData;
    std::vector<Event> pendingEvents;   // audio thread only, sorted by frame
    std::atomic<int> generation { 0 };
    int clearSeen = 0;
    std::atomic<int> voiceStopRequest { 0 };
    int voiceStopSeen = 0;

    std::array<Voice, 64> voices;
    std::array<std::vector<float>, clickKindCount> clicks;   // by ClickKind
    std::vector<float> history;                     // the last two seconds of input, mono (pitch)
    std::atomic<juce::int64> historyEnd { 0 };

    // metronome
    std::atomic<bool> metroOn { false };
    std::atomic<double> metroBPM { 100 };
    std::atomic<int> metroBeats { 4 }, metroSub { 1 };
    std::atomic<bool> metroAccent { true };
    std::atomic<int> metroStartRequest { 0 };
    int metroStartSeen = 0;
    double metroNextFrame = 0;
    juce::int64 metroTick = 0;
    std::atomic<juce::int64> metroBeatFrame { -1 };
    std::atomic<int> metroBeatIndex { -1 };

    // input
    std::unique_ptr<OnsetDetector> detector;
    std::atomic<bool> listening { false };
    std::atomic<int> resetRequest { 0 };
    int resetSeen = 0;
    juce::AbstractFifo onsetFifo { 2048 };
    std::array<Onset, 2048> onsetData;
    std::atomic<float> peak { 0 };
    std::vector<float> monoIn, monoOut;

    juce::AudioFormatManager formats;
};

} // namespace practice
