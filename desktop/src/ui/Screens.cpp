#include "Screens.h"

namespace practice::ui {

static const juce::String dash = juce::String (juce::CharPointer_UTF8 ("\xe2\x80\x93"));
static juce::String loops (int n) { return n == 1 ? juce::String ("1 loop") : juce::String (n) + " loops"; }
static juce::String soundName (SessionSettings::ClickSound s)
{
    switch (s) { case SessionSettings::ClickSound::wood: return "Wood block"; case SessionSettings::ClickSound::beep: return "Beep";
                 case SessionSettings::ClickSound::rim: return "Rim"; default: return "Click"; }
}
static const juce::StringArray soundNames { "Click", "Wood block", "Beep", "Rim" };

// ================================================================ Metronome

MetronomeScreen::MetronomeScreen (Model& m) : Screen (m)
{
    setWantsKeyboardFocus (true);
    for (auto* c : std::initializer_list<juce::Component*> { &tempo, &slider, &form, &signature, &subdivision, &accent, &sound, &tap, &start })
        addAndMakeVisible (c);
    form.managed = { &signature, &subdivision, &accent, &sound };
    form.setInterceptsMouseClicks (false, false);
    tempo.numberSize = 72;
    tempo.onChange = [this] (int v) { model.setMetroBPM (v); };
    slider.setRange (30, 300, 1);
    slider.onValueChange = [this] { model.setMetroBPM ((int) slider.getValue()); };
    signature.setItems ({ "2/4", "3/4", "4/4", "5/4", "6/4", "7/4" }, "4/4");
    signature.onChange = [this] { model.setMetroBeats (signature.getSelectedItemIndex() + 2); };
    subdivision.setItems ({ "Quarter", "Eighth", "Triplet", "16th" }, "Quarter");
    subdivision.onChange = [this] { model.setMetroSub (subdivision.getSelectedItemIndex() + 1); };
    accent.setItems ({ "Off", "Beat 1" }, "Beat 1");
    accent.onChange = [this] { model.setMetroAccent (accent.getSelectedItemIndex() == 1); };
    sound.setItems (soundNames, "Click");
    sound.onChange = [this] { model.setMetroSound ((SessionSettings::ClickSound) sound.getSelectedItemIndex()); };
    tap.setTooltip ("Tap tempo (T)");
    tap.onClick = [this] { model.tap(); };
    start.setTooltip ("Space");
    start.onClick = [this] { model.toggleMetronome(); };
    refresh();
}

void MetronomeScreen::refresh()
{
    tempo.setValue (model.metroBPM);
    slider.setValue (model.metroBPM, juce::dontSendNotification);
    signature.setSelectedItemIndex (model.metroBeats - 2, juce::dontSendNotification);
    subdivision.setSelectedItemIndex (model.metroSub - 1, juce::dontSendNotification);
    accent.setSelectedItemIndex (model.metroAccent ? 1 : 0, juce::dontSendNotification);
    sound.setSelectedItemIndex ((int) model.metroSound, juce::dontSendNotification);
    const bool on = model.metronomeRunning() && ! model.blockClickOn;
    start.setText (on ? "Stop" : "Start");
    start.setIcon (on ? "stop" : "play");
    repaint (beatArea);
}

void MetronomeScreen::resized()
{
    auto r = getLocalBounds().reduced (Theme::sp7);
    auto col = r.withWidth (std::min (560, r.getWidth()));
    titleArea = col.removeFromTop (24);
    col.removeFromTop (Theme::sp7);
    beatArea = col.removeFromTop (12);
    col.removeFromTop (Theme::sp6);
    tempo.setBounds (col.removeFromTop (96));
    col.removeFromTop (Theme::sp4);
    slider.setBounds (col.removeFromTop (Theme::ctlH));
    col.removeFromTop (Theme::sp7);
    form.setTopLeftPosition (col.getPosition());
    form.begin();
    form.row ("Time signature", signature, 160);
    form.row ("Subdivision", subdivision, 160);
    form.row ("Accent", accent, 160);
    form.row ("Click sound", sound, 160);
    const int h = form.layout (col.getWidth());
    col.removeFromTop (h + Theme::sp7);
    auto b = col.removeFromTop (Theme::ctlH);
    tap.setBounds (b.removeFromLeft (96));
    b.removeFromLeft (Theme::sp4);
    start.setBounds (b.removeFromLeft (140));
}

void MetronomeScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    Draw::text (g, "Metronome", titleArea, Theme::text(), Theme::head, true);
    const int beat = model.blockClickOn ? -1 : model.metronomeBeat();
    Draw::beatBar (g, beatArea, model.metroBeats, beat, model.metroAccent ? 0 : -1);
}

bool MetronomeScreen::keyPressed (const juce::KeyPress& k)
{
    if (k == juce::KeyPress::spaceKey) { model.toggleMetronome(); return true; }
    if (k.getTextCharacter() == 't' || k.getTextCharacter() == 'T') { model.tap(); return true; }
    const int step = k.getModifiers().isShiftDown() ? 5 : 1;
    if (k == juce::KeyPress::upKey) { model.setMetroBPM (model.metroBPM + step); return true; }
    if (k == juce::KeyPress::downKey) { model.setMetroBPM (model.metroBPM - step); return true; }
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
    rows.clear();
    for (auto& d : model.drills)
    {
        Row r { d.id, d.tableName(), dash, dash, {} };
        if (auto m = model.level (d.id)) r.max = juce::String (*m);
        int best = -1;
        juce::Time last;
        for (auto& x : runs)
            if (x.exerciseID == d.id)
            {
                if (last.toMilliseconds() == 0) last = x.date;
                if (! x.guided && x.mode != "endurance" && x.mode != "challenge") best = std::max (best, x.accuracyPercent);
            }
        if (best >= 0) r.best = juce::String (best) + "%";
        if (last.toMilliseconds() != 0) r.last = lastPlayed (last);
        rows.push_back (r);
    }
    repaint();
}

int DrillTable::rowAt (int y) const
{
    const int i = (y - 28) / Theme::rowH;
    return y >= 28 && i < (int) rows.size() ? i : -1;
}

void DrillTable::paint (juce::Graphics& g)
{
    const int w = getWidth();
    auto head = juce::Rectangle<int> (0, 0, w, 28).reduced (Theme::sp4, 0);
    Draw::text (g, "Last played", head.removeFromRight (96), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
    Draw::text (g, "Best", head.removeFromRight (64), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
    Draw::text (g, "Max", head.removeFromRight (64), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
    Draw::text (g, "Drill", head, Theme::faint(), Theme::small);
    Draw::hairline (g, 0, 27, w);
    for (int i = 0; i < (int) rows.size(); ++i)
    {
        const auto& r = rows[(size_t) i];
        auto area = juce::Rectangle<int> (0, 28 + i * Theme::rowH, w, Theme::rowH);
        if (i == hover) { g.setColour (Theme::hover()); g.fillRoundedRectangle (area.toFloat(), Theme::rMd); }
        auto inner = area.reduced (Theme::sp4, 0);
        Draw::text (g, r.last, inner.removeFromRight (96), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::text (g, r.best, inner.removeFromRight (64), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::text (g, r.max, inner.removeFromRight (64), Theme::text(), Theme::body, false, juce::Justification::centredRight);
        Draw::text (g, r.name, inner, Theme::text());
        Draw::hairline (g, Theme::sp4, area.getBottom() - 1, w - Theme::sp4);
    }
    if (rows.empty()) Draw::text (g, "No drills. Sync to update", { Theme::sp4, 36, w, 20 }, Theme::muted());
}

void DrillTable::mouseDown (const juce::MouseEvent& e)
{
    const int i = rowAt (e.y);
    if (i >= 0 && onOpen) onOpen (rows[(size_t) i].id);
}

void DrillTable::mouseMove (const juce::MouseEvent& e) { const int i = rowAt (e.y); if (i != hover) { hover = i; repaint(); } }
void DrillTable::mouseExit (const juce::MouseEvent&) { hover = -1; repaint(); }

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
            const float x = (float) (n.at.beats() + k * cycle) * cell + cell * 0.08f + 1.0f;
            const float h = n.accent ? r.getHeight() - 8 : r.getHeight() * 0.45f;
            g.setColour (n.accent ? Theme::accent() : Theme::muted());
            g.fillRoundedRectangle (x, (r.getHeight() - h) / 2, 2, h, 1.0f);
        }
}

// ================================================================ a drill's setup (the drill's own, or a routine block's)

SetupForms::SetupForms (Model& m, bool ownDrill) : model (m), own (ownDrill)
{
    setInterceptsMouseClicks (false, true);
    std::vector<juce::Component*> all { &tempo, &zone, &length, &plan, &sound, &accent, &gap, &tuning, &everyUnit, &windowUnit, &atTop,
        &amount, &target, &over, &cap, &endBPM, &step, &every, &upPct, &upWin, &downPct, &downWin, &lowest, &breakPct, &breakWin,
        &breakLen, &cooldown, &countIn, &passMark, &input, &guide, &downOn, &breakOn, &slower, &click, &intro, &level, &calibrate };
    for (auto* c : all) addChildComponent (c);
    addAndMakeVisible (main);
    addAndMakeVisible (options);
    main.setInterceptsMouseClicks (false, false);
    options.setInterceptsMouseClicks (false, false);
    main.managed = { &zone, &length, &plan, &amount, &target, &over, &cap, &endBPM, &step, &every, &everyUnit, &atTop, &upPct, &upWin,
                     &downOn, &downPct, &downWin, &lowest, &breakOn, &breakPct, &breakWin, &breakLen, &slower, &cooldown, &windowUnit, &input, &guide };
    options.managed = { &sound, &level, &accent, &countIn, &gap, &click, &passMark, &calibrate, &intro, &tuning };
    tempo.numberSize = 44;
    tempo.onChange = [this] (int v) {
        if (own) model.nudgeTempo (v);
        else push ([v] (State& s) { s.bpm = v; });
    };
    zone.onChange = [this] {
        const int i = zone.getSelectedItemIndex();
        if (i == 0) model.setManual (true);
        else if (i - 1 < (int) model.zones.zones.size()) model.chooseZone (model.zones.zones[(size_t) i - 1].id);
    };
    length.onChange = [this] {
        const int i = length.getSelectedItemIndex();
        push ([i] (State& s) {
            s.session.kind = i == 0 ? SessionSettings::Kind::cycles : i == 1 ? SessionSettings::Kind::duration
                           : i == 2 ? SessionSettings::Kind::endurance : SessionSettings::Kind::challenge;
            if (s.session.kind == SessionSettings::Kind::challenge && s.session.targetPercent < 80) s.session.targetPercent = 90;
        });
    };
    plan.onChange = [this] {
        const int i = plan.getSelectedItemIndex();
        push ([i] (State& s) {
            s.session.tempoPlan.mode = i == 0 ? TempoPlan::Mode::off : i == 1 ? TempoPlan::Mode::perLoop : TempoPlan::Mode::accuracy;
            if (i == 2) s.audioInput = true;
        });
    };
    auto stepper = [this] (Stepper& st, int lo, int hi, int by, std::function<void (State&, int)> f) {
        st.minimum = lo; st.maximum = hi; st.step = by;
        st.onChange = [this, f] (int v) { push ([f, v] (State& s) { f (s, v); }); };
    };
    stepper (amount, 1, 1800, 1, [] (State& s, int v) {
        if (s.session.kind == SessionSettings::Kind::cycles) s.session.cycles = v;
        else if (s.session.kind == SessionSettings::Kind::endurance) s.session.targetPercent = v;
        else s.session.seconds = v;
    });
    stepper (target, 50, 100, 1, [] (State& s, int v) { s.session.targetPercent = v; });
    stepper (over, 1, 8, 1, [] (State& s, int v) { s.session.windowCycles = v; });
    stepper (cap, 0, 3600, 60, [] (State& s, int v) { s.session.capSeconds = v; });
    stepper (endBPM, 20, 400, 1, [] (State& s, int v) { s.session.tempoPlan.endBPM = v; });
    stepper (step, 1, 20, 1, [] (State& s, int v) { s.session.tempoPlan.step = v; });
    stepper (every, 1, 300, 1, [] (State& s, int v) { s.session.tempoPlan.every = v; });
    stepper (upPct, 50, 100, 1, [] (State& s, int v) { s.session.tempoPlan.upPercent = v; });
    stepper (upWin, 1, 300, 1, [] (State& s, int v) { s.session.tempoPlan.upWindow = v; });
    stepper (downPct, 30, 95, 1, [] (State& s, int v) { s.session.tempoPlan.downPercent = v; });
    stepper (downWin, 1, 300, 1, [] (State& s, int v) { s.session.tempoPlan.downWindow = v; });
    stepper (lowest, 20, 400, 1, [] (State& s, int v) { s.session.tempoPlan.minBPM = v; });
    stepper (breakPct, 0, 90, 1, [] (State& s, int v) { s.session.tempoPlan.breakPercent = v; });
    stepper (breakWin, 1, 300, 1, [] (State& s, int v) { s.session.tempoPlan.breakWindow = v; });
    stepper (breakLen, 10, 120, 5, [] (State& s, int v) { s.session.tempoPlan.breakSeconds = v; });
    stepper (cooldown, 0, 8, 1, [] (State& s, int v) { s.session.tempoPlan.cooldownLoops = v; });
    stepper (countIn, 0, 4, 1, [] (State& s, int v) { s.session.countInBars = v; });
    stepper (passMark, 50, 100, 5, [] (State& s, int v) { s.session.targetPercent = v; });
    everyUnit.setItems ({ "Loops", "Seconds" }, "Loops");
    everyUnit.onChange = [this] { const int i = everyUnit.getSelectedItemIndex(); push ([i] (State& s) { s.session.tempoPlan.everyUnit = i == 1 ? TempoPlan::Unit::seconds : TempoPlan::Unit::loops; }); };
    windowUnit.setItems ({ "Loops", "Seconds" }, "Loops");
    windowUnit.onChange = [this] { const int i = windowUnit.getSelectedItemIndex(); push ([i] (State& s) { s.session.tempoPlan.windowUnit = i == 1 ? TempoPlan::Unit::seconds : TempoPlan::Unit::loops; }); };
    atTop.setItems ({ "Hold", "Restart" }, "Hold");
    atTop.onChange = [this] { const int i = atTop.getSelectedItemIndex(); push ([i] (State& s) { s.session.tempoPlan.atTop = i == 1 ? TempoPlan::AtTop::restart : TempoPlan::AtTop::hold; }); };
    sound.setItems (soundNames, "Click");
    sound.onChange = [this] { const int i = sound.getSelectedItemIndex(); push ([i] (State& s) { s.session.clickSound = (SessionSettings::ClickSound) i; }); };
    accent.setItems ({ "Off", "Beat 1", "Group starts" }, "Beat 1");
    accent.onChange = [this] { const int i = accent.getSelectedItemIndex(); push ([i] (State& s) { s.session.accent = i == 0 ? SessionSettings::Accent::off : i == 2 ? SessionSettings::Accent::groups : SessionSettings::Accent::one; }); };
    gap.setItems ({ "Off", "Every 2nd bar", "Every 3rd bar", "Every 4th bar", "Every 8th bar" }, "Off");
    gap.onChange = [this] { static const int n[] = { 0, 2, 3, 4, 8 }; const int i = juce::jlimit (0, 4, gap.getSelectedItemIndex()); push ([i] (State& s) { s.session.gapEvery = n[i]; }); };
    tuning.onChange = [this] {
        const int i = tuning.getSelectedItemIndex();
        push ([i] (State& s) { if (i <= 0) s.session.tuning.reset(); else if (i - 1 < (int) Tuning::presets().size()) s.session.tuning = Tuning::presets()[(size_t) i - 1]; });
    };
    level.setRange (0, 1, 0.01);
    level.onValueChange = [this] { const double v = level.getValue(); push ([v] (State& s) { s.session.clickLevel = v; }); };
    auto sw = [this] (Switch& s, std::function<void (State&, bool)> f) { s.onChange = [this, f] (bool on) { push ([f, on] (State& st) { f (st, on); }); }; };
    sw (input, [] (State& s, bool on) {
        s.audioInput = on;
        if (! on && s.session.tempoPlan.mode == TempoPlan::Mode::accuracy) s.session.tempoPlan.mode = TempoPlan::Mode::perLoop;
        if (! on && s.session.kind == SessionSettings::Kind::challenge) s.session.kind = SessionSettings::Kind::duration;
    });
    sw (guide, [] (State& s, bool on) { s.guided = on; });
    sw (downOn, [] (State& s, bool on) { s.session.tempoPlan.downOn = on; });
    sw (breakOn, [] (State& s, bool on) { s.session.tempoPlan.breakOn = on; });
    sw (slower, [] (State& s, bool on) { s.session.tempoPlan.slowerAfterBreak = on; });
    sw (intro, [] (State& s, bool on) { s.intro = on; });
    click.onChange = [this] (bool on) { model.setGridClicks (on); };
    calibrate.onClick = [this] { model.startCalibration(); };
}

void SetupForms::push (std::function<void (State&)> change)
{
    if (! get || ! set) return;
    auto s = get();
    change (s);
    set (s);
}

void SetupForms::refresh()
{
    if (! get || ! drill) return;
    const auto s = get();
    const auto& ss = s.session;
    const auto p = ss.tempoPlan.normalized();
    const auto b = p.bounds (s.bpm, drill->tempo.min, drill->tempo.max);
    tempo.minimum = drill->tempo.min; tempo.maximum = drill->tempo.max;
    tempo.setValue (s.bpm);
    tempo.setVisible (true);
    // Zones
    juce::StringArray zs { "Manual" };
    juce::String zsel = "Manual";
    if (auto max = model.level (drill->id))
        for (auto& z : model.zones.zones)
        {
            auto r = TempoZones::range (z, *max);
            const auto label = z.name + ", " + juce::String (r.first) + " to " + juce::String (r.second);
            zs.add (label);
            if (model.resume && model.activeZone() && model.activeZone()->id == z.id) zsel = label;
        }
    zone.setItems (zs, zsel);
    length.setItems (s.audioInput ? juce::StringArray { "Loops", "Time", "Hold accuracy", "Challenge" } : juce::StringArray { "Loops", "Time", "Until stopped" },
                     ss.kind == SessionSettings::Kind::cycles ? "Loops" : ss.kind == SessionSettings::Kind::duration ? "Time"
                     : ss.kind == SessionSettings::Kind::challenge ? "Challenge" : (s.audioInput ? "Hold accuracy" : "Until stopped"));
    plan.setItems ({ "Off", "Per loop", "By accuracy" }, ss.tempoPlan.mode == TempoPlan::Mode::perLoop ? "Per loop" : ss.tempoPlan.mode == TempoPlan::Mode::accuracy ? "By accuracy" : "Off");
    switch (ss.kind)
    {
        case SessionSettings::Kind::cycles: amount.minimum = 1; amount.maximum = 100; amount.step = 1; amount.setValue (ss.cycles, loops (ss.cycles)); break;
        case SessionSettings::Kind::duration: case SessionSettings::Kind::challenge:
            amount.minimum = 30; amount.maximum = 1800; amount.step = 30; amount.setValue (ss.seconds, formatClock (ss.seconds)); break;
        case SessionSettings::Kind::endurance: amount.minimum = 50; amount.maximum = 100; amount.step = 5; amount.setValue (ss.targetPercent, juce::String (ss.targetPercent) + "%"); break;
    }
    target.setValue (ss.targetPercent, juce::String (ss.targetPercent) + "%");
    over.setValue (ss.windowCycles, loops (ss.windowCycles));
    cap.setValue (ss.capSeconds, ss.capSeconds == 0 ? juce::String ("Off") : formatClock (ss.capSeconds));
    endBPM.minimum = s.bpm; endBPM.maximum = drill->tempo.max; endBPM.setValue (b.top, juce::String (b.top) + " bpm");
    step.setValue (p.step, "+" + juce::String (p.step) + " bpm");
    const bool secs = p.everyUnit == TempoPlan::Unit::seconds;
    every.minimum = secs ? 5 : 1; every.maximum = secs ? 300 : 16; every.step = secs ? 5 : 1;
    every.setValue (p.every, secs ? formatClock (p.every) : loops (p.every));
    everyUnit.setSelectedItemIndex (secs ? 1 : 0, juce::dontSendNotification);
    atTop.setSelectedItemIndex (p.atTop == TempoPlan::AtTop::restart ? 1 : 0, juce::dontSendNotification);
    const bool wsec = p.windowUnit == TempoPlan::Unit::seconds;
    windowUnit.setSelectedItemIndex (wsec ? 1 : 0, juce::dontSendNotification);
    auto win = [&] (Stepper& st, int v) { st.minimum = wsec ? 5 : 1; st.maximum = wsec ? 300 : 32; st.step = wsec ? 5 : 1; st.setValue (v, wsec ? formatClock (v) : loops (v)); };
    upPct.setValue (p.upPercent, juce::String (p.upPercent) + "%");
    win (upWin, p.upWindow);
    downOn.setOn (p.downOn);
    downPct.maximum = std::max (30, p.upPercent - 5);
    downPct.setValue (p.downPercent, juce::String (p.downPercent) + "%");
    win (downWin, p.downWindow);
    lowest.minimum = drill->tempo.min; lowest.maximum = s.bpm; lowest.setValue (b.floor, juce::String (b.floor) + " bpm");
    breakOn.setOn (p.breakOn);
    breakPct.maximum = std::max (0, (p.downOn ? p.downPercent : p.upPercent - 5) - 5);
    breakPct.setValue (p.breakPercent, juce::String (p.breakPercent) + "%");
    win (breakWin, p.breakWindow);
    breakLen.setValue (p.breakSeconds, juce::String (p.breakSeconds) + " s");
    slower.setOn (p.slowerAfterBreak);
    cooldown.setValue (p.cooldownLoops, loops (p.cooldownLoops));
    input.setOn (s.audioInput);
    guide.setOn (s.guided);
    sound.setSelectedItemIndex ((int) ss.clickSound, juce::dontSendNotification);
    level.setValue (ss.clickLevel, juce::dontSendNotification);
    accent.setSelectedItemIndex (ss.accent == SessionSettings::Accent::off ? 0 : ss.accent == SessionSettings::Accent::groups ? 2 : 1, juce::dontSendNotification);
    countIn.setValue (ss.countInBars, ss.countInBars == 0 ? juce::String ("Off") : ss.countInBars == 1 ? juce::String ("1 bar") : juce::String (ss.countInBars) + " bars");
    gap.setSelectedItemIndex (ss.gapEvery == 0 ? 0 : ss.gapEvery == 2 ? 1 : ss.gapEvery == 3 ? 2 : ss.gapEvery == 4 ? 3 : 4, juce::dontSendNotification);
    click.setOn (model.gridClicks);
    passMark.setValue (ss.targetPercent, juce::String (ss.targetPercent) + "%");
    intro.setOn (s.intro);
    juce::StringArray ts { "Default, " + model.guitarTuning.name };
    for (auto& t : Tuning::presets()) ts.add (t.name);
    tuning.setItems (ts, ss.tuning ? ss.tuning->name : ts[0]);
}

void SetupForms::layoutIn (juce::Rectangle<int> left, juce::Rectangle<int> right)
{
    if (! get || ! drill) return;
    const auto s = get();
    const auto& ss = s.session;
    const auto p = ss.tempoPlan.normalized();
    tempoArea = left.removeFromTop (72);
    tempo.setBounds (tempoArea);
    captionArea = left.removeFromTop (18);
    left.removeFromTop (Theme::sp6);
    main.setTopLeftPosition (left.getPosition());
    main.begin();
    if (own && model.level (drill->id)) main.row ("Tempo zone", zone, 200);
    main.row ("Length", length, 200);
    switch (ss.kind)
    {
        case SessionSettings::Kind::cycles: main.row ("Loops", amount, 200); break;
        case SessionSettings::Kind::duration: main.row ("Time", amount, 200); break;
        case SessionSettings::Kind::endurance: if (s.audioInput) { main.row ("Accuracy", amount, 200); main.row ("Over", over, 200); } break;
        case SessionSettings::Kind::challenge:
            main.row ("Earn", amount, 200);
            main.row ("At or above", target, 200);
            main.row ("Over", over, 200);
            main.row ("Most time", cap, 200);
            main.note ("The clock counts only while the accuracy holds", Theme::muted());
            break;
    }
    main.row ("Ascending tempo", plan, 200);
    if (p.mode != TempoPlan::Mode::off)
    {
        main.row ("End", endBPM, 200);
        main.row ("Step", step, 200);
    }
    if (p.mode == TempoPlan::Mode::perLoop)
    {
        main.row ("Count", everyUnit, 200);
        main.row ("Every", every, 200);
        main.row ("At the top", atTop, 200);
    }
    if (p.mode == TempoPlan::Mode::accuracy)
    {
        main.section ("Speed up");
        main.row ("At or above", upPct, 200);
        main.row ("For", upWin, 200);
        main.section ("Slow down");
        main.row ("Slow down", downOn, 44);
        if (p.downOn) { main.row ("Below", downPct, 200); main.row ("For", downWin, 200); main.row ("Lowest", lowest, 200); }
        main.section ("Break");
        main.row ("Auto break", breakOn, 44);
        if (p.breakOn)
        {
            main.row ("Below", breakPct, 200);
            main.row ("For", breakWin, 200);
            main.row ("Break length", breakLen, 200);
            main.row ("Resume one step slower", slower, 44);
        }
        main.section ("Stability");
        main.row ("Count", windowUnit, 200);
        main.row ("Wait after a change", cooldown, 200);
        main.note ("The thresholds stay at least 5 points apart", Theme::muted());
    }
    main.section ("Sound in");
    main.row ("Audio input", input, 44);
    main.row ("Guide notes", guide, 44);
    if (own && s.audioInput)
    {
        juce::String note;
        if (! model.device.open) note = "No audio device. Pick one in Settings.";
        else if (! model.hasInput()) note = "Pick an audio input to score.";
        else if (! model.calibration()) note = "New audio setup. Calibrate for accurate timing.";
        if (note.isNotEmpty()) main.note (note, Theme::warn());
    }
    const int mh = main.layout (left.getWidth());
    // Options: beside the main form, or under it
    auto o = right.isEmpty() ? left.withTrimmedTop (mh + Theme::sp7) : right;
    options.setTopLeftPosition (o.getPosition());
    options.begin();
    options.section ("Click");
    options.row ("Click sound", sound, 160);
    options.row ("Click level", level, 160);
    options.row ("Accent", accent, 160);
    options.row ("Count-in", countIn, 160);
    options.row ("Gap trainer", gap, 160);
    options.row ("Click", click, 44);
    if (s.audioInput)
    {
        options.section ("Scoring");
        if (! ss.endsItself()) options.row ("Pass mark", passMark, 160);
        if (own)
        {
            auto c = model.calibration();
            options.row ("Calibration", calibrate, calibrate.idealWidth(), c ? juce::String ((int) std::round (model.currentOffset() * 1000)) + " ms" : juce::String ("Not yet"));
        }
    }
    if (own) { options.section ("Voice"); options.row ("Voice intro", intro, 44); }
    options.section ("Guitar");
    options.row ("Tuning", tuning, 200);
    const int oh = options.layout (o.getWidth());
    setSize (getWidth(), std::max (main.getBottom(), options.getY() + oh) + Theme::sp6);
    repaint();
}

void SetupForms::paint (juce::Graphics& g)
{
    if (! get || ! drill) return;
    const auto s = get();
    juce::String caption = "No max yet";
    if (own) if (auto max = model.level (drill->id)) caption = juce::String ((int) std::round (100.0 * s.bpm / *max)) + "% of max " + juce::String (*max);
    if (! own) caption = {};
    Draw::text (g, caption, captionArea, Theme::muted(), Theme::small);
}

// ================================================================ Drills

DrillsScreen::DrillsScreen (Model& m) : Screen (m), table (m), forms (m, true)
{
    setWantsKeyboardFocus (true);
    addAndMakeVisible (table);
    addChildComponent (scroller);
    addChildComponent (back);
    addChildComponent (hearIntro);
    addChildComponent (start);
    scroller.setViewedComponent (&content, false);
    scroller.setScrollBarsShown (true, false);
    content.addAndMakeVisible (strip);
    content.addAndMakeVisible (forms);
    table.onOpen = [this] (const juce::String& id) { model.select (id); setupOpen = true; refresh(); resized(); };
    back.onClick = [this] { setupOpen = false; refresh(); resized(); };
    hearIntro.setTooltip ("Play intro");
    hearIntro.onClick = [this] { model.repeatIntro(); };
    start.setTooltip ("Enter");
    start.onClick = [this] { model.start(); };
    forms.get = [this] { return SetupForms::State { model.startTempo(), model.session, model.guided, model.audioInput, model.intro }; };
    forms.set = [this] (const SetupForms::State& s) {
        if (s.bpm != model.startTempo()) model.nudgeTempo (s.bpm);
        if (s.guided != model.guided) model.setGuided (s.guided);
        if (s.audioInput != model.audioInput) model.setAudioInput (s.audioInput);
        if (s.intro != model.intro) model.setIntro (s.intro);
        if (! (s.session == model.session)) model.setSession (s.session);
    };
    refresh();
}

void DrillsScreen::refresh()
{
    table.refresh();
    table.setVisible (! setupOpen);
    for (auto* c : std::initializer_list<juce::Component*> { &scroller, &back, &hearIntro, &start }) c->setVisible (setupOpen);
    forms.drill = &model.drill();
    strip.drill = &model.drill();
    start.setEnabled (model.phase == Model::Phase::ready);
    if (setupOpen) { forms.refresh(); resized(); }
    repaint();
}

void DrillsScreen::resized()
{
    auto r = getLocalBounds().reduced (Theme::sp7, Theme::sp6);
    headArea = r.removeFromTop (Theme::ctlH);
    r.removeFromTop (Theme::sp5);
    if (! setupOpen)
    {
        titleArea = headArea;
        table.setBounds (r.withHeight (28 + Theme::rowH * (int) std::max<size_t> (1, model.drills.size()) + 4));
        return;
    }
    back.setBounds (headArea.withWidth (back.idealWidth()));
    hearIntro.setBounds (headArea.getRight() - Theme::ctlH, headArea.getY(), Theme::ctlH, Theme::ctlH);
    titleArea = headArea.withTrimmedLeft (back.idealWidth() + Theme::sp5).withTrimmedRight (Theme::ctlH + Theme::sp4);
    footArea = r.removeFromBottom (Theme::ctlH + Theme::sp5);
    start.setBounds (footArea.getX(), footArea.getBottom() - Theme::ctlH, 140, Theme::ctlH);
    messageArea = footArea.withTrimmedLeft (140 + Theme::sp5).withTrimmedTop (Theme::sp5);
    scroller.setBounds (r);
    const int w = r.getWidth() - scroller.getScrollBarThickness();
    const bool two = w >= 820;
    const int leftW = two ? std::min (560, w - 360 - Theme::sp8) : std::min (560, w);
    content.setSize (w, 2000);
    detailArea = { 0, 0, leftW, 18 };
    strip.setBounds (0, 24, leftW, 48);
    forms.setBounds (0, 84, w, 1200);
    auto left = juce::Rectangle<int> (0, 0, leftW, 3000);
    auto right = two ? juce::Rectangle<int> (leftW + Theme::sp8, 0, w - leftW - Theme::sp8, 3000).withWidth (360) : juce::Rectangle<int>();
    forms.layoutIn (left, right);
    content.setSize (w, forms.getBottom() + Theme::sp6);
}

void DrillsScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    if (! setupOpen)
    {
        Draw::text (g, "Drills", titleArea, Theme::text(), Theme::head, true);
        if (model.catalogNote.isNotEmpty())
            Draw::text (g, model.catalogNote, { table.getX(), table.getBottom() + Theme::sp4, table.getWidth(), 18 }, Theme::muted(), Theme::small);
        return;
    }
    const auto& d = model.drill();
    Draw::text (g, d.name, titleArea, Theme::text(), Theme::head, true);
    Draw::hairline (g, 0, footArea.getY(), getWidth());
    if (model.message.isNotEmpty())
    {
        g.setColour (Theme::warn());
        g.setFont (Theme::ui (Theme::small));
        g.drawFittedText (model.message, messageArea, juce::Justification::centredLeft, 2, 1.0f);
    }
}

bool DrillsScreen::keyPressed (const juce::KeyPress& k)
{
    if (setupOpen && (k == juce::KeyPress::returnKey || k == juce::KeyPress::spaceKey) && model.phase == Model::Phase::ready) { model.start(); return true; }
    if (setupOpen && k == juce::KeyPress::escapeKey) { setupOpen = false; refresh(); resized(); return true; }
    if (! setupOpen && k == juce::KeyPress::returnKey) { setupOpen = true; refresh(); resized(); return true; }
    return false;
}

} // namespace practice::ui
