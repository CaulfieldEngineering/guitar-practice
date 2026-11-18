#pragma once
// What the desktop app keeps on the computer (%APPDATA%\Practice): its settings, the calibrations per pair of audio
// devices, every run it made (and which of them the drill server has acknowledged), the server's copy of every run
// from every device (for Progress when offline), the catalog and voice it last pulled.
#include "../core/Results.h"
#include "../engine/DeviceController.h"
#include <mutex>

namespace practice {

struct AppPaths {
    juce::File data;        // %APPDATA%\Practice
    juce::File resources;   // the bundled catalog, voice and guitar (beside the program, or the repo in a dev build)
    juce::File catalogBundled() const { return resources.getChildFile ("catalog"); }
    juce::File catalogCache() const { return data.getChildFile ("catalog"); }
    juce::File catalogUser() const { return data.getChildFile ("Exercises"); }
    juce::File voiceBundled() const { return resources.getChildFile ("voice"); }
    juce::File voiceCache() const { return data.getChildFile ("voice"); }
    juce::File guitar() const;
    static AppPaths find (const juce::File& dataOverride = {});
};

/// The calibration of one pair of devices: what was measured on top of what the drivers report.
struct Calibration {
    double residual = 0;     // seconds: measured minus the drivers' estimate when it was measured
    double measured = 0;     // seconds, the whole offset that day
    juce::String routeName;
    juce::Time date;
    std::optional<double> spreadMs;
    std::optional<int> hits;
};

class Settings {
public:
    explicit Settings (const juce::File& file);
    ~Settings();
    juce::var get (const juce::String& key, const juce::var& dflt = {}) const;
    void set (const juce::String& key, const juce::var& value);
    int getInt (const juce::String& key, int dflt) const;
    bool getBool (const juce::String& key, bool dflt) const;
    double getDouble (const juce::String& key, double dflt) const;
    void save();

    std::optional<Calibration> calibration (const juce::String& routeKey) const;
    void setCalibration (const juce::String& routeKey, const Calibration& c);
    double displayOffset (const juce::String& outputKey) const;
    void setDisplayOffset (const juce::String& outputKey, double seconds);
    double unscoredSeconds (const juce::String& drill) const;
    void addUnscored (const juce::String& drill, double seconds);
    juce::String serverBase() const;

private:
    juce::File file;
    juce::var root;
    bool dirty = false;
};

/// Every run made on this computer, and which ones the drill server has acknowledged (the send queue).
class History {
public:
    explicit History (const juce::File& file);
    void add (const SessionResult& r);
    std::vector<SessionResult> results() const;       // newest first
    std::vector<SessionResult> pending() const;       // not yet acknowledged
    void markUploaded (const juce::StringArray& ids);
    int pendingCount() const;
private:
    void save() const;
    juce::File file;
    mutable std::mutex lock;
    struct Entry { SessionResult result; bool uploaded = false; };
    std::vector<Entry> entries;
};

} // namespace practice
