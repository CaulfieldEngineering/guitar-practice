#pragma once
// What the screens are built from, one style of each (app-design.md section 4): buttons (one primary per view, quiet,
// text, icon), a segmented control, a switch, a compact stepper, the big tempo with drag-to-scrub, a slider, a
// dropdown, the input meter, and a few drawing helpers.
#include "Theme.h"
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

namespace Draw {
    void text (juce::Graphics&, const juce::String&, juce::Rectangle<int>, juce::Colour, float size = Theme::body,
               bool semibold = false, juce::Justification j = juce::Justification::centredLeft);
    void hairline (juce::Graphics&, int x, int y, int w);
    void group (juce::Graphics&, juce::Rectangle<int>);   // a raised group, radius 10
    void sectionLabel (juce::Graphics&, const juce::String&, juce::Rectangle<int>);
}

} // namespace practice::ui
