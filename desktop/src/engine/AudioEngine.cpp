#include "AudioEngine.h"
#include <cmath>

namespace practice {

static constexpr double kPi = 3.14159265358979323846;

// ---- the guide guitar ----

const std::array<int, 13> GuitarBank::pitches { 40, 45, 48, 50, 52, 55, 59, 61, 64, 67, 71, 74, 77 };

bool GuitarBank::load (const juce::File& folder)
{
    juce::AudioFormatManager fm;
    fm.registerBasicFormats();
    std::vector<std::vector<float>> all;
    for (int p : pitches)
        for (auto name : { "s1", "s2", "h1", "h2" })
        {
            auto f = folder.getChildFile ("g" + juce::String (p) + "_" + name + ".wav");
            std::unique_ptr<juce::AudioFormatReader> r (fm.createReaderFor (f));
            if (! r || r->lengthInSamples <= 0) return false;
            juce::AudioBuffer<float> b (1, (int) r->lengthInSamples);
            r->read (&b, 0, (int) r->lengthInSamples, 0, true, false);
            all.emplace_back (b.getReadPointer (0), b.getReadPointer (0) + b.getNumSamples());
            sampleRate = r->sampleRate;
        }
    samples = std::move (all);
    return true;
}

std::pair<int, double> GuitarBank::lookup (int pitch, bool accent, bool up) const
{
    int best = 0;
    for (int i = 0; i < (int) pitches.size(); ++i)
        if (std::abs (pitches[(size_t) i] - pitch) < std::abs (pitches[(size_t) best] - pitch)) best = i;
    return { best * 4 + (accent ? 2 : 0) + (up ? 1 : 0), std::pow (2.0, (pitch - pitches[(size_t) best]) / 12.0) };
}

// ---- sounds made in code (ios/Practice/Engine/ClickSounds.swift) ----

static std::vector<float> tone (double sr, std::initializer_list<std::pair<double, double>> freqs, double decay, double length, double gain)
{
    const int n = (int) (length * sr);
    std::vector<float> out ((size_t) std::max (1, n), 0.0f);
    const int rise = std::max (1, (int) (0.001 * sr));
    float pk = 0;
    for (int i = 0; i < n; ++i)
    {
        const double t = i / sr;
        double s = 0;
        for (auto& [f, a] : freqs) s += a * std::sin (2 * kPi * f * t);
        const double env = std::exp (-decay * t) * std::min (1.0, (double) i / rise);
        out[(size_t) i] = (float) (s * env);
        pk = std::max (pk, std::abs (out[(size_t) i]));
    }
    if (pk > 0) for (auto& x : out) x *= (float) gain / pk;
    const int fade = std::min (n, (int) (0.004 * sr));
    for (int k = 0; k < fade; ++k) out[(size_t) (n - 1 - k)] *= (float) k / (float) fade;
    return out;
}

static std::vector<float> pluckTone (double sr, double gain, double freq = 123.47)
{
    const int n = (int) (0.22 * sr);
    const int period = std::max (2, (int) std::round (sr / freq));
    std::vector<float> line ((size_t) period);
    uint32_t seed = 12345;
    for (int i = 0; i < period; ++i) { seed = seed * 1664525u + 1013904223u; line[(size_t) i] = (float) (int32_t) seed / (float) INT32_MAX; }
    std::vector<float> out ((size_t) n);
    int idx = 0; float pk = 0;
    for (int i = 0; i < n; ++i)
    {
        const int next = (idx + 1) % period;
        const float v = line[(size_t) idx];
        line[(size_t) idx] = 0.5f * (v + line[(size_t) next]) * 0.985f;
        out[(size_t) i] = v * (float) std::exp (-(double) i / sr * 14);
        pk = std::max (pk, std::abs (out[(size_t) i]));
        idx = next;
    }
    if (pk > 0) for (auto& x : out) x *= (float) gain / pk;
    return out;
}

std::vector<float> AudioEngine::makeClick (ClickKind kind) const
{
    const double sr = rate.load();
    switch (kind)
    {
        case ClickKind::accent:  return tone (sr, { { 2000, 1 }, { 4100, 0.3 } }, 70, 0.06, 0.95);
        case ClickKind::beat:    return tone (sr, { { 1400, 1 }, { 2900, 0.25 } }, 80, 0.05, 0.7);
        case ClickKind::sub:     return tone (sr, { { 1000, 1 } }, 110, 0.035, 0.35);
        case ClickKind::countIn: return tone (sr, { { 1700, 1 }, { 2950, 0.5 } }, 90, 0.05, 0.8);
        case ClickKind::change:  return tone (sr, { { 880, 1 }, { 2210, 0.45 }, { 3520, 0.2 } }, 3.5, 1.0, 0.55);
        case ClickKind::rest:    return tone (sr, { { 587, 1 }, { 1470, 0.35 } }, 4.5, 0.8, 0.5);
        case ClickKind::done:
        {
            std::vector<float> out ((size_t) (1.6 * sr), 0.0f);
            const double notes[] = { 880.0, 1108.7, 1318.5 };
            for (int i = 0; i < 3; ++i)
            {
                auto t = tone (sr, { { notes[i], 1 }, { notes[i] * 2.5, 0.3 } }, 3.5, 1.1, 0.4);
                const size_t at = (size_t) (i * 0.16 * sr);
                for (size_t k = 0; k < t.size() && at + k < out.size(); ++k) out[at + k] += t[k];
            }
            return out;
        }
        case ClickKind::pluck:       return pluckTone (sr, 0.45);
        case ClickKind::pluckAccent: return pluckTone (sr, 0.8);
    }
    return {};
}

std::shared_ptr<SoundBuffer> AudioEngine::makeTone (double hz, double seconds, float dbfs) const
{
    auto b = std::make_shared<SoundBuffer>();
    const double sr = rate.load();
    const int n = (int) (seconds * sr);
    const float g = juce::Decibels::decibelsToGain (dbfs);
    b->samples.resize ((size_t) n);
    for (int i = 0; i < n; ++i)
    {
        const float env = (float) std::min ({ 1.0, i / (0.01 * sr), (n - i) / (0.01 * sr) });
        b->samples[(size_t) i] = g * env * (float) std::sin (2 * kPi * hz * i / sr);
    }
    return b;
}

std::shared_ptr<SoundBuffer> AudioEngine::decode (const juce::MemoryBlock& bytes) const
{
    auto stream = std::make_unique<juce::MemoryInputStream> (bytes, false);
    std::unique_ptr<juce::AudioFormatReader> r (const_cast<juce::AudioFormatManager&> (formats).createReaderFor (std::move (stream)));
    if (! r || r->lengthInSamples <= 0) return nullptr;
    juce::AudioBuffer<float> src (1, (int) r->lengthInSamples);
    r->read (&src, 0, (int) r->lengthInSamples, 0, true, false);
    const double ratio = r->sampleRate / rate.load();
    auto b = std::make_shared<SoundBuffer>();
    const int n = (int) (src.getNumSamples() / ratio);
    b->samples.resize ((size_t) std::max (0, n));
    const float* s = src.getReadPointer (0);
    for (int i = 0; i < n; ++i)
    {
        const double p = i * ratio;
        const int k = (int) p;
        const float f = (float) (p - k);
        const float a = s[k], c = k + 1 < src.getNumSamples() ? s[k + 1] : a;
        b->samples[(size_t) i] = a + (c - a) * f;
    }
    return b;
}

// ---- the engine ----

AudioEngine::AudioEngine()
{
    fifoData.resize (16384);
    pendingEvents.reserve (16384);
    monoIn.resize (16384);
    monoOut.resize (16384);
    formats.registerBasicFormats();
    buildSounds (48000);
    detector = std::make_unique<OnsetDetector> (48000);
}

AudioEngine::~AudioEngine() = default;

void AudioEngine::setResources (const juce::File& guitarFolder) { guitar.load (guitarFolder); }

void AudioEngine::buildSounds (double sr)
{
    rate = sr;
    for (int k = 0; k < 9; ++k) clicks[(size_t) k] = makeClick ((ClickKind) k);
}

double AudioEngine::nowFrames() const
{
    const double since = juce::Time::getMillisecondCounterHiRes() - lastCallbackMs.load();
    const double ahead = std::min (std::max (0.0, since) * rate.load() / 1000.0, (double) blockSize.load());
    return (double) framePos.load() + (started.load() ? ahead : 0.0);
}

juce::int64 AudioEngine::frameAt (juce::int64 originFrame, double seconds) const
{
    return originFrame + (juce::int64) std::llround (seconds * rate.load());
}

AudioEngine::Event AudioEngine::guideEvent (juce::int64 frame, int pitch, bool accent, bool up) const
{
    Event e;
    e.frame = frame;
    e.kind = accent ? ClickKind::pluckAccent : ClickKind::pluck;
    if (guitar.loaded())
    {
        auto [sample, step] = guitar.lookup (pitch, accent, up);
        e.sample = sample;
        e.step = step * guitar.sampleRate / rate.load();
    }
    return e;
}

bool AudioEngine::push (const std::vector<Event>& events)
{
    if (events.empty()) return true;
    if (fifo.getFreeSpace() < (int) events.size()) return false;
    auto w = fifo.write ((int) events.size());
    int k = 0;
    const int gen = generation.load();
    for (int i = 0; i < w.blockSize1; ++i) { fifoData[(size_t) (w.startIndex1 + i)] = events[(size_t) k++]; fifoData[(size_t) (w.startIndex1 + i)].gen = gen; }
    for (int i = 0; i < w.blockSize2; ++i) { fifoData[(size_t) (w.startIndex2 + i)] = events[(size_t) k++]; fifoData[(size_t) (w.startIndex2 + i)].gen = gen; }
    return true;
}

void AudioEngine::clearAll() { generation++; }
void AudioEngine::stopVoices() { voiceStopRequest++; }

void AudioEngine::startMetronome (double bpm, int beats, int sub, bool accent)
{
    setMetronome (bpm, beats, sub, accent);
    metroStartRequest++;
    metroOn = true;
}

void AudioEngine::setMetronome (double bpm, int beats, int sub, bool accent)
{
    metroBPM = juce::jlimit (20.0, 400.0, bpm);
    metroBeats = std::max (1, beats);
    metroSub = std::max (1, sub);
    metroAccent = accent;
}

void AudioEngine::stopMetronome() { metroOn = false; metroBeatIndex = -1; }

int AudioEngine::metronomeBeat() const
{
    if (! metroOn.load()) return -1;
    const auto f = metroBeatFrame.load();
    if (f < 0 || nowFrames() < (double) f) return -1;
    return metroBeatIndex.load();
}

std::vector<Onset> AudioEngine::drainOnsets()
{
    std::vector<Onset> out;
    const int n = onsetFifo.getNumReady();
    if (n <= 0) return out;
    auto r = onsetFifo.read (n);
    for (int i = 0; i < r.blockSize1; ++i) out.push_back (onsetData[(size_t) (r.startIndex1 + i)]);
    for (int i = 0; i < r.blockSize2; ++i) out.push_back (onsetData[(size_t) (r.startIndex2 + i)]);
    return out;
}

void AudioEngine::injectOnset (const Onset& o)
{
    if (! testPicks.load() || onsetFifo.getFreeSpace() < 1) return;   // never alongside the real detector
    auto w = onsetFifo.write (1);
    onsetData[(size_t) (w.blockSize1 > 0 ? w.startIndex1 : w.startIndex2)] = o;
}

void AudioEngine::setListening (bool on)
{
    if (on && ! listening.load()) resetRequest++;
    listening = on;
}

void AudioEngine::startVoice (const float* data, int length, double step, float gain, int offset, bool pluck, SoundBuffer* buf)
{
    if (pluck)
        for (auto& v : voices) if (v.active && v.pluck && v.release < 0) v.release = 96;   // as on one string
    Voice* slot = nullptr;
    for (auto& v : voices) if (! v.active) { slot = &v; break; }
    if (! slot)
    {
        slot = &voices[0];
        for (auto& v : voices) if (v.pos / std::max (1, v.length) > slot->pos / std::max (1, slot->length)) slot = &v;
        if (slot->buffer) slot->buffer->playing = false;
    }
    *slot = Voice { data, length, 0, step, gain, offset, -1, pluck, buf, true };
    if (buf) buf->playing = true;
}

void AudioEngine::render (float* mono, int n)
{
    for (auto& v : voices)
    {
        if (! v.active) continue;
        int i = v.startOffset;
        v.startOffset = 0;
        for (; i < n; ++i)
        {
            const int k = (int) v.pos;
            if (k + 1 >= v.length || v.release == 0) { v.active = false; if (v.buffer) v.buffer->playing = false; break; }
            const float f = (float) (v.pos - k);
            float s = v.data[k] + (v.data[k + 1] - v.data[k]) * f;
            if (v.release > 0) { s *= (float) v.release / 96.0f; v.release--; }
            mono[i] += s * v.gain;
            v.pos += v.step;
        }
    }
}

void AudioEngine::audioDeviceIOCallbackWithContext (const float* const* in, int numIn, float* const* out, int numOut,
                                                    int numSamples, const juce::AudioIODeviceCallbackContext&)
{
    const double sr = rate.load();
    const juce::int64 start = framePos.load();
    const juce::int64 end = start + numSamples;
    float* mono = monoOut.data();
    const int n = std::min (numSamples, (int) monoOut.size());
    std::fill (mono, mono + n, 0.0f);

    const int gen = generation.load();
    if (gen != clearSeen)
    {
        clearSeen = gen;
        pendingEvents.clear();
        for (auto& v : voices) { if (v.active && v.buffer) v.buffer->playing = false; v.active = false; }
    }
    if (voiceStopRequest.load() != voiceStopSeen)
    {
        voiceStopSeen = voiceStopRequest.load();
        for (auto& v : voices) if (v.active && v.buffer) { v.buffer->playing = false; v.active = false; }
    }

    // take queued events into the sorted list
    if (const int ready = fifo.getNumReady(); ready > 0)
    {
        auto r = fifo.read (ready);
        auto take = [this, gen] (const Event& e) {
            if (e.gen != gen) return;
            if (pendingEvents.size() >= pendingEvents.capacity()) return;
            auto it = std::upper_bound (pendingEvents.begin(), pendingEvents.end(), e.frame,
                                        [] (juce::int64 f, const Event& x) { return f < x.frame; });
            pendingEvents.insert (it, e);
        };
        for (int i = 0; i < r.blockSize1; ++i) take (fifoData[(size_t) (r.startIndex1 + i)]);
        for (int i = 0; i < r.blockSize2; ++i) take (fifoData[(size_t) (r.startIndex2 + i)]);
    }

    const float sounds = soundsGain.load(), click = clickGain.load();
    size_t used = 0;
    for (; used < pendingEvents.size() && pendingEvents[used].frame < end; ++used)
    {
        const auto& e = pendingEvents[used];
        const int offset = (int) std::max<juce::int64> (0, e.frame - start);
        if (e.frame < start - (juce::int64) (0.05 * sr)) continue;   // far too late (after a stall): skip it
        if (e.buffer)
            startVoice (e.buffer->samples.data(), (int) e.buffer->samples.size(), 1, sounds * e.gain, offset, false, e.buffer);
        else if (e.sample >= 0 && e.sample < (int) guitar.samples.size())
        {
            const auto& s = guitar.samples[(size_t) e.sample];
            startVoice (s.data(), (int) s.size(), e.step, sounds * 0.9f * e.gain, offset, true, nullptr);
        }
        else
        {
            const auto& c = clicks[(size_t) e.kind];
            const bool isClick = e.kind == ClickKind::accent || e.kind == ClickKind::beat || e.kind == ClickKind::sub || e.kind == ClickKind::countIn;
            startVoice (c.data(), (int) c.size(), 1, sounds * e.gain * (isClick ? click : 1.0f), offset,
                        e.kind == ClickKind::pluck || e.kind == ClickKind::pluckAccent, nullptr);
        }
    }
    if (used > 0) pendingEvents.erase (pendingEvents.begin(), pendingEvents.begin() + (long) used);

    // the free metronome
    if (metroStartRequest.load() != metroStartSeen)
    {
        metroStartSeen = metroStartRequest.load();
        metroNextFrame = (double) start + 0.03 * sr;
        metroTick = 0;
    }
    if (metroOn.load())
    {
        const int sub = metroSub.load(), beats = metroBeats.load();
        const double step = 60.0 / metroBPM.load() * sr / sub;
        while (metroNextFrame < (double) end)
        {
            const int offset = (int) std::max (0.0, metroNextFrame - (double) start);
            const bool onBeat = metroTick % sub == 0;
            const int beat = (int) ((metroTick / sub) % beats);
            const ClickKind k = ! onBeat ? ClickKind::sub : (beat == 0 && metroAccent.load() ? ClickKind::accent : ClickKind::beat);
            const auto& c = clicks[(size_t) k];
            startVoice (c.data(), (int) c.size(), 1, sounds * click, offset, false, nullptr);
            if (onBeat) { metroBeatFrame = (juce::int64) metroNextFrame; metroBeatIndex = beat; }
            metroNextFrame += step;
            metroTick++;
        }
    }

    render (mono, n);

    // input: summed to mono, level, picks, and Hear Guitar
    float pk = 0;
    if (numIn > 0)
    {
        float* m = monoIn.data();
        std::fill (m, m + n, 0.0f);
        for (int c = 0; c < numIn; ++c)
            if (in[c]) for (int i = 0; i < n; ++i) m[i] += in[c][i];
        for (int i = 0; i < n; ++i) pk = std::max (pk, std::abs (m[i]));
        if (resetRequest.load() != resetSeen) { resetSeen = resetRequest.load(); detector->reset(); }
        if (listening.load() && ! testPicks.load())
            detector->process (m, n, (double) start / sr, [this] (const Onset& o) {
                if (onsetFifo.getFreeSpace() < 1) return;
                auto w = onsetFifo.write (1);
                onsetData[(size_t) (w.blockSize1 > 0 ? w.startIndex1 : w.startIndex2)] = o;
            });
        if (hearGuitar.load())
        {
            const float g = guitarGain.load();
            for (int i = 0; i < n; ++i) mono[i] += m[i] * g;
        }
    }
    peak = pk;

    for (int c = 0; c < numOut; ++c)
        if (out[c])
        {
            std::copy (mono, mono + n, out[c]);
            for (int i = n; i < numSamples; ++i) out[c][i] = 0;
        }
    framePos = end;
    lastCallbackMs = juce::Time::getMillisecondCounterHiRes();
}

void AudioEngine::audioDeviceAboutToStart (juce::AudioIODevice* device)
{
    const double sr = device->getCurrentSampleRate() > 0 ? device->getCurrentSampleRate() : 48000.0;
    for (auto& v : voices) { if (v.active && v.buffer) v.buffer->playing = false; v.active = false; }
    pendingEvents.clear();
    blockSize = device->getCurrentBufferSizeSamples();
    inputChannels = device->getActiveInputChannels().countNumberOfSetBits();
    if (std::abs (sr - rate.load()) > 0.5 || ! detector)
    {
        buildSounds (sr);
        detector = std::make_unique<OnsetDetector> (sr);
    }
    const int need = std::max (blockSize.load(), 4096) * 2;
    if ((int) monoOut.size() < need) { monoOut.resize ((size_t) need); monoIn.resize ((size_t) need); }
    started = true;
}

void AudioEngine::audioDeviceStopped() { started = false; inputChannels = 0; peak = 0; }

void AudioEngine::audioDeviceError (const juce::String& message)
{
    if (onDeviceError) onDeviceError (message);
}

} // namespace practice
