# Stage 02 — salience and forgetting

**Status: next. Not started. Blocked on stage 01 passing test 10.**

## The problem

The episode list is a ring buffer of twelve, first in first out. That means an NPC forgets
the day you shot their friend because you have since killed fifty zombies together. The
memory that matters is exactly the one that gets pushed out.

Forgetting is not the bug. The research is blunt that a model which lets an agent forget or
hold hazy memories is what produces human-like variability — and we need forgetting for
cost reasons regardless. The bug is forgetting *by arrival order*.

## Deliverables

### 1. Episodes carry a salience

`{ day, delta, reason, salience }`. Salience is an integer set when the episode is written,
derived from what happened rather than from how much trust moved. Being shot at is salient.
A good afternoon is not.

The seed rule, to be tuned in `docs/NPC-BEHAVIOR-PLAN.md` like every other number here:
violence against the NPC or its people ranks highest, gifts and rescues next, incidental
help lowest.

### 2. Eviction ranks, it does not queue

When the list is full, drop the **least salient**, breaking ties by age. `SR.MEMORY_CAP`
stays at twelve; what changes is which twelve survive.

### 3. Dropped episodes leave a mark

This is the load-bearing part and the reason the stage exists. In the 25-agent Generative
Agents study, removing the step that synthesises episodes into conclusions made emergent
coordination **disappear entirely**. Agents that only accumulate events never develop
opinions.

We have no language model, so consolidation produces a label and a weight, not a sentence:

```lua
record.labels = { dangerous = 4, generous = 1 }
```

An evicted episode folds into one label. The labels are permanent and tiny — a handful of
integers per person you have actually met — and they are what lets an NPC have an *opinion*
rather than a transcript. An NPC that has forgotten the incident but not the conclusion is
the whole point.

### 4. Nothing reads the labels yet

Deliberately. Stage 03 (traits) and stage 08 (the social graph) are the consumers. Writing
a reader now would be guessing at an interface before its caller exists.

## Done when

- Attacking an NPC once, then fighting beside it twenty times, still leaves the attack in
  its episode list.
- `record.labels` accumulates across a session and survives a reload.
- The episode list never exceeds twelve entries.

## How it is tested

An explicit ordering, because this one cannot be seen on screen — it has to be read out of
`console.txt`:

1. Attack the companion once. Note the `SREL|` line.
2. Fight beside it through twenty-plus zombie kills.
3. Force a log dump of its record.

**Pass:** the attack episode is still there and `labels.dangerous` is non-zero.
**Fail:** the attack has been evicted by routine `+2 fought beside` entries — eviction is
still queueing rather than ranking.

That dump needs a way to ask an NPC for its record on demand. Adding it is part of this
stage, not an afterthought.

## Cost note

Ranked eviction is a linear scan of twelve entries, on an event that fires per melee swing
at worst. `BanditUtils.AreEnemies` already runs 460,361 times per minute in this game; this
is not where the budget goes. Consolidation runs only on eviction, which is rarer still.
