#pragma once
// The screens (0.3.0, docs/design-0.3.md section 4): Metronome; Drills (the table, then a drill's setup in two
// columns); a run (a left column of what to read, the lane on the right); a break; a result; the calibration in two
// steps; Routines (the list, the blocks, a block's editor); the routine runner; Progress; Settings with Audio.
#include "Widgets.h"
#include "../app/Model.h"
#include "../app/RoutineRunner.h"

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
    TempoBlock tempo;
    Slider slider;
    Dropdown signature, subdivision, accent, sound;
    Button tap { Button::Kind::quiet, "Tap", "tap" }, start { Button::Kind::primary, "Start", "play" };
    Form form;
    juce::Rectangle<int> beatArea, titleArea;
};

/// The Drills table: Drill, Max, Best. One line a drill.
class DrillTable : public juce::Component {
public:
    explicit DrillTable (Model&);
    void refresh();
    void paint (juce::Graphics&) override;
    void mouseDown (const juce::MouseEvent&) override;
    void mouseMove (const juce::MouseEvent&) override;
    void mouseExit (const juce::MouseEvent&) override;
    std::function<void (const juce::String&)> onOpen;
private:
    struct Row { juce::String id, name, max, best, last; };
    Model& model;
    std::vector<Row> rows;
    int hover = -1;
    int rowAt (int y) const;
};

class PatternStrip : public juce::Component {
public:
    const Drill* drill = nullptr;
    void paint (juce::Graphics&) override;
};

/// The controls of a drill's setup, for the drill's own screen and for a routine's drill block: the tempo, Length,
/// Ascending tempo, Audio input, Guide notes, and the Options. Reads and writes through the two callbacks.
class SetupForms : public juce::Component {
public:
    struct State { int bpm; SessionSettings session; bool guided, audioInput, intro; };
    SetupForms (Model&, bool ownDrill);
    std::function<State()> get;
    std::function<void (const State&)> set;
    const Drill* drill = nullptr;
    void refresh();
    /// Lays out the main form at `left` and the options at `right` (or under the main one when `right` is empty).
    void layoutIn (juce::Rectangle<int> left, juce::Rectangle<int> right);
    void paint (juce::Graphics&) override;
    Form main, options;
private:
    void push (std::function<void (State&)> change);
    Model& model;
    bool own;
    TempoBlock tempo;
    Dropdown zone, length, plan, sound, accent, gap, tuning, everyUnit, windowUnit, atTop;
    Stepper amount, target, over, cap, endBPM, step, every, upPct, upWin, downPct, downWin, lowest, breakPct, breakWin, breakLen,
            cooldown, countIn, passMark;
    Switch input, guide, downOn, breakOn, slower, click, intro;
    Slider level;
    Button calibrate { Button::Kind::quiet, "Calibrate" };
    juce::Rectangle<int> tempoArea, captionArea;
};

class DrillsScreen : public Screen {
public:
    explicit DrillsScreen (Model&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    bool keyPressed (const juce::KeyPress&) override;
    bool setupOpen = false;
private:
    DrillTable table;
    SetupForms forms;
    PatternStrip strip;
    Button back { Button::Kind::text, "Drills", "back" }, hearIntro { Button::Kind::icon, {}, "speaker" },
           start { Button::Kind::primary, "Start", "play" };
    juce::Viewport scroller;
    juce::Component content;
    juce::Rectangle<int> titleArea, detailArea, headArea, messageArea, footArea;
};

/// The run as scrolling tablature: one line a string of the tuning in use, a note its fret or an X, the hit line a
/// third of the way in.
class TabLane : public juce::Component {
public:
    explicit TabLane (Model& m) : model (m) {}
    void paint (juce::Graphics&) override;
    bool calibrationMarks = false;
private:
    Model& model;
};

class RunScreen : public Screen {
public:
    explicit RunScreen (Model&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    void mouseUp (const juce::MouseEvent&) override;
    bool keyPressed (const juce::KeyPress&) override;
    /// In a routine, the routine's own controls take the place of Pause and Stop.
    bool inRoutine = false;
    /// Draws the left column's run detail into `r` (shared with the routine runner).
    static void paintColumn (juce::Graphics&, Model&, juce::Rectangle<int> r);
private:
    TabLane lane { model };
    Button pause { Button::Kind::quiet, "Pause", "pause" }, stop { Button::Kind::quiet, "Stop", "stop" };
    Button resume { Button::Kind::primary, "Resume", "play" }, end { Button::Kind::text, "End" }, skip { Button::Kind::quiet, "Skip", "skip" };
    juce::Rectangle<int> column, top, buttons;
};

class ResultScreen : public Screen {
public:
    explicit ResultScreen (Model&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
private:
    Button again { Button::Kind::primary, "Again", "again" }, done { Button::Kind::quiet, "Done" };
    juce::Rectangle<int> column, right, buttons;
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
    Button next { Button::Kind::primary, "Next", "arrow" }, done { Button::Kind::quiet, "Cancel" };
    juce::Rectangle<int> head, value, help;
};

/// Routines: the list at the left; the chosen routine's blocks; a block's editor at the right.
class RoutinesScreen : public Screen {
public:
    RoutinesScreen (Model&, RoutineRunner&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    void mouseDown (const juce::MouseEvent&) override;
    void mouseDoubleClick (const juce::MouseEvent&) override;
    void mouseDrag (const juce::MouseEvent&) override;
    void mouseUp (const juce::MouseEvent&) override;
    bool keyPressed (const juce::KeyPress&) override;
    juce::String selected, blockSelected;
private:
    void update (std::function<void (PracticeRoutine&)> change);
    void showAddMenu();
    RoutineRunner& runner;
    Button add { Button::Kind::icon, {}, "plus" }, addBlock { Button::Kind::text, "Add block", "plus" },
           start { Button::Kind::primary, "Start", "play" }, copyBlock { Button::Kind::icon, {}, "copy" },
           deleteBlock { Button::Kind::icon, {}, "trash" }, more { Button::Kind::icon, {}, "more" };
    // the block editor
    juce::TextEditor blockName;
    Stepper seconds, bpm;
    Switch click;
    SetupForms forms;
    juce::Viewport editorScroll;
    juce::Component editorContent;
    Form plain;
    juce::Rectangle<int> listArea, blocksArea, editorArea, titleArea, summaryArea;
    std::vector<juce::Rectangle<int>> listRows, blockRows;
    int dragFrom = -1, dragTo = -1;
};

/// The routine runner: the run layout with the routine's line along the top, what is next, and Back, Pause, Skip.
class RunnerScreen : public Screen {
public:
    RunnerScreen (Model&, RoutineRunner&);
    void refresh() override;
    void resized() override;
    void paint (juce::Graphics&) override;
    bool keyPressed (const juce::KeyPress&) override;
private:
    RoutineRunner& runner;
    TabLane lane { model };
    Button back { Button::Kind::quiet, {}, "skip-back" }, pause { Button::Kind::quiet, "Pause", "pause" },
           skip { Button::Kind::quiet, {}, "skip" }, resume { Button::Kind::primary, "Resume", "play" },
           restart { Button::Kind::text, "Restart block" }, end { Button::Kind::text, "End routine" },
           done { Button::Kind::primary, "Done" }, again { Button::Kind::quiet, "Again", "again" };
    juce::Rectangle<int> column, top, line, middle, nextArea, buttons;
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
    Dropdown type, input, channel, output, buffer, tuning, clickSound;
    std::vector<std::unique_ptr<Dropdown>> strings;
    Meter meter;
    Button tone { Button::Kind::quiet, "Test tone" }, clickTest { Button::Kind::quiet, "Click test" };
    Slider sounds, guitar, clickLevel;
    Switch hear, cues, appearanceDark, chime, ticks, sevenStrings;
    Button calibrate { Button::Kind::quiet, "Calibrate" }, syncNow { Button::Kind::quiet, "Sync now" }, update { Button::Kind::primary, "Update" };
    juce::TextEditor server;
    std::vector<std::pair<juce::Rectangle<int>, juce::String>> labels, values;
    std::vector<std::pair<juce::Rectangle<int>, juce::String>> sectionTitles;
    juce::Rectangle<int> statusLine;
};

juce::String modeName (const juce::String& mode);

} // namespace practice::ui
