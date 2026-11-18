#pragma once
// The screens, the phone's in a desktop layout: Metronome; Drills (the table on the left, the chosen drill's setup on
// the right); a run (scrolling tablature); a result; the calibration in two steps; Progress; Settings with Audio.
#include "Widgets.h"
#include "../app/Model.h"

namespace practice::ui {

class Screen : public juce::Component {
public:
    explicit Screen (Model& m) : model (m) {}
    virtual void refresh() {}
protected:
    Model& model;
};

class MetronomeScreen : public Screen {
public:
    explicit MetronomeScreen (Model&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    bool keyPressed (const juce::KeyPress&) override;
private:
    TempoDial dial;
    Slider slider;
    Dropdown signature;
    Switch accent;
    Segmented sub { { "Quarter", "Eighth", "Triplet", "16th" } };
    Button tap { Button::Kind::quiet, "Tap", "tap" }, start { Button::Kind::primary, "Start", "play" };
    juce::Rectangle<int> dots, rowSig, rowAccent, rowSub;
};

/// The Drills table: name, pattern, max, best; grouped by category; sorted as listed, by last played, max or name.
class DrillTable : public juce::Component {
public:
    explicit DrillTable (Model&);
    void refresh();
    void paint (juce::Graphics&) override;
    void resized() override;
    void mouseDown (const juce::MouseEvent&) override;
    void mouseMove (const juce::MouseEvent&) override;
    void mouseExit (const juce::MouseEvent&) override;
    void mouseWheelMove (const juce::MouseEvent&, const juce::MouseWheelDetails&) override;
    int sort = 0;   // 0 as listed, 1 last played, 2 max, 3 name
    juce::String filter;
private:
    struct Row { bool header; juce::String text, id, glyph, max, best, last; };
    Model& model;
    std::vector<Row> rows;
    int hover = -1;
    float scroll = 0;
    int rowAt (int y) const;
    int contentHeight() const;
};

class DrillsScreen : public Screen {
public:
    explicit DrillsScreen (Model&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    bool keyPressed (const juce::KeyPress&) override;
    void optionsToggleForScreens() { optionsOpen = true; refresh(); }
private:
    void layoutSetup (juce::Rectangle<int> r);
    DrillTable table;
    Button sortButton { Button::Kind::icon, {}, "sort" };
    juce::TextEditor search;
    // the setup
    Segmented tempoMode { { "Zones", "Manual" } };
    Segmented zoneChips;
    TempoDial dial;
    Dropdown levels;
    Segmented guide { { "Guided", "Solo" } };
    Segmented runKind { { "Cycles", "Time", "Endurance" } };
    Stepper amount;
    Switch audioInput;
    Button optionsToggle { Button::Kind::text, "Options", "chevron" };
    bool optionsOpen = false;
    Stepper ladder, target;
    Switch click, voiceIntro;
    Button calibrate { Button::Kind::quiet, "Calibrate" };
    Button hearIntro { Button::Kind::icon, {}, "speaker" };
    Button start { Button::Kind::primary, "Start", "play" };
    juce::Rectangle<int> setupArea, titleArea, detailArea, patternArea, tempoArea, zoneLineArea, guideArea, guideHelp,
                         runArea, amountArea, inputArea, inputNote, optionsArea, rowLadder, rowTarget, rowClick, rowIntro, rowTiming,
                         messageArea, tableHeader, footer;
};

/// The run as scrolling tablature (LaneView.swift): six strings, each note its fret on its string, scrolling to a
/// fixed line and taking its colour there; the rhythm above with the pick direction; the picks heard as dots below.
class TabLane : public juce::Component {
public:
    explicit TabLane (Model& m) : model (m) {}
    void paint (juce::Graphics&) override;
    bool calibrationMarks = false;   // the calibration: plain marks on one line, no strings
private:
    Model& model;
};

class PatternStrip : public juce::Component {
public:
    const Drill* drill = nullptr;
    void paint (juce::Graphics&) override;
};

class RunScreen : public Screen {
public:
    explicit RunScreen (Model&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    void mouseUp (const juce::MouseEvent&) override;
    bool keyPressed (const juce::KeyPress&) override;
private:
    TabLane lane { model };
    Button pause { Button::Kind::quiet, "Pause", "pause" }, stop { Button::Kind::quiet, "Stop", "stop" };
    Button resume { Button::Kind::primary, "Resume", "play" }, end { Button::Kind::quiet, "End" }, skip { Button::Kind::quiet, "Skip" };
    juce::Rectangle<int> header, pattern, stats, meterArea, timingArea, buttons;
    Meter meter;
};

class ResultScreen : public Screen {
public:
    explicit ResultScreen (Model&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
private:
    Button again { Button::Kind::primary, "Again", "again" }, done { Button::Kind::quiet, "Done" };
    juce::Rectangle<int> top, strip, table, buttons;
};

class CalibrationScreen : public Screen {
public:
    explicit CalibrationScreen (Model&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    std::function<void()> onDone;
private:
    TabLane lane { model };
    Slider offset;
    Button earlier { Button::Kind::square, {}, "minus" }, later { Button::Kind::square, {}, "plus" };
    Button next { Button::Kind::primary, "Next", "arrow" }, done { Button::Kind::quiet, "Done" };
    juce::Rectangle<int> head, value, help;
};

class ProgressScreen : public Screen {
public:
    explicit ProgressScreen (Model&);
    void refresh() override;
    void paint (juce::Graphics&) override;
    void resized() override;
    void mouseWheelMove (const juce::MouseEvent&, const juce::MouseWheelDetails&) override;
private:
    float scroll = 0;
    int contentH = 0;
};

class SettingsScreen : public Screen {
public:
    explicit SettingsScreen (Model&);
    ~SettingsScreen() override;
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    void visibilityChanged() override;
    std::function<void()> onCalibrate;
private:
    void pushDevice();
    Dropdown type, input, channel, output, buffer;
    Meter meter;
    Button tone { Button::Kind::quiet, "Test tone" }, clickTest { Button::Kind::quiet, "Click test" };
    Slider sounds, guitar;
    Switch hear, cues, appearanceDark;
    Button calibrate { Button::Kind::quiet, "Calibrate" }, syncNow { Button::Kind::quiet, "Sync now" }, update { Button::Kind::primary, "Update" };
    juce::TextEditor server;
    struct RowSpec { juce::String label; juce::Component* control; int width; juce::String value; };
    std::vector<std::pair<juce::String, std::vector<RowSpec>>> sections;
    std::vector<std::pair<juce::Rectangle<int>, juce::String>> labels, values;
    std::vector<juce::Rectangle<int>> groups;
    std::vector<std::pair<juce::Rectangle<int>, juce::String>> sectionTitles;
    juce::Rectangle<int> statusLine;
};

} // namespace practice::ui
