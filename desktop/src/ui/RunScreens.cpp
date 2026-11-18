#include "Screens.h"

namespace practice::ui {

static const juce::String dot = juce::String (juce::CharPointer_UTF8 (" \xc2\xb7 "));
static const juce::String dash = juce::String (juce::CharPointer_UTF8 ("\xe2\x80\x93"));

static juce::String groupWord (int n)
{
    switch (n) { case 0: return "Rest"; case 2: return "Eighths"; case 3: return "Triplets"; case 4: return "Sixteenths"; default: return juce::String (n) + " per beat"; }
}

// ================================================================ the lane

void TabLane::paint (juce::Graphics& g)
{
    auto bounds = getLocalBounds().toFloat();
    g.setColour (Theme::side());
    g.fillRoundedRectangle (bounds, Theme::rLg);
    juce::Graphics::ScopedSaveState clip (g);
    g.reduceClipRegion (getLocalBounds());
    const double past = 0.8, ahead = 2.4;
    const float w = bounds.getWidth(), h = bounds.getHeight();
    const float hitX = w * (float) (past / (past + ahead));
    const float pps = w / (float) (past + ahead);
    const double now = model.laneNow();
    auto x = [&] (double t) { return hitX + (float) (t - now) * pps; };
    const auto& notes = model.notes;
    const auto& states = model.states;

    if (calibrationMarks)
    {
        g.setColour (Theme::muted());
        g.fillRoundedRectangle (hitX - 1.5f, 4, 3, h - 8, 1.5f);
        for (size_t i = 0; i < notes.size(); ++i)
        {
            const auto& n = notes[i];
            if (n.time < now - past - 0.1 || n.time > now + ahead + 0.1) continue;
            juce::Colour c = Theme::text();
            if (i < states.size())
                switch (states[i]) { case Model::NoteState::tight: c = Theme::accent(); break; case Model::NoteState::close: c = Theme::accent().withAlpha (0.6f); break;
                                     case Model::NoteState::loose: c = Theme::warn(); break; case Model::NoteState::missed: c = Theme::danger(); break; default: break; }
            g.setColour (c);
            g.fillRoundedRectangle (x (n.time) - 3, h * 0.25f, 6, h * 0.5f, 3);
        }
        return;
    }

    const float arrowY = 14, rhythmY = 46, top = 86, dotY = h - 12;
    const float gap = std::max (10.0f, (dotY - 22 - top) / 5);
    auto stringY = [&] (int s) { return top + (float) juce::jlimit (0, 5, s - 1) * gap; };
    g.setColour (Theme::lineStrong());
    for (int s = 1; s <= 6; ++s) g.fillRect (0.0f, stringY (s) - 0.5f, w, 1.0f);

    int lastBeat = INT_MIN;
    const int bpb = std::max (1, model.runDrill().beatsPerBar);
    for (auto& n : notes)
    {
        if (n.time < now - past - 0.1 || n.time > now + ahead + 0.1 || n.beat == lastBeat) continue;
        lastBeat = n.beat;
        const bool bar = n.beat % bpb == 0;
        const float bx = x (n.time) - 9;
        g.setColour (bar ? Theme::faint() : Theme::line());
        const float y0 = bar ? 24.0f : 32.0f;
        g.fillRect (bx - 0.5f, y0, bar ? 1.5f : 1.0f, stringY (6) - y0);
    }
    g.setColour (Theme::muted());
    g.fillRoundedRectangle (hitX - 1.5f, 4, 3, h - 8, 1.5f);

    for (size_t i = 0; i < notes.size(); ++i)
    {
        const auto& n = notes[i];
        if (n.time < now - past - 0.1 || n.time > now + ahead + 0.1) continue;
        const float nx = x (n.time);
        const auto st = i < states.size() ? states[i] : Model::NoteState::waiting;
        juce::Colour c;
        switch (st)
        {
            case Model::NoteState::waiting: c = n.time < now ? Theme::faint() : Theme::text(); break;
            case Model::NoteState::tight: c = Theme::accent(); break;
            case Model::NoteState::close: c = Theme::accent().withAlpha (0.6f); break;
            case Model::NoteState::loose: c = Theme::warn(); break;
            case Model::NoteState::missed: c = Theme::danger(); break;
        }
        const float bh = n.accent ? 34.0f : 22.0f;
        g.setColour (st == Model::NoteState::waiting ? Theme::faint() : c);
        g.fillRoundedRectangle (nx - 2.5f, rhythmY - bh / 2, 5, bh, 2.5f);
        if (n.pick != Pick::none)
        {
            g.setColour (Theme::muted());
            g.setFont (Theme::ui (11));
            g.drawText (juce::String (juce::CharPointer_UTF8 (n.pick == Pick::down ? "\xe2\x86\x93" : "\xe2\x86\x91")),
                        juce::Rectangle<float> (nx - 8, arrowY - 8, 16, 16), juce::Justification::centred);
        }
        const float y = stringY (n.string > 0 ? n.string : 3);
        const juce::String label (std::max (0, n.fret));
        const float lw = label.length() > 1 ? 20.0f : 14.0f;
        g.setColour (Theme::side());
        g.fillRoundedRectangle (nx - lw / 2, y - 8, lw, 16, 4);
        g.setColour (c);
        g.setFont (Theme::number (11));
        g.drawText (label, juce::Rectangle<float> (nx - lw / 2, y - 8, lw, 16), juce::Justification::centred);
    }
    // the picks heard (the model's list is private; the errors place them)
    for (size_t i = 0; i < notes.size() && i < model.errors.size(); ++i)
        if (model.errors[i] && notes[i].time > now - past - 0.1 && notes[i].time < now + 0.2)
        {
            g.setColour (Theme::text());
            g.fillEllipse (x (notes[i].time + *model.errors[i] / 1000.0) - 3, dotY - 3, 6, 6);
        }
    g.setColour (Theme::side());
    g.fillRect (0.0f, top - 12, 18.0f, stringY (6) - top + 24);
    const char* names[] = { "e", "B", "G", "D", "A", "E" };
    g.setColour (Theme::faint());
    g.setFont (Theme::ui (10));
    for (int s = 1; s <= 6; ++s) g.drawText (names[s - 1], juce::Rectangle<float> (2, stringY (s) - 7, 14, 14), juce::Justification::centred);
}

// ================================================================ a run

RunScreen::RunScreen (Model& m) : Screen (m)
{
    setWantsKeyboardFocus (true);
    for (auto* c : std::initializer_list<juce::Component*> { &lane, &pause, &stop, &meter }) addAndMakeVisible (c);
    addChildComponent (resume); addChildComponent (end); addChildComponent (skip);
    lane.setInterceptsMouseClicks (false, false);
    pause.setTooltip ("Space");
    pause.onClick = [this] { model.pause(); };
    stop.onClick = [this] { model.stop(); };
    resume.onClick = [this] { model.resumeRun(); };
    end.onClick = [this] { model.endRun(); };
    skip.onClick = [this] { model.skipIntro(); };
}

void RunScreen::refresh()
{
    const auto p = model.phase;
    pause.setVisible (p == Model::Phase::running);
    stop.setVisible (p == Model::Phase::running || p == Model::Phase::intro);
    resume.setVisible (p == Model::Phase::paused);
    end.setVisible (p == Model::Phase::paused);
    skip.setVisible (p == Model::Phase::intro);
    lane.setVisible (p != Model::Phase::intro);
    meter.setVisible (model.lastRunWasScored && p == Model::Phase::running);
    meter.push (model.meterPeak());
    repaint();
}

void RunScreen::resized()
{
    auto r = getLocalBounds().reduced (Theme::sp7, Theme::sp6);
    header = r.removeFromTop (22);
    r.removeFromTop (Theme::sp5);
    pattern = r.removeFromTop (56);
    r.removeFromTop (Theme::sp5);
    stats = r.removeFromTop (76);
    r.removeFromTop (Theme::sp6);
    buttons = r.removeFromBottom (Theme::ctlH + 20);
    r.removeFromBottom (Theme::sp5);
    meterArea = r.removeFromBottom (20);
    timingArea = r.removeFromBottom (40);
    r.removeFromBottom (Theme::sp5);
    lane.setBounds (r);
    meter.setBounds (meterArea.withTrimmedLeft (56));
    auto b = buttons.removeFromTop (Theme::ctlH).withSizeKeepingCentre (2 * 140 + Theme::sp4, Theme::ctlH);
    pause.setBounds (b.removeFromLeft (140));
    resume.setBounds (pause.getBounds());
    skip.setBounds (pause.getBounds());
    b.removeFromLeft (Theme::sp4);
    stop.setBounds (b);
    end.setBounds (b);
}

void RunScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    const auto& d = model.runDrill();
    const auto p = model.phase;
    if (p == Model::Phase::intro)
    {
        const auto& sd = model.drill();
        Draw::text (g, sd.name, pattern, Theme::text(), 22, true, juce::Justification::centred);
        Draw::text (g, juce::String (model.startTempo()) + " bpm", stats.removeFromTop (24), Theme::muted(), Theme::body, false, juce::Justification::centred);
        return;
    }
    // the line on top: guided or solo, the zone and the share of his max, or not scored
    juce::String head = model.lastRunWasGuided ? "Guided" : "Solo";
    if (! model.lastRunWasScored) head += dot + "Not scored";
    if (model.runZoneMax > 0)
        if (auto* z = model.zones.zoneFor (model.currentBPM, model.runZoneMax))
            head += dot + z->name + " " + z->title + dot + juce::String ((int) std::round (model.currentBPM / model.runZoneMax * 100)) + "% of max";
    Draw::text (g, head, header, Theme::accentText(), Theme::body, false, juce::Justification::centred);

    // the pattern now
    juce::String big, small;
    juce::Colour smallColour = Theme::muted();
    if (model.countingIn()) big = "Count-in";
    else if (auto* s = model.currentSlot(); s && model.now < s->end())
    {
        auto sizes = d.groupSizes();
        const int local = juce::jlimit (0, (int) sizes.size() - 1, (int) ((model.now - s->start) / (60 / s->bpm)));
        big = groupWord (sizes[(size_t) local]);
        if (auto cue = model.groupCue())
        {
            small = cue->beatsUntil == 1 ? groupWord (cue->next) + " next beat" : groupWord (cue->next) + " in " + juce::String (cue->beatsUntil);
            if (cue->beatsUntil == 1) smallColour = Theme::warn();
        }
    }
    else big = d.tableName();
    auto pa = pattern;
    Draw::text (g, big, pa.removeFromTop (34), Theme::text(), 22, true, juce::Justification::centred);
    Draw::text (g, small, pa, smallColour, Theme::body, false, juce::Justification::centred);

    // bpm, accuracy, time
    auto st = stats;
    const int cw = std::min (200, st.getWidth() / 3);
    auto row = st.withSizeKeepingCentre (cw * 3, st.getHeight());
    auto stat = [&] (juce::Rectangle<int> a, const juce::String& v, const juce::String& cap, juce::Colour c) {
        g.setColour (c);
        g.setFont (Theme::number (36, true));
        g.drawText (v, a.removeFromTop (56), juce::Justification::centred, false);
        Draw::text (g, cap, a, Theme::muted(), Theme::small, false, juce::Justification::centredTop);
    };
    stat (row.removeFromLeft (cw), juce::String ((int) std::round (model.currentBPM)), "bpm", Theme::text());
    if (model.lastRunWasScored)
    {
        auto acc = model.rolling ? juce::String ((int) std::round (*model.rolling * 100)) + "%" : juce::String (dash);
        const bool good = model.rolling && *model.rolling * 100 >= model.runTarget();
        stat (row.removeFromLeft (cw), acc, "accuracy", good ? Theme::accentText() : Theme::text());
    }
    else
    {
        auto c = model.cycleNumber();
        stat (row.removeFromLeft (cw), c ? juce::String (*c) : juce::String (dash), "cycle", Theme::text());
    }
    const auto kind = model.runKind();
    const double elapsed = std::max (0.0, model.now - model.countInEnd);
    if (kind == SessionSettings::Kind::endurance && model.lastRunWasScored) stat (row, formatClock (model.sustained), "held", Theme::text());
    else if (kind == SessionSettings::Kind::duration && model.plannedEnd) stat (row, formatClock (std::max (0.0, *model.plannedEnd - std::max (model.now, model.countInEnd))), "left", Theme::text());
    else if (kind == SessionSettings::Kind::cycles)
    {
        auto c = model.cycleNumber();
        stat (row, (c ? juce::String (std::min (*c, model.runCycles())) : juce::String ("0")) + " of " + juce::String (model.runCycles()), "cycle", Theme::text());
    }
    else stat (row, formatClock (elapsed), "elapsed", Theme::text());

    // early / late, the latest picks
    if (model.lastRunWasScored)
    {
        auto t = timingArea;
        auto line = t.withSizeKeepingCentre (std::min (480, t.getWidth()), 20);
        g.setColour (Theme::lineStrong());
        g.fillRect (line.getX(), line.getCentreY(), line.getWidth(), 1);
        g.fillRect (line.getCentreX(), line.getY(), 1, line.getHeight());
        const double span = std::max (30.0, model.timingSpanMs());
        auto errs = model.recentErrors();
        for (size_t i = 0; i < errs.size(); ++i)
        {
            const double f = juce::jlimit (-1.0, 1.0, errs[i] / span);
            const float px = (float) line.getCentreX() + (float) f * (float) line.getWidth() / 2;
            const float a = 0.25f + 0.75f * (float) (i + 1) / (float) errs.size();
            g.setColour ((std::abs (f) <= 0.35 ? Theme::accent() : std::abs (f) < 0.7 ? Theme::accent().withAlpha (0.55f) : Theme::warn()).withMultipliedAlpha (a));
            g.fillEllipse (px - 4, (float) line.getCentreY() - 4, 8, 8);
        }
        Draw::text (g, "early", line.withY (line.getBottom()).withHeight (16), Theme::faint(), Theme::micro);
        Draw::text (g, "late", line.withY (line.getBottom()).withHeight (16), Theme::faint(), Theme::micro, false, juce::Justification::centredRight);
        Draw::text (g, "Input", meterArea.withWidth (50), Theme::faint(), Theme::micro);
    }

    if (p == Model::Phase::paused)
    {
        g.setColour (Theme::bg().withAlpha (0.86f));
        g.fillRect (lane.getBounds());
        Draw::text (g, "Paused", lane.getBounds().withSizeKeepingCentre (400, 30).translated (0, -12), Theme::text(), 17, true, juce::Justification::centred);
        Draw::text (g, model.message.isNotEmpty() ? model.message : juce::String ("Resumes after a one-bar count-in."),
                    lane.getBounds().withSizeKeepingCentre (600, 20).translated (0, 16), model.message.isNotEmpty() ? Theme::warn() : Theme::muted(),
                    Theme::body, false, juce::Justification::centred);
    }
    else if (p == Model::Phase::running)
        Draw::text (g, "Click anywhere or press Space to pause", buttons.withTrimmedTop (Theme::ctlH + 4), Theme::faint(), Theme::micro, false, juce::Justification::centred);
}

void RunScreen::mouseUp (const juce::MouseEvent& e)
{
    if (model.phase == Model::Phase::running && ! buttons.contains (e.getPosition())) model.pause();
}

bool RunScreen::keyPressed (const juce::KeyPress& k)
{
    if (k == juce::KeyPress::spaceKey)
    {
        if (model.phase == Model::Phase::running) model.pause();
        else if (model.phase == Model::Phase::paused) model.resumeRun();
        else if (model.phase == Model::Phase::intro) model.skipIntro();
        return true;
    }
    if (k == juce::KeyPress::escapeKey) { model.stop(); return true; }
    return false;
}

// ================================================================ the result

ResultScreen::ResultScreen (Model& m) : Screen (m)
{
    addAndMakeVisible (again);
    addAndMakeVisible (done);
    again.onClick = [this] { if (model.lastRunWasGuided && model.lastRunWasScored) model.nowSolo(); else { model.clearResult(); model.start(); } };
    done.onClick = [this] { model.clearResult(); };
}

void ResultScreen::refresh()
{
    const bool solo = model.lastRunWasGuided && model.lastRunWasScored;
    again.setText (solo ? "Play solo" : "Again");
    repaint();
}

void ResultScreen::resized()
{
    auto r = getLocalBounds().reduced (Theme::sp7, Theme::sp6);
    r = r.withSizeKeepingCentre (std::min (620, r.getWidth()), r.getHeight());
    buttons = r.removeFromBottom (Theme::ctlH);
    r.removeFromBottom (Theme::sp6);
    top = r.removeFromTop (196);
    strip = r.removeFromTop (100);
    table = r;
    auto b = buttons.withSizeKeepingCentre (2 * 160 + Theme::sp4, Theme::ctlH);
    again.setBounds (b.removeFromLeft (160));
    b.removeFromLeft (Theme::sp4);
    done.setBounds (b);
}

static juce::String averageText (double e)
{
    if (std::abs (e) < 3) return "On the beat";
    const int ms = (int) std::round (std::abs (e));
    return juce::String (ms) + (e > 0 ? " ms late" : " ms early");
}

void ResultScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    auto t = top;
    if (auto& u = model.unscored)
    {
        Draw::text (g, "Not scored", t.removeFromTop (22), Theme::accentText(), Theme::body, false, juce::Justification::centred);
        g.setColour (Theme::text());
        g.setFont (Theme::number (44, true));
        g.drawText (formatClock (u->seconds), t.removeFromTop (70), juce::Justification::centred);
        const juce::String tempo = u->topBPM > u->startBPM ? juce::String (u->startBPM) + dash + juce::String (u->topBPM) + " bpm" : juce::String (u->startBPM) + " bpm";
        Draw::text (g, tempo + (u->cycles > 0 ? dot + juce::String (u->cycles) + " cycles" : juce::String()), t.removeFromTop (20), Theme::muted(), Theme::body, false, juce::Justification::centred);
        const double total = model.unscoredSeconds (model.runDrill().id);
        Draw::text (g, "Not scored" + dot + juce::String ((int) std::round (total / 60)) + " minutes total", t.removeFromTop (40), Theme::muted(), Theme::small, false, juce::Justification::centred);
        return;
    }
    if (! model.score || ! model.saved) return;
    const auto& s = *model.score;
    const auto& r = *model.saved;
    const bool endurance = r.mode == "endurance";
    const juce::String tempo = r.topBPM > r.startBPM ? juce::String (r.startBPM) + dash + juce::String (r.topBPM) + " bpm" : juce::String (r.startBPM) + " bpm";
    Draw::text (g, juce::String (r.guided ? "Guided" : "Solo") + dot + tempo, t.removeFromTop (22), Theme::accentText(), Theme::body, false, juce::Justification::centred);
    g.setFont (Theme::number (44, true));
    if (endurance)
    {
        g.setColour (Theme::accentText());
        g.drawText (formatClock (r.sustainedSeconds.value_or (0)), t.removeFromTop (70), juce::Justification::centred);
        Draw::text (g, "Held at " + juce::String (r.targetPercent) + "% accuracy", t.removeFromTop (20), Theme::muted(), Theme::body, false, juce::Justification::centred);
    }
    else
    {
        g.setColour (s.passed() ? Theme::accentText() : Theme::text());
        g.drawText (juce::String (s.score) + "%", t.removeFromTop (70), juce::Justification::centred);
        Draw::text (g, s.passed() ? juce::String ("Accuracy") + dot + "Passed" : "Accuracy" + dot + "Pass mark " + juce::String (s.passMark) + "%",
                    t.removeFromTop (20), Theme::muted(), Theme::body, false, juce::Justification::centred);
    }
    t.removeFromTop (Theme::sp4);
    Draw::text (g, averageText (s.meanError) + dot + "spread " + juce::String ((int) std::round (s.spread)) + " ms" + dot + Scoring::band (s.spread),
                t.removeFromTop (20), Theme::text(), Theme::body, true, juce::Justification::centred);
    int cost = 0;
    if (s.expected > 0 && s.extra > 0)
    {
        const double n = s.expected, x = s.extra;
        cost = (int) std::round (std::min (100.0, s.score * (n + x) / n) - s.score);
    }
    if (cost >= 5) Draw::text (g, juce::String (s.extra) + " extra notes took " + juce::String (cost) + " points off", t.removeFromTop (18), Theme::warn(), Theme::small, false, juce::Justification::centred);
    g.setColour (Theme::faint());
    g.setFont (Theme::ui (Theme::small));
    g.drawFittedText (juce::String (juce::CharPointer_UTF8 ("Spread: session players 10\xe2\x80\x93" "15 ms, good amateurs 20\xe2\x80\x93" "30, beginners 40\xe2\x80\x93" "60. At 90 bpm sixteenths, 15 ms scores about 99%, 25 about 91%, 40 about 74%.")),
                      t.removeFromTop (32), juce::Justification::centred, 2, 1.0f);
    juce::StringArray up;
    if (model.newBest) up.add ("New best at this tempo");
    if (auto& l = model.levelUp) up.add ("New max: " + juce::String (l->second) + " bpm" + (l->first > 0 ? " (was " + juce::String (l->first) + ")" : juce::String()));
    Draw::text (g, up.joinIntoString (dot), t.removeFromTop (20), Theme::accentText(), Theme::body, true, juce::Justification::centred);

    // every note's timing
    auto st = strip;
    Draw::sectionLabel (g, "Timing per note", st.removeFromTop (18));
    auto box = st.removeFromTop (64);
    g.setColour (Theme::side());
    g.fillRoundedRectangle (box.toFloat(), Theme::rMd);
    const float mid = (float) box.getCentreY();
    g.setColour (Theme::lineStrong());
    g.fillRect ((float) box.getX(), mid - 0.5f, (float) box.getWidth(), 1.0f);
    if (! s.errors.empty())
    {
        const float step = (float) box.getWidth() / (float) s.errors.size();
        const double span = std::max (40.0, s.zeroMs);
        for (size_t i = 0; i < s.errors.size(); ++i)
        {
            const float px = (float) box.getX() + ((float) i + 0.5f) * step;
            if (! s.errors[i]) { g.setColour (Theme::danger()); g.fillEllipse (px - 1.5f, mid - 1.5f, 3, 3); continue; }
            const double f = juce::jlimit (-1.0, 1.0, *s.errors[i] / span);
            g.setColour (std::abs (f) <= 0.35 ? Theme::accent() : std::abs (f) < 0.7 ? Theme::accent().withAlpha (0.55f) : Theme::warn());
            g.fillEllipse (px - 2, mid + (float) f * ((float) box.getHeight() / 2 - 3) - 2, 4, 4);
        }
    }
    Draw::text (g, "early", st.removeFromTop (16), Theme::faint(), Theme::micro);
    Draw::text (g, "late", st.withY (st.getY() - 16).withHeight (16), Theme::faint(), Theme::micro, false, juce::Justification::centredRight);

    // the detail
    std::vector<std::pair<juce::String, juce::String>> rows;
    if (endurance) rows.push_back ({ "Accuracy", juce::String (s.score) + "%" });
    rows.push_back ({ "On the beat", juce::String (s.pctFull()) + "%" });
    rows.push_back ({ "Average", averageText (s.meanError) });
    rows.push_back ({ "Spread", juce::String ((int) std::round (s.spread)) + " ms" });
    rows.push_back ({ "Missed", juce::String (s.missed) + " of " + juce::String (s.expected) });
    rows.push_back ({ "Extra", juce::String (s.extra) });
    if (r.accentsPercent) rows.push_back ({ "Accents", juce::String (*r.accentsPercent) + "%" });
    rows.push_back ({ "Duration", formatClock (r.seconds) + (r.cycles > 0 ? dot + juce::String (r.cycles) + (r.cycles == 1 ? " cycle" : " cycles") : juce::String()) });
    auto tb = table;
    const int rh = std::min (28, tb.getHeight() / std::max (1, (int) rows.size()));
    for (auto& [k, v] : rows)
    {
        auto row = tb.removeFromTop (rh);
        Draw::text (g, k, row, Theme::text());
        Draw::text (g, v, row, Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::hairline (g, row.getX(), row.getBottom() - 1, row.getWidth());
    }
}

// ================================================================ the calibration

CalibrationScreen::CalibrationScreen (Model& m) : Screen (m)
{
    for (auto* c : std::initializer_list<juce::Component*> { &lane, &offset, &earlier, &later, &next, &done }) addAndMakeVisible (c);
    lane.calibrationMarks = true;
    offset.setRange (-100, 300, 5);
    offset.onValueChange = [this] { model.setDisplayOffset (offset.getValue() / 1000.0); };
    earlier.repeats = later.repeats = true;
    earlier.setTooltip ("Earlier");
    later.setTooltip ("Later");
    earlier.onClick = [this] { model.setDisplayOffset (model.displayOffset() - 0.005); };
    later.onClick = [this] { model.setDisplayOffset (model.displayOffset() + 0.005); };
    next.onClick = [this] { model.calibrateInput(); };
    done.onClick = [this] { model.stop(); if (onDone) onDone(); };
}

void CalibrationScreen::refresh()
{
    const bool step1 = model.phase == Model::Phase::syncing;
    offset.setValue (std::round (model.displayOffset() * 1000), juce::dontSendNotification);
    for (auto* c : std::initializer_list<juce::Component*> { &offset, &earlier, &later, &next }) c->setVisible (step1);
    repaint();
}

void CalibrationScreen::resized()
{
    auto r = getLocalBounds().reduced (Theme::sp7, Theme::sp6);
    r = r.withSizeKeepingCentre (std::min (620, r.getWidth()), r.getHeight());
    head = r.removeFromTop (64);
    r.removeFromTop (Theme::sp5);
    lane.setBounds (r.removeFromTop (std::min (220, r.getHeight() / 2)));
    r.removeFromTop (Theme::sp6);
    value = r.removeFromTop (44);
    auto s = r.removeFromTop (Theme::ctlH);
    earlier.setBounds (s.removeFromLeft (Theme::ctlH));
    later.setBounds (s.removeFromRight (Theme::ctlH));
    offset.setBounds (s.reduced (Theme::sp4, 0));
    help = r.removeFromTop (28);
    auto b = r.removeFromBottom (Theme::ctlH).withSizeKeepingCentre (2 * 140 + Theme::sp4, Theme::ctlH);
    next.setBounds (b.removeFromLeft (140));
    b.removeFromLeft (Theme::sp4);
    done.setBounds (b);
}

void CalibrationScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    const bool step1 = model.phase == Model::Phase::syncing;
    auto h = head;
    Draw::text (g, juce::String ("Calibration") + dot + (step1 ? "1" : "2") + " of 2", h.removeFromTop (18), Theme::muted(), Theme::small, false, juce::Justification::centred);
    Draw::text (g, step1 ? "Display sync" : "Input", h.removeFromTop (24), Theme::text(), Theme::head, true, juce::Justification::centred);
    Draw::text (g, step1 ? "Adjust until each mark crosses the line on the click." : "Play one note as each mark crosses the line.",
                h, Theme::muted(), Theme::body, false, juce::Justification::centred);
    if (step1)
    {
        const int ms = (int) std::round (model.displayOffset() * 1000);
        g.setColour (Theme::text());
        g.setFont (Theme::number (22));
        g.drawText ((ms >= 0 ? "+" : "") + juce::String (ms) + " ms", value, juce::Justification::centred);
        Draw::text (g, "Output: " + model.device.opened.output, help, Theme::faint(), Theme::small, false, juce::Justification::centred);
    }
    else
        Draw::text (g, "In: " + model.routeName(), value, Theme::muted(), Theme::body, false, juce::Justification::centred);
}

} // namespace practice::ui
