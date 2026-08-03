# Where we are, and what to test next

One page. Updated every time a stage opens or closes. If this file and anything else
disagree, this file is the one that is stale — fix it.

Full roadmap: [`docs/plans/README.md`](plans/README.md).

---

## Open right now

| Stage | State |
|---|---|
| [00 — Test world](plans/00-test-world.md) | built, never run |
| [01 — Durable memory](plans/01-durable-memory.md) | built (`a7de2dc`), never run |

Both are waiting on the same session. **Nothing new gets built until this run comes back**,
because two answers from it can rewrite several later stages.

Next up once they pass: [02 — Salience and forgetting](plans/02-salience-and-forgetting.md).

---

## Before you start

```bash
tools/sync-mods.sh
```

Non-negotiable. Three of the last four test runs measured a build that was one sync behind,
and each time we spent the session diagnosing something that was already fixed.

Then: **start a NEW game.** `OnNewGame` fires only on new games, so loading an existing save
gets you no companion and proves nothing about stage 00.

---

## What to test, in order

### 1. Somebody is standing next to you

**Do:** start a new game. Look around.

**Pass:** exactly one survivor is beside you and follows when you walk. `console.txt` has
`TLOU| new game -- one companion queued` followed by `TLOU| companion requested at …`.

**If it fails,** the table in [stage 00](plans/00-test-world.md) says what each symptom
means — no `TLOU|` lines at all, `Spawner unavailable`, `gave up after 200 ticks`, or
spawned-but-not-following are four different causes.

---

### 2. Survivors are living in houses

**Do:** walk into an area you have not explored. Give it a few in-game hours.

**Pass:** you find friendly survivors inside houses who stay in them rather than roaming.
Their `PROBE` lines show `prog=Defend`.

**Expected non-failure:** houses you already entered will never have them. `spawnHouse`
refuses any building the player visited in the last 7 in-game days. That is by design
upstream, not our bug.

---

### 3. Trust still moves — regression

**Do:** tests 1, 2 and 3 in [`docs/TEST-RUNS.md`](TEST-RUNS.md), unchanged.

**Pass:** hitting a friendly survivor drops trust, fighting beside one raises it, and the
right-click label shows the number. Stage 01 was supposed to change *nothing* about how the
mod plays. If the behaviour moved, the refactor did something it should not have.

---

### 4. **The one that matters — memory across a cell unload**

Test 10 in [`docs/TEST-RUNS.md`](TEST-RUNS.md). Everything else is a feature; this decides
whether an NPC can know you at all.

1. Fight beside the companion until its trust is clearly above zero.
2. In `console.txt`, find its `PROBE` line. Write down **both** `id=` and `trust=`.
3. Walk at least ten blocks away. Wait for two `PROBE sweep` lines with no `PROBE` line for
   it in between — that is how you know its cell unloaded.
4. Walk back.

**Pass:** same `id`, same `trust`, `known=true`.

**Each failure means something different** and the table in TEST-RUNS test 10 spells it
out. The one worth knowing in advance: a *different* `id` means recognition needs the fuzzy
name-plus-traits fallback, and stages 02 onward slip.

---

### 5. Two seconds of looking at the screen

Early in the session, `console.txt` prints two `PROBE halo` lines. `threw=false` is not the
answer — it only means it did not crash.

**Look at the screen** and tell me whether the words *SCENES probe* actually appeared above
a survivor's head.

That single observation decides whether an NPC's inner state can be shown in the world or
whether it needs a UI panel — which is the difference between stage 06 being cheap and
being a rebuild.

---

## What to send back

`console.txt`, plus one line per test: number, pass or fail, what you saw.

For test 4, the two `id`/`trust` pairs — before and after — are worth more than any
description. For test 5, one word.

Do not delete the log between tests. The frame numbers are how the order gets reconstructed.
