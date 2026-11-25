#include "MainComponent.h"

namespace practice::ui {

static constexpr int sideW = 176;

MainComponent::MainComponent (Model& m) : model (m)
{
    setWantsKeyboardFocus (true);
    for (auto* s : std::initializer_list<Screen*> { &metronome, &drills, &run, &result, &calibration, &routines, &runnerScreen, &progress, &settings })
        addChildComponent (s);
    settings.onCalibrate = [this] { model.startCalibration(); };
    calibration.onDone = [this] { refresh(); };
    model.addChangeListener (this);
    runner.addChangeListener (this);
    refresh();
}

MainComponent::~MainComponent()
{
    runner.removeChangeListener (this);
    model.removeChangeListener (this);
}

void MainComponent::show (Page p)
{
    if (p != Page::drills && (model.phase == Model::Phase::running || model.phase == Model::Phase::paused || model.phase == Model::Phase::intro
                              || model.phase == Model::Phase::resting) && ! runner.open())
        model.leave();   // leaving a drill ends it (Joe, 0.1.6: "Drills keep running when I leave the drill")
    if (p == Page::drills && page == Page::drills) drills.setupOpen = false;
    page = p;
    refresh();
}

bool MainComponent::fullWindow() const
{
    if (runner.open()) return true;
    switch (model.phase)
    {
        case Model::Phase::syncing: case Model::Phase::calibrating: case Model::Phase::intro: case Model::Phase::running:
        case Model::Phase::paused: case Model::Phase::resting: case Model::Phase::result: return true;
        default: return false;
    }
}

Screen* MainComponent::current()
{
    if (runner.open()) return &runnerScreen;
    switch (model.phase)
    {
        case Model::Phase::syncing: case Model::Phase::calibrating: return &calibration;
        case Model::Phase::intro: case Model::Phase::running: case Model::Phase::paused: case Model::Phase::resting: return &run;
        case Model::Phase::result: return &result;
        default: break;
    }
    switch (page)
    {
        case Page::metronome: return &metronome;
        case Page::routines: return &routines;
        case Page::progress: return &progress;
        case Page::settings: return &settings;
        default: return &drills;
    }
}

void MainComponent::refresh()
{
    auto* s = current();
    if (s != shown)
    {
        for (auto* x : std::initializer_list<Screen*> { &metronome, &drills, &run, &result, &calibration, &routines, &runnerScreen, &progress, &settings })
            x->setVisible (x == s);
        shown = s;
        resized();
        s->refresh();
        if (isShowing()) s->grabKeyboardFocus();
    }
    else
        s->refresh();
    repaint (side);
}

void MainComponent::changeListenerCallback (juce::ChangeBroadcaster*) { refresh(); }

void MainComponent::resized()
{
    auto r = getLocalBounds();
    if (fullWindow()) side = {};
    else side = r.removeFromLeft (sideW);
    navRows.clear();
    if (! side.isEmpty())
    {
        auto s = side.reduced (Theme::sp4, Theme::sp6);
        s.removeFromTop (Theme::sp4);
        for (auto p : { Page::metronome, Page::drills, Page::routines, Page::progress }) { navRows.push_back ({ s.removeFromTop (Theme::rowH + 4), p }); s.removeFromTop (2); }
        navRows.push_back ({ s.removeFromBottom (Theme::rowH + 4), Page::settings });
        s.removeFromBottom (Theme::sp4);
        updateRow = model.updateFile.existsAsFile() ? s.removeFromBottom (Theme::rowH) : juce::Rectangle<int>();
        metroLine = model.metronomeRunning() && page != Page::metronome && ! model.blockClickOn ? s.removeFromBottom (Theme::rowH) : juce::Rectangle<int>();
    }
    if (shown) shown->setBounds (r);
}

void MainComponent::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    if (side.isEmpty()) return;
    g.setColour (Theme::side());
    g.fillRect (side);
    g.setColour (Theme::line());
    g.fillRect (side.getRight() - 1, 0, 1, getHeight());
    const char* names[] = { "Metronome", "Drills", "Routines", "Progress", "Settings" };
    const char* icons[] = { "timer", "guitar", "list", "chart", "settings" };
    for (int i = 0; i < (int) navRows.size(); ++i)
    {
        auto [row, p] = navRows[(size_t) i];
        const bool sel = p == page;
        if (sel || i == hoverRow)
        {
            g.setColour (sel ? Theme::active() : Theme::hover());
            g.fillRoundedRectangle (row.toFloat(), Theme::rMd);
        }
        auto in = row.reduced (Theme::sp4, 0);
        Theme::icon (g, icons[(int) p], in.removeFromLeft (16).withSizeKeepingCentre (16, 16).toFloat(), sel ? Theme::text() : Theme::muted());
        in.removeFromLeft (Theme::sp4);
        Draw::text (g, names[(int) p], in, sel ? Theme::text() : Theme::muted(), Theme::body, sel);
    }
    if (! updateRow.isEmpty())
        Draw::text (g, "Update to " + model.updateVersion, updateRow.reduced (Theme::sp4, 0), Theme::accentText(), Theme::body, true);
    if (! metroLine.isEmpty())
    {
        auto in = metroLine.reduced (Theme::sp4, 0);
        g.setColour (Theme::accent());
        g.fillEllipse ((float) in.getX(), (float) in.getCentreY() - 3, 6, 6);
        Draw::text (g, juce::String (model.metroBPM) + " bpm, Stop", in.withTrimmedLeft (12), Theme::muted(), Theme::small);
    }
}

void MainComponent::mouseUp (const juce::MouseEvent& e)
{
    for (auto& [row, p] : navRows) if (row.contains (e.getPosition())) { show (p); return; }
    if (updateRow.contains (e.getPosition())) { model.installUpdate(); return; }
    if (metroLine.contains (e.getPosition())) { model.toggleMetronome(); return; }
}

void MainComponent::mouseMove (const juce::MouseEvent& e)
{
    int h = -1;
    for (int i = 0; i < (int) navRows.size(); ++i) if (navRows[(size_t) i].first.contains (e.getPosition())) h = i;
    if (h != hoverRow) { hoverRow = h; repaint (side); }
}

void MainComponent::mouseExit (const juce::MouseEvent&) { if (hoverRow != -1) { hoverRow = -1; repaint (side); } }

bool MainComponent::keyPressed (const juce::KeyPress& k)
{
    if (k.getModifiers().isCtrlDown() && k.getKeyCode() == ',') { show (Page::settings); return true; }
    if (k.getModifiers().isCtrlDown() && k.getKeyCode() >= '1' && k.getKeyCode() <= '4') { show ((Page) (k.getKeyCode() - '1')); return true; }
    return false;
}

// ---- the design check: every screen as a picture ----

void MainComponent::screenshots (Model& model, const juce::File& folder)
{
    folder.createDirectory();
    struct Size { int w, h; const char* name; } sizes[] = { { 1100, 720, "default" }, { 1280, 800, "1280" } };
    for (bool dark : { true, false })
    {
        Theme::setDark (dark);
        for (auto& sz : sizes)
        {
            auto snap = [&] (const juce::String& name, std::function<void (MainComponent&)> setup) {
                LookAndFeel lnf;
                juce::LookAndFeel::setDefaultLookAndFeel (&lnf);
                {
                    MainComponent mc (model);
                    mc.setSize (sz.w, sz.h);
                    setup (mc);
                    mc.refresh();
                    mc.resized();
                    if (mc.shown) { mc.shown->refresh(); mc.shown->resized(); mc.shown->refresh(); }
                    auto img = mc.createComponentSnapshot (mc.getLocalBounds(), true, 1.0f);
                    juce::PNGImageFormat png;
                    auto f = folder.getChildFile (name + "-" + sz.name + (dark ? "-dark" : "-light") + ".png");
                    f.deleteFile();
                    juce::FileOutputStream out (f);
                    png.writeImageToStream (img, out);
                    mc.runner.close();
                }
                juce::LookAndFeel::setDefaultLookAndFeel (nullptr);
            };
            auto seedSession = [&] (std::function<void (SessionSettings&)> f) { auto s = model.session; f (s); model.setSession (s); };
            const auto before = model.session;
            snap ("01-metronome", [] (MainComponent& mc) { mc.show (Page::metronome); });
            snap ("02-drills", [] (MainComponent& mc) { mc.show (Page::drills); });
            snap ("03-setup", [] (MainComponent& mc) { mc.show (Page::drills); mc.drills.setupOpen = true; });
            seedSession ([] (SessionSettings& s) { s.tempoPlan.mode = TempoPlan::Mode::accuracy; s.tempoPlan.breakOn = true; });
            snap ("04-setup-by-accuracy", [] (MainComponent& mc) { mc.show (Page::drills); mc.drills.setupOpen = true; });
            seedSession ([] (SessionSettings& s) { s.tempoPlan.mode = TempoPlan::Mode::off; s.kind = SessionSettings::Kind::challenge; s.seconds = 300; s.targetPercent = 90; });
            snap ("05-setup-challenge", [] (MainComponent& mc) { mc.show (Page::drills); mc.drills.setupOpen = true; });
            model.setSession (before);
            model.debugSeed (1);
            snap ("06-run", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (5);
            snap ("07-run-by-accuracy", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (6);
            snap ("08-break", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (2);
            snap ("09-run-paused", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (3);
            snap ("10-result", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (4);
            snap ("11-calibration", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (0);
            snap ("12-routines", [] (MainComponent& mc) { mc.show (Page::routines); });
            snap ("13-routine-block", [&] (MainComponent& mc) {
                mc.show (Page::routines);
                if (auto r = model.routines->routines(); ! r.empty() && r.front().blocks.size() > 1) { mc.routines.selected = r.front().id; mc.routines.blockSelected = r.front().blocks[1].id; }
            });
            snap ("14-runner-countdown", [&] (MainComponent& mc) { if (auto r = model.routines->routines(); ! r.empty()) mc.runner.start (r.front()); });
            snap ("15-progress", [] (MainComponent& mc) { mc.show (Page::progress); });
            snap ("16-settings", [] (MainComponent& mc) { mc.show (Page::settings); });
        }
    }
    Theme::setDark (true);
}

} // namespace practice::ui
