// Practice for Windows: Joe's guitar practice app on the computer (desktop/README.md).
//   Practice.exe                      the app
//   Practice.exe --screens <folder>   draws every screen, dark and light, at two sizes, and quits (the design check)
//   Practice.exe --data <folder>      keeps its settings and runs in that folder instead of %APPDATA%\Practice
//   Practice.exe --selftest <report>  drives the real app on the real audio device: the metronome, an unscored run,
//                                     pause and resume, a scored run (picks injected where there is no input), device
//                                     picks while idle; writes a report and quits (exit code 1 on any failure)
#include <JuceHeader.h>
#include "ui/MainComponent.h"
#include <set>

using namespace practice;

/// The self-test: a script of steps, each waiting on the app's own state, run on the message thread as clicks are.
class SelfTest : private juce::Timer {
public:
    SelfTest (Model& m, juce::File r) : model (m), report (std::move (r)) { startTimer (10); }
    std::function<void (bool)> onDone;

private:
    Model& model;
    juce::File report;
    juce::StringArray lines;
    int step = 0, fails = 0;
    double stepStart = 0, worstPick = 0;
    std::set<size_t> injected;
    bool sawBeat = false;
    juce::Random rnd { 20261117 };

    static double now() { return juce::Time::getMillisecondCounterHiRes() / 1000.0; }
    void check (bool ok, const juce::String& what) { lines.add ((ok ? "ok    " : "FAIL  ") + what); if (! ok) ++fails; }
    void next() { ++step; stepStart = now(); }
    double since() const { return now() - stepStart; }

    void finish()
    {
        stopTimer();
        lines.add (juce::String (fails == 0 ? "PASSED" : "FAILED") + " (" + juce::String (fails) + " failures)");
        report.replaceWithText (lines.joinIntoString (juce::newLine) + juce::newLine);
        if (onDone) onDone (fails == 0);
    }

    // a steady player: 6 ms late on average, a little spread, every note
    void injectPicks()
    {
        for (size_t i = 0; i < model.notes.size(); ++i)
            if (! injected.count (i) && model.notes[i].time <= model.now + 0.02)
            {
                injected.insert (i);
                model.debugPick (model.notes[i].time + 0.006 + (rnd.nextDouble() - 0.5) * 0.012);
            }
    }

    void timerCallback() override
    {
        if (stepStart == 0) stepStart = now();
        using P = Model::Phase;
        switch (step)
        {
            case 0:   // the device opens by itself on first start
                if (model.device.open)
                {
                    check (true, "audio device open: " + model.routeName() + ", " + juce::String (model.device.info.sampleRate) + " Hz, buffer "
                                 + juce::String (model.device.info.bufferSize) + " (" + model.device.opened.type + ")");
                    next();
                }
                else if (since() > 15) { check (false, "audio device opens (" + model.device.error + ")"); finish(); }
                break;
            case 1:
                if (since() < 0.5) break;
                model.toggleMetronome();
                check (model.metronomeRunning(), "metronome starts");
                next();
                break;
            case 2:
                sawBeat |= model.metronomeBeat() >= 0;
                if (since() > 1.5)
                {
                    check (sawBeat, "metronome beats light up");
                    model.toggleMetronome();
                    check (! model.metronomeRunning(), "metronome stops");
                    next();
                }
                break;
            case 3:
            {
                model.select ("alt8");
                model.setAudioInput (false); model.setIntro (false); model.setGuided (true); model.setManual (true); model.setBPM (200);
                auto s = model.session; s.kind = SessionSettings::Kind::cycles; s.cycles = 8; s.ladderStep = 0; model.setSession (s);
                model.start();
                check (model.phase == P::running, "an unscored run starts");
                next();
                break;
            }
            case 4:
                if (model.phase == P::result)
                {
                    check (model.unscored && model.unscored->seconds > 0.5, "the unscored run ends by itself with its minutes ("
                           + juce::String (model.unscored ? model.unscored->seconds : 0.0, 2) + " s)");
                    model.clearResult();
                    next();
                }
                else if (since() > 8) { check (false, "the unscored run ends"); finish(); }
                break;
            case 5:
            {
                auto s = model.session; s.cycles = 12; model.setSession (s);
                model.start();
                next();
                break;
            }
            case 6:
                if (since() > 1.0) { model.pause(); check (model.phase == P::paused, "a run pauses"); next(); }
                break;
            case 7:
                if (since() > 0.5) { model.resumeRun(); check (model.phase == P::running, "and resumes"); next(); }
                break;
            case 8:
                if (model.phase == P::result) { check (model.unscored.has_value(), "the resumed run ends"); model.clearResult(); next(); }
                else if (since() > 10) { check (false, "the resumed run ends"); finish(); }
                break;
            case 9:
            {
                model.selfTestNoInput = true;
                model.engine.testPicks = true;
                model.select ("trip16x4");
                model.setAudioInput (true); model.setIntro (false); model.setGuided (false); model.setManual (true); model.setBPM (120);
                auto s = model.session; s.kind = SessionSettings::Kind::cycles; s.cycles = 2; s.ladderStep = 0; model.setSession (s);
                injected.clear();
                model.start();
                check (model.phase == P::running, "a scored run starts");
                next();
                break;
            }
            case 10:
                if (model.phase == P::running) injectPicks();
                if (model.phase == P::result)
                {
                    const auto& sc = model.score;
                    // injected 6 ms late with up to 6 ms either way: the average and spread must come back as put in
                    const bool ok = sc && model.saved && sc->score >= 90 && sc->missed == 0 && sc->extra == 0
                                 && std::abs (sc->meanError - 6) < 1.5 && sc->spread > 1.5 && sc->spread < 5;
                    check (ok, "the scored run scores a steady player (" + (sc ? juce::String (sc->score) + "%, average " + juce::String (sc->meanError, 1)
                                 + " ms, spread " + juce::String (sc->spread, 1) + " ms, missed " + juce::String (sc->missed) + ", extra "
                                 + juce::String (sc->extra) + ", first errors " + [&] { juce::String e; for (size_t k = 0; k < 4 && k < sc->errors.size(); ++k) e << (sc->errors[k] ? juce::String (*sc->errors[k], 2) : juce::String ("-")) << " "; return e; }() : juce::String ("no score")) + ")");
                    auto saved = model.history.results();
                    check (model.saved && ! saved.empty() && saved.front().id == model.saved->id, "the run is saved and queued for the drill server");
                    model.clearResult();
                    model.selfTestNoInput = false;
                    model.engine.testPicks = false;
                    next();
                }
                else if (since() > 30) { check (false, "the scored run ends"); finish(); }
                break;
            case 11:
            {
                // device picks while idle: none may wait
                auto lists = model.device.lists;
                juce::StringArray kinds;
                for (auto& [k, l] : lists) if (! l.outputs.isEmpty() && k != "ASIO") kinds.add (k);
                const auto keep = model.deviceSetup;
                for (int i = 0; i < 40 && ! kinds.isEmpty(); ++i)
                {
                    auto k = kinds[i % kinds.size()];
                    auto& l = lists[k];
                    DeviceSetup s { k, l.inputs.isEmpty() ? juce::String() : l.inputs[0], l.outputs[i % l.outputs.size()], -1 };
                    const double t0 = juce::Time::getMillisecondCounterHiRes();
                    model.pickDevice (s);
                    worstPick = std::max (worstPick, juce::Time::getMillisecondCounterHiRes() - t0);
                }
                model.pickDevice (keep);
                check (worstPick < 10, "40 device picks in a row never wait (worst " + juce::String (worstPick, 2) + " ms)");
                next();
                break;
            }
            case 12:
                if (! model.device.busy && model.device.opened == model.deviceSetup && since() > 0.3)
                {
                    check (model.device.open, "settles on the last pick, open: " + model.routeName());
                    finish();
                }
                else if (since() > 20) { check (false, "settles after the picks"); finish(); }
                break;
            default: break;
        }
    }
};

class PracticeApp : public juce::JUCEApplication {
public:
    const juce::String getApplicationName() override { return "Practice"; }
    const juce::String getApplicationVersion() override { return PRACTICE_VERSION; }
    // one window for him; the design check and the self-test may run beside it
    bool moreThanOneInstanceAllowed() override { return getCommandLineParameters().contains ("--"); }

    void initialise (const juce::String& commandLine) override
    {
        auto args = juce::StringArray::fromTokens (commandLine, true);
        for (auto& a : args) a = a.unquoted();
        const int dataAt = args.indexOf ("--data");
        const int screensAt = args.indexOf ("--screens");
        const int selfAt = args.indexOf ("--selftest");
        auto paths = AppPaths::find (dataAt >= 0 ? juce::File (args[dataAt + 1]) : juce::File());
        if (screensAt >= 0)
        {
            model = std::make_unique<Model> (paths, true);
            model->freeze();
            ui::MainComponent::screenshots (*model, juce::File (args[screensAt + 1]));
            quit();
            return;
        }
        if (selfAt >= 0)
        {
            model = std::make_unique<Model> (paths, true);
            selfTest = std::make_unique<SelfTest> (*model, juce::File (args[selfAt + 1]));
            selfTest->onDone = [this] (bool ok) { setApplicationReturnValue (ok ? 0 : 1); quit(); };
            return;
        }
        model = std::make_unique<Model> (paths, false);
        ui::Theme::setDark (model->settings.getBool ("dark", true));
        lnf = std::make_unique<ui::LookAndFeel>();
        juce::LookAndFeel::setDefaultLookAndFeel (lnf.get());
        window = std::make_unique<Window> (*model);
    }

    void shutdown() override
    {
        window.reset();
        selfTest.reset();
        juce::LookAndFeel::setDefaultLookAndFeel (nullptr);
        lnf.reset();
        model.reset();
    }

    void systemRequestedQuit() override { quit(); }
    void anotherInstanceStarted (const juce::String&) override { if (window) window->toFront (true); }

private:
    class Window : public juce::DocumentWindow {
    public:
        explicit Window (Model& m)
            : juce::DocumentWindow ("Practice", ui::Theme::bg(), juce::DocumentWindow::allButtons)
        {
            setUsingNativeTitleBar (true);
            setContentOwned (new ui::MainComponent (m), false);
            setResizable (true, false);
            setResizeLimits (900, 640, 4000, 3000);
            centreWithSize (1100, 720);
            setVisible (true);
        }
        void closeButtonPressed() override { juce::JUCEApplication::getInstance()->systemRequestedQuit(); }
    };

    std::unique_ptr<Model> model;
    std::unique_ptr<ui::LookAndFeel> lnf;
    std::unique_ptr<Window> window;
    std::unique_ptr<SelfTest> selfTest;
};

START_JUCE_APPLICATION (PracticeApp)
