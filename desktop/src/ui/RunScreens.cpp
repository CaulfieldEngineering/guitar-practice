#include "Screens.h"

namespace practice::ui {

static const juce::String dash = juce::String (juce::CharPointer_UTF8 ("\xe2\x80\x93"));
static const juce::String times = juce::String (juce::CharPointer_UTF8 ("\xc3\x97"));

static juce::String groupWord (int n)
{
    switch (n) { case 0: return "Rest"; case 2: return "Eighths"; case 3: return "Triplets"; case 4: return "16ths"; default: return juce::String (n) + " per beat"; }
}

static juce::String averageText (double e)
{
    if (std::abs (e) < 3) return "On the beat";
    const int ms = (int) std::round (std::abs (e));
    return juce::String (ms) + (e > 0 ? " ms late" : " ms early");
}

// ================================================================ the lane

void TabLane::paint (juce::Graphics& g)
{
    auto bounds = getLocalBounds().toFloat();
    juce::Graphics::ScopedSaveState clip (g);
    g.reduceClipRegion (getLocalBounds());
    g.setColour (Theme::line());
    g.fillRect (0.0f, 0.0f, bounds.getWidth(), 1.0f);
    g.fillRect (0.0f, bounds.getHeight() - 1, bounds.getWidth(), 1.0f);
    const double past = calibrationMarks ? 1.5 : 1.2, ahead = calibrationMarks ? 1.5 : 2.4;
    const float w = bounds.getWidth(), h = bounds.getHeight();
    const float hitX = w * (float) (past / (past + ahead));
    const float pps = w / (float) (past + ahead);
    const double now = model.laneNow();
    auto x = [&] (double t) { return hitX + (float) (t - now) * pps; };
    const auto& notes = model.notes;
    const auto& states = model.states;

    if (calibrationMarks)
    {
        for (size_t i = 0; i < notes.size(); ++i)
        {
            const auto& n = notes[i];
            if (n.time < now - past - 0.1 || n.time > now + ahead + 0.1) continue;
            const bool near = std::abs (n.time - now) < 0.045;
            g.setColour (near ? Theme::accent() : (n.time < now ? Theme::lineStrong() : Theme::muted()));
            const float mh = near ? h * 0.4f : h * 0.3f;
            g.fillRoundedRectangle (x (n.time) - 3, h * 0.42f - mh / 2, 6, mh, 2);
        }
        g.setColour (Theme::accent());
        g.fillRect (hitX - 1, 0.0f, 2.0f, h);
        for (size_t i = 0; i < notes.size() && i < model.errors.size(); ++i)
            if (model.errors[i] && notes[i].time > now - past - 0.1 && notes[i].time < now + 0.2)
            {
                g.setColour (Theme::text());
                g.fillEllipse (x (notes[i].time + *model.errors[i] / 1000.0) - 3, h - 19, 6, 6);
            }
        return;
    }

    const auto& tuning = model.runTuning;
    const int strings = std::max (1, (int) tuning.strings.size());
    const float arrowY = 12, rhythmY = 34, top = 62;
    const float gap = juce::jlimit (9.0f, 36.0f, (h - 36 - top) / (float) std::max (1, strings - 1));
    auto stringY = [&] (int s) { return top + (float) juce::jlimit (0, strings - 1, s - 1) * gap; };
    const float bottom = stringY (strings) + 4, dotY = std::min (h - 8, bottom + 24);
    g.setColour (Theme::lineStrong());
    for (int s = 1; s <= strings; ++s) g.fillRect (18.0f, stringY (s) - 0.5f, w - 18, 1.0f);

    int lastBeat = INT_MIN;
    const int bpb = std::max (1, model.runDrill().beatsPerBar);
    for (auto& n : notes)
    {
        if (n.time < now - past - 0.1 || n.time > now + ahead + 0.1 || n.beat == lastBeat) continue;
        lastBeat = n.beat;
        const bool bar = n.beat % bpb == 0;
        const float bx = x (n.time) - 9;
        g.setColour (bar ? Theme::faint().withAlpha (0.6f) : Theme::line());
        const float y0 = bar ? 18.0f : 24.0f;
        g.fillRect (bx - 0.5f, y0, 1.0f, stringY (strings) - y0);
    }
    g.setColour (Theme::accent());
    g.fillRect (hitX - 1, 0.0f, 2.0f, h);

    const auto glyph = Theme::ui (14, true);
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
            case Model::NoteState::missed: case Model::NoteState::wrong: c = Theme::danger(); break;
        }
        const float bh = n.accent ? 22.0f : 14.0f;
        g.setColour (st == Model::NoteState::waiting ? Theme::faint() : c);
        g.fillRoundedRectangle (nx - 1.5f, rhythmY - bh / 2, 3, bh, 1.5f);
        if (n.pick != Pick::none)
        {
            g.setColour (Theme::muted());
            g.setFont (Theme::ui (11));
            g.drawText (juce::String (juce::CharPointer_UTF8 (n.pick == Pick::down ? "\xe2\x86\x93" : "\xe2\x86\x91")),
                        juce::Rectangle<float> (nx - 8, arrowY - 8, 16, 16), juce::Justification::centred);
        }
        const float y = stringY (n.string > 0 ? n.string : (strings + 1) / 2);
        const juce::String label = n.pitch ? juce::String (std::max (0, n.fret)) : times;
        const float lw = label.length() > 1 ? 22.0f : 16.0f;
        g.setColour (Theme::bg());
        g.fillRoundedRectangle (nx - lw / 2, y - 9, lw, 18, 4);
        if (st == Model::NoteState::wrong)
        {
            g.setColour (Theme::danger());
            g.drawRoundedRectangle (nx - 10, y - 10, 20, 20, 4, 1.0f);
            if (auto it = model.heardPitch.find ((int) i); it != model.heardPitch.end())
                Draw::text (g, Tuning::noteName ((int) std::round (it->second)), juce::Rectangle<int> ((int) nx - 14, (int) bottom + 2, 28, 16), Theme::danger(),
                            Theme::small, false, juce::Justification::centred);
        }
        g.setColour (c);
        g.setFont (glyph);
        g.drawText (label, juce::Rectangle<float> (nx - lw / 2, y - 9, lw, 18), juce::Justification::centred);
    }
    for (size_t i = 0; i < notes.size() && i < model.errors.size(); ++i)
        if (model.errors[i] && notes[i].time > now - past - 0.1 && notes[i].time < now + 0.2)
        {
            g.setColour (Theme::muted());
            g.fillEllipse (x (notes[i].time + *model.errors[i] / 1000.0) - 2.5f, dotY - 2.5f, 5, 5);
        }
    g.setColour (Theme::bg());
    g.fillRect (0.0f, 1.0f, 18.0f, h - 2);
    g.setFont (Theme::ui (11));
    g.setColour (Theme::faint());
    for (int s = 1; s <= strings; ++s) g.drawText (tuning.stringName (s), juce::Rectangle<float> (0, stringY (s) - 7, 16, 14), juce::Justification::centred);
}

// ================================================================ a run

RunScreen::RunScreen (Model& m) : Screen (m)
{
    setWantsKeyboardFocus (true);
    for (auto* c : std::initializer_list<juce::Component*> { &lane, &pause, &stop }) addAndMakeVisible (c);
    addChildComponent (resume); addChildComponent (end); addChildComponent (skip);
    lane.setInterceptsMouseClicks (false, false);
    pause.setTooltip ("Space");
    pause.onClick = [this] { model.pause(); };
    stop.setTooltip ("Esc");
    stop.onClick = [this] { model.stop(); };
    resume.onClick = [this] { model.resumeRun(); };
    end.onClick = [this] { model.endRun(); };
    skip.onClick = [this] {
        if (model.phase == Model::Phase::resting) model.endBreak();
        else model.skipIntro();
    };
}

void RunScreen::refresh()
{
    const auto p = model.phase;
    const bool own = ! inRoutine;
    pause.setVisible (own && p == Model::Phase::running);
    stop.setVisible (own && (p == Model::Phase::running || p == Model::Phase::intro || p == Model::Phase::resting));
    resume.setVisible (own && p == Model::Phase::paused);
    end.setVisible (own && p == Model::Phase::paused);
    skip.setVisible (p == Model::Phase::intro || p == Model::Phase::resting);
    lane.setVisible (p != Model::Phase::intro);
    lane.setAlpha (p == Model::Phase::paused || p == Model::Phase::resting ? 0.4f : 1.0f);
    repaint();
}

void RunScreen::resized()
{
    auto r = getLocalBounds();
    top = r.removeFromTop (Theme::rowH + Theme::sp4).reduced (Theme::sp7, 0);
    auto body = r.reduced (Theme::sp7, Theme::sp5);
    column = body.removeFromLeft (320);
    body.removeFromLeft (Theme::sp8);
    lane.setBounds (body.withHeight (std::min (body.getHeight(), 300 + 40 * std::max (0, (int) model.runTuning.strings.size() - 6))));
    buttons = column.removeFromBottom (Theme::ctlH);
    auto b = buttons;
    const int bw = (b.getWidth() - Theme::sp4) / 2;
    pause.setBounds (b.removeFromLeft (bw));
    resume.setBounds (pause.getBounds());
    skip.setBounds (pause.getBounds());
    b.removeFromLeft (Theme::sp4);
    stop.setBounds (b);
    end.setBounds (b);
}

void RunScreen::paintColumn (juce::Graphics& g, Model& model, juce::Rectangle<int> c)
{
    const auto p = model.phase;
    if (p == Model::Phase::resting)
    {
        Draw::text (g, "Break", c.removeFromTop (28), Theme::text(), 18, true);
        const double left = model.breakLeft;
        g.setColour (Theme::text());
        g.setFont (Theme::number (72, true));
        g.drawText (left <= 3 ? juce::String ((int) std::ceil (left)) : formatClock (std::ceil (left)), c.removeFromTop (90), juce::Justification::centredLeft);
        Draw::text (g, "Rest your hand", c.removeFromTop (22), Theme::muted());
        Draw::text (g, "Resumes at " + juce::String (model.resumeBPM) + " bpm", c.removeFromTop (20), Theme::muted(), Theme::small);
        c.removeFromTop (Theme::sp5);
        Draw::progress (g, c.removeFromTop (8), model.breakLength > 0 ? left / model.breakLength : 0, Theme::lineStrong(), Theme::line());
        return;
    }
    if (p == Model::Phase::intro)
    {
        Draw::text (g, "Intro", c.removeFromTop (28), Theme::text(), 18, true);
        return;
    }
    // the pattern now
    const bool counting = model.countingIn();
    juce::String cue = model.runDrill().tableName(), detail;
    bool warn = false;
    if (counting) cue = "Count-in";
    else if (auto gc = model.groupCue())
    {
        cue = groupWord (gc->now);
        detail = gc->beatsUntil == 1 ? groupWord (gc->next) + " next beat" : groupWord (gc->next) + " in " + juce::String (gc->beatsUntil);
        warn = gc->beatsUntil == 1;
    }
    auto cueRow = c.removeFromTop (28);
    Draw::text (g, detail, cueRow, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
    Draw::text (g, cue, cueRow, warn ? Theme::warn() : Theme::text(), 18, true);
    // the tempo
    auto tempoRow = c.removeFromTop (72);
    auto stack = tempoRow.removeFromRight (90);
    g.setFont (Theme::number (56, true));
    g.setColour (counting ? Theme::muted() : Theme::text());
    const juce::String bpmText ((int) model.currentBPM);
    g.drawText (bpmText, tempoRow, juce::Justification::centredLeft);
    Draw::text (g, "bpm", tempoRow.withTrimmedLeft (Theme::number (56, true).getStringWidth (bpmText) + 6).withTrimmedTop (22), Theme::muted());
    auto step = model.stepInfo();
    if (counting) Draw::text (g, "Count-in", stack, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
    else if (step)
    {
        Draw::text (g, "Target " + juce::String (step->target), stack.withHeight (stack.getHeight() / 2).withY (stack.getY() + 14), Theme::muted(), Theme::small, false, juce::Justification::centredRight);
        if (step->next) Draw::text (g, "Next " + juce::String (*step->next), stack.withHeight (stack.getHeight() / 2).withY (stack.getCentreY()), Theme::muted(), Theme::small, false, juce::Justification::centredRight);
    }
    c.removeFromTop (Theme::sp2);
    int beatNow = -1;
    const int bpb = std::max (1, model.runDrill().beatsPerBar);
    if (auto* sl = model.currentSlot(); sl && ! counting && model.now >= sl->start)
        beatNow = (sl->index * model.runDrill().cycleBeats + (int) ((model.now - sl->start) / (60.0 / std::max (1.0, sl->bpm)))) % bpb;
    Draw::beatBar (g, c.removeFromTop (12), bpb, beatNow);
    // where the tempo is going
    if (step)
    {
        c.removeFromTop (Theme::sp6);
        auto cap = c.removeFromTop (18);
        const char* words[] = { "Next step", "Speeding up", "Holding", "Slowing down", "Break", "Settling", "Top tempo" };
        Draw::text (g, words[(int) step->state], cap, Theme::muted(), Theme::small);
        Draw::text (g, step->measure, cap, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
        const auto col = step->state == Model::StepInfo::State::down ? Theme::warn() : step->state == Model::StepInfo::State::rest ? Theme::danger() : Theme::accent();
        Draw::progress (g, c.removeFromTop (8), step->state == Model::StepInfo::State::top ? 1.0 : step->fraction, col, Theme::lineStrong());
    }
    // the accuracy
    if (model.lastRunWasScored)
    {
        c.removeFromTop (Theme::sp6);
        auto cap = c.removeFromTop (24);
        const auto acc = model.rolling ? model.rolling : model.lastCycleAccuracy;
        const auto zone = model.accuracyZone();
        const bool zoned = model.runSettingsNow().tempoPlan.mode == TempoPlan::Mode::accuracy;
        Draw::text (g, "Accuracy", cap, Theme::muted(), Theme::small);
        auto right = cap.removeFromRight (130);
        if (zoned && zone && acc)
        {
            const char* zw[] = { "Up", "Hold", "Down", "Break" };
            Draw::text (g, zw[(int) *zone], right.removeFromRight (44), *zone == TempoPlan::Zone::hold ? Theme::text() : Draw::zoneColour (*zone), Theme::body, true,
                        juce::Justification::centredRight);
            right.removeFromRight (Theme::sp4);
        }
        g.setColour (Theme::text());
        g.setFont (Theme::number (20));
        g.drawText (acc ? juce::String ((int) std::round (*acc * 100)) + "%" : dash, right, juce::Justification::centredRight);
        Draw::accuracyMeter (g, c.removeFromTop (20), acc, model.meterLines(), zone, zoned);
    }
    // the Challenge clock
    if (model.challenge)
    {
        const auto& k = *model.challenge;
        const bool running = k.inZone || k.elapsed == 0;
        c.removeFromTop (Theme::sp6);
        auto cap = c.removeFromTop (24);
        Draw::text (g, "Challenge", cap, Theme::muted(), Theme::small);
        g.setColour (running ? Theme::text() : Theme::warn());
        g.setFont (Theme::number (20));
        g.drawText (formatClock (k.earned) + " of " + formatClock (k.target), cap, juce::Justification::centredRight);
        Draw::progress (g, c.removeFromTop (8), k.target > 0 ? k.earned / k.target : 0, running ? Theme::accent() : Theme::warn(), Theme::lineStrong());
        Draw::text (g, (running ? juce::String ("Clock running") : juce::String ("Clock held, accuracy under the line")) + ", "
                       + formatClock (k.elapsed) + " elapsed, " + juce::String ((int) std::round (k.share() * 100)) + "% in the zone",
                    c.removeFromTop (20), running ? Theme::muted() : Theme::warn(), Theme::small);
    }
    // the status line
    c.removeFromTop (Theme::sp6);
    auto st = c.removeFromTop (20);
    juce::String leftText, rightText;
    if (! counting)
        if (auto n = model.cycleNumber())
            leftText = model.runKind() == SessionSettings::Kind::cycles ? "Loop " + juce::String (*n) + " of " + juce::String (std::max (1, model.runCycles()))
                                                                        : "Loop " + juce::String (*n);
    rightText = model.plannedEnd ? formatClock (std::max (0.0, *model.plannedEnd - model.now)) + " left" : formatClock (std::max (0.0, model.now - model.countInEnd));
    Draw::text (g, leftText, st, Theme::muted(), Theme::small);
    Draw::text (g, rightText, st, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
    if (p == Model::Phase::paused)
    {
        c.removeFromTop (Theme::sp7);
        Draw::text (g, "Paused", c.removeFromTop (28), Theme::text(), 18, true);
        Draw::text (g, model.message.isNotEmpty() ? model.message : "In " + model.routeName(), c.removeFromTop (20),
                    model.message.isNotEmpty() ? Theme::warn() : Theme::muted(), Theme::small);
    }
}

void RunScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    Draw::text (g, model.runDrill().name, top, Theme::muted(), Theme::small);
    Draw::text (g, model.routeName(), top, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
    paintColumn (g, model, column.withTrimmedBottom (Theme::ctlH + Theme::sp5));
}

void RunScreen::mouseUp (const juce::MouseEvent& e)
{
    if (! inRoutine && model.phase == Model::Phase::running && ! buttons.contains (e.getPosition())) model.pause();
}

bool RunScreen::keyPressed (const juce::KeyPress& k)
{
    if (inRoutine) return false;
    if (k == juce::KeyPress::spaceKey)
    {
        if (model.phase == Model::Phase::running) model.pause();
        else if (model.phase == Model::Phase::paused) model.resumeRun();
        else if (model.phase == Model::Phase::intro) model.skipIntro();
        else if (model.phase == Model::Phase::resting) model.endBreak();
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
    column = r.removeFromLeft (std::min (340, r.getWidth() / 2));
    r.removeFromLeft (Theme::sp8);
    right = r;
    buttons = column.removeFromBottom (Theme::ctlH);
    auto b = buttons;
    again.setBounds (b.removeFromLeft (140));
    b.removeFromLeft (Theme::sp4);
    done.setBounds (b.removeFromLeft (100));
}

void ResultScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    auto c = column;
    if (auto& u = model.unscored)
    {
        Draw::text (g, "Audio input off, not scored", c.removeFromTop (20), Theme::muted(), Theme::small);
        g.setColour (Theme::text());
        g.setFont (Theme::number (40));
        g.drawText (formatClock (u->seconds), c.removeFromTop (56), juce::Justification::centredLeft);
        Draw::text (g, (u->topBPM > u->startBPM ? juce::String (u->startBPM) + " to " + juce::String (u->topBPM) : juce::String (u->startBPM)) + " bpm",
                    c.removeFromTop (20), Theme::muted());
        return;
    }
    if (! model.score || ! model.saved) return;
    const auto& s = *model.score;
    const auto& r = *model.saved;
    const bool endurance = r.mode == "endurance", challenge = r.mode == "challenge";
    const juce::String tempo = r.topBPM > r.startBPM ? juce::String (r.startBPM) + " to " + juce::String (r.topBPM) : juce::String (r.startBPM);
    Draw::text (g, juce::String (r.guided ? "Guided" : "Solo") + ", " + tempo + " bpm, " + formatClock (r.seconds), c.removeFromTop (20), Theme::muted(), Theme::small);
    c.removeFromTop (Theme::sp2);
    auto head = c.removeFromTop (56);
    const juce::String big = challenge ? formatClock (r.earnedSeconds.value_or (0)) : endurance ? formatClock (r.sustainedSeconds.value_or (0)) : juce::String (s.score) + "%";
    const bool good = challenge || endurance ? r.passed : s.passed();
    g.setFont (Theme::number (40));
    g.setColour (good ? Theme::accentText() : Theme::text());
    g.drawText (big, head, juce::Justification::centredLeft);
    const int bw = Theme::number (40).getStringWidth (big);
    Draw::text (g, challenge ? "earned at " + juce::String (r.targetPercent) + "%" : endurance ? "held at " + juce::String (r.targetPercent) + "%"
                                                                                               : "accuracy, pass mark " + juce::String (s.passMark) + "%",
                head.withTrimmedLeft (bw + 10).withTrimmedTop (16), Theme::muted());
    if (auto& l = model.levelUp)
        Draw::text (g, "New max " + juce::String (l->second) + " bpm" + (l->first > 0 ? ", up from " + juce::String (l->first) : juce::String()),
                    c.removeFromTop (20), Theme::accentText(), Theme::body, true);
    c.removeFromTop (Theme::sp6);
    std::vector<std::pair<juce::String, juce::String>> rows;
    if (endurance || challenge) rows.push_back ({ "Accuracy", juce::String (s.score) + "%" });
    if (challenge)
    {
        rows.push_back ({ "Elapsed", formatClock (r.elapsedSeconds.value_or (r.seconds)) });
        if (r.elapsedSeconds && *r.elapsedSeconds > 0) rows.push_back ({ "In the zone", juce::String ((int) std::round (r.earnedSeconds.value_or (0) / *r.elapsedSeconds * 100)) + "%" });
        rows.push_back ({ "Best streak", formatClock (r.bestStreakSeconds.value_or (0)) });
    }
    rows.push_back ({ "Timing", averageText (s.meanError) });
    rows.push_back ({ "Spread", juce::String ((int) std::round (s.spread)) + " ms, " + juce::String (Scoring::band (s.spread)).toLowerCase() });
    if (s.extra > 0) rows.push_back ({ "Extra notes", juce::String (s.extra) });
    rows.push_back ({ "Missed", juce::String (s.missed) + " of " + juce::String (s.expected) });
    if (r.wrongPitch) rows.push_back ({ "Wrong notes", juce::String (*r.wrongPitch) });
    if (r.accentsPercent) rows.push_back ({ "Accents", juce::String (*r.accentsPercent) + "%" });
    if (r.breaks && *r.breaks > 0) rows.push_back ({ "Breaks", juce::String (*r.breaks) });
    rows.push_back ({ "Loops", juce::String (r.cycles) });
    for (auto& [k, v] : rows)
    {
        if (c.getHeight() < Theme::rowH + Theme::ctlH + Theme::sp6) break;
        auto row = c.removeFromTop (Theme::rowH);
        Draw::text (g, k, row, Theme::text());
        Draw::text (g, v, row, Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::hairline (g, row.getX(), row.getBottom() - 1, row.getWidth());
    }

    // the right: the tempo table, then every note's timing
    auto rr = right;
    if (r.tempoSteps.size() > 1)
    {
        auto h = rr.removeFromTop (20);
        Draw::text (g, "Accuracy", h.removeFromRight (90), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
        Draw::text (g, "Time", h.removeFromRight (80), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
        Draw::text (g, "Tempo", h, Theme::faint(), Theme::small);
        Draw::hairline (g, rr.getX(), rr.getY(), rr.getWidth());
        for (auto& t : r.tempoSteps)
        {
            auto row = rr.removeFromTop (Theme::rowH);
            Draw::text (g, t.accuracy ? juce::String (*t.accuracy) + "%" : dash, row.removeFromRight (90), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
            Draw::text (g, formatClock (t.seconds), row.removeFromRight (80), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
            Draw::text (g, t.rest ? juce::String ("Break") : juce::String (t.bpm), row, Theme::text());
            Draw::hairline (g, rr.getX(), row.getBottom() - 1, rr.getWidth());
        }
        rr.removeFromTop (Theme::sp7);
    }
    Draw::text (g, "Timing per note", rr.removeFromTop (18), Theme::muted(), Theme::small);
    auto box = rr.removeFromTop (72);
    const float mid = (float) box.getCentreY();
    g.setColour (Theme::lineStrong());
    g.fillRect ((float) box.getX(), mid - 0.5f, (float) box.getWidth(), 1.0f);
    if (! s.errors.empty())
    {
        const float stepX = (float) box.getWidth() / (float) s.errors.size();
        const double span = std::max (40.0, s.zeroMs);
        for (size_t i = 0; i < s.errors.size(); ++i)
        {
            const float px = (float) box.getX() + ((float) i + 0.5f) * stepX;
            if (! s.errors[i]) { g.setColour (Theme::danger()); g.fillEllipse (px - 1.5f, mid - 1.5f, 3, 3); continue; }
            const double f = juce::jlimit (-1.0, 1.0, *s.errors[i] / span);
            g.setColour (std::abs (f) <= 0.35 ? Theme::accent() : std::abs (f) < 0.7 ? Theme::accent().withAlpha (0.55f) : Theme::warn());
            g.fillEllipse (px - 1.5f, mid + (float) f * ((float) box.getHeight() / 2 - 3) - 1.5f, 3, 3);
        }
    }
    auto lab = rr.removeFromTop (16);
    Draw::text (g, "Early", lab, Theme::faint(), Theme::small);
    Draw::text (g, "Late", lab, Theme::faint(), Theme::small, false, juce::Justification::centredRight);
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
    done.setText (step1 ? "Cancel" : "Stop");
    repaint();
}

void CalibrationScreen::resized()
{
    auto r = getLocalBounds().reduced (Theme::sp7, Theme::sp6);
    head = r.removeFromTop (72).withWidth (std::min (560, r.getWidth()));
    r.removeFromTop (Theme::sp5);
    lane.setBounds (r.removeFromTop (std::min (200, r.getHeight() / 2)));
    r.removeFromTop (Theme::sp6);
    auto col = r.withWidth (std::min (560, r.getWidth()));
    value = col.removeFromTop (32);
    auto s = col.removeFromTop (Theme::ctlH);
    earlier.setBounds (s.removeFromLeft (Theme::ctlH));
    later.setBounds (s.removeFromRight (Theme::ctlH));
    offset.setBounds (s.reduced (Theme::sp4, 0));
    help = col.removeFromTop (24);
    auto b = col.removeFromBottom (Theme::ctlH);
    next.setBounds (b.removeFromLeft (140));
    b.removeFromLeft (Theme::sp4);
    done.setBounds (b.removeFromLeft (100));
}

void CalibrationScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    const bool step1 = model.phase == Model::Phase::syncing;
    auto h = head;
    Draw::text (g, juce::String ("Step ") + (step1 ? "1" : "2") + " of 2", h.removeFromTop (18), Theme::muted(), Theme::small);
    Draw::text (g, step1 ? "Line up the marks" : "Play on the line", h.removeFromTop (26), Theme::text(), 18, true);
    Draw::text (g, step1 ? "Move the slider until each mark crosses the line on the click" : "Play one note as each mark crosses the line",
                h.removeFromTop (20), Theme::muted());
    if (step1)
    {
        const int ms = (int) std::round (model.displayOffset() * 1000);
        g.setColour (Theme::text());
        g.setFont (Theme::number (20));
        g.drawText ((ms >= 0 ? "+" : "") + juce::String (ms) + " ms", value, juce::Justification::centredLeft);
        Draw::text (g, "Output " + model.device.opened.output, help, Theme::muted(), Theme::small);
    }
    else
    {
        int heard = 0;
        for (auto& e : model.errors) if (e) ++heard;
        Draw::text (g, "Heard " + juce::String (heard) + " of " + juce::String (Model::calibrationCount), value, Theme::text());
        Draw::text (g, "In " + model.routeName(), help, Theme::muted(), Theme::small);
    }
}

} // namespace practice::ui
