#include "MainComponent.h"

namespace practice::ui {

MainComponent::MainComponent (Model& m) : model (m)
{
    setWantsKeyboardFocus (true);
    for (auto* c : std::initializer_list<juce::Component*> { &tabs, &progressButton, &settingsButton })
        addAndMakeVisible (c);
    addChildComponent (backButton);
    addChildComponent (updateButton);
    addChildComponent (metroStop);
    for (auto* s : std::initializer_list<Screen*> { &metronome, &drills, &run, &result, &calibration, &progress, &settings })
        addChildComponent (s);
    tabs.setSelected (1);
    tabs.onChange = [this] (int i) { show (i == 0 ? Page::metronome : Page::drills); };
    backButton.onClick = [this] { show (back); };
    progressButton.setTooltip ("Progress");
    progressButton.onClick = [this] { show (Page::progress); };
    settingsButton.setTooltip ("Settings");
    settingsButton.onClick = [this] { show (Page::settings); };
    updateButton.setTooltip ("Install the new version and restart");
    updateButton.onClick = [this] { model.installUpdate(); };
    metroStop.onClick = [this] { model.toggleMetronome(); };
    settings.onCalibrate = [this] { model.startCalibration(); };
    calibration.onDone = [this] { refresh(); };
    model.addChangeListener (this);
    refresh();
}

MainComponent::~MainComponent() { model.removeChangeListener (this); }

void MainComponent::show (Page p)
{
    if (p == Page::progress || p == Page::settings) { if (page != Page::progress && page != Page::settings) back = page; }
    if ((p == Page::metronome || p == Page::progress || p == Page::settings)
        && (model.phase == Model::Phase::running || model.phase == Model::Phase::paused || model.phase == Model::Phase::intro))
        model.leave();   // leaving a drill ends it (Joe, 0.1.6: "Drills keep running when I leave the drill")
    if (p == Page::metronome || p == Page::drills) tabs.setSelected (p == Page::metronome ? 0 : 1);
    page = p;
    refresh();
}

Screen* MainComponent::current()
{
    switch (model.phase)
    {
        case Model::Phase::syncing: case Model::Phase::calibrating: return &calibration;
        case Model::Phase::intro: case Model::Phase::running: case Model::Phase::paused: if (page == Page::drills) return &run; break;
        case Model::Phase::result: if (page == Page::drills) return &result; break;
        default: break;
    }
    switch (page)
    {
        case Page::metronome: return &metronome;
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
        for (auto* x : std::initializer_list<Screen*> { &metronome, &drills, &run, &result, &calibration, &progress, &settings })
            x->setVisible (x == s);
        shown = s;
        s->refresh();
        resized();
        if (isShowing()) s->grabKeyboardFocus();
    }
    else
        s->refresh();
    const bool sub = page == Page::progress || page == Page::settings;
    tabs.setVisible (! sub);
    backButton.setVisible (sub);
    updateButton.setVisible (model.updateFile.existsAsFile());
    updateButton.setText ("Update to " + model.updateVersion);
    metroStop.setVisible (model.metronomeRunning() && page != Page::metronome);
    resized();
    repaint (bar);
}

void MainComponent::changeListenerCallback (juce::ChangeBroadcaster*) { refresh(); }

void MainComponent::resized()
{
    auto r = getLocalBounds();
    bar = r.removeFromTop (48);
    auto b = bar.reduced (Theme::sp7, 10);
    tabs.setBounds (b.removeFromLeft (tabs.idealWidth()).withSizeKeepingCentre (tabs.idealWidth(), Theme::ctlH));
    backButton.setBounds (bar.reduced (Theme::sp6, 10).withWidth (backButton.idealWidth()));
    titleArea = bar.withSizeKeepingCentre (300, 28);
    settingsButton.setBounds (b.removeFromRight (Theme::ctlH));
    b.removeFromRight (Theme::sp2);
    progressButton.setBounds (b.removeFromRight (Theme::ctlH));
    b.removeFromRight (Theme::sp5);
    if (updateButton.isVisible()) { updateButton.setBounds (b.removeFromRight (updateButton.idealWidth())); b.removeFromRight (Theme::sp5); }
    if (metroStop.isVisible())
    {
        metroStop.setBounds (b.removeFromRight (metroStop.idealWidth()));
        metroLine = b.removeFromRight (160);
    }
    else metroLine = {};
    if (shown) shown->setBounds (r);
}

void MainComponent::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    g.setColour (Theme::line());
    g.fillRect (0, bar.getBottom() - 1, getWidth(), 1);
    if (page == Page::progress || page == Page::settings)
        Draw::text (g, page == Page::progress ? "Progress" : "Settings", titleArea, Theme::text(), Theme::head, true, juce::Justification::centred);
    if (! metroLine.isEmpty())
        Draw::text (g, "Metronome" + juce::String (juce::CharPointer_UTF8 (" \xc2\xb7 ")) + juce::String (model.metroBPM) + " bpm", metroLine, Theme::muted(),
                    Theme::small, false, juce::Justification::centredRight);
}

bool MainComponent::keyPressed (const juce::KeyPress& k)
{
    if (k == juce::KeyPress::escapeKey && (page == Page::progress || page == Page::settings)) { show (back); return true; }
    if (k.getModifiers().isCtrlDown() && k.getKeyCode() == ',') { show (Page::settings); return true; }
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
                    if (mc.shown) mc.shown->refresh();
                    auto img = mc.createComponentSnapshot (mc.getLocalBounds(), true, 1.0f);
                    juce::PNGImageFormat png;
                    auto f = folder.getChildFile (name + "-" + sz.name + (dark ? "-dark" : "-light") + ".png");
                    f.deleteFile();
                    juce::FileOutputStream out (f);
                    png.writeImageToStream (img, out);
                }
                juce::LookAndFeel::setDefaultLookAndFeel (nullptr);
            };
            snap ("01-metronome", [] (MainComponent& mc) { mc.show (Page::metronome); });
            snap ("02-drills", [] (MainComponent& mc) { mc.show (Page::drills); });
            snap ("03-drills-options", [] (MainComponent& mc) { mc.show (Page::drills); mc.drills.optionsToggleForScreens(); });
            model.debugSeed (1);
            snap ("04-run", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (2);
            snap ("05-run-paused", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (3);
            snap ("06-result", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (4);
            snap ("07-calibration", [] (MainComponent& mc) { mc.show (Page::drills); });
            model.debugSeed (0);
            snap ("08-progress", [] (MainComponent& mc) { mc.show (Page::progress); });
            snap ("09-settings", [] (MainComponent& mc) { mc.show (Page::settings); });
        }
    }
    Theme::setDark (true);
}

} // namespace practice::ui
