#include "Screens.h"

namespace practice::ui {

static const juce::String dash = juce::String (juce::CharPointer_UTF8 ("\xe2\x80\x93"));

static juce::String minutes (double s) { return juce::String (std::max (1, (int) std::round (s / 60))) + " min"; }

static juce::String tempoText (const RoutineBlock& b, const std::vector<Drill>& drills)
{
    if (b.kind == RoutineBlock::Kind::drill)
    {
        if (! b.drill) return {};
        const auto& p = b.drill->session.tempoPlan;
        if (p.mode != TempoPlan::Mode::off)
            for (auto& d : drills)
                if (d.id == b.drillID)
                    return juce::String (b.drill->bpm) + " to " + juce::String (p.normalized().bounds (b.drill->bpm, d.tempo.min, d.tempo.max).top);
        return juce::String (b.drill->bpm);
    }
    if (b.kind == RoutineBlock::Kind::rest) return {};
    return b.click ? juce::String (b.bpm) : juce::String();
}

static juce::String lengthText (const RoutineBlock& b)
{
    if (b.kind != RoutineBlock::Kind::drill || ! b.drill) return formatClock (b.seconds);
    const auto& s = b.drill->session;
    switch (s.kind)
    {
        case SessionSettings::Kind::cycles: return s.cycles == 1 ? juce::String ("1 loop") : juce::String (s.cycles) + " loops";
        case SessionSettings::Kind::endurance: return "Hold";
        default: return formatClock (s.seconds);
    }
}

// ================================================================ Routines

RoutinesScreen::RoutinesScreen (Model& m, RoutineRunner& r) : Screen (m), runner (r), forms (m, false)
{
    setWantsKeyboardFocus (true);
    for (auto* c : std::initializer_list<juce::Component*> { &add, &addBlock, &start, &more })
        addAndMakeVisible (c);
    for (auto* c : std::initializer_list<juce::Component*> { &copyBlock, &deleteBlock, &blockName, &seconds, &bpm, &click, &editorScroll, &plain })
        addChildComponent (c);
    plain.managed = { &blockName, &seconds, &click, &bpm };
    plain.setInterceptsMouseClicks (false, false);
    editorScroll.setViewedComponent (&editorContent, false);
    editorScroll.setScrollBarsShown (true, false);
    editorContent.addAndMakeVisible (forms);
    add.setTooltip ("New routine");
    add.onClick = [this] { auto r = model.routines->newRoutine (model.drills); selected = r.id; blockSelected = {}; refresh(); };
    addBlock.onClick = [this] { showAddMenu(); };
    start.setTooltip ("Start the routine");
    start.onClick = [this] { if (auto r = model.routines->routine (selected)) runner.start (*r); };
    more.setTooltip ("Rename, duplicate or delete");
    more.onClick = [this] {
        juce::PopupMenu menu;
        menu.addItem (1, "Rename");
        menu.addItem (2, "Duplicate");
        menu.addItem (3, "Delete");
        menu.showMenuAsync (juce::PopupMenu::Options().withTargetComponent (more), [this] (int i) {
            auto r = model.routines->routine (selected);
            if (! r) return;
            if (i == 1)
            {
                auto* w = new juce::AlertWindow ("Rename", {}, juce::MessageBoxIconType::NoIcon);
                w->addTextEditor ("name", r->name);
                w->addButton ("Save", 1, juce::KeyPress (juce::KeyPress::returnKey));
                w->addButton ("Cancel", 0, juce::KeyPress (juce::KeyPress::escapeKey));
                w->enterModalState (true, juce::ModalCallbackFunction::create ([this, w] (int res) {
                    const auto n = w->getTextEditorContents ("name").trim();
                    if (res == 1 && n.isNotEmpty()) update ([n] (PracticeRoutine& x) { x.name = n; });
                }), true);
            }
            if (i == 2) if (auto c = model.routines->duplicate (selected)) { selected = c->id; refresh(); }
            if (i == 3)
                juce::AlertWindow::showOkCancelBox (juce::MessageBoxIconType::NoIcon, "Delete this routine?", {}, "Delete", "Cancel", this,
                    juce::ModalCallbackFunction::create ([this] (int res) { if (res == 1) { model.routines->remove (selected); selected = {}; refresh(); } }));
        });
    };
    copyBlock.setTooltip ("Duplicate (Ctrl+D)");
    copyBlock.onClick = [this] {
        update ([this] (PracticeRoutine& r) {
            for (size_t i = 0; i < r.blocks.size(); ++i)
                if (r.blocks[i].id == blockSelected) { auto c = r.blocks[i]; c.id = juce::Uuid().toDashedString(); r.blocks.insert (r.blocks.begin() + (long) i + 1, c); break; }
        });
    };
    deleteBlock.setTooltip ("Delete (Del)");
    deleteBlock.onClick = [this] {
        update ([this] (PracticeRoutine& r) { r.blocks.erase (std::remove_if (r.blocks.begin(), r.blocks.end(), [this] (auto& b) { return b.id == blockSelected; }), r.blocks.end()); });
        blockSelected = {};
        refresh();
    };
    blockName.setFont (Theme::ui (Theme::field));
    blockName.setIndents (8, 6);
    blockName.onTextChange = [this] { const auto t = blockName.getText(); update ([this, t] (PracticeRoutine& r) { for (auto& b : r.blocks) if (b.id == blockSelected) b.name = t; }); };
    seconds.minimum = 15; seconds.maximum = 1800; seconds.step = 15;
    seconds.onChange = [this] (int v) { update ([this, v] (PracticeRoutine& r) { for (auto& b : r.blocks) if (b.id == blockSelected) b.seconds = v; }); };
    bpm.minimum = 30; bpm.maximum = 300; bpm.step = 1;
    bpm.onChange = [this] (int v) { update ([this, v] (PracticeRoutine& r) { for (auto& b : r.blocks) if (b.id == blockSelected) b.bpm = v; }); };
    click.onChange = [this] (bool on) { update ([this, on] (PracticeRoutine& r) { for (auto& b : r.blocks) if (b.id == blockSelected) b.click = on; }); };
    forms.get = [this] {
        SetupForms::State s { 100, {}, false, true, false };
        if (auto r = model.routines->routine (selected))
            for (auto& b : r->blocks)
                if (b.id == blockSelected && b.drill) { s.bpm = b.drill->bpm; s.session = b.drill->session; s.guided = b.drill->guided; s.audioInput = b.drill->audioInput; }
        return s;
    };
    forms.set = [this] (const SetupForms::State& s) {
        update ([this, s] (PracticeRoutine& r) {
            for (auto& b : r.blocks)
                if (b.id == blockSelected)
                {
                    DrillSetup d = b.drill.value_or (DrillSetup {});
                    d.bpm = s.bpm; d.session = s.session; d.guided = s.guided; d.audioInput = s.audioInput;
                    b.drill = d;
                    if (b.drillID.isEmpty() && ! model.drills.empty()) b.drillID = model.drills.front().id;
                }
        });
    };
}

void RoutinesScreen::update (std::function<void (PracticeRoutine&)> change)
{
    auto r = model.routines->routine (selected);
    if (! r) return;
    change (*r);
    model.routines->save (*r);
    refresh();
}

void RoutinesScreen::showAddMenu()
{
    juce::PopupMenu menu;
    menu.addItem (1, "Warm-up");
    menu.addItem (2, "Drill");
    menu.addItem (3, "Break");
    menu.addItem (4, "Open practice");
    menu.addItem (5, "Custom");
    menu.showMenuAsync (juce::PopupMenu::Options().withTargetComponent (addBlock), [this] (int i) {
        if (i <= 0) return;
        const RoutineBlock::Kind kinds[] = { RoutineBlock::Kind::warmup, RoutineBlock::Kind::drill, RoutineBlock::Kind::rest, RoutineBlock::Kind::free, RoutineBlock::Kind::custom };
        auto b = RoutineBlock::make (kinds[i - 1], model.drills);
        update ([b] (PracticeRoutine& r) { r.blocks.push_back (b); });
        blockSelected = b.id;
        refresh();
    });
}

void RoutinesScreen::refresh()
{
    auto list = model.routines->routines();
    if (selected.isEmpty() || ! model.routines->routine (selected)) selected = list.empty() ? juce::String() : list.front().id;
    auto r = model.routines->routine (selected);
    const RoutineBlock* b = nullptr;
    if (r) for (auto& x : r->blocks) if (x.id == blockSelected) b = &x;
    if (! b) blockSelected = {};
    start.setEnabled (r && ! r->blocks.empty());
    addBlock.setVisible (r.has_value());
    more.setVisible (r.has_value());
    const bool editing = b != nullptr;
    copyBlock.setVisible (editing);
    deleteBlock.setVisible (editing);
    editorScroll.setVisible (editing && b->kind == RoutineBlock::Kind::drill);
    plain.setVisible (editing && b->kind != RoutineBlock::Kind::drill);
    if (editing && b->kind != RoutineBlock::Kind::drill)
    {
        if (! blockName.hasKeyboardFocus (true)) blockName.setText (b->name, juce::dontSendNotification);
        blockName.setTextToShowWhenEmpty (b->title (model.drills), Theme::faint());
        seconds.setValue (b->seconds, formatClock (b->seconds));
        click.setOn (b->click);
        bpm.setValue (b->bpm, juce::String (b->bpm) + " bpm");
    }
    if (editing && b->kind == RoutineBlock::Kind::drill)
    {
        forms.drill = nullptr;
        for (auto& d : model.drills) if (d.id == b->drillID) forms.drill = &d;
        if (! forms.drill && ! model.drills.empty()) forms.drill = &model.drills.front();
        forms.refresh();
    }
    resized();
    repaint();
}

void RoutinesScreen::resized()
{
    auto r = getLocalBounds().reduced (Theme::sp7, Theme::sp6);
    auto head = r.removeFromTop (Theme::ctlH);
    r.removeFromTop (Theme::sp5);
    listArea = r.removeFromLeft (260);
    add.setBounds (head.getX() + 260 - Theme::ctlH, head.getY(), Theme::ctlH, Theme::ctlH);
    r.removeFromLeft (Theme::sp7);
    const bool editing = blockSelected.isNotEmpty();
    editorArea = editing ? r.removeFromRight (std::min (360, r.getWidth() / 2)) : juce::Rectangle<int>();
    if (editing) r.removeFromRight (Theme::sp7);
    titleArea = head.withX (r.getX()).withRight (r.getRight() - Theme::ctlH - Theme::sp4);
    more.setBounds (r.getRight() - Theme::ctlH, head.getY(), Theme::ctlH, Theme::ctlH);
    auto foot = r.removeFromBottom (Theme::ctlH);
    start.setBounds (foot.getRight() - 140, foot.getY(), 140, Theme::ctlH);
    r.removeFromBottom (Theme::sp5);
    blocksArea = r;
    // rows
    listRows.clear();
    auto lr = listArea.withTrimmedTop (28);
    for (size_t i = 0; i < model.routines->routines().size(); ++i) listRows.push_back (lr.removeFromTop (Theme::rowH));
    blockRows.clear();
    auto br = blocksArea.withTrimmedTop (28);
    if (auto rt = model.routines->routine (selected))
        for (size_t i = 0; i < rt->blocks.size(); ++i) blockRows.push_back (br.removeFromTop (Theme::rowH));
    addBlock.setBounds (br.getX(), br.getY() + Theme::sp2, addBlock.idealWidth(), Theme::ctlH);
    summaryArea = br.withY (br.getY() + Theme::ctlH + Theme::sp4).withHeight (18);
    if (editing)
    {
        auto e = editorArea;
        auto eh = e.removeFromTop (Theme::ctlH);
        deleteBlock.setBounds (eh.removeFromRight (Theme::ctlH));
        copyBlock.setBounds (eh.removeFromRight (Theme::ctlH));
        e.removeFromTop (Theme::sp5);
        plain.setTopLeftPosition (e.getPosition());
        plain.begin();
        plain.row ("Name", blockName, 180);
        plain.row ("Length", seconds, 180);
        auto rt = model.routines->routine (selected);
        const RoutineBlock* b = nullptr;
        if (rt) for (auto& x : rt->blocks) if (x.id == blockSelected) b = &x;
        if (b && b->kind != RoutineBlock::Kind::rest)
        {
            plain.row ("Click", click, 44);
            if (b->click) plain.row ("Tempo", bpm, 180);
        }
        if (plain.isVisible()) plain.layout (e.getWidth());
        editorScroll.setBounds (e);
        const int w = e.getWidth() - editorScroll.getScrollBarThickness();
        forms.setBounds (0, 0, w, 1200);
        forms.layoutIn ({ 0, 0, w, 3000 }, {});
        editorContent.setSize (w, forms.getHeight());
    }
}

void RoutinesScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    auto list = model.routines->routines();
    Draw::text (g, "Routines", juce::Rectangle<int> (listArea.getX(), add.getY(), 200, Theme::ctlH), Theme::text(), Theme::head, true);
    auto lh = listArea.withHeight (28);
    Draw::text (g, "Time", lh.removeFromRight (64), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
    Draw::text (g, "Routine", lh, Theme::faint(), Theme::small);
    Draw::hairline (g, listArea.getX(), listArea.getY() + 27, listArea.getWidth());
    for (size_t i = 0; i < list.size() && i < listRows.size(); ++i)
    {
        auto row = listRows[i];
        if (list[i].id == selected) { g.setColour (Theme::active()); g.fillRoundedRectangle (row.toFloat(), Theme::rMd); }
        auto in = row.reduced (Theme::sp4, 0);
        Draw::text (g, minutes (list[i].estimate (model.drills)), in.removeFromRight (64), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::text (g, list[i].name, in, Theme::text());
    }
    if (list.empty()) Draw::text (g, "No routines. Click + to make one", listArea.withTrimmedTop (32).withHeight (20), Theme::muted());

    auto rt = model.routines->routine (selected);
    if (! rt) return;
    Draw::text (g, rt->name, titleArea, Theme::text(), Theme::head, true);
    auto bh = blocksArea.withHeight (28);
    Draw::text (g, "Length", bh.removeFromRight (72), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
    Draw::text (g, "Tempo", bh.removeFromRight (96), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
    Draw::text (g, "Block", bh, Theme::faint(), Theme::small);
    Draw::hairline (g, blocksArea.getX(), blocksArea.getY() + 27, blocksArea.getWidth());
    for (size_t i = 0; i < rt->blocks.size() && i < blockRows.size(); ++i)
    {
        const auto& b = rt->blocks[i];
        auto row = blockRows[i];
        if (b.id == blockSelected) { g.setColour (Theme::active()); g.fillRoundedRectangle (row.toFloat(), Theme::rMd); }
        if (dragTo == (int) i && dragFrom >= 0 && dragFrom != dragTo) { g.setColour (Theme::accent()); g.fillRect (row.getX(), row.getY() - 1, row.getWidth(), 2); }
        auto in = row.reduced (Theme::sp4, 0);
        Draw::text (g, lengthText (b), in.removeFromRight (72), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::text (g, tempoText (b, model.drills), in.removeFromRight (96), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::text (g, b.title (model.drills), in, Theme::text());
        Draw::hairline (g, row.getX() + Theme::sp4, row.getBottom() - 1, row.getWidth() - Theme::sp4);
    }
    Draw::text (g, juce::String ((int) rt->blocks.size()) + (rt->blocks.size() == 1 ? " block" : " blocks") + ", about " + minutes (rt->estimate (model.drills)),
                summaryArea, Theme::muted(), Theme::small);
    if (! editorArea.isEmpty())
    {
        for (auto& b : rt->blocks)
            if (b.id == blockSelected)
                Draw::text (g, RoutineBlock::kindTitle (b.kind), editorArea.withHeight (Theme::ctlH), Theme::text(), Theme::head, true);
        g.setColour (Theme::line());
        g.fillRect (editorArea.getX() - Theme::sp5, editorArea.getY(), 1, editorArea.getHeight());
    }
}

void RoutinesScreen::mouseDown (const juce::MouseEvent& e)
{
    auto list = model.routines->routines();
    for (size_t i = 0; i < listRows.size() && i < list.size(); ++i)
        if (listRows[i].contains (e.getPosition())) { selected = list[i].id; blockSelected = {}; refresh(); return; }
    dragFrom = dragTo = -1;
    if (auto rt = model.routines->routine (selected))
        for (size_t i = 0; i < blockRows.size() && i < rt->blocks.size(); ++i)
            if (blockRows[i].contains (e.getPosition())) { blockSelected = rt->blocks[i].id; dragFrom = (int) i; refresh(); return; }
}

void RoutinesScreen::mouseDrag (const juce::MouseEvent& e)
{
    if (dragFrom < 0) return;
    int to = dragFrom;
    for (size_t i = 0; i < blockRows.size(); ++i) if (e.getPosition().y >= blockRows[i].getY()) to = (int) i;
    if (to != dragTo) { dragTo = to; repaint(); }
}

void RoutinesScreen::mouseUp (const juce::MouseEvent&)
{
    if (dragFrom >= 0 && dragTo >= 0 && dragFrom != dragTo)
    {
        const int from = dragFrom, to = dragTo;
        update ([from, to] (PracticeRoutine& r) {
            auto b = r.blocks[(size_t) from];
            r.blocks.erase (r.blocks.begin() + from);
            r.blocks.insert (r.blocks.begin() + to, b);
        });
    }
    dragFrom = dragTo = -1;
    repaint();
}

void RoutinesScreen::mouseDoubleClick (const juce::MouseEvent& e)
{
    if (titleArea.contains (e.getPosition())) more.onClick();
}

bool RoutinesScreen::keyPressed (const juce::KeyPress& k)
{
    if (blockSelected.isNotEmpty() && k == juce::KeyPress::deleteKey && ! blockName.hasKeyboardFocus (true)) { deleteBlock.onClick(); return true; }
    if (blockSelected.isNotEmpty() && k.getModifiers().isCtrlDown() && (k.getKeyCode() == 'D' || k.getKeyCode() == 'd')) { copyBlock.onClick(); return true; }
    if (k == juce::KeyPress::escapeKey && blockSelected.isNotEmpty()) { blockSelected = {}; refresh(); return true; }
    return false;
}

// ================================================================ the runner

RunnerScreen::RunnerScreen (Model& m, RoutineRunner& r) : Screen (m), runner (r)
{
    setWantsKeyboardFocus (true);
    for (auto* c : std::initializer_list<juce::Component*> { &lane, &back, &pause, &skip }) addAndMakeVisible (c);
    for (auto* c : std::initializer_list<juce::Component*> { &resume, &restart, &end, &done, &again }) addChildComponent (c);
    lane.setInterceptsMouseClicks (false, false);
    back.setTooltip ("Back (Left)");
    back.onClick = [this] { runner.back(); };
    pause.setTooltip ("Space");
    pause.onClick = [this] { if (model.phase != Model::Phase::resting) runner.pause(); };
    skip.setTooltip ("Skip (Right)");
    skip.onClick = [this] { runner.skip(); };
    resume.onClick = [this] { runner.resume(); };
    restart.onClick = [this] { runner.back(); };
    end.onClick = [this] {
        juce::AlertWindow::showOkCancelBox (juce::MessageBoxIconType::NoIcon, "End the routine?", "What is done is saved.", "End", "Cancel", this,
            juce::ModalCallbackFunction::create ([this] (int res) { if (res == 1) runner.endNow(); }));
    };
    done.onClick = [this] { runner.close(); };
    again.onClick = [this] { if (runner.routine) { auto r = *runner.routine; runner.start (r); } };
}

void RunnerScreen::refresh()
{
    const bool finished = runner.record.has_value();
    const bool paused = runner.paused();
    for (auto* c : std::initializer_list<juce::Component*> { &back, &pause, &skip }) c->setVisible (! finished && ! paused);
    for (auto* c : std::initializer_list<juce::Component*> { &resume, &restart, &end }) c->setVisible (! finished && paused);
    done.setVisible (finished);
    again.setVisible (finished);
    const auto* b = runner.block();
    const bool drillLive = ! finished && b && b->kind == RoutineBlock::Kind::drill && ! runner.state().countdownTick
                           && (model.phase == Model::Phase::running || model.phase == Model::Phase::paused);
    const bool wasVisible = lane.isVisible();
    lane.setVisible (drillLive);
    lane.setAlpha (paused ? 0.4f : 1.0f);
    if (wasVisible != drillLive) resized();
    repaint();
}

void RunnerScreen::resized()
{
    auto r = getLocalBounds();
    top = r.removeFromTop (Theme::rowH + Theme::sp4).reduced (Theme::sp7, 0);
    auto body = r.reduced (Theme::sp7, Theme::sp5);
    // A drill block: a column of what to read beside the lane. Any other block: one wider column.
    column = lane.isVisible() ? body.removeFromLeft (320) : body.removeFromLeft (std::min (560, body.getWidth()));
    body.removeFromLeft (Theme::sp8);
    lane.setBounds (body.withHeight (std::min (body.getHeight(), 300)));
    line = column.removeFromTop (8);
    column.removeFromTop (Theme::sp6);
    buttons = column.removeFromBottom (Theme::ctlH);
    nextArea = column.removeFromBottom (28);
    middle = column;
    auto b = buttons;
    back.setBounds (b.removeFromLeft (Theme::ctlH + 8));
    skip.setBounds (b.removeFromRight (Theme::ctlH + 8));
    b.reduce (Theme::sp4, 0);
    pause.setBounds (b);
    auto p = buttons;
    resume.setBounds (p.removeFromLeft (140));
    p.removeFromLeft (Theme::sp4);
    restart.setBounds (p.removeFromLeft (restart.idealWidth()));
    end.setBounds (p.removeFromRight (end.idealWidth()));
    auto f = buttons;
    done.setBounds (f.removeFromLeft (120));
    f.removeFromLeft (Theme::sp4);
    again.setBounds (f.removeFromLeft (120));
}

void RunnerScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    if (! runner.routine) return;
    const auto& r = *runner.routine;
    if (runner.record)
    {
        const auto& rec = *runner.record;
        auto c = getLocalBounds().reduced (Theme::sp7, Theme::sp6).withWidth (std::min (640, getWidth() - 2 * Theme::sp7));
        Draw::text (g, rec.routineName, c.removeFromTop (Theme::ctlH), Theme::text(), Theme::head, true);
        int played = 0;
        for (auto& b : rec.blocks) if (! b.skipped) ++played;
        Draw::text (g, juce::String ((int) rec.blocks.size()) + " blocks, " + juce::String (played) + " played, " + rec.date.formatted ("%b %e at %I:%M %p"),
                    c.removeFromTop (20), Theme::muted(), Theme::small);
        auto big = c.removeFromTop (56);
        g.setColour (Theme::text());
        g.setFont (Theme::number (40));
        g.drawText (formatClock (rec.seconds), big, juce::Justification::centredLeft);
        Draw::text (g, "total", big.withTrimmedLeft (Theme::number (40).getStringWidth (formatClock (rec.seconds)) + 10).withTrimmedTop (16), Theme::muted());
        int sum = 0, n = 0, top = 0;
        for (auto& b : rec.blocks) { if (b.accuracy) { sum += *b.accuracy; ++n; } if (b.topBPM) top = std::max (top, *b.topBPM); }
        if (n > 0) Draw::text (g, "Accuracy " + juce::String (sum / n) + "%" + (top > 0 ? ", top tempo " + juce::String (top) + " bpm" : juce::String()), c.removeFromTop (22), Theme::text());
        c.removeFromTop (Theme::sp6);
        auto h = c.removeFromTop (20);
        Draw::text (g, "Accuracy", h.removeFromRight (90), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
        Draw::text (g, "Tempo", h.removeFromRight (110), Theme::faint(), Theme::small, false, juce::Justification::centredRight);
        Draw::text (g, "Block", h, Theme::faint(), Theme::small);
        Draw::hairline (g, c.getX(), c.getY(), c.getWidth());
        for (auto& b : rec.blocks)
        {
            auto row = c.removeFromTop (Theme::rowH);
            Draw::text (g, b.skipped ? juce::String ("Skipped") : b.accuracy ? juce::String (*b.accuracy) + "%" : dash, row.removeFromRight (90),
                        b.skipped ? Theme::faint() : Theme::muted(), Theme::body, false, juce::Justification::centredRight);
            Draw::text (g, b.startBPM ? juce::String (*b.startBPM) + (b.topBPM && *b.topBPM > *b.startBPM ? " to " + juce::String (*b.topBPM) : juce::String()) : juce::String(),
                        row.removeFromRight (110), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
            Draw::text (g, b.name, row, Theme::text());
            Draw::hairline (g, row.getX(), row.getBottom() - 1, row.getWidth());
        }
        return;
    }
    const auto st = runner.state();
    Draw::text (g, juce::String (std::min (st.index + 1, (int) r.blocks.size())) + " of " + juce::String ((int) r.blocks.size()) + "  " + r.name, top, Theme::muted(), Theme::small);
    Draw::text (g, model.routeName(), top, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
    // one segment a block, as wide as its share
    const auto est = runner.estimates();
    double total = 0;
    for (double e : est) total += e;
    total = std::max (1.0, total);
    float x = (float) line.getX();
    const float avail = (float) line.getWidth() - 2.0f * (float) std::max<size_t> (1, est.size()) + 2.0f;
    for (size_t i = 0; i < est.size(); ++i)
    {
        const float w = std::max (4.0f, avail * (float) (est[i] / total));
        auto seg = juce::Rectangle<float> (x, (float) line.getCentreY() - 2, w, 4);
        g.setColour ((int) i < st.index ? Theme::muted() : Theme::lineStrong());
        g.fillRoundedRectangle (seg, 2);
        if ((int) i == st.index) { g.setColour (Theme::accent()); g.fillRoundedRectangle (seg.withWidth (w * (float) runner.fraction ((int) i)), 2); }
        x += w + 2;
    }
    auto c = middle;
    const auto* b = runner.block();
    if (st.countdownTick)
    {
        Draw::text (g, "Next", c.removeFromTop (18), Theme::muted(), Theme::small);
        if (b) Draw::text (g, b->title (model.drills), c.removeFromTop (28), Theme::text(), 18, true);
        if (b) Draw::text (g, (tempoText (*b, model.drills).isNotEmpty() ? tempoText (*b, model.drills) + " bpm, " : juce::String()) + lengthText (*b),
                           c.removeFromTop (20), Theme::muted(), Theme::small);
        g.setColour (Theme::text());
        g.setFont (Theme::number (120, true));
        g.drawText (juce::String (*st.countdownTick), c.removeFromTop (150), juce::Justification::centredLeft);
    }
    else if (b && b->kind == RoutineBlock::Kind::drill)
    {
        if (model.phase == Model::Phase::running || model.phase == Model::Phase::paused || model.phase == Model::Phase::resting || model.phase == Model::Phase::intro)
            RunScreen::paintColumn (g, model, c);
        else
        {
            Draw::text (g, b->title (model.drills), c.removeFromTop (28), Theme::text(), 18, true);
            if (model.message.isNotEmpty()) Draw::text (g, model.message, c.removeFromTop (20), Theme::warn(), Theme::small);
        }
    }
    else if (b)
    {
        Draw::text (g, b->title (model.drills), c.removeFromTop (28), Theme::text(), 18, true);
        g.setColour (Theme::text());
        g.setFont (Theme::number (120, true));
        g.drawText (formatClock (std::ceil (st.left.value_or (0))), c.removeFromTop (150), juce::Justification::centredLeft);
        if (b->kind != RoutineBlock::Kind::rest && b->click)
        {
            Draw::text (g, juce::String (b->bpm) + " bpm", c.removeFromTop (28), Theme::text(), 18, true);
            Draw::beatBar (g, c.removeFromTop (14), 4, model.blockClickOn ? model.metronomeBeat() : -1);
        }
    }
    if (runner.paused() && ! (b && b->kind == RoutineBlock::Kind::drill))
        Draw::text (g, "Paused", middle.withTrimmedTop (middle.getHeight() - 40).withHeight (28), Theme::text(), 18, true);
    if (const auto* n = runner.nextBlock())
    {
        auto a = nextArea;
        Draw::text (g, lengthText (*n), a.removeFromRight (80), Theme::muted(), Theme::small, false, juce::Justification::centredRight);
        Draw::text (g, "Next", a.removeFromLeft (40), Theme::muted(), Theme::small);
        Draw::text (g, n->title (model.drills), a, Theme::text(), Theme::small);
    }
    else Draw::text (g, "Last block", nextArea, Theme::muted(), Theme::small);
}

bool RunnerScreen::keyPressed (const juce::KeyPress& k)
{
    if (runner.record) { if (k == juce::KeyPress::escapeKey || k == juce::KeyPress::returnKey) { runner.close(); return true; } return false; }
    if (k == juce::KeyPress::spaceKey) { if (runner.paused()) runner.resume(); else runner.pause(); return true; }
    if (k == juce::KeyPress::leftKey) { runner.back(); return true; }
    if (k == juce::KeyPress::rightKey) { runner.skip(); return true; }
    if (k == juce::KeyPress::escapeKey) { end.onClick(); return true; }
    return false;
}

} // namespace practice::ui
