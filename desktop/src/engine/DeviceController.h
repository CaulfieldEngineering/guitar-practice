#pragma once
// Picking an audio device without ever freezing (the iPhone app froze in 0.2.0 when a device was picked a few times:
// three listeners each asked the system again on every change and the main thread spun; 0.2.1 coalesced them).
// Here every device call (scanning, opening an ASIO driver, starting WASAPI exclusive) runs on one worker thread
// that owns the devices. The UI only posts what it wants and reads a snapshot back:
//   - request() never waits: it stores the newest wish and wakes the worker. Picks made while a device is opening
//     are coalesced: only the newest is opened next, the ones in between are dropped.
//   - state() copies the latest snapshot under a short lock that the worker never holds during a device call.
//   - onChange is called from the worker; the app hops to the message thread itself.
// The backend is an interface so the stress test can stand in a slow fake device (desktop/tests).
#include <juce_audio_devices/juce_audio_devices.h>
#include <functional>
#include <map>
#include <mutex>

namespace practice {

struct DeviceSetup {
    juce::String type;         // "ASIO", "Windows Audio (Exclusive Mode)", "Windows Audio"
    juce::String input;        // device name ("" for none); for ASIO the same as output
    juce::String output;
    int inputChannel = -1;     // -1: inputs 1 and 2 summed; 0: input 1; 1: input 2
    double sampleRate = 0;     // 0: the device's own
    int bufferSize = 0;        // 0: the device's own
    bool operator== (const DeviceSetup& o) const
    {
        return type == o.type && input == o.input && output == o.output && inputChannel == o.inputChannel
            && sampleRate == o.sampleRate && bufferSize == o.bufferSize;
    }
    bool operator!= (const DeviceSetup& o) const { return ! (*this == o); }
    juce::var toVar() const;
    static DeviceSetup fromVar (const juce::var& v);
    /// A key for this pair of devices (calibrations are kept per pair, as the phone keeps them per route).
    juce::String routeKey() const { return "in:" + type + "/" + input + "|out:" + type + "/" + output; }
    juce::String outputKey() const { return type + "/" + output; }
};

struct DeviceLists {
    juce::StringArray inputs, outputs;
    bool sameDeviceForBoth = false;   // ASIO: one driver is both
};

struct OpenResult {
    bool ok = false;
    juce::String error;
    double sampleRate = 0;
    int bufferSize = 0;
    int inputLatency = 0, outputLatency = 0;   // samples, as the driver reports them
    juce::Array<double> rates;
    juce::Array<int> buffers;
    int inputChannels = 0;
};

class DeviceBackend {
public:
    virtual ~DeviceBackend() = default;
    virtual void prepareThread() {}
    virtual juce::StringArray types() = 0;
    virtual DeviceLists scan (const juce::String& type) = 0;
    virtual OpenResult open (const DeviceSetup& setup, juce::AudioIODeviceCallback* callback) = 0;
    virtual void close() = 0;
    virtual void finishThread() {}
};

/// The real one: JUCE's ASIO and WASAPI types, made and used only on the worker thread.
class JuceDeviceBackend : public DeviceBackend {
public:
    JuceDeviceBackend();
    ~JuceDeviceBackend() override;
    void prepareThread() override;
    juce::StringArray types() override;
    DeviceLists scan (const juce::String& type) override;
    OpenResult open (const DeviceSetup& setup, juce::AudioIODeviceCallback* callback) override;
    void close() override;
    void finishThread() override;
    std::function<void()> onDeviceListChanged;   // called on the message thread by the system
private:
    juce::AudioIODeviceType* findType (const juce::String& name);
    struct Listener;
    std::unique_ptr<Listener> listener;
    juce::OwnedArray<juce::AudioIODeviceType> deviceTypes;
    std::unique_ptr<juce::AudioIODevice> device;
    bool comReady = false;
};

class DeviceController : private juce::Thread {
public:
    struct State {
        DeviceSetup wanted;        // the newest pick
        DeviceSetup opened;        // what is open now
        bool open = false;
        bool busy = false;         // the worker is opening or scanning
        juce::String error;        // in plain words, when the last pick failed
        OpenResult info;
        juce::StringArray types;
        std::map<juce::String, DeviceLists> lists;
        int opens = 0;             // how many times a device was opened (the stress test reads it)
        int requests = 0;
    };

    DeviceController (std::unique_ptr<DeviceBackend> backend, juce::AudioIODeviceCallback* callback);
    ~DeviceController() override;

    void start();
    /// Never waits. The newest pick wins; picks made while one is opening are dropped.
    void request (const DeviceSetup& setup);
    void rescan();
    void closeDevice();
    State state() const;
    std::function<void()> onChange;   // from the worker thread
    DeviceBackend& backend() { return *backend_; }

private:
    void run() override;
    void publish();

    std::unique_ptr<DeviceBackend> backend_;
    juce::AudioIODeviceCallback* callback;
    mutable std::mutex lock;
    State snapshot;
    std::optional<DeviceSetup> pending;
    bool wantScan = true, wantClose = false;
};

} // namespace practice
