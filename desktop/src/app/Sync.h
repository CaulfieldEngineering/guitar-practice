#pragma once
// The common backend: the drill server on the mini PC (server/index.mjs, port 4700; its address is set in Settings, by default the one in config.local.json) is where both
// apps get their drills, the scoring numbers and the voice, and where every run from either app is kept. This side:
//   - sends every run not yet acknowledged (POST /api/sessions, 50 at a time) until the server answers with its id;
//     away from the server the runs wait in the queue (History) and go at the next sync,
//   - reads every run from every device (GET /api/sessions) for Progress, and his max per drill (GET /api/levels),
//   - pulls a newer catalog or voice when the server has one, swapping it in whole only when every file read,
//   - asks whether a newer desktop build is out (GET /desktop/latest.json).
// All of it runs on one worker thread, every 30 seconds and whenever kicked; nothing here ever runs on the UI thread.
#include "Store.h"
#include <functional>

namespace practice {

namespace DrillServer {
    struct Response { int status = 0; juce::String body; bool ok() const { return status == 200; } };
    Response get (const juce::String& url, int timeoutMs = 5000);
    Response post (const juce::String& url, const juce::String& json, int timeoutMs = 8000);
    bool download (const juce::String& url, const juce::File& to, int timeoutMs = 20000);

    /// Sends runs; answers the ids the server now holds (empty when it could not be reached).
    juce::StringArray send (const juce::String& base, const std::vector<SessionResult>& runs);
    std::optional<std::vector<SessionResult>> sessions (const juce::String& base);
    std::optional<std::map<juce::String, int>> levels (const juce::String& base);
    enum class Pull { updated, upToDate, unreachable, invalid };
    Pull pullCatalog (const juce::String& base, const juce::File& cache, int have);
    bool pullVoice (const juce::String& base, const juce::File& cache, int have);
}

class SyncWorker : private juce::Thread {
public:
    struct Snapshot {
        std::optional<bool> reachable;
        juce::Time lastSync;
        std::vector<SessionResult> serverRuns;   // every run the server holds, newest first
        std::map<juce::String, int> levels;
        int pending = 0;
        DrillServer::Pull catalog = DrillServer::Pull::upToDate;
        bool catalogChanged = false, voiceChanged = false;
        juce::var update;                        // the server's latest.json for the desktop app, when newer
    };

    SyncWorker (History& history, std::function<juce::String()> base, AppPaths paths, juce::String appVersion);
    ~SyncWorker() override;
    void start (int intervalMs = 30000);
    void kick();                       // sync now
    Snapshot snapshot() const;
    std::function<void()> onChange;    // from the worker
    std::function<int()> catalogVersion, voiceVersion;   // what the app has now
    /// More to do on each pass once the server answered (routines, routine runs, settings), on this thread.
    std::function<void (const juce::String& base)> extra;
    void runOnceForTest();             // one pass on the calling thread (the sync test)

private:
    void run() override;
    void pass();
    History& history;
    std::function<juce::String()> base;
    AppPaths paths;
    juce::String appVersion;
    int interval = 30000;
    mutable std::mutex lock;
    Snapshot snap;
};

/// "0.1.10" > "0.1.9"
bool versionNewer (const juce::String& a, const juce::String& b);

} // namespace practice
