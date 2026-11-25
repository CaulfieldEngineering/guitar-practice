#include "RoutineRunner.h"

namespace practice {

using EK = RoutineClock::Event::Kind;

const RoutineBlock* RoutineRunner::block() const
{
    if (! routine || clock.index() >= (int) routine->blocks.size()) return nullptr;
    return &routine->blocks[(size_t) clock.index()];
}

const RoutineBlock* RoutineRunner::nextBlock() const
{
    if (! routine || clock.index() + 1 >= (int) routine->blocks.size()) return nullptr;
    return &routine->blocks[(size_t) clock.index() + 1];
}

std::vector<double> RoutineRunner::estimates() const
{
    std::vector<double> e;
    if (routine) for (auto& b : routine->blocks) e.push_back (b.estimate (model.drills));
    return e;
}

double RoutineRunner::fraction (int i) const
{
    if (i < clock.index() || clock.phase() == RoutineClock::Phase::done) return 1;
    if (i > clock.index()) return 0;
    const double ran = clock.ranInBlock (now);
    const auto e = estimates();
    return ran <= 0 ? 0 : std::min (1.0, ran / std::max (1.0, i < (int) e.size() ? e[(size_t) i] : 1.0));
}

bool RoutineRunner::paused() const
{
    return state().paused || (block() && block()->kind == RoutineBlock::Kind::drill && model.phase == Model::Phase::paused);
}

void RoutineRunner::start (const PracticeRoutine& r)
{
    stopTimer();
    if (model.blockClickOn) model.stopBlockClick();
    if (model.metronomeRunning()) model.toggleMetronome();
    routine = r;
    record.reset();
    results.clear();
    runID = juce::Uuid().toDashedString().toUpperCase();
    started = juce::Time::getCurrentTime();
    std::vector<std::optional<double>> blocks;
    for (auto& b : r.blocks) blocks.push_back (b.fixedSeconds());
    clock = RoutineClock (blocks);
    base = juce::Time::getMillisecondCounterHiRes() / 1000.0;
    now = 0;
    lastTick = -1;
    model.routineRunID = runID;
    handle (clock.start (0));
    startTimerHz (30);
    sendChangeMessage();
}

void RoutineRunner::timerCallback()
{
    now = t();
    handle (clock.tick (now));
    const auto s = clock.state (now);
    if (s.countdownTick && ! s.paused && *s.countdownTick != lastTick && *s.countdownTick > 0)
    {
        lastTick = *s.countdownTick;
        model.playTick (lastTick == 1);
    }
    if (! s.countdownTick) lastTick = -1;
    sendChangeMessage();
}

void RoutineRunner::handle (const std::vector<RoutineClock::Event>& events)
{
    for (auto& e : events)
    {
        if (e.kind == EK::start) begin (e.index);
        else if (e.kind == EK::end) end (e.index);
        else finish (true);
    }
}

void RoutineRunner::begin (int i)
{
    if (! routine || i >= (int) routine->blocks.size()) return;
    const auto& b = routine->blocks[(size_t) i];
    model.playChime();
    switch (b.kind)
    {
        case RoutineBlock::Kind::drill:
        {
            bool known = false;
            for (auto& d : model.drills) if (d.id == b.drillID) known = true;
            if (! known || ! b.drill) { handle (clock.skip (t())); return; }
            ending = false;
            model.onRunEnded = [this, i] (const SessionResult* r) {
                if (r) results[i] = *r;
                if (ending) return;
                juce::MessageManager::callAsync ([this] { handle (clock.blockDone (t())); sendChangeMessage(); });
            };
            Model::RunSetup s;
            s.drillID = b.drillID; s.bpm = b.drill->bpm; s.guided = b.drill->guided; s.audioInput = b.drill->audioInput; s.session = b.drill->session;
            model.startBlock (s);
            if (model.phase == Model::Phase::ready) clock.pause (t());   // it could not start: the reason is on the screen
            break;
        }
        case RoutineBlock::Kind::warmup: case RoutineBlock::Kind::free: case RoutineBlock::Kind::custom:
            if (b.click) model.startBlockClick (b.bpm);
            break;
        case RoutineBlock::Kind::rest: break;
    }
}

void RoutineRunner::end (int i)
{
    if (! routine || i >= (int) routine->blocks.size()) return;
    if (routine->blocks[(size_t) i].kind == RoutineBlock::Kind::drill) stopDrill();
    else model.stopBlockClick();
}

void RoutineRunner::stopDrill()
{
    ending = true;
    if (model.phase == Model::Phase::running || model.phase == Model::Phase::paused || model.phase == Model::Phase::resting
        || model.phase == Model::Phase::intro)
        model.stop();
    model.onRunEnded = nullptr;
    if (model.phase == Model::Phase::result) model.clearResult();
    ending = false;
}

void RoutineRunner::pause()
{
    if (! active() || clock.state (t()).paused) return;
    clock.pause (t());
    now = t();
    if (block() && block()->kind == RoutineBlock::Kind::drill) { if (model.phase == Model::Phase::running) model.pause(); }
    else model.stopBlockClick();
    sendChangeMessage();
}

void RoutineRunner::resume()
{
    if (! active()) return;
    if (! clock.state (t()).paused)
    {
        if (model.phase == Model::Phase::paused) model.resumeRun();
        return;
    }
    const bool wasBlock = ! clock.state (t()).countdownTick.has_value();
    handle (clock.resume (t()));
    now = t();
    if (wasBlock && block())
    {
        const auto& b = *block();
        if (b.kind == RoutineBlock::Kind::drill)
        {
            if (model.phase == Model::Phase::paused) model.resumeRun();
            else if (model.phase == Model::Phase::ready) begin (clock.index());
        }
        else if (b.kind != RoutineBlock::Kind::rest && b.click) model.startBlockClick (b.bpm);
    }
    sendChangeMessage();
}

void RoutineRunner::skip()
{
    if (! active()) return;
    if (block() && block()->kind == RoutineBlock::Kind::drill && ! clock.state (t()).countdownTick) stopDrill();
    handle (clock.skip (t()));
    now = t();
    sendChangeMessage();
}

void RoutineRunner::back()
{
    if (! routine) return;
    if (block() && block()->kind == RoutineBlock::Kind::drill) stopDrill();
    else model.stopBlockClick();
    clock.back (t());
    if (record) { record.reset(); startTimerHz (30); }
    now = t();
    sendChangeMessage();
}

void RoutineRunner::endNow()
{
    if (! active()) return;
    if (block() && block()->kind == RoutineBlock::Kind::drill) stopDrill();
    finish (false);
}

void RoutineRunner::finish (bool completed)
{
    stopTimer();
    model.stopBlockClick();
    if (model.phase != Model::Phase::ready && model.phase != Model::Phase::result) stopDrill();
    if (model.phase == Model::Phase::result) model.clearResult();
    model.endBlockSetup();
    if (! routine) return;
    RoutineRunRecord rec;
    rec.id = runID;
    rec.date = started;
    rec.routineID = routine->id;
    rec.routineName = routine->name;
    rec.completed = completed;
    rec.device = model.computerName();
    rec.appVersion = "desktop " + model.appVersion();
    for (size_t i = 0; i < routine->blocks.size(); ++i)
    {
        const auto& b = routine->blocks[i];
        const auto l = i < clock.log().size() ? clock.log()[i] : RoutineClock::Log {};
        RoutineRunRecord::Block x;
        x.kind = RoutineBlock::kindName (b.kind);
        x.name = b.title (model.drills);
        x.seconds = l.seconds;
        x.skipped = l.skipped || ! (l.seconds > 0 || l.done);
        if (auto it = results.find ((int) i); it != results.end())
        {
            x.sessionID = it->second.id;
            x.accuracy = it->second.accuracyPercent;
            x.startBPM = it->second.startBPM;
            x.topBPM = it->second.topBPM;
        }
        rec.seconds += l.seconds;
        rec.blocks.push_back (x);
    }
    record = rec;
    if (rec.seconds >= 1) { model.routines->addRun (rec); model.syncNow(); }
    if (completed) model.playChime();
    sendChangeMessage();
}

void RoutineRunner::close()
{
    stopTimer();
    if (active()) finish (false);
    routine.reset();
    record.reset();
    sendChangeMessage();
}

} // namespace practice
