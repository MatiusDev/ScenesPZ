# NPC behaviour plan

Started 2026-08-03. The staged plan for making Bandits NPCs behave like people instead
of a friend/killer switch. Read `docs/BANDITS-API.md` first for what already exists;
this file is only about what we add and in what order.

Each stage names **what it proves**. A stage that proves nothing is not a stage, it is a
feature we guessed at. Nothing moves forward until the previous stage has been seen in a
real log — every session on the gaming PC is expensive and there is no hot reload.

## The vision this serves

**People follow you because they are safer with you, and together you build a place worth
living in.**

That sentence decides arguments. Every stage below has to move toward it, and anything
that does not is out of scope no matter how interesting.

Three things follow from it directly:

1. **Safety has to be felt, not asserted.** An NPC should follow because staying near you
   demonstrably keeps it alive, not because a number crossed a threshold. The number is
   how we record what happened; it is not the reason.
2. **Idle is the enemy.** An NPC standing in a field playing the Shrug animation has no
   reason to be anywhere. Purpose is what makes a companion read as a person, and right
   now Bandits gives non-combat NPCs nothing to do.
3. **The settlement is the point, not a reward.** A village is what a group of people who
   trust each other produces. It is the destination, so the systems underneath — trust,
   purpose, safety — have to be built as if something will eventually stand on them.

What this rules out: quest chains, dialogue trees for their own sake, faction reputation
tables. Those are content. The relationship is the mechanic.

## Ground rules, learned the hard way

1. **Grep `pzserver/media/` before writing any identifier.** Not the wiki, not upstream
   code. `isNPC()` and `getTarget()` both look obvious and both appear **zero times** in
   the 2,680 vanilla Lua files of 42.20. The first one silently killed `OnHitZombie` for
   two full play sessions.
2. **Vendored upstream code is not a verification source.** Bandits carries the same
   `isNPC()` defect at `BanditPlayer.lua:91`, which is exactly how we inherited it.
   Their `CheckFriendlyFire` is dead in 42.20 — anything we assumed it handled, it does
   not.
3. **Wrap, never replace.** Every change so far is a wrapper that still calls the
   original. Overwriting a Bandits function makes us mutually exclusive with every other
   mod that touches it.
4. **A comment that states an assumption must state how it was checked.** Two of our
   bugs were correct-sounding comments whose premise had never been verified.

## Verified levers

Confirmed by reading 42.20 source. Line numbers are Bandits 42.20 unless noted.

| Lever | Where | What it does |
|---|---|---|
| `Bandit.IsHostile(z)` | `Bandit.lua:604` | returns `brain.hostile or brain.hostileP` |
| Player targeting gate | `BanditUtils.lua:962` | player is only targeted when `IsHostile` |
| Zombie targeting | `BanditUtils.lua:840` | **no range limit** — we wrap it |
| `config.hearDist` | `BanditUtils.lua:815` | players only, **no effect on zombies** |
| Program switch | `BanditMenu.SwitchProgram` | global fn on a global table, wrappable |
| "Join Me!" gate | `BanditMenu.lua:214` | requires `program.name == "Looter"` |
| Spawn hostility | `BanditServerSpawner.lua:397` | `brain.hostile = not spawn.friendly` |
| Debug spawn program | `BanditMenu.lua:176` | hardcodes `"Bandit"`, ignores clan flags |
| Per-NPC seed | `brain.rnd` | 5 stable ints, free per-individual variation |

Known caveat: `Bandit.SetHostile` (`Bandit.lua:588`) has its `BanditBrain.Update` call
commented out, so the flag lives only in the client-side brain mirror. Our `trust` value
is stored in `getModData()` and does persist. Expect the number to survive a reload and
the flag possibly not.

## Do not use

- `character:isNPC()` — does not exist in 42.20. Use `instanceof(c, "IsoPlayer")`.
- `zombie:getTarget()` — does not exist in 42.20 Lua. We have **no verified way** to ask
  whether a zombie is chasing someone. Any "feels threatened" behaviour needs a signal
  found in `pzserver/media/` first, not invented.
- `brain.personality` — flavour only (`alcoholic`, `smoker`, collectors). Useless for
  social logic.
- `brain.id` as an identity key — it comes from `getPersistentOutfitID()` and identifies
  an outfit, so two NPCs in the same clothes share it.

## Stages

### Stage 0 — foundation (DONE, confirmed 2026-08-03)

Trust store on the entity, hit and witness penalties, escalation to hostile, engagement
range. **Proved:** an engine event can move a number that changes what an NPC does.

Observed in `logs/console.txt`:

```
9306369:  -25 (attacked)   -> trust  -25 [wary]
9306369:  -25 (attacked)   -> trust  -50 [hostile]
12452221: -10 (saw attack) -> trust  -10 [neutral]
...
12452221: -10 (saw attack) -> trust  -50 [hostile]
```

The witness crossed to hostile on the fifth observed beating, exactly as predicted. The
NPCs also held position instead of running the map, confirming the engagement cap.

### Stage 1 — a way back up (built 2026-08-03, untested)

Trust could only fall. That alone is strictly worse than vanilla Bandits: a way to lose
allies and none to earn them.

The player hits a **non-bandit** zombie within sight of a non-hostile bandit, and that
bandit gains `HELP_REWARD`. Same `OnHitZombie` event, same proximity cache, opposite
sign — the branch is chosen by whether the victim carries the `Bandit` flag.

Two deliberate constraints:

- **Hostile NPCs are excluded.** Killing zombies in front of someone already trying to
  kill you does not make them reconsider. Earning peace back needs to know who made them
  hostile first, which is a separate feature.
- **The reward logs quietly.** `OnHitZombie` fires per swing, not per kill, so only tier
  crossings print. `SR.Adjust` takes a `quiet` flag for exactly this.

**Proves:** trust is a relationship, not a punishment counter.

**Note what this does and does not do yet.** `SR.Apply` only escalates — nothing acts on
positive trust until stage 2 exists. Expect to see the number climb in the log and the
NPC behave the same. That is correct, not broken.

### Stage 2 — asking for something (built 2026-08-03, untested)

`ScenesRelationsMenu.lua` adds our own submenu on any non-hostile bandit: **Follow me**
above `FOLLOW_MIN_TRUST`, greyed out with the required number below it, and **Leave me**
on anyone already following.

Two decisions worth keeping:

- **We decide, Bandits executes.** The switch itself is `BanditMenu.SwitchProgram`
  (`BanditMenu.lua:145`), which sets `brain.master`, replaces `brain.program`, updates and
  syncs. `ZPCompanion` does nothing without `brain.master` (`ZPCompanion.lua:26`).
  Reimplementing that would mean owning their multiplayer sync forever.
- **Refusal is visible, dismissal is not gated.** A hidden option reads as a bug; a greyed
  one reads as a person. And a companion you cannot release is a prisoner, not an ally.

This also sidesteps the Looter blocker. Bandits only offers "Join Me!" on Looters, but
nothing in `SwitchProgram` requires it, so a debug-spawned `Bandit`-program NPC can be
promoted the same way — which is what makes any of this testable at all.

**Proves:** trust gates access, not just aggression.

### Stage 3 — something to do when nobody is shooting

The observed failure right now: capped at 8 tiles, a survivor with no zombie nearby stands
still playing the Shrug animation from `ZPBandit.lua:227`. That branch is Bandits' idea of
"nothing to do", and it is where most of an NPC's life is spent.

An NPC with no purpose cannot read as a person no matter how good the trust maths are.
This is the stage that turns a follower into a companion.

Direction, not yet designed: companions already have `ZPCompanion` behaviour to draw
from, and the task queue (`Bandit.AddTask`, 49 verified actions in `BANDITS-API.md`) is
the mechanism. The question to answer first is what an idle survivor *should* want —
follow, scavenge, keep watch, stay warm — not how to queue it.

**Proves:** an NPC has a reason to be where it is.

### Stage 4 — safety you can feel

The heart of the vision. Today trust rises because you swing at zombies near someone.
That is a proxy. What should actually raise it is **outcome**: they were in danger, you
were there, they lived.

Candidate signals, none verified yet — this stage starts with reading
`pzserver/media/lua/`, not writing:

- an NPC's health dropping while the player is close, and not dropping further
- a zombie that was targeting them dying
- distance held during a fight rather than the player fleeing

The inverse matters as much: getting hurt beside you should cost trust. Someone who leads
you into danger and leaves is not safe, and the system should be able to say so.

**Proves:** the relationship responds to what happened, not to what was clicked.

### Stage 5 — a place worth defending

The village. Companions attach to a location as well as to a person, so the group survives
the player logging off, dying, or walking away.

Bandits already has `BanditPlayerBase` and `ZPCamper` / `ZPDefend`. Whether they can carry
a settlement is an open question and the first thing to investigate when we get here.

**Proves:** the group is a thing in the world, not an escort quest.

### Stage 6 — trust is not one number

Deliberately undesigned until stages 3-5 produce data.

- **A floor, not a drift.** In an apocalypse a stranger starts below neutral. No time
  decay, ever: it fires ~10x per real minute at `DayLength=4`, and worse, it makes
  *waiting* a strategy.
- **Separate axes.** "You fight well" and "you won't stab me" are different judgements.
  That gap is what makes betrayal coherent instead of random.
- **External propagation.** Another NPC reporting what you did. `brain.clan` and the
  proximity cache already exist; nothing new needs inventing.
- **Per-individual variation.** `brain.rnd` gives 5 stable ints per NPC, free.

### Cross-cutting — dialogue

Not a stage, because it is not a prerequisite for any of them and it is the easiest thing
to overbuild. Base Bandits has none (see below), so it is entirely ours.

Build it when there is something worth saying — a companion explaining why it will not
follow, a survivor naming what it wants. A dialogue tree with nothing behind it is a
content treadmill, which the vision explicitly rules out.

### Deferred — threat response

Wanted: NPCs that engage because they feel threatened, not merely because something is
within 8 tiles. Blocked on a verified "is this zombie hunting me" signal;
`zombie:getTarget()` does not exist. Until one is found in `pzserver/media/`, engagement
is proximity and nothing more. Do not fake it with guessed API names.

## Tuning log

Values we have chosen and why, so the next session does not re-litigate them.

| Value | Where | Set | Reason |
|---|---|---|---|
| `HIT_PENALTY = -25` | `ScenesRelationsEvents.lua` | 2026-08-02 | one hit is a warning, two is a decision |
| `WITNESS_PENALTY = -10` | `ScenesRelationsEvents.lua` | 2026-08-02 | seeing costs less than receiving |
| `WITNESS_RADIUS_SQ = 144` | `ScenesRelationsEvents.lua` | 2026-08-02 | 12 tiles, matches `BanditPlayer.lua:97` |
| `ENGAGE_RANGE = 8` | `ScenesRelationsEngagement.lua` | 2026-08-03 | user's call; close enough to read as defence |
| `HELP_REWARD = 2` | `ScenesRelationsEvents.lua` | 2026-08-03 | per swing, not per kill; ~13 swings to `friendly` |

Resolved 2026-08-03: five observed beatings to flip a witness was confirmed in a real log
and left as is for now — it reads as a person taking a while to give up on you.

Open question: `HELP_REWARD` is measured per swing because `Events.OnZombieDead` carries
no attacker argument, so a slow weapon earns trust faster than a fast one. If that shows
up as gamey in play, the fix is a cooldown per NPC, not a smaller number.

## Missing from base Bandits

Things Week One and The Ark provided that plain Bandits does not, confirmed by grep:

- **No dialogue.** No key handler, no conversation UI anywhere in Bandits' Lua. The `T`
  key belonged to Week One. `Bandit.Say` (`Bandit.lua:1161`) is one-way NPC speech.
  Any talking system is ours to build, and it is the natural home for intent-based trust.

## Cleanup owed before anything ships

- `ScenesRelationsRun.lua` is marked TEMPORARY and must be deleted once its questions are
  answered.
- `SR.DEBUG = true` must go back to `false`.
