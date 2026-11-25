#pragma once
// The app's one model, on the message thread: the catalog, the audio engine and its devices, the metronome, the
// play-along (ported from the iPhone app's PlayAlongModel.swift: the same run, the same judging of each cycle, the
// same endurance and ladder, the same result), the calibration in two steps, sync with the drill server, and the
// updater. The screens read it and call it; it tells them to repaint through ChangeBroadcaster.
#include "Store.h"
#include "Sync.h"
#include "Voice.h"
#include "Routines.h"
#include "../core/PitchDetector.h"
#include "../engine/AudioEngine.h"
#include "../engine/DeviceController.h"

namespace practice {

class Model : public juce::ChangeBroadcaster, private juce::Timer {
public:
    /// `resting`: a break the accuracy called for (the tempo plan's Break); a countdown, then the run goes on.
    enum class Phase { ready, intro, syncing, calibrating, running, paused, resting, result };
    /// `wrong`: on time, on the wrong pitch (a pitched note only).
    enum class NoteState { waiting, tight, close, loose, missed, wrong };

    /// A run set up from a routine's drill block: used for that run only, never saved as the drill's own.
    struct RunSetup { juce::String drillID; int bpm = 100; bool guided = false, audioInput = true; SessionSettings session; };
    /// The tempo plan's progress for the run screen.
    struct StepInfo {
        enum class State { perLoop, up, hold, down, rest, settling, top };
        State state = State::hold;
        double fraction = 0;
        juce::String measure;
        int target = 0;
        std::optional<int> next;
    };

    explicit Model (AppPaths paths, bool offline = false);
    ~Model() override;

    AppPaths paths;
    Settings settings;
    History history;
    AudioEngine engine;

    // ---- the catalog ----
    std::vector<Drill> drills;
    TempoZones zones = TempoZones::standard();
    ScoringConfig scoring;
    int catalogVersion = 0;
    juce::String catalogNote;
    void reloadCatalog();
    const Drill& drill() const;          // the selected one
    juce::String drillID;
    void select (const juce::String& id);

    // ---- audio devices ----
    DeviceController& devices() { return *deviceController; }
    DeviceController::State device;      // the latest snapshot
    DeviceSetup deviceSetup;             // what he picked (kept)
    void pickDevice (const DeviceSetup& s);
    juce::String routeName() const;
    bool hasInput() const;
    double latencyEstimate() const;      // seconds: input + output + buffer, as the drivers report them
    std::optional<Calibration> calibration() const;
    double currentOffset() const;        // seconds taken off every pick
    double displayOffset() const;
    void setDisplayOffset (double seconds);
    float meterPeak() const { return engine.inputPeak(); }
    void setMeterListening (bool on);    // the Audio screen's meter wants the input
    void testTone();
    void clickTest();
    void setHearGuitar (bool on);
    void setSoundsGain (float g);
    float soundsGain() const;

    // ---- the metronome ----
    int metroBPM = 100, metroBeats = 4, metroSub = 1;
    bool metroAccent = true;
    SessionSettings::ClickSound metroSound = SessionSettings::ClickSound::click;
    double metroLevel = 1;
    void setMetroSound (SessionSettings::ClickSound s);
    void setMetroLevel (double v);
    /// A routine's warm-up or open practice with a click: the metronome at the block's tempo, nothing of its own
    /// settings changed.
    void startBlockClick (int bpm);
    void stopBlockClick();
    bool blockClickOn = false;
    /// The routine's sounds between blocks: a tick (the last one accented) and the block chime.
    void playTick (bool last);
    void playChime();

    // ---- the guitar's tuning (kept here and on the drill server) ----
    Tuning guitarTuning;
    void setGuitarTuning (const Tuning& t);
    Tuning tuning() const;   // the drill's (or block's) own, else the guitar's

    // ---- routines ----
    std::unique_ptr<RoutineStore> routines;
    std::optional<RunSetup> runSetup;
    std::function<void (const SessionResult*)> onRunEnded;
    juce::String routineRunID;
    void startBlock (const RunSetup& s);
    void endBlockSetup() { runSetup.reset(); routineRunID = {}; onRunEnded = nullptr; }
    bool metronomeRunning() const { return engine.metronomeRunning(); }
    int metronomeBeat() const { return engine.metronomeBeat(); }
    void toggleMetronome();
    void setMetroBPM (int bpm);
    void setMetroBeats (int b);
    void setMetroSub (int s);
    void setMetroAccent (bool a);
    void tap();

    // ---- a drill's setup (remembered per drill) ----
    int bpm = 100;
    SessionSettings session;
    bool guided = true, intro = true, resume = true, audioInput = true, gridClicks = true, voiceCues = false;
    juce::String zoneChoice;
    void setBPM (int v);
    void nudgeTempo (int v);
    void chooseZone (const juce::String& id);
    void setManual (bool manual);
    void apply (const Level& l);
    void setSession (const SessionSettings& s);
    void setGuided (bool g);
    void setIntro (bool on);
    void setAudioInput (bool on);
    void setGridClicks (bool on);
    void setVoiceCues (bool on);
    std::optional<int> level (const juce::String& id = {}) const;   // his max
    const TempoZones::Zone* activeZone() const;
    juce::String zoneLine() const;
    int startTempo() const;

    // ---- the run ----
    Phase phase = Phase::ready;
    juce::String message;
    double now = 0;
    std::vector<Note> notes;
    std::vector<NoteState> states;
    std::vector<std::optional<double>> errors;
    std::vector<CycleSlot> slots;
    double countInEnd = 0, countInUntil = 0;
    std::optional<double> plannedEnd;
    double currentBPM = 0, sustained = 0;
    std::optional<double> rolling, lastCycleAccuracy;
    int runZoneMax = 0;
    bool lastRunWasGuided = false, lastRunWasScored = true;
    std::optional<ScoreResult> score;
    std::optional<SessionResult> saved;
    struct UnscoredRun { double seconds; int startBPM, topBPM, cycles; };
    std::optional<UnscoredRun> unscored;
    bool newBest = false;
    std::optional<std::pair<int, int>> levelUp;
    int doubles = 0;
    // the tempo plan of the run going on, breaks, Challenge, pitches heard
    std::vector<TempoChange> tempoChanges;
    int breaks = 0, resumeBPM = 0, planTop = 0, planFloor = 0;
    double breakLeft = 0, breakLength = 0;
    std::optional<TempoGovernor> governor;
    std::optional<ChallengeClock> challenge;
    std::map<int, double> heardPitch;
    Tuning runTuning;
    void endBreak();
    std::optional<StepInfo> stepInfo() const;
    std::optional<TempoPlan::Zone> accuracyZone() const;
    std::vector<int> meterLines() const;
    const SessionSettings& runSettingsNow() const { return runSettings; }

    void start();
    void calibrate();
    void nowSolo();
    void stop();
    void pause();
    void resumeRun();
    void endRun();
    void clearResult();
    void leave();
    void skipIntro();
    void repeatIntro();
    void startCalibration();    // step 1: sight against sound
    void calibrateInput();      // step 2: the guitar
    static constexpr int calibrationCount = 12;

    double laneNow() const { return now - displayOffset(); }
    const CycleSlot* currentSlot() const;
    std::optional<int> cycleNumber() const;
    SessionSettings::Kind runKind() const { return runSettings.kind; }
    int runCycles() const { return runSettings.cycles; }
    int runTarget() const { return runSettings.targetPercent; }
    const Drill& runDrill() const { return runDrill_; }
    std::vector<double> recentErrors() const;
    double timingSpanMs() const;
    struct GroupCue { int now, next, beatsUntil; };
    std::optional<GroupCue> groupCue() const;
    bool countingIn() const { return now < countInUntil; }

    // ---- progress and sync ----
    std::vector<SessionResult> allRuns() const;   // the server's copy and this computer's, once each, newest first
    SyncWorker::Snapshot syncState;
    void syncNow();
    double unscoredSeconds (const juce::String& id) const { return settings.unscoredSeconds (id); }

    // ---- updates ----
    juce::String appVersion() const { return PRACTICE_VERSION; }
    juce::String updateVersion;     // a newer build, once downloaded
    juce::File updateFile;
    bool updateDownloading = false;
    void installUpdate();

    juce::String computerName() const;

    /// For the screenshots (--screens): 0 ready, 1 a run, 2 paused, 3 a result, 4 the calibration. Made-up values.
    void debugSeed (int which);
    void freeze() { stopTimer(); }
    /// The self-test: score runs on a computer with no input, with picks injected at given plan times.
    bool selfTestNoInput = false;
    void debugPick (double planSeconds, float strength = 1.0f);
    double planOffsetForTest() const { return currentOffset(); }

private:
    void timerCallback() override;
    void loadDrillSettings();
    void saveDrillSettings();
    bool inputReady();
    void begin (bool calibrating);
    void launch (bool calibrating);
    void scheduleAhead();
    void pushEvents (const std::vector<TimedEvent>& events);
    void frame();
    void updateStates();
    void evaluateCycles();
    void finishUnscored();
    void finish (bool stoppedEarly);
    void endSync();
    void stopRunAudio();
    void deviceChanged();
    void speakCues();
    void maybeDownloadUpdate();
    double window() const;
    double shift() const;
    int noteEnd (size_t i) const;
    double tempoForLoop (size_t k) const;
    void takeBreak (size_t judged, int resumeAt);
    void notifyEnded (const SessionResult* r) { if (onRunEnded) { auto f = onRunEnded; f (r); } }
    const Drill& setupDrill() const;
    const SessionSettings& setupSession() const { return runSetup ? runSetup->session : session; }
    bool setupGuided() const { return runSetup ? runSetup->guided : guided; }
    bool setupAudioInput() const { return runSetup ? runSetup->audioInput : audioInput; }
    bool setupIntro() const { return runSetup ? false : intro; }
    int setupTempo() const;
    void syncTuning (const juce::String& base);
    PitchDetector pitchDetector;
    std::vector<Onset> pendingPitch;   // engine seconds; waiting for the samples that tell their pitch
    bool wantsPitch = false;
    double breakStartMs = 0, breakTotal = 0;
    std::vector<TempoStep::Break> breakLog;
    mutable std::mutex tuningLock;

    std::unique_ptr<DeviceController> deviceController;
    std::unique_ptr<SyncWorker> sync;
    VoiceLines voice;
    std::vector<std::shared_ptr<SoundBuffer>> voiceKeep;
    std::shared_ptr<SoundBuffer> introLine;
    double introDeadline = 0;
    std::vector<double> taps;
    bool loading = false, meterListening = false;

    std::vector<Onset> played;
    std::vector<double> gaps;
    std::vector<char> usedPlayed;
    std::vector<int> noteStart;
    std::vector<double> accuracies;
    std::optional<bool> lastPassed;
    int topBPM = 0;
    double scheduledUntil = 0;
    bool doneScheduling = false, runGuided = false, runScored = true;
    SessionSettings runSettings;
    Drill runDrill_ = Drill::fallback();
    juce::int64 origin = 0;
    std::vector<double> calibrationClicks;
    std::vector<TimedEvent> introEvents;
    double pausedAt = 0;
    DeviceSetup runDevice;
    std::shared_ptr<SoundBuffer> toneBuffer;
    int lastCueBeat = -1;
    double lastCueBPM = 0;
    juce::String lastOpenedKey;
};

juce::String formatClock (double seconds);

} // namespace practice
