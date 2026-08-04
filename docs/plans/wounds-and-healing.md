# Wounds and healing — the flow, in three stages

> *"construye un flujo lógico con el funcionamiento actual -> El funcionamiento inicial de
> que busquen vendas para curarse o si tienen lo apliquen -> El funcionamiento final, que es
> que no dependan solo de vendas o elementos quirurgicos para curarse."*

Deliberately not numbered as a stage. It cuts across 03 (autonomy) and 07 (errands) and is
sequenced by what has been proven in play, not by the roadmap.

---

## Stage 0 — what actually happens today, before any of this

Worth writing down exactly, because all three facts are surprising.

**There are no body parts.** The whole injury model is one float, `getHealth()`, roughly
0..2.6 where the maximum is `brain.health`, fixed at spawn. Nothing is bitten, scratched,
cut or bandaged *anywhere*. `getBodyDamage()` answers on an `IsoZombie`, but nothing in
Bandits ever writes to it — a vanilla-style body diagram would render zeroes forever.

**Bleeding is a single line.** `ManageHealth` (`BanditUpdate.lua:491-501`): below `0.7`,
subtract `0.00005` per tick and occasionally add a blood splat. Below `0.7`, forever, with
no floor other than death.

**Healing was free and nearly unreachable.** Two separate problems:

```lua
if not BanditBrain.HasActionTask(brain) then   -- BanditUpdate.lua:952
    local health = bandit:getHealth()
    if health < 0.4 then healing = true end    -- :955-957
```

`HasActionTask` returns true if the queue holds *anything* that is not `Move` or `GoTo`. So
a survivor who is doing something — which, with the autonomy ladder running, is most of the
time — never gets the flag. And when it does fire, `ZABandage.onComplete` is:

```lua
zombie:setHealth(1.2)
zombie:addVisualBandage(bodyPart.name, true)
```

No item consumed. No inventory checked. A flat 1.2 regardless of who they are — which for a
tough survivor with a 2.6 maximum is a *downgrade*, and for a frail one is a full heal.

### And the reason yours bled out was ours

```
AUTO Benjamin Morgan | stuck on Bandage@nil,nil for 3 sweeps -- queue cleared
```

Three times in the 04-08 log. The first watchdog read an unchanged task at the head of the
queue as "stuck", and `Bandage` sits there while it works. We were cancelling their heal,
mid-heal, every twenty seconds. Fixed in the second pass; recorded here because the reported
symptom was a bug we introduced, not a gap in the framework.

---

## Stage 1 — healing costs something *(BUILT, untested)*

`ScenesRelationsWounds.lua` wraps `ZombieActions.Bandage.onComplete`. Their onStart, their
animation and their sound are untouched — the outcome changes, not the act.

| What they had | Restored | Dressing state |
|---|---|---|
| sterile (alcohol) | 100% of their max | clean |
| proper bandage | 95% | clean |
| clean rag | 80% | clean |
| dirty rag | 55% | **dirty** |
| nothing at all | 40% | **improvised**, dirty |

**Ranked, never listed.** `item:getBandagePower() > 0` is how vanilla itself decides
something is a bandage (`ISHealthPanel.lua:1154`), and `>= 2` is how it separates a proper
bandage from a rag (`:1722`). Sterility is `item:isAlcoholic()`, the flag
`ISApplyBandage.lua:119` passes through. So this covers every dressing in the game, and any
mod's, with no list to go stale.

**Nobody bleeds to death with a shirt on.** The last row is the floor: with nothing at all,
they tear up what they are wearing. Weak, dirty, and something they will want to replace —
but never nothing.

**Risk is a trait, not a die roll.** `brain.rnd[1]` is `ZombRand(2)`, the last of the five
still unspoken for. Half of them will tie a filthy rag on rather than bleed; the cautious
half improvise from clean clothing instead — worse at stopping blood, better at not killing
them. The same person makes the same choice every time.

**`brain.infection` is deliberately not touched.** It would be the obvious home for "this
rag is filthy". It is also the counter Bandits turns into a `Zombify` task at 100
(`BanditUpdate.lua:509`). A dirty bandage must not turn somebody into a zombie.

### Also built: broken glass cuts

`isSmashed() and not isGlassRemoved()` is vanilla's own test — it is the `isValid` of
`ISRemoveBrokenGlass`, the action a player takes specifically so they can climb through
without being cut. An NPC standing in such a frame loses 0.25 health and its dressing.

**Known limit, stated rather than hidden.** The autonomy sweep runs about every six seconds,
so this SAMPLES rather than intercepts. Bandits has no `ClimbThroughWindow` action at all —
the engine's pathing carries them over — so there is no event to hook. `OpenWindow` is
queued with `time=60` and they linger, so most crossings should be caught. If the log shows
crossings going unpunished, the fix is a faster dedicated tick, not a cleverer test.

---

## Stage 2 — going and getting one *(designed, not built)*

Today they dress a wound with whatever happens to be in their pockets. Stage 2 makes finding
a dressing something they will cross a room for.

1. **Rung 4 (errand) gets its first real content.** A survivor below some health fraction
   with no dressing in inventory wants one, and that want outranks searching for food.
2. **The search is the one already built.** `SR.Loot.FindContainer` plus a predicate —
   medicine cabinets first, then anything. No new mechanism.
3. **Ripping cloth becomes deliberate rather than a fallback.** Vanilla turns a `Sheet` into
   `RippedSheets`; if that recipe is reachable from Lua for an NPC, tearing a curtain in the
   room beats walking to the next house. If it is not, the improvised dressing from stage 1
   stays the floor.
4. **The player can be asked.** Trust-gated. This is the seam into stage 07 (errands) and
   the first time an NPC asks you for a specific object.

**Done when:** a wounded survivor with nothing walks to a bathroom cabinet, finds a bandage
and uses it — and one with nothing available asks you instead.

---

## Stage 3 — clean it, and want it clean *(designed, not built)*

> *"siempre queriendose cambiarla por una limpia o si están en una casa looteando, que vayan
> a limpiar la tela en un lavabo para terminar de curarse y estar bien."*

1. **A dirty dressing degrades.** `wound.dressing == "dirty"` with `wound.day` already
   recorded; after some days it stops holding and health starts drifting again. Our own
   counter, never `brain.infection`.
2. **They want to replace it.** `SR.Wounds.WantsCleanDressing(brain)` already exists and
   already answers. It has no consumer yet — that is this stage.
3. **Washing at a sink.** Vanilla has `ISCleanBandage`, and a water source in a room is
   findable the same way a container is. A dirty rag washed becomes clean; the survivor
   finishes healing. This is the piece that makes a looted house a place you *recover* in
   rather than only take from.
4. **The visible tell.** A dirty dressing should be readable without opening the health
   panel, so the player can decide to help. Gated on stage 09 (visible inner state).

**Done when:** a survivor with an improvised dressing, left alone in a house with running
water, ends up clean and whole without the player doing anything.

---

## The probe this is all waiting on

Does the engine *process* `getBodyDamage()` for an `IsoZombie`?

We know it **binds** — `ok=true` under the corrected probe. We know Bandits never writes to
it. We do **not** know whether writing `bodyPart:setCut(true)` or `generateDeepShardWound()`
on an NPC would produce bleeding, infection, or anything at all, or whether it would be a
write into a structure nothing ever reads.

If it ticks, per-body-part wounds become real and most of stage 3 is vanilla's job. If it
does not, everything stays on `brain.scenesWound` where it is now.

**This is exactly the shape of question this project has twice paid for guessing.** It gets
a probe before anything leans on it — the same treatment `getStats()` got, which came back
`FROZEN` and settled a stage's worth of design in one line of log.

---

## Where the numbers live

`docs/NPC-BEHAVIOR-PLAN.md`, tuning log. Every value above is there with the reason it was
chosen, including why the restore is a fraction of each person's own maximum rather than the
framework's flat 1.2.
