#include "Theme.h"

namespace practice::ui {

static Palette makeDark()
{
    return { juce::Colour (0xff1c1c1b), juce::Colour (0xff161615), juce::Colour (0xff262625), juce::Colour (0xffe4e3df),
             juce::Colour (0xffa3a29c), juce::Colour (0xff6b6a65), juce::Colour (0xff2b2b29), juce::Colour (0xff3b3b38),
             juce::Colour (0x0effffFA), juce::Colour (0x17fffffa), juce::Colour (0xff6fb7a0), juce::Colour (0xff7cc4ad),
             juce::Colour (0xff10201b), juce::Colour (0xff24332e), juce::Colour (0xffd9a441), juce::Colour (0xffe8796b) };
}

static Palette makeLight()
{
    return { juce::Colour (0xffffffff), juce::Colour (0xfff7f7f5), juce::Colour (0xffffffff), juce::Colour (0xff1c1b19),
             juce::Colour (0xff6a6964), juce::Colour (0xffa09f99), juce::Colour (0xffebeae6), juce::Colour (0xffdcdbd6),
             juce::Colour (0x0e37352f), juce::Colour (0x1737352f), juce::Colour (0xff6fb7a0), juce::Colour (0xff2f7f69),
             juce::Colour (0xff10201b), juce::Colour (0xffe3f1ec), juce::Colour (0xffa9781c), juce::Colour (0xffc4402b) };
}

static bool isDark = true;

const Palette& Theme::colours()
{
    static const Palette d = makeDark(), l = makeLight();
    return isDark ? d : l;
}
bool Theme::dark() { return isDark; }
void Theme::setDark (bool d) { isDark = d; }

// Sizes are CSS pixels (the em), as app-design.md gives them; JUCE's Font height is ascent plus descent, so the
// font is asked for by its point height instead.
juce::Font Theme::ui (float size, bool semibold)
{
    static const juce::String face = [] {
        auto names = juce::Font::findAllTypefaceNames();
        return names.contains ("Segoe UI") ? juce::String ("Segoe UI") : juce::Font::getDefaultSansSerifFontName();
    }();
    static const bool hasSemibold = juce::Font::findAllTypefaceNames().contains ("Segoe UI Semibold");
    if (semibold && hasSemibold) return juce::Font ("Segoe UI Semibold", size, juce::Font::plain).withPointHeight (size);
    return juce::Font (face, size, semibold ? juce::Font::bold : juce::Font::plain).withPointHeight (size);
}

juce::Font Theme::number (float size, bool light)
{
    // Segoe UI's figures are tabular; the light cut for the big numbers, as SF Pro Rounded is on the phone.
    static const bool hasLight = juce::Font::findAllTypefaceNames().contains ("Segoe UI Light");
    static const bool hasSemibold = juce::Font::findAllTypefaceNames().contains ("Segoe UI Semibold");
    if (light && hasLight) return juce::Font ("Segoe UI Light", size, juce::Font::plain).withPointHeight (size);
    if (! light && hasSemibold) return juce::Font ("Segoe UI Semibold", size, juce::Font::plain).withPointHeight (size);
    return juce::Font ("Segoe UI", size, light ? juce::Font::plain : juce::Font::bold).withPointHeight (size);
}

// Lucide icons (ISC licence), the paths of the 24 px line set.
static const char* iconSVG (const juce::String& name)
{
    if (name == "settings") return R"(<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>)";
    if (name == "chart") return R"(<path d="M3 3v16a2 2 0 0 0 2 2h16"/><path d="m19 9-5 5-4-4-3 3"/>)";
    if (name == "play") return R"(<polygon points="6 3 20 12 6 21 6 3"/>)";
    if (name == "pause") return R"(<rect x="14" y="4" width="4" height="16" rx="1"/><rect x="6" y="4" width="4" height="16" rx="1"/>)";
    if (name == "stop") return R"(<rect width="16" height="16" x="4" y="4" rx="2"/>)";
    if (name == "plus") return R"(<path d="M5 12h14"/><path d="M12 5v14"/>)";
    if (name == "minus") return R"(<path d="M5 12h14"/>)";
    if (name == "back") return R"(<path d="m15 18-6-6 6-6"/>)";
    if (name == "chevron") return R"(<path d="m9 18 6-6-6-6"/>)";
    if (name == "down") return R"(<path d="m6 9 6 6 6-6"/>)";
    if (name == "again") return R"(<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>)";
    if (name == "sort") return R"(<path d="m21 16-4 4-4-4"/><path d="M17 20V4"/><path d="m3 8 4-4 4 4"/><path d="M7 4v16"/>)";
    if (name == "speaker") return R"(<path d="M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"/><path d="M16 9a5 5 0 0 1 0 6"/><path d="M19.364 18.364a9 9 0 0 0 0-12.728"/>)";
    if (name == "tap") return R"(<path d="M9 9V4.5a1.5 1.5 0 0 1 3 0V12"/><path d="M12 11.5V10a1.5 1.5 0 0 1 3 0v2"/><path d="M15 11.5a1.5 1.5 0 0 1 3 0V16a6 6 0 0 1-6 6h-1.5a6 6 0 0 1-5.2-3l-1.7-3a1.5 1.5 0 0 1 2.6-1.5L9 16"/>)";
    if (name == "arrow") return R"(<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>)";
    if (name == "download") return R"(<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>)";
    return R"(<circle cx="12" cy="12" r="9"/>)";
}

void Theme::icon (juce::Graphics& g, const juce::String& name, juce::Rectangle<float> area, juce::Colour colour, float stroke)
{
    static std::map<juce::String, std::unique_ptr<juce::Drawable>> cache;
    const auto key = name + juce::String (stroke);
    auto it = cache.find (key);
    if (it == cache.end())
    {
        juce::String svg = juce::String ("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#000000\" stroke-width=\"")
                         + juce::String (stroke) + "\" stroke-linecap=\"round\" stroke-linejoin=\"round\">" + iconSVG (name) + "</svg>";
        auto xml = juce::XmlDocument::parse (svg);
        it = cache.emplace (key, xml ? juce::Drawable::createFromSVG (*xml) : nullptr).first;
    }
    if (! it->second) return;
    auto d = it->second->createCopy();
    d->replaceColour (juce::Colours::black, colour);
    // the 24 unit grid, not the path's own bounds, so every icon keeps its size and weight
    const float s = std::min (area.getWidth(), area.getHeight()) / 24.0f;
    d->draw (g, 1.0f, juce::AffineTransform::scale (s).translated (area.getCentreX() - 12 * s, area.getCentreY() - 12 * s));
}

// ---- look and feel ----

LookAndFeel::LookAndFeel() { refresh(); }

void LookAndFeel::refresh()
{
    setColour (juce::ResizableWindow::backgroundColourId, Theme::bg());
    setColour (juce::ComboBox::textColourId, Theme::text());
    setColour (juce::ComboBox::backgroundColourId, Theme::hover());
    setColour (juce::ComboBox::outlineColourId, juce::Colours::transparentBlack);
    setColour (juce::PopupMenu::backgroundColourId, Theme::raised());
    setColour (juce::PopupMenu::textColourId, Theme::text());
    setColour (juce::PopupMenu::highlightedBackgroundColourId, Theme::hover());
    setColour (juce::PopupMenu::highlightedTextColourId, Theme::text());
    setColour (juce::Label::textColourId, Theme::text());
    setColour (juce::TextEditor::backgroundColourId, Theme::hover());
    setColour (juce::TextEditor::textColourId, Theme::text());
    setColour (juce::TextEditor::outlineColourId, juce::Colours::transparentBlack);
    setColour (juce::TextEditor::focusedOutlineColourId, Theme::accent());
    setColour (juce::TextEditor::highlightColourId, Theme::accentSoft());
    setColour (juce::CaretComponent::caretColourId, Theme::accent());
    setColour (juce::ScrollBar::thumbColourId, Theme::lineStrong());
    setColour (juce::TooltipWindow::backgroundColourId, Theme::raised());
    setColour (juce::TooltipWindow::textColourId, Theme::text());
    setColour (juce::Slider::thumbColourId, Theme::accent());
}

juce::Font LookAndFeel::getComboBoxFont (juce::ComboBox&) { return Theme::ui (Theme::body); }
juce::Font LookAndFeel::getPopupMenuFont() { return Theme::ui (Theme::body); }
juce::Font LookAndFeel::getLabelFont (juce::Label&) { return Theme::ui (Theme::body); }

void LookAndFeel::drawComboBox (juce::Graphics& g, int w, int h, bool, int, int, int, int, juce::ComboBox& box)
{
    auto r = juce::Rectangle<float> (0, 0, (float) w, (float) h);
    g.setColour (box.isMouseOver (true) ? Theme::active() : Theme::hover());
    g.fillRoundedRectangle (r, Theme::rMd);
    if (box.hasKeyboardFocus (true)) { g.setColour (Theme::accent()); g.drawRoundedRectangle (r.reduced (0.5f), Theme::rMd, 1.0f); }
    Theme::icon (g, "down", r.removeFromRight (24).reduced (5), Theme::muted(), 2.0f);
}

void LookAndFeel::positionComboBoxText (juce::ComboBox& box, juce::Label& label)
{
    label.setBounds (8, 0, box.getWidth() - 30, box.getHeight());
    label.setFont (getComboBoxFont (box));
    label.setJustificationType (juce::Justification::centredLeft);
}

void LookAndFeel::drawPopupMenuBackground (juce::Graphics& g, int w, int h)
{
    g.fillAll (Theme::raised());
    g.setColour (Theme::lineStrong());
    g.drawRect (0, 0, w, h);
}

void LookAndFeel::drawPopupMenuItem (juce::Graphics& g, const juce::Rectangle<int>& area, bool isSeparator, bool isActive,
                                     bool isHighlighted, bool isTicked, bool, const juce::String& text, const juce::String&,
                                     const juce::Drawable*, const juce::Colour*)
{
    if (isSeparator) { g.setColour (Theme::line()); g.fillRect (area.reduced (8, 0).withHeight (1).withY (area.getCentreY())); return; }
    auto r = area.reduced (4, 1);
    if (isHighlighted && isActive) { g.setColour (Theme::hover()); g.fillRoundedRectangle (r.toFloat(), Theme::rSm); }
    g.setColour (isActive ? Theme::text() : Theme::faint());
    g.setFont (Theme::ui (Theme::body));
    g.drawText (text, r.withTrimmedLeft (24).withTrimmedRight (8), juce::Justification::centredLeft, true);
    if (isTicked) Theme::icon (g, "chevron", r.removeFromLeft (24).toFloat().reduced (6), Theme::accentText(), 2.0f);
}

void LookAndFeel::getIdealPopupMenuItemSize (const juce::String& text, bool isSeparator, int, int& w, int& h)
{
    h = isSeparator ? 9 : Theme::rowH;
    w = Theme::ui (Theme::body).getStringWidth (text) + 48;
}

void LookAndFeel::drawLinearSlider (juce::Graphics& g, int x, int y, int w, int h, float pos, float, float,
                                    juce::Slider::SliderStyle, juce::Slider& s)
{
    const float cy = (float) y + (float) h * 0.5f;
    g.setColour (Theme::lineStrong());
    g.fillRoundedRectangle ((float) x, cy - 1.5f, (float) w, 3.0f, 1.5f);
    g.setColour (s.isEnabled() ? Theme::accent() : Theme::faint());
    g.fillRoundedRectangle ((float) x, cy - 1.5f, pos - (float) x, 3.0f, 1.5f);
    g.setColour (Theme::dark() ? juce::Colour (0xffe4e3df) : juce::Colours::white);
    g.fillEllipse (pos - 7, cy - 7, 14, 14);
    g.setColour (Theme::lineStrong());
    g.drawEllipse (pos - 7, cy - 7, 14, 14, 1.0f);
}

void LookAndFeel::drawScrollbar (juce::Graphics& g, juce::ScrollBar&, int x, int y, int w, int h, bool vertical, int start, int size, bool over, bool)
{
    auto r = vertical ? juce::Rectangle<int> (x + 2, start, w - 4, size) : juce::Rectangle<int> (start, y + 2, size, h - 4);
    g.setColour (over ? Theme::faint() : Theme::lineStrong());
    g.fillRoundedRectangle (r.toFloat(), 3.0f);
}

void LookAndFeel::drawTooltip (juce::Graphics& g, const juce::String& text, int w, int h)
{
    g.fillAll (Theme::raised());
    g.setColour (Theme::lineStrong());
    g.drawRect (0, 0, w, h);
    g.setColour (Theme::text());
    g.setFont (Theme::ui (Theme::small));
    g.drawText (text, 8, 0, w - 16, h, juce::Justification::centredLeft, true);
}

juce::Rectangle<int> LookAndFeel::getTooltipBounds (const juce::String& text, juce::Point<int> pos, juce::Rectangle<int> parent)
{
    const int w = Theme::ui (Theme::small).getStringWidth (text) + 18, h = 24;
    return juce::Rectangle<int> (pos.x + 12, pos.y + 18, w, h).constrainedWithin (parent);
}

} // namespace practice::ui
