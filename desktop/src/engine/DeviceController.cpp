#if defined (_WIN32) && ! defined (NOMINMAX)
 #define NOMINMAX
#endif
#include "DeviceController.h"
#if JUCE_WINDOWS
 #include <objbase.h>
#endif

namespace practice {

juce::var DeviceSetup::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("type", type);
    o->setProperty ("input", input);
    o->setProperty ("output", output);
    o->setProperty ("inputChannel", inputChannel);
    o->setProperty ("sampleRate", sampleRate);
    o->setProperty ("bufferSize", bufferSize);
    return juce::var (o);
}

DeviceSetup DeviceSetup::fromVar (const juce::var& v)
{
    DeviceSetup s;
    if (! v.isObject()) return s;
    s.type = v["type"].toString();
    s.input = v["input"].toString();
    s.output = v["output"].toString();
    s.inputChannel = (int) v.getProperty ("inputChannel", -1);
    s.sampleRate = (double) v.getProperty ("sampleRate", 0.0);
    s.bufferSize = (int) v.getProperty ("bufferSize", 0);
    return s;
}

// ---- the real backend ----

struct JuceDeviceBackend::Listener : juce::AudioIODeviceType::Listener {
    JuceDeviceBackend& owner;
    explicit Listener (JuceDeviceBackend& o) : owner (o) {}
    void audioDeviceListChanged() override { if (owner.onDeviceListChanged) owner.onDeviceListChanged(); }
};

JuceDeviceBackend::JuceDeviceBackend() : listener (std::make_unique<Listener> (*this)) {}
JuceDeviceBackend::~JuceDeviceBackend() = default;

void JuceDeviceBackend::prepareThread()
{
   #if JUCE_WINDOWS
    // ASIO drivers are COM objects and expect an apartment on the thread that loads them.
    comReady = SUCCEEDED (CoInitializeEx (nullptr, COINIT_APARTMENTTHREADED));
   #endif
   #if JUCE_ASIO
    if (auto* t = juce::AudioIODeviceType::createAudioIODeviceType_ASIO()) deviceTypes.add (t);
   #endif
   #if JUCE_WASAPI
    if (auto* t = juce::AudioIODeviceType::createAudioIODeviceType_WASAPI (juce::WASAPIDeviceMode::exclusive)) deviceTypes.add (t);
    if (auto* t = juce::AudioIODeviceType::createAudioIODeviceType_WASAPI (juce::WASAPIDeviceMode::shared)) deviceTypes.add (t);
   #endif
   #if JUCE_MAC
    if (auto* t = juce::AudioIODeviceType::createAudioIODeviceType_CoreAudio()) deviceTypes.add (t);
   #endif
    for (auto* t : deviceTypes) t->addListener (listener.get());
}

void JuceDeviceBackend::finishThread()
{
    close();
    for (auto* t : deviceTypes) t->removeListener (listener.get());
    deviceTypes.clear();
   #if JUCE_WINDOWS
    if (comReady) CoUninitialize();
   #endif
}

juce::StringArray JuceDeviceBackend::types()
{
    juce::StringArray out;
    for (auto* t : deviceTypes) out.add (t->getTypeName());
    return out;
}

juce::AudioIODeviceType* JuceDeviceBackend::findType (const juce::String& name)
{
    for (auto* t : deviceTypes) if (t->getTypeName() == name) return t;
    return nullptr;
}

DeviceLists JuceDeviceBackend::scan (const juce::String& type)
{
    DeviceLists l;
    if (auto* t = findType (type))
    {
        t->scanForDevices();
        l.inputs = t->getDeviceNames (true);
        l.outputs = t->getDeviceNames (false);
        l.sameDeviceForBoth = ! t->hasSeparateInputsAndOutputs();
        if (l.sameDeviceForBoth) l.inputs = l.outputs;
    }
    return l;
}

OpenResult JuceDeviceBackend::open (const DeviceSetup& s, juce::AudioIODeviceCallback* callback)
{
    close();
    OpenResult r;
    auto* t = findType (s.type);
    if (! t) { r.error = "That kind of audio device is not available here."; return r; }
    const auto outName = s.output, inName = t->hasSeparateInputsAndOutputs() ? s.input : s.output;
    device.reset (t->createDevice (outName, inName));
    if (! device) { r.error = "Couldn't find " + (outName.isNotEmpty() ? outName : inName) + ". Pick it again or choose another."; return r; }
    juce::BigInteger ins, outs;
    const int inCount = device->getInputChannelNames().size();
    if (inCount > 0)
    {
        if (s.inputChannel >= 0 && s.inputChannel < inCount) ins.setBit (s.inputChannel);
        else ins.setRange (0, std::min (2, inCount), true);
    }
    outs.setRange (0, std::min (2, std::max (1, device->getOutputChannelNames().size())), true);
    const double rate = s.sampleRate > 0 ? s.sampleRate : device->getCurrentSampleRate() > 0 ? device->getCurrentSampleRate() : 48000.0;
    const int buffer = s.bufferSize > 0 ? s.bufferSize : device->getDefaultBufferSize();
    auto err = device->open (ins, outs, rate, buffer);
    if (err.isNotEmpty())
    {
        device.reset();
        r.error = "Couldn't open " + (outName.isNotEmpty() ? outName : inName) + ": " + err;
        return r;
    }
    r.ok = true;
    r.sampleRate = device->getCurrentSampleRate();
    r.bufferSize = device->getCurrentBufferSizeSamples();
    r.inputLatency = device->getInputLatencyInSamples();
    r.outputLatency = device->getOutputLatencyInSamples();
    r.rates = device->getAvailableSampleRates();
    r.buffers = device->getAvailableBufferSizes();
    r.inputChannels = device->getActiveInputChannels().countNumberOfSetBits();
    device->start (callback);
    return r;
}

void JuceDeviceBackend::close()
{
    if (device) { device->stop(); device->close(); device.reset(); }
}

// ---- the controller ----

DeviceController::DeviceController (std::unique_ptr<DeviceBackend> b, juce::AudioIODeviceCallback* cb)
    : juce::Thread ("Practice audio devices"), backend_ (std::move (b)), callback (cb) {}

DeviceController::~DeviceController()
{
    signalThreadShouldExit();
    notify();
    stopThread (10000);
}

void DeviceController::start() { startThread(); }

void DeviceController::request (const DeviceSetup& s)
{
    {
        std::lock_guard<std::mutex> g (lock);
        pending = s;
        snapshot.wanted = s;
        snapshot.busy = true;
        snapshot.requests++;
    }
    notify();
}

void DeviceController::rescan()
{
    { std::lock_guard<std::mutex> g (lock); wantScan = true; }
    notify();
}

void DeviceController::closeDevice()
{
    { std::lock_guard<std::mutex> g (lock); wantClose = true; pending.reset(); }
    notify();
}

DeviceController::State DeviceController::state() const
{
    std::lock_guard<std::mutex> g (lock);
    return snapshot;
}

void DeviceController::publish()
{
    if (onChange) onChange();
}

void DeviceController::run()
{
    backend_->prepareThread();
    {
        auto types = backend_->types();
        std::lock_guard<std::mutex> g (lock);
        snapshot.types = types;
    }
    while (! threadShouldExit())
    {
        std::optional<DeviceSetup> next;
        bool scan = false, close = false;
        {
            std::lock_guard<std::mutex> g (lock);
            next = pending; pending.reset();
            scan = wantScan; wantScan = false;
            close = wantClose; wantClose = false;
            if (scan || next) snapshot.busy = true;
        }
        if (! next && ! scan && ! close) { wait (-1); continue; }

        if (scan)
        {
            std::map<juce::String, DeviceLists> lists;
            for (auto& t : backend_->types()) lists[t] = backend_->scan (t);
            std::lock_guard<std::mutex> g (lock);
            snapshot.lists = lists;
        }
        if (close)
        {
            backend_->close();
            std::lock_guard<std::mutex> g (lock);
            snapshot.open = false;
        }
        if (next)
        {
            auto r = backend_->open (*next, callback);
            std::lock_guard<std::mutex> g (lock);
            snapshot.opens++;
            snapshot.opened = *next;
            snapshot.open = r.ok;
            snapshot.info = r;
            snapshot.error = r.ok ? juce::String() : r.error;
        }
        {
            std::lock_guard<std::mutex> g (lock);
            snapshot.busy = pending.has_value() || wantScan;
        }
        publish();
    }
    backend_->finishThread();
}

} // namespace practice
