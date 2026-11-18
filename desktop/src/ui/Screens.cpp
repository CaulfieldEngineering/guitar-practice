#include "Screens.h"

namespace practice::ui {

static const juce::String dot = juce::String (juce::CharPointer_UTF8 (" \xc2\xb7 "));
static const juce::String dash = juce::String (juce::CharPointer_UTF8 ("\xe2\x80\x93"));

// ================================================================ Metronome

MetronomeScreen::MetronomeScreen (Model& m) : Screen (m)
{
    setWantsKeyboardFocus (true);
    for (auto* c : std::initializer_list<juce::Component*> { &dial, &slider, &signature, &accent, &sub, &tap, &start }) addAndMakeVisible (c);
    dial.onChange = [this] (int v) { model.setMetroBPM (v); };
    slider.setRange (20, 300, 1);
    slider.onValueChange = [this] { model.setMetroBPM ((int) slider.getValue()); };
    signature.setItems ({ "2/4", "3/4", "4/4", "5/4", "6/4", "7/4" }, "4/4");
    signature.onChange = [this] { model.setMetroBeats (signature.getSelectedItemIndex() + 2); };
    accent.onChange = [this] (bool on) { model.setMetroAccent (on); };
    sub.onChange = [this] (int i) { model.setMetroSub (i + 1); };
    tap.setTooltip ("Tap tempo (T)");
    tap.onClick = [this] { model.tap(); };
    start.setTooltip ("Space");
    start.onClick = [this] { model.toggleMetronome(); };
    refresh();
}

void MetronomeScreen::refresh()
{
    dial.minimum = 20; dial.maximum = 400;
    dial.setValue (model.metroBPM);
    slider.setValue (model.metroBPM, juce::dontSendNotification);
    signature.setSelectedItemIndex (model.metroBeats - 2, juce::dontSendNotification);
    accent.setOn (model.metroAccent);
    sub.setSelected (model.metroSub - 1);
    const bool on = model.metronomeRunning();
    start.setText (on ? "Stop" : "Start");
    start.setIcon (on ? "stop" : "play");
    repaint (dots);
}

void MetronomeScreen::resized()
{
    const int cw = std::min (460, getWidth() - 48);
    const int total = 16 + 24 + 118 + 12 + 28 + 28 + 3 * 36 + 28 + 28;
    auto col = juce::Rectangle<int> ((getWidth() - cw) / 2, std::max (24, (getHeight() - total) / 2), cw, total);
    dots = col.removeFromTop (16);
    col.removeFromTop (24);
    dial.setBounds (col.removeFromTop (118));
    col.removeFromTop (12);
    slider.setBounds (col.removeFromTop (28));
    col.removeFromTop (28);
    auto row = [&] (juce::Rectangle<int>& area, juce::Component& c, int w) {
        area = col.removeFromTop (36);
        c.setBounds (area.withLeft (area.getRight() - w).withSizeKeepingCentre (w, Theme::ctlH).withX (area.getRight() - w));
    };
    row (rowSig, signature, 96);
    row (rowAccent, accent, 44);
    row (rowSub, sub, sub.idealWidth());
    col.removeFromTop (28);
    auto b = col.removeFromTop (Theme::ctlH);
    tap.setBounds (b.removeFromLeft (96));
    b.removeFromLeft (Theme::sp4);
    start.setBounds (b);
}

void MetronomeScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    const int beat = model.metronomeBeat();
    const int n = model.metroBeats;
    const int size = 10, gap = 10;
    int x = dots.getCentreX() - (n * size + (n - 1) * gap) / 2;
    for (int i = 0; i < n; ++i)
    {
        g.setColour (i == beat ? Theme::accent() : Theme::lineStrong());
        const float s = i == 0 && model.metroAccent ? 12.0f : 10.0f;
        g.fillEllipse ((float) x + (size - s) / 2, (float) dots.getCentreY() - s / 2, s, s);
        x += size + gap;
    }
    Draw::text (g, "Time signature", rowSig, Theme::text());
    Draw::text (g, "Accent first beat", rowAccent, Theme::text());
    Draw::text (g, "Subdivision", rowSub, Theme::text());
    Draw::hairline (g, rowSig.getX(), rowSig.getBottom(), rowSig.getWidth());
    Draw::hairline (g, rowAccent.getX(), rowAccent.getBottom(), rowAccent.getWidth());
}

bool MetronomeScreen::keyPressed (const juce::KeyPress& k)
{
    if (k == juce::KeyPress::spaceKey) { model.toggleMetronome(); return true; }
    if (k.getTextCharacter() == 't' || k.getTextCharacter() == 'T') { model.tap(); return true; }
    if (k == juce::KeyPress::upKey || k == juce::KeyPress::rightKey) { model.setMetroBPM (model.metroBPM + 1); return true; }
    if (k == juce::KeyPress::downKey || k == juce::KeyPress::leftKey) { model.setMetroBPM (model.metroBPM - 1); return true; }
    return false;
}

// ================================================================ the Drills table

DrillTable::DrillTable (Model& m) : model (m) { setMouseCursor (juce::MouseCursor::PointingHandCursor); }

static juce::String lastPlayed (juce::Time t)
{
    const auto days = (int) ((juce::Time::getCurrentTime() - t).inDays());
    if (days <= 0) return "Today";
    if (days == 1) return "Yesterday";
    if (days < 7) return juce::String (days) + " days ago";
    return t.formatted ("%b %e");
}

void DrillTable::refresh()
{
    auto runs = model.allRuns();
    struct Item { const Drill* d; juce::String max, best, last; juce::Time lastT; int maxV; };
    std::vector<Item> items;
    for (auto& d : model.drills)
    {
        if (filter.isNotEmpty() && ! d.name.containsIgnoreCase (filter) && ! d.tableName().containsIgnoreCase (filter)) continue;
        Item it { &d, juce::String (dash), juce::String (dash), {}, juce::Time(), 0 };
        if (auto m = model.level (d.id)) { it.max = juce::String (*m); it.maxV = *m; }
        int best = -1;
        for (auto& r : runs)
            if (r.exerciseID == d.id)
            {
                if (it.lastT.toMilliseconds() == 0) it.lastT = r.date;
                if (! r.guided && r.mode != "endurance") best = std::max (best, r.accuracyPercent);
            }
        if (best >= 0) it.best = juce::String (best) + "%";
        if (it.lastT.toMilliseconds() != 0) it.last = lastPlayed (it.lastT);
        items.push_back (it);
    }
    if (sort == 1) std::stable_sort (items.begin(), items.end(), [] (auto& a, auto& b) { return a.lastT > b.lastT; });
    if (sort == 2) std::stable_sort (items.begin(), items.end(), [] (auto& a, auto& b) { return a.maxV > b.maxV; });
    if (sort == 3) std::stable_sort (items.begin(), items.end(), [] (auto& a, auto& b) { return a.d->tableName().compareIgnoreCase (b.d->tableName()) < 0; });
    rows.clear();
    if (sort == 0)
    {
        juce::StringArray cats;
        for (auto& it : items) cats.addIfNotAlreadyThere (it.d->category);
        for (auto& c : cats)
        {
            rows.push_back ({ true, c });
            for (auto& it : items) if (it.d->category == c) rows.push_back ({ false, it.d->tableName(), it.d->id, it.d->glyph(), it.max, it.best, it.last });
        }
    }
    else
        for (auto& it : items) rows.push_back ({ false, it.d->tableName(), it.d->id, it.d->glyph(), it.max, it.best, it.last });
    scroll = juce::jlimit (0.0f, (float) std::max (0, contentHeight() - getHeight()), scroll);
    repaint();
}

int DrillTable::contentHeight() const
{
    int h = 0;
    for (auto& r : rows) h += r.header ? 30 : 40;
    return h;
}

int DrillTable::rowAt (int y) const
{
    int top = -(int) scroll;
    for (int i = 0; i < (int) rows.size(); ++i)
    {
        const int h = rows[(size_t) i].header ? 30 : 40;
        if (y >= top && y < top + h) return rows[(size_t) i].header ? -1 : i;
        top += h;
    }
    return -1;
}

void DrillTable::resized() { refresh(); }

void DrillTable::paint (juce::Graphics& g)
{
    const int w = getWidth();
    const int colBest = 52, colMax = 44, colPattern = 56;
    int y = -(int) scroll;
    for (int i = 0; i < (int) rows.size(); ++i)
    {
        const auto& r = rows[(size_t) i];
        if (r.header)
        {
            Draw::text (g, r.text, { 8, y + 10, w - 16, 18 }, Theme::muted(), Theme::small);
            y += 30;
            continue;
        }
        auto area = juce::Rectangle<int> (0, y, w, 40);
        const bool sel = r.id == model.drillID;
        if (sel || i == hover)
        {
            g.setColour (sel ? Theme::accentSoft() : Theme::hover());
            g.fillRoundedRectangle (area.toFloat().reduced (0, 1), Theme::rMd);
        }
        auto inner = area.reduced (8, 0);
        auto best = inner.removeFromRight (colBest), max = inner.removeFromRight (colMax), pat = inner.removeFromRight (colPattern);
        if (r.last.isNotEmpty())
        {
            Draw::text (g, r.text, inner.withHeight (22).withY (y + 3), Theme::text(), Theme::body, sel);
            Draw::text (g, r.last, inner.withHeight (14).withY (y + 23), Theme::faint(), Theme::micro);
        }
        else
            Draw::text (g, r.text, inner, Theme::text(), Theme::body, sel);
        Draw::text (g, r.glyph, pat, Theme::muted(), Theme::small);
        Draw::text (g, r.max, max, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
        Draw::text (g, r.best, best, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
        if (i + 1 < (int) rows.size() && ! rows[(size_t) i + 1].header && ! sel) Draw::hairline (g, 8, y + 39, w - 16);
        y += 40;
    }
}

void DrillTable::mouseDown (const juce::MouseEvent& e)
{
    const int i = rowAt (e.y);
    if (i >= 0) model.select (rows[(size_t) i].id);
}

void DrillTable::mouseMove (const juce::MouseEvent& e) { const int i = rowAt (e.y); if (i != hover) { hover = i; repaint(); } }
void DrillTable::mouseExit (const juce::MouseEvent&) { hover = -1; repaint(); }

void DrillTable::mouseWheelMove (const juce::MouseEvent&, const juce::MouseWheelDetails& w)
{
    scroll = juce::jlimit (0.0f, (float) std::max (0, contentHeight() - getHeight()), scroll - w.deltaY * 120.0f);
    repaint();
}

// ================================================================ a drill's pattern

void PatternStrip::paint (juce::Graphics& g)
{
    if (! drill) return;
    auto r = getLocalBounds().toFloat();
    const int cycle = std::max (1, drill->cycleBeats);
    const int repeats = cycle >= 4 ? 1 : (int) std::ceil (4.0 / cycle);
    const int beats = cycle * repeats;
    const float cell = r.getWidth() / (float) beats;
    g.setColour (Theme::line());
    for (int b = 1; b < beats; ++b) g.fillRect (b * cell - 0.5f, 2.0f, 1.0f, r.getHeight() - 4);
    for (int k = 0; k < repeats; ++k)
        for (auto& n : drill->notes)
        {
            const float x = (float) (n.at.beats() + k * cycle) * cell + cell * 0.08f + 1.5f;
            const float h = n.accent ? r.getHeight() - 6 : r.getHeight() * 0.5f;
            g.setColour (n.accent ? Theme::accent() : Theme::muted());
            g.fillRoundedRectangle (x, (r.getHeight() - h) / 2, 3, h, 1.5f);
        }
}

// ================================================================ Drills: the table and the setup

DrillsScreen::DrillsScreen (Model& m) : Screen (m), table (m)
{
    setWantsKeyboardFocus (true);
    for (auto* c : std::initializer_list<juce::Component*> { &table, &sortButton, &tempoMode, &zoneChips, &dial, &levels, &guide, &runKind,
                                                              &amount, &audioInput, &optionsToggle, &ladder, &target, &click, &voiceIntro,
                                                              &calibrate, &hearIntro, &start })
        addAndMakeVisible (c);
    addChildComponent (search);
    search.setTextToShowWhenEmpty ("Search", Theme::faint());
    search.setFont (Theme::ui (Theme::field));
    search.setIndents (8, 6);
    search.onTextChange = [this] { table.filter = search.getText(); table.refresh(); };
    sortButton.setTooltip ("Sort");
    sortButton.onClick = [this] {
        juce::PopupMenu menu;
        const char* names[] = { "Default", "Last played", "Max tempo", "Name" };
        for (int i = 0; i < 4; ++i) menu.addItem (i + 1, names[i], true, table.sort == i);
        menu.showMenuAsync (juce::PopupMenu::Options().withTargetComponent (sortButton), [this] (int r) {
            if (r > 0) { table.sort = r - 1; table.refresh(); }
        });
    };
    tempoMode.onChange = [this] (int i) { model.setManual (i == 1); };
    zoneChips.onChange = [this] (int i) { if (i < (int) model.zones.zones.size()) model.chooseZone (model.zones.zones[(size_t) i].id); };
    dial.numberSize = 48;
    dial.onChange = [this] (int v) { model.nudgeTempo (v); };
    levels.onChange = [this] {
        const int i = levels.getSelectedItemIndex();
        const auto& d = model.drill();
        if (i >= 0 && i < (int) d.levels.size()) model.apply (d.levels[(size_t) i]);
    };
    guide.onChange = [this] (int i) { model.setGuided (i == 0); };
    runKind.onChange = [this] (int i) {
        auto s = model.session;
        s.kind = i == 0 ? SessionSettings::Kind::cycles : i == 1 ? SessionSettings::Kind::duration : SessionSettings::Kind::endurance;
        model.setSession (s);
    };
    amount.onChange = [this] (int v) {
        auto s = model.session;
        if (s.kind == SessionSettings::Kind::cycles) s.cycles = v;
        else if (s.kind == SessionSettings::Kind::duration) s.seconds = v;
        else s.targetPercent = v;
        model.setSession (s);
    };
    audioInput.onChange = [this] (bool on) { model.setAudioInput (on); };
    optionsToggle.onClick = [this] { optionsOpen = ! optionsOpen; refresh(); resized(); };
    ladder.minimum = 0; ladder.maximum = 12; ladder.step = 2;
    ladder.onChange = [this] (int v) { auto s = model.session; s.ladderStep = v; model.setSession (s); };
    target.minimum = 50; target.maximum = 100; target.step = 1;
    target.onChange = [this] (int v) { auto s = model.session; s.targetPercent = v; model.setSession (s); };
    click.onChange = [this] (bool on) { model.setGridClicks (on); };
    voiceIntro.onChange = [this] (bool on) { model.setIntro (on); };
    calibrate.onClick = [this] { model.startCalibration(); };
    hearIntro.setTooltip ("Play intro");
    hearIntro.onClick = [this] { model.repeatIntro(); };
    start.setTooltip ("Space");
    start.onClick = [this] { model.start(); };
    refresh();
}

void DrillsScreen::refresh()
{
    const auto& d = model.drill();
    table.refresh();
    search.setVisible (model.drills.size() > 12);
    const auto lvl = model.level();
    tempoMode.setVisible (lvl.has_value());
    tempoMode.setSelected (model.resume ? 0 : 1);
    const bool zonesShown = lvl.has_value() && model.resume;
    zoneChips.setVisible (zonesShown);
    dial.setVisible (! zonesShown);
    juce::StringArray chips;
    int sel = 0;
    for (size_t i = 0; i < model.zones.zones.size(); ++i)
    {
        chips.add (model.zones.zones[i].name);
        if (auto* z = model.activeZone(); z && z->id == model.zones.zones[i].id) sel = (int) i;
    }
    zoneChips.setOptions (chips);
    zoneChips.setSelected (sel);
    dial.minimum = d.tempo.min; dial.maximum = d.tempo.max;
    dial.setValue (model.bpm);
    juce::StringArray lv;
    for (auto& l : d.levels) lv.add (l.name + dot + juce::String (l.bpm) + " bpm");
    levels.setItems (lv, {}, "Levels");
    levels.setVisible (! d.levels.empty() && ! zonesShown);
    guide.setSelected (model.guided ? 0 : 1);
    const auto& s = model.session;
    runKind.setOptions ({ "Cycles", "Time", model.audioInput ? "Endurance" : "Open" });
    runKind.setSelected (s.kind == SessionSettings::Kind::cycles ? 0 : s.kind == SessionSettings::Kind::duration ? 1 : 2);
    if (s.kind == SessionSettings::Kind::cycles) { amount.minimum = 1; amount.maximum = 40; amount.step = 1; amount.setValue (s.cycles); }
    else if (s.kind == SessionSettings::Kind::duration) { amount.minimum = 15; amount.maximum = 1200; amount.step = 15; amount.setValue (s.seconds, formatClock (s.seconds)); }
    else { amount.minimum = 50; amount.maximum = 100; amount.step = 1; amount.setValue (s.targetPercent, juce::String (s.targetPercent) + "%"); }
    amount.setVisible (! (s.kind == SessionSettings::Kind::endurance && ! model.audioInput));
    audioInput.setOn (model.audioInput);
    optionsToggle.setIcon (optionsOpen ? "down" : "chevron");
    for (auto* c : std::initializer_list<juce::Component*> { &ladder, &target, &click, &voiceIntro, &calibrate }) c->setVisible (optionsOpen);
    ladder.setValue (s.ladderStep, s.ladderStep == 0 ? juce::String ("Off") : "+" + juce::String (s.ladderStep) + " bpm");
    target.setValue (s.targetPercent, juce::String (s.targetPercent) + "%");
    target.setVisible (optionsOpen && model.audioInput && s.kind != SessionSettings::Kind::endurance);
    click.setOn (model.gridClicks);
    voiceIntro.setOn (model.intro);
    const bool busy = model.phase != Model::Phase::ready;
    start.setEnabled (! busy);
    resized();
    repaint();
}

void DrillsScreen::resized()
{
    auto r = getLocalBounds().reduced (Theme::sp7, Theme::sp6);
    const int tw = juce::jlimit (340, 460, (int) (getWidth() * 0.4));
    auto left = r.removeFromLeft (tw);
    r.removeFromLeft (Theme::sp8);
    // the table
    auto head = left.removeFromTop (Theme::ctlH);
    sortButton.setBounds (head.removeFromRight (Theme::ctlH));
    if (search.isVisible()) { head.removeFromRight (Theme::sp4); search.setBounds (head.removeFromRight (180)); }
    left.removeFromTop (Theme::sp4);
    tableHeader = left.removeFromTop (20);
    footer = left.removeFromBottom (20);
    table.setBounds (left);
    // the setup
    setupArea = r.withWidth (std::min (r.getWidth(), 600));
    layoutSetup (setupArea);
}

void DrillsScreen::layoutSetup (juce::Rectangle<int> r)
{
    auto take = [&] (int h) { auto a = r.removeFromTop (h); return a; };
    auto right = [] (juce::Rectangle<int> row, juce::Component& c, int w) { c.setBounds (row.getRight() - w, row.getCentreY() - Theme::ctlH / 2, w, Theme::ctlH); };
    titleArea = take (Theme::ctlH);
    {
        // the one primary action sits with the drill's name, so it never leaves the window
        auto t = titleArea;
        start.setBounds (t.removeFromRight (120));
        t.removeFromRight (Theme::sp2);
        hearIntro.setBounds (t.removeFromRight (Theme::ctlH));
        titleArea = t.withTrimmedRight (Theme::sp4);
    }
    take (Theme::sp2);
    detailArea = take (34);
    patternArea = take (26);
    take (Theme::sp5);
    tempoArea = take (Theme::ctlH);
    right (tempoArea, tempoMode, tempoMode.isVisible() ? 160 : 0);
    if (zoneChips.isVisible())
    {
        take (Theme::sp4);
        auto z = take (Theme::ctlH);
        zoneChips.setBounds (z);
        zoneLineArea = take (22);
    }
    else
    {
        auto d = take (84);
        dial.setBounds (d.withSizeKeepingCentre (std::min (d.getWidth(), 360), 84).withX (d.getX()));
        if (levels.isVisible()) levels.setBounds (d.getRight() - 180, d.getY() + 16, 180, Theme::ctlH);
        zoneLineArea = {};
    }
    take (Theme::sp5);
    guideArea = take (32);
    right (guideArea, guide, 180);
    guideHelp = take (18);
    take (Theme::sp4);
    runArea = take (32);
    right (runArea, runKind, 260);
    amountArea = take (32);
    right (amountArea, amount, 200);
    take (Theme::sp4);
    inputArea = take (32);
    right (inputArea, audioInput, 44);
    inputNote = take (18);
    take (Theme::sp4);
    optionsArea = take (Theme::ctlH);
    optionsToggle.setBounds (optionsArea.withWidth (optionsToggle.idealWidth()));
    if (optionsOpen)
    {
        rowLadder = take (30); right (rowLadder, ladder, 200);
        if (target.isVisible()) { rowTarget = take (30); right (rowTarget, target, 200); } else rowTarget = {};
        rowClick = take (30); right (rowClick, click, 44);
        rowIntro = take (30); right (rowIntro, voiceIntro, 44);
        rowTiming = take (30); right (rowTiming, calibrate, calibrate.idealWidth());
    }
    else rowLadder = rowTarget = rowClick = rowIntro = rowTiming = {};
    take (Theme::sp2);
    messageArea = take (34);
}

void DrillsScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    const auto& d = model.drill();
    Draw::text (g, "Drills", sortButton.getBounds().withX (getLocalBounds().reduced (Theme::sp7, 0).getX()).withWidth (200), Theme::text(), Theme::head, true);
    // the table's column header
    auto h = tableHeader.reduced (8, 0);
    Draw::text (g, "Best", h.removeFromRight (52), Theme::faint(), Theme::micro, false, juce::Justification::centredRight);
    Draw::text (g, "Max", h.removeFromRight (44), Theme::faint(), Theme::micro, false, juce::Justification::centredRight);
    Draw::text (g, "Pattern", h.removeFromRight (56), Theme::faint(), Theme::micro);
    Draw::text (g, "Drill", h, Theme::faint(), Theme::micro);
    Draw::text (g, model.catalogNote, footer, Theme::faint(), Theme::small);
    // a divider between the two panes
    g.setColour (Theme::line());
    g.fillRect (setupArea.getX() - Theme::sp6, setupArea.getY(), 1, getHeight() - 2 * Theme::sp6);

    // the setup
    Draw::text (g, d.name, titleArea, Theme::text(), Theme::head, true);
    g.setColour (Theme::muted());
    g.setFont (Theme::ui (Theme::body));
    g.drawFittedText (d.detail, detailArea, juce::Justification::topLeft, 2, 1.0f);
    PatternStrip strip;
    strip.drill = &d;
    strip.setBounds (patternArea);
    {
        juce::Graphics::ScopedSaveState s (g);
        g.setOrigin (patternArea.getPosition());
        strip.paint (g);
    }
    Draw::text (g, "Tempo", tempoArea, Theme::text());
    if (zoneChips.isVisible()) Draw::text (g, model.zoneLine(), zoneLineArea, Theme::muted(), Theme::small);
    Draw::text (g, "Guide", guideArea, Theme::text());
    Draw::text (g, model.guided ? "Plays the pattern with the click." : "Click only.", guideHelp, Theme::muted(), Theme::small);
    Draw::text (g, "Run", runArea, Theme::text());
    const auto& s = model.session;
    const juce::String amountLabel = s.kind == SessionSettings::Kind::cycles ? "Cycles" : s.kind == SessionSettings::Kind::duration ? "Duration"
                                   : model.audioInput ? "Target accuracy" : "Runs until you stop it";
    Draw::text (g, amountLabel, amountArea, model.audioInput || s.kind != SessionSettings::Kind::endurance ? Theme::text() : Theme::muted());
    Draw::text (g, "Audio input", inputArea.withWidth (120), Theme::text());
    Draw::text (g, model.audioInput ? "Scored" : "Not scored", inputArea.withTrimmedRight (56), Theme::muted(), Theme::small, false, juce::Justification::centredRight);
    juce::String note;
    juce::Colour noteColour = Theme::warn();
    if (model.audioInput)
    {
        if (! model.device.open) note = "No audio device. Pick one in Settings, Audio.";
        else if (! model.hasInput()) note = "Pick an audio input to score.";
        else if (! model.calibration()) note = "New audio setup. Calibrate for accurate timing.";
        else { note = "In: " + model.routeName() + dot + juce::String ((int) std::round (model.currentOffset() * 1000)) + " ms offset"; noteColour = Theme::muted(); }
    }
    Draw::text (g, note, inputNote, noteColour, Theme::small);
    for (auto* row : { &rowLadder, &rowTarget, &rowClick, &rowIntro, &rowTiming })
        if (! row->isEmpty()) Draw::hairline (g, row->getX(), row->getY(), row->getWidth());
    if (optionsOpen)
    {
        Draw::text (g, "Ladder", rowLadder, Theme::text());
        if (! rowTarget.isEmpty()) Draw::text (g, "Pass mark", rowTarget, Theme::text());
        Draw::text (g, "Click", rowClick, Theme::text());
        Draw::text (g, "Voice intro", rowIntro, Theme::text());
        auto c = model.calibration();
        Draw::text (g, "Timing", rowTiming.withWidth (80), Theme::text());
        Draw::text (g, c ? juce::String ((int) std::round (model.currentOffset() * 1000)) + " ms" + dot + c->routeName : juce::String ("Not calibrated"),
                    rowTiming.withTrimmedLeft (80).withTrimmedRight (calibrate.getWidth() + 12), Theme::muted(), Theme::small);
    }
    if (model.message.isNotEmpty())
    {
        g.setColour (Theme::warn());
        g.setFont (Theme::ui (Theme::small));
        g.drawFittedText (model.message, messageArea, juce::Justification::centredLeft, 2, 1.0f);
    }
}

bool DrillsScreen::keyPressed (const juce::KeyPress& k)
{
    if (k == juce::KeyPress::spaceKey && model.phase == Model::Phase::ready) { model.start(); return true; }
    if (k == juce::KeyPress::upKey || k == juce::KeyPress::downKey)
    {
        for (size_t i = 0; i < model.drills.size(); ++i)
            if (model.drills[i].id == model.drillID)
            {
                const int j = juce::jlimit (0, (int) model.drills.size() - 1, (int) i + (k == juce::KeyPress::upKey ? -1 : 1));
                model.select (model.drills[(size_t) j].id);
                return true;
            }
    }
    return false;
}

} // namespace practice::ui
