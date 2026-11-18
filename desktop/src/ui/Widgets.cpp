#include "Widgets.h"

namespace practice::ui {

// ---- drawing ----

void Draw::text (juce::Graphics& g, const juce::String& s, juce::Rectangle<int> r, juce::Colour c, float size, bool semibold, juce::Justification j)
{
    g.setColour (c);
    g.setFont (Theme::ui (size, semibold));
    g.drawText (s, r, j, true);
}

void Draw::hairline (juce::Graphics& g, int x, int y, int w)
{
    g.setColour (Theme::line());
    g.fillRect (x, y, w, 1);
}

void Draw::group (juce::Graphics& g, juce::Rectangle<int> r)
{
    g.setColour (Theme::raised());
    g.fillRoundedRectangle (r.toFloat(), Theme::rLg);
    if (! Theme::dark()) { g.setColour (Theme::line()); g.drawRoundedRectangle (r.toFloat().reduced (0.5f), Theme::rLg, 1.0f); }
}

void Draw::sectionLabel (juce::Graphics& g, const juce::String& s, juce::Rectangle<int> r)
{
    text (g, s, r, Theme::muted(), Theme::small);
}

// ---- button ----

Button::Button (Kind k, juce::String t, juce::String i) : kind (k), text (std::move (t)), iconName (std::move (i))
{
    setWantsKeyboardFocus (true);
    setMouseCursor (juce::MouseCursor::PointingHandCursor);
}

int Button::idealWidth() const
{
    if (kind == Kind::icon || kind == Kind::square) return Theme::ctlH;
    const int t = Theme::ui (Theme::body, kind == Kind::primary).getStringWidth (text);
    return t + (iconName.isNotEmpty() ? 22 : 0) + (kind == Kind::text ? 8 : 24);
}

void Button::paint (juce::Graphics& g)
{
    auto r = getLocalBounds().toFloat();
    const bool over = isMouseOver() && isEnabled();
    const float alpha = isEnabled() ? 1.0f : 0.4f;
    juce::Colour fg = Theme::text();
    switch (kind)
    {
        case Kind::primary:
            g.setColour (Theme::accent().withMultipliedBrightness (down ? 0.9f : over ? 1.06f : 1.0f).withMultipliedAlpha (alpha));
            g.fillRoundedRectangle (r, Theme::rMd);
            fg = Theme::onAccent();
            break;
        case Kind::quiet:
            g.setColour ((down ? Theme::active() : over ? Theme::active() : Theme::hover()).withMultipliedAlpha (alpha));
            g.fillRoundedRectangle (r, Theme::rMd);
            break;
        case Kind::square:
            g.setColour ((down || over ? Theme::active() : Theme::hover()).withMultipliedAlpha (alpha));
            g.fillRoundedRectangle (r, Theme::rMd);
            break;
        case Kind::text:
            if (over) { g.setColour (Theme::hover()); g.fillRoundedRectangle (r, Theme::rMd); }
            fg = Theme::accentText();
            break;
        case Kind::icon:
            if (over || down) { g.setColour (Theme::hover()); g.fillRoundedRectangle (r, Theme::rMd); }
            fg = over ? Theme::text() : Theme::muted();
            break;
    }
    fg = fg.withMultipliedAlpha (alpha);
    if (hasKeyboardFocus (false) && isShowing() && kind != Kind::primary)
    {
        g.setColour (Theme::accent());
        g.drawRoundedRectangle (r.reduced (0.5f), Theme::rMd, 1.0f);
    }
    if (text.isEmpty())
    {
        Theme::icon (g, iconName, r.withSizeKeepingCentre (16, 16), fg, 1.75f);
        return;
    }
    const auto font = Theme::ui (Theme::body, kind == Kind::primary);
    const int tw = font.getStringWidth (text);
    const int iw = iconName.isNotEmpty() ? 22 : 0;
    const int x0 = kind == Kind::text ? 4 : (getWidth() - tw - iw) / 2;
    if (iw) Theme::icon (g, iconName, juce::Rectangle<float> ((float) x0, r.getCentreY() - 7, 14, 14), fg, 2.0f);
    g.setColour (fg);
    g.setFont (font);
    g.drawText (text, x0 + iw, 0, tw + 2, getHeight(), juce::Justification::centredLeft, false);
}

void Button::mouseDown (const juce::MouseEvent&)
{
    if (! isEnabled()) return;
    down = true;
    repaint();
    if (repeats) { if (onClick) onClick(); repeater.n = 0; repeater.startTimer (380); }
}

void Button::mouseUp (const juce::MouseEvent& e)
{
    const bool wasDown = down;
    down = false;
    repeater.stopTimer();
    repaint();
    if (wasDown && ! repeats && isEnabled() && getLocalBounds().contains (e.getPosition()) && onClick) onClick();
}

bool Button::keyPressed (const juce::KeyPress& k)
{
    if (k == juce::KeyPress::returnKey || k == juce::KeyPress::spaceKey) { if (onClick && isEnabled()) onClick(); return true; }
    return false;
}

void Button::Repeater::timerCallback()
{
    if (! b.down) { stopTimer(); return; }
    if (b.onClick) b.onClick();
    if (++n == 1) startTimer (60);
}

// ---- segmented ----

Segmented::Segmented (juce::StringArray o) : options (std::move (o)) { setMouseCursor (juce::MouseCursor::PointingHandCursor); }

int Segmented::idealWidth() const
{
    int w = 4;
    for (auto& o : options) w += Theme::ui (Theme::body).getStringWidth (o) + 24;
    return w;
}

void Segmented::paint (juce::Graphics& g)
{
    auto r = getLocalBounds().toFloat();
    g.setColour (Theme::active());
    g.fillRoundedRectangle (r, Theme::rMd);
    if (options.isEmpty()) return;
    const float w = (r.getWidth() - 4) / (float) options.size();
    for (int i = 0; i < options.size(); ++i)
    {
        auto seg = juce::Rectangle<float> (2 + w * (float) i, 2, w, r.getHeight() - 4);
        if (i == selected)
        {
            g.setColour (Theme::raised().brighter (Theme::dark() ? 0.08f : 0.0f));
            g.fillRoundedRectangle (seg, Theme::rSm);
            g.setColour (Theme::lineStrong());
            g.drawRoundedRectangle (seg.reduced (0.5f), Theme::rSm, 1.0f);
        }
        g.setColour (i == selected ? Theme::text() : Theme::muted());
        g.setFont (Theme::ui (Theme::body, i == selected));
        g.drawText (options[i], seg.toNearestInt(), juce::Justification::centred, true);
    }
}

void Segmented::mouseDown (const juce::MouseEvent& e)
{
    if (options.isEmpty()) return;
    const int i = juce::jlimit (0, options.size() - 1, (int) ((float) (e.x - 2) / ((float) (getWidth() - 4) / (float) options.size())));
    if (i != selected) { selected = i; repaint(); if (onChange) onChange (i); }
}

// ---- switch ----

void Switch::paint (juce::Graphics& g)
{
    auto r = getLocalBounds().toFloat().withSizeKeepingCentre (34, 20);
    g.setColour (on ? Theme::accent() : Theme::lineStrong());
    g.fillRoundedRectangle (r, 10);
    g.setColour (juce::Colours::white);
    const float x = on ? r.getRight() - 18 : r.getX() + 2;
    g.fillEllipse (x, r.getY() + 2, 16, 16);
}

void Switch::mouseUp (const juce::MouseEvent& e)
{
    if (! getLocalBounds().contains (e.getPosition())) return;
    on = ! on;
    repaint();
    if (onChange) onChange (on);
}

// ---- stepper ----

Stepper::Stepper()
{
    addAndMakeVisible (minus);
    addAndMakeVisible (plus);
    minus.repeats = plus.repeats = true;
    minus.onClick = [this] { if (value - step >= minimum && onChange) onChange (value - step); };
    plus.onClick = [this] { if (value + step <= maximum && onChange) onChange (value + step); };
}

void Stepper::setValue (int v, juce::String s)
{
    value = v;
    shown = s.isNotEmpty() ? s : juce::String (v);
    minus.setEnabled (v - step >= minimum);
    plus.setEnabled (v + step <= maximum);
    repaint();
}

void Stepper::resized()
{
    auto r = getLocalBounds();
    plus.setBounds (r.removeFromRight (Theme::ctlH));
    r.removeFromRight (Theme::sp2);
    minus.setBounds (r.removeFromRight (Theme::ctlH));
}

void Stepper::paint (juce::Graphics& g)
{
    auto r = getLocalBounds().withTrimmedRight (2 * Theme::ctlH + Theme::sp2 + Theme::sp4);
    g.setColour (Theme::muted());
    g.setFont (Theme::ui (Theme::body));
    g.drawText (shown, r, juce::Justification::centredRight, true);
}

// ---- tempo dial ----

TempoDial::TempoDial()
{
    addAndMakeVisible (minus);
    addAndMakeVisible (plus);
    minus.repeats = plus.repeats = true;
    minus.onClick = [this] { set (value - 1); };
    plus.onClick = [this] { set (value + 1); };
    minus.setTooltip ("Slower");
    plus.setTooltip ("Faster");
    setTooltip ("Drag to change the tempo");
    setMouseCursor (juce::MouseCursor::UpDownResizeCursor);
}

void TempoDial::set (int v)
{
    v = juce::jlimit (minimum, maximum, v);
    if (v != value && onChange) onChange (v);
}

void TempoDial::resized()
{
    auto r = getLocalBounds();
    const int y = (int) (numberSize * 0.7f) - Theme::ctlH / 2 + 2;
    minus.setBounds (r.getX(), y, Theme::ctlH, Theme::ctlH);
    plus.setBounds (r.getRight() - Theme::ctlH, y, Theme::ctlH, Theme::ctlH);
}

void TempoDial::paint (juce::Graphics& g)
{
    auto r = getLocalBounds();
    g.setColour (Theme::text());
    g.setFont (Theme::number (numberSize, true));
    g.drawText (juce::String (value), r.removeFromTop ((int) (numberSize * 1.4f)), juce::Justification::centred, false);
    g.setColour (Theme::muted());
    g.setFont (Theme::ui (Theme::small));
    g.drawText (caption, r.removeFromTop (16), juce::Justification::centredTop, false);
}

void TempoDial::mouseDown (const juce::MouseEvent&) { dragStart = value; }

void TempoDial::mouseDrag (const juce::MouseEvent& e)
{
    const int delta = (int) std::round ((float) (e.getDistanceFromDragStartX() - e.getDistanceFromDragStartY()) / 6.0f);
    set (dragStart + delta);
}

void TempoDial::mouseWheelMove (const juce::MouseEvent&, const juce::MouseWheelDetails& w)
{
    wheelRest += w.deltaY * 20.0f;
    const int steps = (int) wheelRest;
    if (steps != 0) { wheelRest -= (float) steps; set (value + steps); }
}

// ---- dropdown ----

void Dropdown::setItems (const juce::StringArray& items, const juce::String& selected, const juce::String& emptyText)
{
    juce::StringArray now;
    for (int i = 0; i < getNumItems(); ++i) now.add (getItemText (i));
    if (now != items)
    {
        clear (juce::dontSendNotification);
        addItemList (items, 1);
    }
    setTextWhenNothingSelected (emptyText);
    setTextWhenNoChoicesAvailable (emptyText);
    const int i = items.indexOf (selected);
    if (i >= 0) setSelectedItemIndex (i, juce::dontSendNotification);
    else setSelectedId (0, juce::dontSendNotification);
}

// ---- meter ----

void Meter::push (float peak)
{
    const double t = juce::Time::getMillisecondCounterHiRes() / 1000.0;
    level = std::max (peak, level * 0.85f);
    if (peak >= hold || t - holdAt > 1.5) { hold = peak; holdAt = t; }
    else hold *= 0.97f;
    if (peak >= 0.977f) clipAt = t;   // -0.2 dBFS
    if (peak >= loudest || t - loudestAt > 3.0) { loudest = peak; loudestAt = t; }
    repaint();
}

juce::String Meter::readout() const
{
    const double db = juce::Decibels::gainToDecibels ((float) loudest, -100.0f);
    if (db < -50) return "No signal";
    if (db < -24) return "Too quiet";
    if (db >= -0.2) return "Clipping";
    return "Good";
}

void Meter::paint (juce::Graphics& g)
{
    auto r = getLocalBounds().toFloat().withSizeKeepingCentre ((float) getWidth(), 6);
    g.setColour (Theme::lineStrong());
    g.fillRoundedRectangle (r, 3);
    auto toX = [&] (float v) { const float db = juce::Decibels::gainToDecibels (v, -60.0f); return r.getX() + r.getWidth() * (db + 60) / 60; };
    const double t = juce::Time::getMillisecondCounterHiRes() / 1000.0;
    g.setColour (t - clipAt < 2.0 ? Theme::danger() : Theme::accent());
    g.fillRoundedRectangle (r.withRight (toX (level)), 3);
    g.setColour (Theme::text());
    g.fillRect (toX (hold) - 1, r.getY() - 2, 2.0f, r.getHeight() + 4);
}

} // namespace practice::ui
