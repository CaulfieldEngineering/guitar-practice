// 0.3.0's pieces of the house style for the desktop: the tempo block, the form, the beat bar, the step line and the
// accuracy meter with its zones (docs/design-0.3.md, section 4).
#include "Widgets.h"
#include <set>

namespace practice::ui {

// ---- the tempo block ----

TempoBlock::TempoBlock()
{
    addAndMakeVisible (minus);
    addAndMakeVisible (plus);
    minus.repeats = plus.repeats = true;
    minus.setTooltip ("Slower");
    plus.setTooltip ("Faster");
    minus.onClick = [this] { set (value - 1); };
    plus.onClick = [this] { set (value + 1); };
    setMouseCursor (juce::MouseCursor::LeftRightResizeCursor);
}

void TempoBlock::set (int v)
{
    v = juce::jlimit (minimum, maximum, v);
    if (v != value && onChange) onChange (v);
}

void TempoBlock::resized()
{
    auto r = getLocalBounds();
    auto b = r.removeFromRight (2 * Theme::ctlH + Theme::sp2).withSizeKeepingCentre (2 * Theme::ctlH + Theme::sp2, Theme::ctlH);
    minus.setBounds (b.removeFromLeft (Theme::ctlH));
    b.removeFromLeft (Theme::sp2);
    plus.setBounds (b);
}

void TempoBlock::paint (juce::Graphics& g)
{
    auto r = getLocalBounds().withTrimmedRight (2 * Theme::ctlH + Theme::sp4);
    const auto f = Theme::number (numberSize, true);
    g.setFont (f);
    g.setColour (muted ? Theme::muted() : Theme::text());
    const juce::String s (value);
    const int w = f.getStringWidth (s);
    g.drawText (s, r.withWidth (w + 4), juce::Justification::centredLeft, false);
    const int base = r.getCentreY() + (int) (f.getAscent() / 2 - f.getDescent() / 2);
    Draw::text (g, "bpm", juce::Rectangle<int> (r.getX() + w + 8, base - 17, 40, 18), Theme::muted(), Theme::body);
}

void TempoBlock::mouseDown (const juce::MouseEvent&) { dragStart = value; }
void TempoBlock::mouseDrag (const juce::MouseEvent& e) { set (dragStart + (e.getDistanceFromDragStartX() - e.getDistanceFromDragStartY()) / 6); }
void TempoBlock::mouseWheelMove (const juce::MouseEvent&, const juce::MouseWheelDetails& w)
{
    wheelRest += w.deltaY * 20;
    const int steps = (int) wheelRest;
    if (steps != 0) { wheelRest -= (float) steps; set (value + steps); }
}

// ---- the form ----

void Form::begin() { rows.clear(); }
void Form::section (const juce::String& t) { Row r; r.label = t; r.section = true; rows.push_back (r); }
void Form::row (const juce::String& label, juce::Component& c, int width, const juce::String& v)
{
    Row r; r.label = label; r.control = &c; r.width = width; r.value = v; rows.push_back (r);
}
void Form::value (const juce::String& label, const juce::String& v) { Row r; r.label = label; r.value = v; rows.push_back (r); }
void Form::note (const juce::String& t, juce::Colour c) { Row r; r.label = t; r.note = true; r.colour = c; rows.push_back (r); }

int Form::layout (int width)
{
    areas.clear();
    std::set<juce::Component*> shown;
    int y = 0;
    const auto pos = getPosition();
    for (auto& r : rows)
    {
        if (r.section)
        {
            if (y > 0) y += Theme::sp6;
            areas.push_back ({ 0, y, width, 20 });
            y += 22;
            continue;
        }
        const int h = r.note ? 18 : Theme::rowH + Theme::sp3;
        areas.push_back ({ 0, y, width, h });
        if (r.width > width - 150) r.width = std::max (44, width - 150);   // the label keeps its room
        if (r.control)
        {
            r.control->setBounds (pos.x + width - r.width, pos.y + y + (h - Theme::ctlH) / 2, r.width, Theme::ctlH);
            shown.insert (r.control);
        }
        y += h;
    }
    for (auto* c : managed) c->setVisible (shown.count (c) > 0 && isVisible());
    setSize (width, y);
    repaint();
    return y;
}

void Form::paint (juce::Graphics& g)
{
    for (size_t i = 0; i < rows.size() && i < areas.size(); ++i)
    {
        const auto& r = rows[i];
        const auto a = areas[i];
        if (r.section) { Draw::text (g, r.label, a, Theme::muted(), Theme::small); continue; }
        if (r.note) { Draw::text (g, r.label, a, r.colour, Theme::small); continue; }
        Draw::text (g, r.label, a.withWidth (std::max (120, a.getWidth() - r.width - Theme::sp5)), Theme::text());
        if (r.value.isNotEmpty())
            Draw::text (g, r.value, a.withTrimmedRight (r.width + (r.width > 0 ? Theme::sp5 : 0)), Theme::muted(), Theme::body, false,
                        juce::Justification::centredRight);
        const bool nextIsRow = i + 1 < rows.size() && ! rows[i + 1].section && ! rows[i + 1].note;
        if (nextIsRow) Draw::hairline (g, a.getX(), a.getBottom() - 1, a.getWidth());
    }
}

// ---- drawing helpers ----

void Draw::beatBar (juce::Graphics& g, juce::Rectangle<int> r, int beats, int current, int accented)
{
    beats = std::max (1, beats);
    const float gap = 4, w = ((float) r.getWidth() - gap * (float) (beats - 1)) / (float) beats;
    for (int i = 0; i < beats; ++i)
    {
        const float h = i == accented ? 10.0f : 6.0f;
        g.setColour (i == current ? Theme::accent() : Theme::lineStrong());
        g.fillRoundedRectangle ((float) r.getX() + (float) i * (w + gap), (float) r.getCentreY() - h / 2, w, h, 2.0f);
    }
}

void Draw::progress (juce::Graphics& g, juce::Rectangle<int> r, double f, juce::Colour fill, juce::Colour track)
{
    auto b = r.toFloat().withSizeKeepingCentre ((float) r.getWidth(), 4);
    g.setColour (track);
    g.fillRoundedRectangle (b, 2);
    g.setColour (fill);
    g.fillRoundedRectangle (b.withWidth (b.getWidth() * (float) juce::jlimit (0.0, 1.0, f)), 2);
}

juce::Colour Draw::zoneColour (TempoPlan::Zone z)
{
    switch (z)
    {
        case TempoPlan::Zone::up: return Theme::accent();
        case TempoPlan::Zone::hold: return Theme::lineStrong();
        case TempoPlan::Zone::down: return Theme::warn();
        case TempoPlan::Zone::rest: return Theme::danger();
    }
    return Theme::lineStrong();
}

void Draw::accuracyMeter (juce::Graphics& g, juce::Rectangle<int> r, std::optional<double> accuracy, const std::vector<int>& lines,
                          std::optional<TempoPlan::Zone> zone, bool zoned)
{
    auto bar = r.toFloat().withSizeKeepingCentre ((float) r.getWidth(), 12);
    auto x = [&] (double pct) { return bar.getX() + bar.getWidth() * (float) juce::jlimit (0.0, 1.0, (pct - 50) / 50); };
    struct Band { double lo, hi; TempoPlan::Zone z; };
    std::vector<Band> bands;
    if (! zoned || lines.size() <= 1)
    {
        const double p = lines.empty() ? 85 : lines.front();
        bands = { { 0, p, TempoPlan::Zone::hold }, { p, 100, TempoPlan::Zone::up } };
    }
    else
    {
        const std::vector<TempoPlan::Zone> zs = lines.size() == 3
            ? std::vector<TempoPlan::Zone> { TempoPlan::Zone::rest, TempoPlan::Zone::down, TempoPlan::Zone::hold }
            : std::vector<TempoPlan::Zone> { TempoPlan::Zone::down, TempoPlan::Zone::hold };
        double lo = 0;
        for (size_t i = 0; i + 1 < lines.size(); ++i) { bands.push_back ({ lo, (double) lines[i], zs[i] }); lo = lines[i]; }
        bands.push_back ({ lo, (double) lines.back(), TempoPlan::Zone::hold });
        bands.push_back ({ (double) lines.back(), 100, TempoPlan::Zone::up });
    }
    juce::Graphics::ScopedSaveState s (g);
    juce::Path clip;
    clip.addRoundedRectangle (bar, 2);
    g.reduceClipRegion (clip);
    for (auto& b : bands)
    {
        g.setColour (zoneColour (b.z).withMultipliedAlpha (0.22f));
        g.fillRect (juce::Rectangle<float> (x (b.lo), bar.getY(), x (b.hi) - x (b.lo), bar.getHeight()));
    }
    if (accuracy)
    {
        g.setColour (zone ? (*zone == TempoPlan::Zone::hold ? Theme::text() : zoneColour (*zone)) : Theme::text());
        const float mx = juce::jlimit (bar.getX(), bar.getRight() - 3, x (*accuracy * 100) - 1.5f);
        g.fillRoundedRectangle (mx, bar.getY(), 3, bar.getHeight(), 1.5f);
    }
}

} // namespace practice::ui
