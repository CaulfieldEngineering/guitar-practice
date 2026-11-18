#pragma once
// The house style (HQ/agent/app-design.md) and the phone app's tokens (ios/Practice/Shared/Theme.swift): dark first,
// light from the same names, one accent (#6FB7A0), a 4 px grid, small radii, 13 px text and 28 px controls on the
// desktop, the system font (Segoe UI), tabular figures for numbers, Lucide line icons.
#include <JuceHeader.h>

namespace practice::ui {

struct Palette {
    juce::Colour bg, side, raised, text, muted, faint, line, lineStrong, hover, active, accent, accentText, onAccent,
                 accentSoft, warn, danger;
};

namespace Theme {
    const Palette& colours();
    bool dark();
    void setDark (bool dark);

    inline juce::Colour bg() { return colours().bg; }
    inline juce::Colour side() { return colours().side; }
    inline juce::Colour raised() { return colours().raised; }
    inline juce::Colour text() { return colours().text; }
    inline juce::Colour muted() { return colours().muted; }
    inline juce::Colour faint() { return colours().faint; }
    inline juce::Colour line() { return colours().line; }
    inline juce::Colour lineStrong() { return colours().lineStrong; }
    inline juce::Colour hover() { return colours().hover; }
    inline juce::Colour active() { return colours().active; }
    inline juce::Colour accent() { return colours().accent; }
    inline juce::Colour accentText() { return colours().accentText; }
    inline juce::Colour onAccent() { return colours().onAccent; }
    inline juce::Colour accentSoft() { return colours().accentSoft; }
    inline juce::Colour warn() { return colours().warn; }
    inline juce::Colour danger() { return colours().danger; }

    // type, desktop
    juce::Font ui (float size = 13.0f, bool semibold = false);
    juce::Font number (float size, bool light = false);   // tabular figures
    constexpr float micro = 11, small = 12, body = 13, field = 14, head = 15;

    // spacing: the 4 px grid
    constexpr int sp1 = 2, sp2 = 4, sp3 = 6, sp4 = 8, sp5 = 12, sp6 = 16, sp7 = 24, sp8 = 32;
    // radius and sizes
    constexpr float rSm = 4, rMd = 6, rLg = 10;
    constexpr int rowH = 28, ctlH = 28;

    /// A Lucide icon (line, 24 grid), drawn in `colour` inside `area`.
    void icon (juce::Graphics& g, const juce::String& name, juce::Rectangle<float> area, juce::Colour colour, float stroke = 1.75f);
}

class LookAndFeel : public juce::LookAndFeel_V4 {
public:
    LookAndFeel();
    void refresh();
    juce::Font getComboBoxFont (juce::ComboBox&) override;
    juce::Font getPopupMenuFont() override;
    juce::Font getLabelFont (juce::Label&) override;
    void drawComboBox (juce::Graphics&, int w, int h, bool down, int bx, int by, int bw, int bh, juce::ComboBox&) override;
    void positionComboBoxText (juce::ComboBox&, juce::Label&) override;
    void drawPopupMenuBackground (juce::Graphics&, int w, int h) override;
    void drawPopupMenuItem (juce::Graphics&, const juce::Rectangle<int>& area, bool isSeparator, bool isActive, bool isHighlighted,
                            bool isTicked, bool hasSubMenu, const juce::String& text, const juce::String& shortcut,
                            const juce::Drawable* icon, const juce::Colour* textColour) override;
    void getIdealPopupMenuItemSize (const juce::String& text, bool isSeparator, int standardHeight, int& w, int& h) override;
    void drawLinearSlider (juce::Graphics&, int x, int y, int w, int h, float pos, float min, float max,
                           juce::Slider::SliderStyle, juce::Slider&) override;
    void drawScrollbar (juce::Graphics&, juce::ScrollBar&, int x, int y, int w, int h, bool vertical, int thumbStart, int thumbSize,
                        bool over, bool down) override;
    int getDefaultScrollbarWidth() override { return 8; }
    void drawTooltip (juce::Graphics&, const juce::String& text, int w, int h) override;
    juce::Rectangle<int> getTooltipBounds (const juce::String& text, juce::Point<int> pos, juce::Rectangle<int> parent) override;
};

} // namespace practice::ui
