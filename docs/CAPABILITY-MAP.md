# Capability map

Started 2026-08-03. **Organised by intention, not by file.** You say what you want to
happen; this says which verified mechanisms can do it, and what each one costs.

## Why it is shaped like this

A complete index of 2,680 vanilla Lua files plus Bandits plus Week One would be a
catalogue nobody reads and that goes stale in one patch. The failure this document exists
to fix is different and specific: **solutions were taking the shape of whatever API I
happened to look up first.** The right-click menu for Follow me / Join me is the evidence
— it works, and it is the wrong interaction, chosen because the context menu was the
mechanism already in front of me.

So the unit here is a question a designer actually asks. Everything listed is verified in
42.20 source. Anything unverified is marked and must be probed before it is designed
against.

Sections fill in as work touches them. An empty section is honest; a guessed one is how
this project lost two sessions to `isNPC()`.

---

## "I want to show the player something"

| Mechanism | Looks like | Verified at | Cost / limit |
|---|---|---|---|
| `HaloTextHelper.addText(char, text, color)` | text floating above a character, drifts up and fades | vanilla, many callsites | one line, no interaction, disappears |
| `HaloTextHelper.addGoodText` / `addBadText` | same, pre-coloured green / red | vanilla | same |
| `Bandit.Say(zombie, phrase, force)` | NPC speech with voice audio | `Bandit.lua:1161` | **only 15 fixed phrase keys**, self-limits to 14 tiles |
| `ISToolTip` | hover panel, multi-line, rich | `ISUI/ISToolTip.lua` | needs an owning UI element |
| Context menu option label | text in the right-click list | in use by us now | only visible while the menu is open |

`HaloTextHelper` is the cheapest way to make an NPC's inner state visible without a UI. A
survivor whose trust just crossed a tier could say so in green above its head, and the
player would never need to read a log or open a menu.

**Settled 2026-08-03, and the answer is no.** `HaloTextHelper` does **not** accept an
`IsoZombie`. The probe threw and the engine said why:

```
java.lang.RuntimeException: No implementation found for function:
addText(class zombie.characters.IsoZombie ..., class java.lang.String SCENES probe)
```

The method exists on the shared base class, every vanilla callsite passes a player, and the
Java binding simply has no `IsoZombie` overload. So the "floating indicator above the NPC"
idea is dead in this form — all feedback renders above the **player**. Making an NPC's
inner state visible in the world needs either `Bandit.Say` (16 fixed phrases, with voice)
or a custom drawn overlay.

**The wider lesson, worth keeping:** a method existing on `IsoGameCharacter` does not mean
it is bound for `IsoZombie`. Two separate findings the same day landed on this, so treat
every character API as player-only until a probe says otherwise.

## "I want the player to trigger something"

| Mechanism | Feels like | Verified at | Cost / limit |
|---|---|---|---|
| `Events.OnKeyStartPressed` / `OnKeyKeepPressed` / `OnKeyPressed` | a keypress | `ISEmoteRadialMenu.lua:266-268` | must not collide with vanilla or other mods |
| `ISRadialMenu` | hold a key, a wheel appears, release to pick | `ISUI/ISRadialMenu.lua`, four vanilla users | one hand-shaped choice, no submenus |
| `Events.OnPreFillWorldObjectContextMenu` | right-click list | Bandits `BanditMenu.lua:248`, us | crowded, slow, needs a precise click on a moving target |
| Custom `ISPanel` window | a real UI | vanilla ISUI | most work, most control |

**The emote wheel is the closest working model to what a good NPC interaction wants.**
`ISEmoteRadialMenu` binds hold-a-key, draws a wheel, and acts on release. It is vanilla,
it is four files of precedent, and it solves exactly the problem the context menu has:
you are not clicking a moving target through a list of unrelated options.

## "I want to know who the player means"

| Mechanism | Answers | Verified at |
|---|---|---|
| `BanditCompatibility.GetClickedSquare()` | the square under the cursor | `BanditMenu.lua:185` |
| `square:getZombie()` + S/W neighbours | which NPC is there | `BanditMenu.lua:188-200` |
| `BanditZombie.CacheLightB` | every bandit near, with x/y/brain | ours, in use |
| `zombie:CanSee(character)` | line of sight | ours, in use |

Note the asymmetry: pointing at **one** NPC is fiddly because it is moving. Selecting
**everyone nearby** is trivial — the cache is already there. That inverts the usual
assumption, and it is why "talk to the group" may be both easier to build and better to
play than "talk to this one person".

## "I want an NPC to do something"

| Mechanism | Scope | Verified at |
|---|---|---|
| `Bandit.AddTask` / `AddTaskFirst` | one action, now | `Bandit.lua:300` |
| 49 task actions | the verb list | `docs/BANDITS-API.md` |
| `Bandit.SetProgram` | change role wholesale | `BANDITS-API.md` |
| `ZombiePrograms.<Name> = {...}` | **register our own behaviour** | dispatch at `BanditUpdate.lua:1894` |
| `BanditMenu.SwitchProgram` | role change + master + sync | `BanditMenu.lua:145` |

Relevant verbs already shipped and unused by any Bandits program: `LootWeapons`,
`LootItems`, `TakeFromContainer`, `Equip`, `OpenWindow`, `SmashWindow`, `Destroy`.
Scavenging behaviour is a matter of choosing when, not of building how.

### "…somewhere else" — always through one walk-then-act primitive

`BWOAPrograms.GoAndDo(bandit, point, task, precision, checkCollision, run)` — The Ark,
`BWOAPrograms.lua`. **Every** one of its dozen go-somewhere-and-do-something decisions
(`Collect`, `Cook`, `CleanFloor`, `PutContainer`, `InsertVHS`) goes through this one function,
and none of them has the class of bug described in R13.

```lua
local asquare = square
if not square:isNotBlocked(false) then
    asquare = BanditUtils.GetAccessSquare(square, bandit)     -- BanditUtils.lua:1039
end
local collide = LosUtil.lineClearCollide(bx,by,bz, ax,ay,az, false)
if dist > precision or collide then
    return { BanditUtils.GetMoveTask(0, ax, ay, az, walkType, dist, false) }  -- move ONLY
else
    return { task }                                                          -- action ONLY
end
```

Four things worth taking, in order of how much they cost to learn the hard way:

| What | Why it matters |
|---|---|
| **Move or action, never both** | A move task guarantees it *ended*, not that it *arrived*. See R13 — this cost three sessions. |
| `BanditUtils.GetAccessSquare(square, bandit)` | Bandits' own adjacent-tile finder. Takes the bandit and uses it (`square:DistToProper(bandit)`, `:1064`), so it returns the free neighbour **closest to this NPC**, and rejects any with a wall between (`isWallTo`, `:1054`). Vanilla's `AdjacentFreeTileFinder.Find` does neither. |
| Only when blocked | `if not square:isNotBlocked(false)`. A container on an open tile is stood on, not walked around. |
| `LosUtil.lineClearCollide` | Close in a straight line is not close. Without it an NPC reaches through a partition wall. |

`precision` defaults to **0.7** tiles. Our first version used 1.6, then 0.9, both invented.

### Deciding and taking are different layers

`ZACollect` (The Ark) takes exactly ONE named type — `item:getFullType() == task.item.ftype`,
`ZACollect.lua:89` — and returns. It has no opinion about what is worth having. The opinion
lives in the program: `BWOABaseObjects.FindClosestItemClass("food", …)` picks the target, and
only then is a `Collect` task built for it.

Ours cannot copy that wholesale, because bounded incidental hauling — *"they must not strip
the house"* — means taking things nobody named. So our filter lives in the action instead
(`Loot.IsWorthTaking`). **Same conclusion, different layer**, and knowing which is which is
what stops the next feature from being bolted to the wrong one.

## "I want an NPC to feel something"

| Mechanism | State | Verified |
|---|---|---|
| `zombie:getStats():get(CharacterStat.X)` | **binds fine, never ticks** — 12 stats frozen over 10 sweeps | probed 2026-08-04 |
| `zombie:getBodyDamage()` | binds, but nothing in Bandits writes to it | probed 2026-08-04 |
| `zombie:getMoodles()` | binds; unused by the framework | probed 2026-08-04 |
| `zombie:getHealth()` / `setHealth()` | **the real live condition**, scale 0..`brain.health` | `BanditUpdate.lua:500`, `ZABandage.lua:50` |
| `zombie:addVisualBandage(BodyPartType.X, true)` | works on an NPC | `ZABandage.lua:51` |
| `brain.health` | **spawn MAXIMUM, not live health** — set once, never updated | `BanditServerSpawner.lua:332` |
| `brain.endurance` / `infection` / `sleep` | Bandits' own parallel model | `Bandit.lua:423` |
| `brain.rnd` | 5 stable ints per NPC, free variation | `BanditServerSpawner.lua:375` |
| `getModData().scenesRel` | ours: trust, memory, posture | ours |

**RETRACTED, same day.** A first probe called `stats:getPanic()`, `stats:getThirst()` and
four more, got `ok=false` on all six, and the conclusion recorded here was "the binding does
not exist for a zombie, emotion must be simulated". That was wrong, and the probe was the
thing at fault.

**Build 42 has no such methods at all — not even for the player.** The real API is one
generic accessor over an enum:

```lua
character:getStats():get(CharacterStat.THIRST)
```

54 callsites in vanilla. And `CharacterStat` carries **24 values**, far more than was being
asked for:

```
PANIC  STRESS  ANGER  MORALE  SANITY  UNHAPPINESS  BOREDOM  IDLENESS
PAIN   FATIGUE  ENDURANCE  FITNESS  HUNGER  THIRST  WETNESS  TEMPERATURE
DISCOMFORT  SICKNESS  POISON  INTOXICATION  FOOD_SICKNESS
NICOTINE_WITHDRAWAL  ZOMBIE_FEVER  ZOMBIE_INFECTION
```

It is also demonstrably **not** player-only: `ISAnimalContextMenu.lua:30` and
`ISVehicleAnimalUI.lua:43` call `animal:getStats():get(CharacterStat.HUNGER)` on an animal.
So the accessor lives on the shared base and is bound for non-player characters — the
opposite of the `HaloTextHelper` result above.

**ANSWERED 2026-08-04: `PROBE stat VERDICT FROZEN`.** The engine does **not** tick those
values for a zombie. Ten sweeps, twelve stats, zero movement:

```
PROBE stat | PANIC ok=true value=0        PROBE stat | PAIN ok=true value=0
PROBE stat | STRESS ok=true value=0       PROBE stat | ANGER ok=true value=0
PROBE stat | FATIGUE ok=true value=0      PROBE stat | MORALE ok=true value=1
PROBE stat | THIRST ok=true value=0       PROBE stat | SANITY ok=true value=1
PROBE stat | HUNGER ok=true value=0       PROBE stat | UNHAPPINESS ok=true value=0
PROBE stat | ENDURANCE ok=true value=1    PROBE stat | BOREDOM ok=true value=0
```

Note what the verdict is and is not. **The binding works** — `ok=true` on all twelve, which
is the correction above holding up. What does not happen is the simulation: nothing in the
engine writes to those fields for an `IsoZombie`, so they are a readable surface with no
author. A hunger bar for an NPC would be a bar that never moves.

**Consequences, both already taken:**

- Emotion is **simulated by us**, on `SR.Mood`, and half of stage 06 stays in scope.
  `ScenesRelationsAutonomy.lua` carries fear as a decaying average because there was no
  engine value to read instead.
- The NPC health panel shows Bandits' own model — `getHealth`, `brain.infection` — and says
  on its face that needs are not simulated, rather than drawing empty bars that look broken.

`getBodyDamage()` deserves the same caveat: it answers `ok=true` under the corrected probe,
but nothing in Bandits ever writes to it, so a vanilla-style body diagram for an NPC would
render zeroes forever.

**And one field that is NOT what its name suggests.** `brain.health` is the SPAWN MAXIMUM,
written once as `BanditUtils.Lerp(health, 1, 9, 1, 2.6)` at `BanditServerSpawner.lua:332`
and never touched again. Live condition is `bandit:getHealth()` — that is what the bleed-out
loop drains (`BanditUpdate.lua:500`) and what their own Bandage action resets
(`ZABandage.lua:50`). Reading `brain.health` as current health cost this project a whole
session: the fear model's hurt term and the wheel's "how are you holding up" were both
reading a per-person constant.

**The lesson is the reverse of the one above and worth holding both at once.** `isNPC()`
failed because an identifier was copied without checking it existed. This failed because
an identifier was *invented* from a plausible naming convention. Grepping vanilla for how
it actually calls the thing would have caught both in under a minute.

## "I want something to happen in the world"

Barely mapped. Known so far:

- `Events.EveryOneMinute` — in-game minute, ~6 real seconds at `DayLength=4`
- `Events.EveryTenMinutes`, `Events.OnGameStart`
- `Events.OnHitZombie(zombie, attacker, bodyPart, weapon)` — target first
- `BanditZombie.Cache` refreshed from `cell:getZombieList()` (`BanditZombie.lua:110`)

**Unmapped and needed for the "NPC asks you to rescue his wife" idea:** how a scripted
situation gets placed in the world at all — spawn triggers, map markers, whether an NPC can
approach the player unprompted. This is the next section to fill.

---

## "I want an NPC to keep the things it picked up"

Vendored 2026-08-05 as `vendor/TheArk` (Workshop `3707475814`, 50k subs, updated the same day
as Bandits). Same author as Bandits and Week One, and the first place he solved this problem
properly. Paths below are relative to
`vendor/TheArk/mods/BanditsWeekOneTheArk/42.20/media/lua/`.

**The conclusion is independent and it matches ours.** `zombie:getInventory()` does not
survive a despawn, so The Ark keeps a parallel inventory **on the brain**: `brain.permaInv`,
in `shared/BWOAPermaInv.lua`. We reached the same shape from the log alone before this mod was
vendored, which is about as strong as corroboration gets.

| Mechanism | What it gives | Verified at |
|---|---|---|
| `BWOAPermaInv.Add(bandit, item)` | writes an `itemConf` onto `brain.permaInv` and syncs | `BWOAPermaInv.lua:11` |
| `BWOAPermaInv.Use(bandit, type, n)` | partial consumption — decrements `size` and **scales every nutrition field** | `:71` |
| `BWOAPermaInv.Has / HasType / HasClass` | "does this person have an X" without touching the live inventory | `:127 / :158 / :190` |
| `BWOAItems.GetItemClass(item)` | `media` / `food` / `food_packaged` / `drink` / `clothing` / `normal` | `BWOAItems.lua:3` |

### Where his is better than ours, concretely

Our `brain.scenesCarry` stores **full types only**. His stores state, and the difference is
not cosmetic:

1. **Item state survives.** `cooked`, `weight`, `dirtiness`, `bloodLevel`, `wetness`, and the
   whole nutrition block. Ours brings a half-drunk bottle back full — a limitation we marked
   with a `ponytail:` comment and he simply does not have.
2. **Partial use exists.** `size` plus proportional scaling of every nutrition field. Ours has
   no notion of eating half of something.
3. **Every mutation syncs.** `Bandit.ForceSyncPart(bandit, {id=..., permaInv=...})`
   (`BWOAPermaInv.lua:3-9`). **Ours does not sync at all**, which is a multiplayer defect in
   our code by principle 3 — the client/server boundary is real even in singleplayer.

### Also worth taking, separately

`GetItemClass` splits **`food` from `food_packaged`** by asking
`item:getOpeningRecipe() or item:getDoubleClickRecipe()` (`BWOAItems.lua:9`). That is a real
distinction our `Loot.GoalOf` is missing: a tin of beans with no opener is not food to an NPC,
and today we would count the goal satisfied.

It also uses `item:isFood() and not item:isPoison()` where we use `instanceof(item, "Food")`.
His excludes poison; ours does not.

> **Not yet applied.** Deliberately. Block A is being tested on the gaming PC and rewriting the
> storage model first would mean tomorrow's run measures something changed blind. Scheduled in
> `docs/TODO.md` for after block A passes.

---

## Applied: the Follow me / Join me problem

The current design puts two options in a right-click menu on a moving target, below
Bandits' own entries and vanilla's. It works and it is bad. Three alternatives, all built
from mechanisms verified above:

1. **Interaction wheel on a key.** Hold a key near NPCs, a radial menu appears with the
   actions available *right now*, release to choose. Follows `ISEmoteRadialMenu` exactly.
   Best fit for one clear intention, no clicking on a moving target.
2. **Group panel.** A key opens a small window listing every NPC nearby with name, trust
   and current state, each row with its available actions. Solves the thing the context
   menu cannot: acting on several people at once, which the cache makes almost free.
3. **Halo feedback, whatever the input.** Independent of the above, and probably required
   by both: the NPC's answer appears above its head rather than in a log. Trust crossing a
   tier, a refusal, an acceptance.

These are not exclusive. 3 is cheap and improves 1 and 2. Whether the primary interface is
a wheel or a panel is a PRD decision, not a technical one — both are reachable.
