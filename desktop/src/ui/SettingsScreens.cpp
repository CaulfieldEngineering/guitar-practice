#include "Screens.h"

namespace practice::ui {

static const juce::String dot = juce::String (juce::CharPointer_UTF8 (" \xc2\xb7 "));
static const juce::String dash = juce::String (juce::CharPointer_UTF8 ("\xe2\x80\x93"));

// ================================================================ Progress

ProgressScreen::ProgressScreen (Model& m) : Screen (m) {}

void ProgressScreen::refresh() { repaint(); }
void ProgressScreen::resized() {}

void ProgressScreen::mouseWheelMove (const juce::MouseEvent&, const juce::MouseWheelDetails& w)
{
    scroll = juce::jlimit (0.0f, (float) std::max (0, contentH - getHeight()), scroll - w.deltaY * 120.0f);
    repaint();
}

juce::String modeName (const juce::String& m)
{
    if (m == "endurance") return "Endurance";
    if (m == "duration") return "Time";
    return "Cycles";
}

void ProgressScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    auto runs = model.allRuns();
    const int x0 = Theme::sp7, w = std::min (900, getWidth() - 2 * Theme::sp7);
    int y = Theme::sp6 - (int) scroll;
    const auto& sync = model.syncState;
    juce::String status = ! sync.reachable.has_value() ? juce::String ("Syncing") : *sync.reachable ? juce::String ("Synced") : juce::String ("Offline");
    if (sync.pending > 0) status += dot + juce::String (sync.pending) + " pending";
    status += dot + "every run from the phone and this computer";
    Draw::text (g, status, { x0, y, w, 18 }, Theme::muted(), Theme::small);
    y += 30;
    if (runs.empty())
    {
        Draw::text (g, "No runs yet", { x0, y, w, 20 }, Theme::muted());
        contentH = y + 40 + (int) scroll;
        return;
    }
    // per drill: his max, the tempo reached run by run, how many runs, minutes not scored
    Draw::text (g, "Drill", { x0, y, 260, 16 }, Theme::faint(), Theme::micro);
    Draw::text (g, "Max", { x0 + 260, y, 70, 16 }, Theme::faint(), Theme::micro, false, juce::Justification::centredRight);
    Draw::text (g, "Tempo by run", { x0 + 350, y, 200, 16 }, Theme::faint(), Theme::micro);
    Draw::text (g, "Runs", { x0 + w - 170, y, 60, 16 }, Theme::faint(), Theme::micro, false, juce::Justification::centredRight);
    Draw::text (g, "Not scored", { x0 + w - 100, y, 100, 16 }, Theme::faint(), Theme::micro, false, juce::Justification::centredRight);
    y += 20;
    for (auto& d : model.drills)
    {
        std::vector<const SessionResult*> mine;
        for (auto& r : runs) if (r.exerciseID == d.id) mine.push_back (&r);
        const double unscored = model.unscoredSeconds (d.id);
        if (mine.empty() && unscored < 1) continue;
        auto row = juce::Rectangle<int> (x0, y, w, 36);
        Draw::text (g, d.name, row.withWidth (260), Theme::text());
        auto m = model.level (d.id);
        Draw::text (g, m ? juce::String (*m) + " bpm" : juce::String (dash), row.withX (x0 + 260).withWidth (70), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        // the sparkline, oldest to newest, solo scored runs
        std::vector<int> tempos;
        for (auto it = mine.rbegin(); it != mine.rend(); ++it) if (! (*it)->guided) tempos.push_back ((*it)->topBPM);
        auto spark = juce::Rectangle<float> ((float) x0 + 350, (float) y + 8, 200, 20);
        if (tempos.size() >= 2)
        {
            const auto [lo, hi] = std::minmax_element (tempos.begin(), tempos.end());
            const float range = (float) std::max (1, *hi - *lo);
            juce::Path p;
            for (size_t i = 0; i < tempos.size(); ++i)
            {
                const float px = spark.getX() + spark.getWidth() * (float) i / (float) (tempos.size() - 1);
                const float py = spark.getBottom() - spark.getHeight() * (float) (tempos[i] - *lo) / range;
                if (i == 0) p.startNewSubPath (px, py); else p.lineTo (px, py);
            }
            g.setColour (Theme::accent());
            g.strokePath (p, juce::PathStrokeType (1.5f, juce::PathStrokeType::curved, juce::PathStrokeType::rounded));
            Draw::text (g, juce::String (*lo) + dash + juce::String (*hi), { (int) spark.getRight() + 8, y, 80, 36 }, Theme::faint(), Theme::small);
        }
        Draw::text (g, juce::String ((int) mine.size()), row.withX (x0 + w - 170).withWidth (60), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::text (g, unscored >= 60 ? juce::String ((int) std::round (unscored / 60)) + " min" : unscored >= 1 ? juce::String ("under a minute") : juce::String (dash),
                    row.withX (x0 + w - 100).withWidth (100), Theme::muted(), Theme::body, false, juce::Justification::centredRight);
        Draw::hairline (g, x0, y + 35, w);
        y += 36;
    }
    // routines, each one session
    auto rruns = model.routines->runs();
    if (! rruns.empty())
    {
        y += 24;
        Draw::text (g, "Routines", { x0, y, w, 18 }, Theme::muted(), Theme::small);
        y += 22;
        int shownR = 0;
        for (auto& rr : rruns)
        {
            if (++shownR > 20) break;
            int sum = 0, n = 0;
            for (auto& b : rr.blocks) if (b.accuracy) { sum += *b.accuracy; ++n; }
            Draw::text (g, rr.date.formatted ("%b %e, %I:%M %p"), { x0, y, 150, 30 }, Theme::muted());
            Draw::text (g, rr.routineName, { x0 + 150, y, 260, 30 }, Theme::text());
            Draw::text (g, juce::String ((int) rr.blocks.size()) + " blocks, " + formatClock (rr.seconds), { x0 + 410, y, 240, 30 }, Theme::muted());
            Draw::text (g, n > 0 ? juce::String (sum / n) + "%" : dash, { x0 + 650, y, 80, 30 }, Theme::muted(), Theme::body, false, juce::Justification::centredRight);
            Draw::text (g, rr.device.isNotEmpty() ? rr.device : juce::String ("Phone"), { x0 + 746, y, w - 746, 30 }, Theme::muted());
            Draw::hairline (g, x0, y + 29, w);
            y += 30;
        }
    }
    y += 24;
    Draw::text (g, "Recent", { x0, y, w, 18 }, Theme::muted(), Theme::small);
    y += 22;
    const int cols[] = { 150, 260, 110, 130, 80, 0 };
    const char* heads[] = { "When", "Drill", "Tempo", "Run", "Score", "Where" };
    int cx = x0;
    for (int i = 0; i < 6; ++i)
    {
        const int cw = cols[i] ? cols[i] : w - (cx - x0);
        Draw::text (g, heads[i], { cx, y, cw, 16 }, Theme::faint(), Theme::micro, false, i == 4 ? juce::Justification::centredRight : juce::Justification::centredLeft);
        cx += cw + (i == 4 ? 16 : 0);
    }
    y += 20;
    int shown = 0;
    for (auto& r : runs)
    {
        if (++shown > 60) break;
        cx = x0;
        const juce::String tempo = r.topBPM > r.startBPM ? juce::String (r.startBPM) + dash + juce::String (r.topBPM) : juce::String (r.startBPM);
        const juce::String score = r.mode == "endurance" ? formatClock (r.sustainedSeconds.value_or (0))
                                 : r.mode == "challenge" ? formatClock (r.earnedSeconds.value_or (0)) : juce::String (r.score) + "%";
        const juce::String where = r.device.isNotEmpty() ? r.device : juce::String ("Phone");
        const juce::String cells[] = { r.date.formatted ("%b %e, %I:%M %p"), r.exerciseName, tempo + " bpm", modeName (r.mode) + (r.guided ? dot + "guided" : juce::String()), score, where };
        for (int i = 0; i < 6; ++i)
        {
            const int cw = cols[i] ? cols[i] : w - (cx - x0);
            Draw::text (g, cells[i], { cx, y, cw, 30 }, i == 1 ? Theme::text() : Theme::muted(), Theme::body, false,
                        i == 4 ? juce::Justification::centredRight : juce::Justification::centredLeft);
            cx += cw + (i == 4 ? 16 : 0);
        }
        Draw::hairline (g, x0, y + 29, w);
        y += 30;
    }
    contentH = y + (int) scroll + Theme::sp6;
}

// ================================================================ Settings

SettingsScreen::SettingsScreen (Model& m) : Screen (m)
{
    for (auto* c : std::initializer_list<juce::Component*> { &type, &input, &channel, &output, &buffer, &meter, &tone, &clickTest, &sounds,
                                                              &guitar, &hear, &cues, &appearanceDark, &calibrate, &syncNow, &server,
                                                              &tuning, &clickSound, &clickLevel, &chime, &ticks })
        addAndMakeVisible (c);
    addChildComponent (sevenStrings);
    for (int i = 0; i < 7; ++i)
    {
        auto d = std::make_unique<Dropdown>();
        juce::StringArray notes;
        for (int m = 28; m <= 70; ++m) notes.add (Tuning::noteName (m, true));
        d->setItems (notes, {});
        d->onChange = [this, i] {
            auto t = model.guitarTuning;
            if (i >= (int) t.strings.size()) return;
            t.strings[(size_t) i] = 28 + strings[(size_t) i]->getSelectedItemIndex();
            model.setGuitarTuning (Tuning::custom (t.strings));
        };
        addChildComponent (*d);
        strings.push_back (std::move (d));
    }
    {
        juce::StringArray names;
        for (auto& t : Tuning::presets()) names.add (t.name);
        names.add ("Custom");
        tuning.setItems (names, model.guitarTuning.name);
        tuning.onChange = [this] {
            const int i = tuning.getSelectedItemIndex();
            if (i >= 0 && i < (int) Tuning::presets().size()) model.setGuitarTuning (Tuning::presets()[(size_t) i]);
            else model.setGuitarTuning (Tuning::custom (model.guitarTuning.strings));
        };
    }
    sevenStrings.onChange = [this] (bool on) {
        auto s = model.guitarTuning.strings;
        if (on && s.size() == 6) s.push_back (s.back() - 5);
        if (! on && s.size() == 7) s.pop_back();
        model.setGuitarTuning (Tuning::custom (s));
    };
    clickSound.setItems ({ "Click", "Wood block", "Beep", "Rim" }, "Click");
    clickSound.onChange = [this] { model.setMetroSound ((SessionSettings::ClickSound) clickSound.getSelectedItemIndex()); };
    clickLevel.setRange (0, 1, 0.01);
    clickLevel.onValueChange = [this] { model.setMetroLevel (clickLevel.getValue()); };
    chime.onChange = [this] (bool on) { model.settings.set ("sound.chime", on); };
    ticks.onChange = [this] (bool on) { model.settings.set ("sound.ticks", on); };
    addChildComponent (update);
    type.onChange = [this] {
        auto s = model.deviceSetup;
        s.type = type.getText();
        auto it = model.device.lists.find (s.type);
        if (it != model.device.lists.end())
        {
            s.output = it->second.outputs.contains (s.output) ? s.output : it->second.outputs[0];
            s.input = it->second.sameDeviceForBoth ? s.output : (it->second.inputs.contains (s.input) ? s.input : it->second.inputs[0]);
        }
        s.bufferSize = 0;
        model.settings.set ("device.explicit", true);
        model.pickDevice (s);
    };
    input.onChange = [this] { pushDevice(); };
    output.onChange = [this] { pushDevice(); };
    channel.onChange = [this] { pushDevice(); };
    buffer.onChange = [this] { pushDevice(); };
    tone.onClick = [this] { model.testTone(); };
    clickTest.onClick = [this] { model.clickTest(); };
    sounds.setRange (0, 1, 0.01);
    sounds.onValueChange = [this] { model.setSoundsGain ((float) sounds.getValue()); };
    guitar.setRange (0, 1, 0.01);
    guitar.onValueChange = [this] { model.engine.guitarGain = (float) guitar.getValue(); model.settings.set ("guitarGain", guitar.getValue()); };
    hear.onChange = [this] (bool on) { model.setHearGuitar (on); };
    cues.onChange = [this] (bool on) { model.setVoiceCues (on); };
    appearanceDark.onChange = [this] (bool on) { model.settings.set ("dark", on); Theme::setDark (on); if (auto* p = getTopLevelComponent()) p->repaint(); model.sendChangeMessage(); };
    calibrate.onClick = [this] { if (onCalibrate) onCalibrate(); };
    syncNow.onClick = [this] { model.syncNow(); };
    update.onClick = [this] { model.installUpdate(); };
    server.setFont (Theme::ui (Theme::field));
    server.setIndents (8, 6);
    server.setText (model.settings.serverBase(), false);
    server.onReturnKey = [this] { model.settings.set ("server", server.getText().trim()); model.syncNow(); };
    server.onFocusLost = [this] { model.settings.set ("server", server.getText().trim()); };
    refresh();
}

SettingsScreen::~SettingsScreen() { model.setMeterListening (false); }

void SettingsScreen::visibilityChanged() { model.setMeterListening (isVisible()); }

void SettingsScreen::pushDevice()
{
    auto s = model.deviceSetup;
    s.type = type.getText();
    s.output = output.getText();
    auto it = model.device.lists.find (s.type);
    const bool same = it != model.device.lists.end() && it->second.sameDeviceForBoth;
    s.input = same ? s.output : (input.getSelectedItemIndex() <= 0 ? juce::String() : input.getText());
    s.inputChannel = channel.getSelectedItemIndex() - 1;
    const int b = buffer.getSelectedItemIndex();
    s.bufferSize = b <= 0 ? 0 : buffer.getText().getIntValue();
    model.settings.set ("device.explicit", true);
    model.pickDevice (s);
}

void SettingsScreen::refresh()
{
    const auto& d = model.device;
    const auto& s = model.deviceSetup;
    type.setItems (d.types, s.type, "No audio devices");
    auto it = d.lists.find (s.type);
    juce::StringArray ins { "None" }, outs;
    bool same = false;
    if (it != d.lists.end()) { outs = it->second.outputs; same = it->second.sameDeviceForBoth; for (auto& n : it->second.inputs) ins.add (n); }
    output.setItems (outs, s.output, "No outputs");
    input.setItems (same ? juce::StringArray { s.output } : ins, same ? s.output : (s.input.isEmpty() ? juce::String ("None") : s.input));
    input.setEnabled (! same);
    channel.setItems ({ "Inputs 1 and 2", "Input 1", "Input 2" }, s.inputChannel == 0 ? "Input 1" : s.inputChannel == 1 ? "Input 2" : "Inputs 1 and 2");
    juce::StringArray bufs { "Default" };
    for (int b : d.info.buffers) bufs.add (juce::String (b) + " samples");
    buffer.setItems (bufs, s.bufferSize > 0 ? juce::String (s.bufferSize) + " samples" : juce::String ("Default"));
    sounds.setValue (model.soundsGain(), juce::dontSendNotification);
    guitar.setValue (model.engine.guitarGain.load(), juce::dontSendNotification);
    hear.setOn (model.engine.hearGuitar.load());
    cues.setOn (model.voiceCues);
    appearanceDark.setOn (Theme::dark());
    {
        juce::StringArray names;
        for (auto& t : Tuning::presets()) names.add (t.name);
        names.add ("Custom");
        tuning.setItems (names, model.guitarTuning.isCustom() ? juce::String ("Custom") : model.guitarTuning.name);
        const bool custom = model.guitarTuning.isCustom();
        sevenStrings.setVisible (custom);
        sevenStrings.setOn (model.guitarTuning.strings.size() == 7);
        for (size_t i = 0; i < strings.size(); ++i)
        {
            const bool show = custom && i < model.guitarTuning.strings.size();
            strings[i]->setVisible (show);
            if (show) strings[i]->setSelectedItemIndex (juce::jlimit (0, 42, model.guitarTuning.strings[i] - 28), juce::dontSendNotification);
        }
    }
    clickSound.setSelectedItemIndex ((int) model.metroSound, juce::dontSendNotification);
    clickLevel.setValue (model.metroLevel, juce::dontSendNotification);
    chime.setOn (model.settings.getBool ("sound.chime", true));
    ticks.setOn (model.settings.getBool ("sound.ticks", true));
    update.setVisible (model.updateFile.existsAsFile());
    meter.push (model.meterPeak());
    resized();
    repaint();
}

void SettingsScreen::resized()
{
    labels.clear(); values.clear(); sectionTitles.clear();
    const int gap = Theme::sp8;
    auto area = getLocalBounds().reduced (Theme::sp7, Theme::sp6);
    const int colW = std::min (520, (area.getWidth() - gap) / 2);
    auto left = area.withWidth (colW);
    auto right = area.withX (left.getRight() + gap).withWidth (colW);
    const int rh = 32, labelW = 150;
    auto section = [&] (juce::Rectangle<int>& col, const juce::String& title) {
        sectionTitles.push_back ({ col.removeFromTop (20), title });
        col.removeFromTop (Theme::sp2);
    };
    auto row = [&] (juce::Rectangle<int>& col, const juce::String& label, juce::Component* c, int w, const juce::String& value = {}) {
        auto r = col.removeFromTop (rh);
        labels.push_back ({ r.withWidth (labelW), label });
        if (c) c->setBounds (w < 0 ? r.withTrimmedLeft (labelW).withSizeKeepingCentre (r.getWidth() - labelW, Theme::ctlH)
                                    : juce::Rectangle<int> (r.getRight() - w, r.getCentreY() - Theme::ctlH / 2, w, Theme::ctlH));
        if (value.isNotEmpty()) values.push_back ({ r.withTrimmedLeft (labelW).withTrimmedRight (c ? w + Theme::sp4 : 0), value });
    };
    const auto& d = model.device;
    section (left, "Audio");
    row (left, "Device type", &type, 260);
    row (left, "Input", &input, 260);
    row (left, "Input channel", &channel, 260);
    row (left, "Output", &output, 260);
    row (left, "Buffer", &buffer, 260);
    statusLine = left.removeFromTop (22);
    left.removeFromTop (Theme::sp4);
    row (left, "Level", &meter, 260, {});
    values.push_back ({ juce::Rectangle<int> (meter.getX() - 110, meter.getY(), 100, Theme::ctlH), meter.readout() });
    {
        auto r = left.removeFromTop (rh);
        labels.push_back ({ r.withWidth (labelW), "Test" });
        clickTest.setBounds (r.getRight() - 100, r.getCentreY() - Theme::ctlH / 2, 100, Theme::ctlH);
        tone.setBounds (clickTest.getX() - Theme::sp4 - 100, r.getCentreY() - Theme::ctlH / 2, 100, Theme::ctlH);
    }
    row (left, "App sounds", &sounds, 260);
    row (left, "Hear guitar", &hear, 44, "Adds the input's delay");
    row (left, "Guitar level", &guitar, 260);
    auto ms = [&] (int samples) { return d.info.sampleRate > 0 ? juce::String ((int) std::round (1000.0 * samples / d.info.sampleRate)) : juce::String (dash); };
    row (left, "Latency", nullptr, 0, d.open ? "in " + ms (d.info.inputLatency) + " + out " + ms (d.info.outputLatency) + " + buffer " + ms (d.info.bufferSize)
                                              + " = " + juce::String ((int) std::round (model.latencyEstimate() * 1000)) + " ms" : juce::String (dash));
    auto c = model.calibration();
    row (left, "Calibration", &calibrate, calibrate.idealWidth(),
         c ? juce::String ((int) std::round (model.currentOffset() * 1000)) + " ms" + (c->spreadMs ? dot + "varied " + juce::String ((int) std::round (*c->spreadMs)) + " ms" : juce::String())
           : juce::String ("Not calibrated"));

    section (right, "Guitar");
    row (right, "Tuning", &tuning, 200, model.guitarTuning.lowToHigh());
    if (model.guitarTuning.isCustom())
    {
        row (right, "7 strings", &sevenStrings, 44);
        auto r = right.removeFromTop (rh);
        labels.push_back ({ r.withWidth (labelW), "Strings, low first" });
        auto a = r.withTrimmedLeft (labelW);
        const int n = (int) model.guitarTuning.strings.size();
        const int cw = std::max (40, (a.getWidth() - (n - 1) * Theme::sp2) / std::max (1, n));
        for (int i = n - 1; i >= 0; --i)
        {
            strings[(size_t) i]->setBounds (a.removeFromLeft (cw).withSizeKeepingCentre (cw, Theme::ctlH));
            a.removeFromLeft (Theme::sp2);
        }
    }
    right.removeFromTop (Theme::sp7);
    section (right, "Sound");
    row (right, "Click sound", &clickSound, 200);
    row (right, "Click level", &clickLevel, 200);
    row (right, "Block chime", &chime, 44);
    row (right, "Countdown ticks", &ticks, 44);
    right.removeFromTop (Theme::sp7);
    section (right, "Voice");
    row (right, "Voice cues", &cues, 44, "The next pattern and tempo");
    right.removeFromTop (Theme::sp7);
    section (right, "Sync");
    row (right, "Drill server", &server, 240);
    const auto& sy = model.syncState;
    row (right, "Status", &syncNow, syncNow.idealWidth(),
         (! sy.reachable.has_value() ? juce::String ("Syncing") : *sy.reachable ? "Synced " + sy.lastSync.formatted ("%I:%M %p") : juce::String ("Offline"))
         + (sy.pending > 0 ? dot + juce::String (sy.pending) + " pending" : juce::String()));
    row (right, "Drills", nullptr, 0, "Catalog " + juce::String (model.catalogVersion) + dot + juce::String ((int) model.drills.size()) + (model.drills.size() == 1 ? " drill" : " drills"));
    right.removeFromTop (Theme::sp7);
    section (right, "Appearance");
    row (right, "Dark", &appearanceDark, 44);
    right.removeFromTop (Theme::sp7);
    section (right, "About");
    row (right, "Version", update.isVisible() ? &update : nullptr, update.idealWidth(),
         model.appVersion() + (model.updateVersion.isNotEmpty() ? dot + model.updateVersion + " ready" : model.updateDownloading ? dot + "downloading an update" : juce::String()));
    row (right, "This computer", nullptr, 0, model.computerName());
}

void SettingsScreen::paint (juce::Graphics& g)
{
    g.fillAll (Theme::bg());
    for (auto& [r, t] : sectionTitles) Draw::text (g, t, r, Theme::muted(), Theme::small);
    for (auto& [r, t] : labels)
    {
        Draw::text (g, t, r, Theme::text());
    }
    for (auto& [r, t] : values) Draw::text (g, t, r, Theme::muted(), Theme::small, false, juce::Justification::centredRight);
    const auto& d = model.device;
    juce::String st;
    juce::Colour c = Theme::muted();
    if (d.busy) st = "Opening " + (model.deviceSetup.output.isNotEmpty() ? model.deviceSetup.output : model.deviceSetup.type);
    else if (d.error.isNotEmpty()) { st = d.error; c = Theme::warn(); }
    else if (d.open) st = model.routeName() + dot + juce::String ((int) d.info.sampleRate) + " Hz" + dot + juce::String (d.info.bufferSize) + " samples"
                         + (d.info.inputChannels > 0 ? dot + juce::String (d.info.inputChannels) + (d.info.inputChannels == 1 ? " input" : " inputs") : dot + "no input");
    else st = "No audio device open";
    if (model.message.isNotEmpty() && ! d.busy) { st = model.message; c = Theme::warn(); }
    Draw::text (g, st, statusLine.withTrimmedLeft (150), c, Theme::small);
}

} // namespace practice::ui
