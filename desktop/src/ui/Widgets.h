#pragma once
// What the screens are built from, one style of each (app-design.md section 4): buttons (one primary per view, quiet,
// text, icon), a segmented control, a switch, a compact stepper, the big tempo with drag-to-scrub, a slider, a
// dropdown, the input meter, and a few drawing helpers.
#include "Theme.h"
#include "../core/TempoPlan.h"
#include <functional>

namespace practice::ui {

class Button : public juce::Component, public juce::SettableTooltipClient {
public:
    enum class Kind { primary, quiet, text, icon, square };
    Button (Kind k = Kind::quiet, juce::String text = {}, juce::String icon = {});
    void setText (const juce::String& t) { if (t != text) { text = t; repaint(); } }
    void setIcon (const juce::String& i) { if (i != iconName) { iconName = i; repaint(); } }
    void setKind (Kind k) { kind = k; repaint(); }
    std::function<void()> onClick;
    bool repeats = false;   // held down: keeps clicking (the minus and plus)
    void paint (juce::Graphics&) override;
    void mouseEnter (const juce::MouseEvent&) override { repaint(); }
    void mouseExit (const juce::MouseEvent&) override { repaint(); }
    void mouseDown (const juce::MouseEvent&) override;
    void mouseUp (const juce::MouseEvent&) override;
    bool keyPressed (const juce::KeyPress& k) override;
    int idealWidth() const;
private:
    struct Repeater : juce::Timer { Button& b; int n = 0; explicit Repeater (Button& x) : b (x) {} void timerCallback() override; };
    Kind kind;
    juce::String text, iconName;
    Repeater repeater { *this };
    bool down = false;
};

class Segmented : public juce::Component {
public:
    explicit Segmented (juce::StringArray options = {});
    void setOptions (const juce::StringArray& o) { options = o; repaint(); }
    void setSelected (int i) { if (i != selected) { selected = i; repaint(); } }
    int getSelected() const { return selected; }
    std::function<void (int)> onChange;
    void paint (juce::Graphics&) override;
    void mouseDown (const juce::MouseEvent&) override;
    int idealWidth() const;
private:
    juce::StringArray options;
    int selected = 0;
};

class Switch : public juce::Component {
public:
    void setOn (bool v) { if (v != on) { on = v; repaint(); } }
    bool isOn() const { return on; }
    std::function<void (bool)> onChange;
    void paint (juce::Graphics&) override;
    void mouseUp (const juce::MouseEvent&) override;
private:
    bool on = false;
};

/// A small number with a minus and a plus: "4" [−][+].
class Stepper : public juce::Component {
public:
    Stepper();
    void setValue (int v, juce::String shown = {});
    int value = 0, minimum = 0, maximum = 100, step = 1;
    std::function<void (int)> onChange;
    void resized() override;
    void paint (juce::Graphics&) override;
private:
    Button minus { Button::Kind::square, {}, "minus" }, plus { Button::Kind::square, {}, "plus" };
    juce::String shown;
};

/// The big tempo: drag up or right to raise it (each step ticks), the wheel, or the minus and plus beside it.
/// Only calls out; the model clamps and returns early when nothing changes (the phone's 0.1.4 crash).
class TempoDial : public juce::Component, public juce::SettableTooltipClient {
public:
    TempoDial();
    void setValue (int v) { if (v != value) { value = v; repaint(); } }
    void setCaption (const juce::String& c) { if (c != caption) { caption = c; repaint(); } }
    int value = 100, minimum = 20, maximum = 400;
    float numberSize = 72;
    std::function<void (int)> onChange;
    void resized() override;
    void paint (juce::Graphics&) override;
    void mouseDown (const juce::MouseEvent&) override;
    void mouseDrag (const juce::MouseEvent&) override;
    void mouseWheelMove (const juce::MouseEvent&, const juce::MouseWheelDetails&) override;
private:
    void set (int v);
    Button minus { Button::Kind::square, {}, "minus" }, plus { Button::Kind::square, {}, "plus" };
    juce::String caption = "bpm";
    int dragStart = 0;
    float wheelRest = 0;
};

class Slider : public juce::Slider {
public:
    Slider() : juce::Slider (juce::Slider::LinearHorizontal, juce::Slider::NoTextBox) {}
};

class Dropdown : public juce::ComboBox {
public:
    Dropdown() { setScrollWheelEnabled (false); }
    /// Sets the items and the selection without calling onChange.
    void setItems (const juce::StringArray& items, const juce::String& selected, const juce::String& emptyText = {});
};

/// The input level: a bar, a peak-hold tick (1.5 s, then it falls) and a clip light (2 s), as on the phone.
class Meter : public juce::Component {
public:
    void push (float peak);
    void paint (juce::Graphics&) override;
    juce::String readout() const;
private:
    float level = 0, hold = 0;
    double holdAt = 0, clipAt = -10, loudest = 0, loudestAt = 0;
};

/// The tempo, big and left-aligned, "bpm" on its baseline, minus and plus at the right (0.3.0). Drag sideways on
/// the number or use the wheel to change it.
class TempoBlock : public juce::Component {
public:
    TempoBlock();
    void setValue (int v) { if (v != value) { value = v; repaint(); } }
    int value = 100, minimum = 20, maximum = 400;
    float numberSize = 72;
    bool muted = false;
    std::function<void (int)> onChange;
    void resized() override;
    void paint (juce::Graphics&) override;
    void mouseDown (const juce::MouseEvent&) override;
    void mouseDrag (const juce::MouseEvent&) override;
    void mouseWheelMove (const juce::MouseEvent&, const juce::MouseWheelDetails&) override;
private:
    void set (int v);
    Button minus { Button::Kind::square, {}, "minus" }, plus { Button::Kind::square, {}, "plus" };
    int dragStart = 0;
    float wheelRest = 0;
};

/// A form: rows of a label and a control (or a value), in sections, down a column; the controls on its right edge.
/// The rows are given again on each refresh; the controls are the owner's children, shown or hidden by the form.
class Form : public juce::Component {
public:
    struct Row { juce::String label; juce::Component* control = nullptr; int width = 0; juce::String value; bool section = false;
                 bool note = false; juce::Colour colour; };
    void begin();
    void section (const juce::String& title);
    void row (const juce::String& label, juce::Component& control, int width, const juce::String& value = {});
    void value (const juce::String& label, const juce::String& v);
    void note (const juce::String& text, juce::Colour colour);
    /// Lays the rows out from the form's own top left (set its position first); returns the height used.
    int layout (int width);
    void paint (juce::Graphics&) override;
    std::vector<juce::Component*> managed;   // every control this form may show; the ones not in a row are hidden
private:
    std::vector<Row> rows;
    std::vector<juce::Rectangle<int>> areas;
};

namespace Draw {
    /// The beats of the bar as equal segments across `r`; the one playing lit, the accented one taller.
    void beatBar (juce::Graphics&, juce::Rectangle<int> r, int beats, int current, int accented = 0);
    /// A thin line filling from the left.
    void progress (juce::Graphics&, juce::Rectangle<int> r, double fraction, juce::Colour fill, juce::Colour track);
    /// The accuracy meter: bands split at the thresholds (break, down, hold, up), and a mark at the accuracy.
    void accuracyMeter (juce::Graphics&, juce::Rectangle<int> r, std::optional<double> accuracy, const std::vector<int>& lines,
                        std::optional<TempoPlan::Zone> zone, bool zoned);
    juce::Colour zoneColour (TempoPlan::Zone z);
    void text (juce::Graphics&, const juce::String&, juce::Rectangle<int>, juce::Colour, float size = Theme::body,
               bool semibold = false, juce::Justification j = juce::Justification::centredLeft);
    void hairline (juce::Graphics&, int x, int y, int w);
    void group (juce::Graphics&, juce::Rectangle<int>);   // a raised group, radius 10
    void sectionLabel (juce::Graphics&, const juce::String&, juce::Rectangle<int>);
}

} // namespace practice::ui
