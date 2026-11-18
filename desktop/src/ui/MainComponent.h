#pragma once
// The window's content: a top bar (Metronome and Drills, then Progress and Settings as icons, an Update button when a
// newer build is ready, and a line when the metronome is ticking behind another screen) over the screen in use. A
// run, its result and the calibration take the content area while they last.
#include "Screens.h"

namespace practice::ui {

class MainComponent : public juce::Component, private juce::ChangeListener {
public:
    explicit MainComponent (Model&);
    ~MainComponent() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    bool keyPressed (const juce::KeyPress&) override;

    enum class Page { metronome, drills, progress, settings };
    void show (Page p);
    /// Draws every screen, dark and light, at the default size and at 1280 by 800, into `folder` (the design check).
    static void screenshots (Model& model, const juce::File& folder);

private:
    void changeListenerCallback (juce::ChangeBroadcaster*) override;
    void refresh();
    Screen* current();

    Model& model;
    Page page = Page::drills, back = Page::drills;
    Segmented tabs { { "Metronome", "Drills" } };
    Button backButton { Button::Kind::text, "Back", "back" };
    Button progressButton { Button::Kind::icon, {}, "chart" }, settingsButton { Button::Kind::icon, {}, "settings" };
    Button updateButton { Button::Kind::text, "Update", "download" }, metroStop { Button::Kind::text, "Stop" };
    MetronomeScreen metronome { model };
    DrillsScreen drills { model };
    RunScreen run { model };
    ResultScreen result { model };
    CalibrationScreen calibration { model };
    ProgressScreen progress { model };
    SettingsScreen settings { model };
    juce::Rectangle<int> bar, titleArea, metroLine;
    juce::TooltipWindow tooltips { this, 600 };
    Screen* shown = nullptr;
};

} // namespace practice::ui
