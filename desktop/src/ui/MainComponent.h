#pragma once
// The window's content (0.3.0): a side panel (Metronome, Drills, Routines, Progress; Settings at the foot; an Update
// link when a newer build is ready) beside the screen in use. A run, a break, its result, the calibration and a
// routine take the whole window while they last; the side panel hides.
#include "Screens.h"

namespace practice::ui {

class MainComponent : public juce::Component, private juce::ChangeListener {
public:
    explicit MainComponent (Model&);
    ~MainComponent() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    bool keyPressed (const juce::KeyPress&) override;
    void mouseUp (const juce::MouseEvent&) override;
    void mouseMove (const juce::MouseEvent&) override;
    void mouseExit (const juce::MouseEvent&) override;

    enum class Page { metronome, drills, routines, progress, settings };
    void show (Page p);
    /// Draws every screen, dark and light, at the default size and at 1280 by 800, into `folder` (the design check).
    static void screenshots (Model& model, const juce::File& folder);

private:
    void changeListenerCallback (juce::ChangeBroadcaster*) override;
    void refresh();
    Screen* current();
    bool fullWindow() const;

    Model& model;
    RoutineRunner runner { model };
    Page page = Page::drills;
    MetronomeScreen metronome { model };
    DrillsScreen drills { model };
    RunScreen run { model };
    ResultScreen result { model };
    CalibrationScreen calibration { model };
    RoutinesScreen routines { model, runner };
    RunnerScreen runnerScreen { model, runner };
    ProgressScreen progress { model };
    SettingsScreen settings { model };
    juce::Rectangle<int> side;
    std::vector<std::pair<juce::Rectangle<int>, Page>> navRows;
    juce::Rectangle<int> updateRow, metroLine;
    int hoverRow = -1;
    juce::TooltipWindow tooltips { this, 600 };
    Screen* shown = nullptr;
};

} // namespace practice::ui
