# Code review rules

Every rule here was written after a real bug in this project cost a play session. None of
them are general good practice — they are the specific ways Project Zomboid modding has
already bitten us, in the order the money was lost.

The reviewer's job is not to find style problems. It is to answer one question per rule,
with evidence, before the build reaches the gaming PC. **There is no hot reload here.** A
bug that ships costs a sync, a restart, and a context switch to another machine.

---

## R1 — Every identifier must be grepped before it is written

**Cost so far: three bugs, two of them multi-session.**

| Bug | How it happened |
|---|---|
| `character:isNPC()` | **Copied** from vendored Bandits code without checking it existed. Threw on every hit for two sessions; trust never moved and we blamed the design. |
| `stats:getPanic()` | **Invented** from a plausible naming convention. Six accessors, all false, and the wrong conclusion recorded in three documents. |
| `Bandit.Say(z, "PANIC")` | **Invented** a phrase key. Caught before commit only by luck. |

Both failure modes produce the same review question:

> For every engine or upstream identifier in the diff, is there a grep of
> `pzserver/media/` showing a real callsite?

**Vendored mod code is not a verification source.** Bandits calling something proves
Bandits calls it, not that it exists — `isNPC()` came from `BanditPlayer.lua:91` and is
still broken there today.

**The API is often not shaped the way the name suggests.** `getPanic()` felt obvious;
Build 42 actually uses `getStats():get(CharacterStat.PANIC)`. Grep for how the game calls
the thing, not for whether a word appears somewhere.

---

## R2 — A method verified on one class is not verified on another

**Cost so far: one dead design branch, one wrong conclusion, and one bug that broke four
things at once across three play sessions.**

R1 asks whether a real callsite exists. That question can be answered **yes** and the code
can still be wrong, because a callsite proves the method works on the class in *that*
callsite — not on the class you are about to call it on.

> Name the receiver. Not "does `getBodyLocation` exist" but "does `getBodyLocation` exist
> **on the thing I am passing it**".

### The item case, 2026-08-05

`isBag(item)` tested `item:getBodyLocation() == "Back"`. `getBodyLocation()` is real, has
**107 callsites** in `pzserver/media/lua/`, and returns exactly what you expect. On
**clothing**. A bag is an `InventoryContainer` and declares itself with
`CanBeEquipped = base:back` (`media/scripts/generated/items/container.txt:57`) — it has no
`BodyLocation` field at all, so the predicate was false for every rucksack in the game.

Four separate symptoms, all reported from play, all one wrong receiver: bags on the floor
were never seen, the goal "find a bag" could never be satisfied, the priority pass in the
loot action never matched, and a bag pulled out of a drawer was never worn.

Corroborated after the fact in third-party code: Week One, an independent Bandits addon,
tests a bag with `instanceof(item, "InventoryContainer")` (`BWOEvents.lua:2401`) and reaches
for `getBodyLocation()` only inside `Variants/`, on gowns and prison suits. Two different
questions, two different methods. Vanilla draws the same line at `ISInventoryPane.lua:967`.

**A silent wrong answer is worse than a crash.** `isNPC()` threw and we found it in two
sessions. This one returned `false` politely and survived three.

### The character case

Bandits NPCs are `IsoZombie`. Vanilla almost never calls character APIs on a zombie, so
the Lua binding frequently does not exist even when the Java method does.

Proven negative:

```
java.lang.RuntimeException: No implementation found for function:
addText(class zombie.characters.IsoZombie ..., class java.lang.String ...)
```

Proven positive: `getStats():get(CharacterStat.HUNGER)` works on an **animal**
(`ISAnimalContextMenu.lua:30`), so that one is bound for non-players.

> Does the diff call a character method on an NPC? If yes, is there a vanilla callsite
> passing something that is not an `IsoPlayer` — or a probe result in the log?

Unverified is not the same as broken. It means it must sit behind a probe with a one-time
log line, never behind a silent `pcall`.

---

## R3 — `pcall` does not make a failing call safe

**Cost so far: 511 exceptions in one session, a 3 MB log, and the real findings buried.**

`pcall` catches the Lua error. **The engine still logs the Java exception.** A guarded call
that fails in a per-frame function produces thousands of stack traces and drowns every
other line in the log — which is the only debugging tool this project has.

> Is any `pcall` in the diff inside `render`, `prerender`, `OnTick`, or an event that
> fires per frame or per swing? If so it must be preceded by a real check, not wrapped in
> hope.

Correct use of `pcall`: a **one-time probe** whose failure is logged once and remembered
in a flag. Incorrect use: making a call you have not verified, every frame, forever.

---

## R4 — Per-frame code is a different risk class

Anything reaching `render`, `prerender`, `OnTick`, `OnWeaponSwingHitPoint` or
`OnHitZombie` runs thousands of times per minute. `BanditUtils.AreEnemies` already runs
460,361 times a minute in this game.

> For each new per-frame line: what does it allocate, what can it fail on, and what does
> it log? A line that logs on a per-frame path is a bug even when it is correct.

---

## R5 — Textures and assets may not exist even when vanilla names them

**Cost so far: the sidebar buttons drew as nothing, then crashed per frame.**

`media/ui/emotes/stop.png` appears verbatim in `ISEmoteRadialMenu.lua`. `getTexture` still
returned `nil` — a string being present in a shipped Lua file does not mean the asset
resolves in our context.

> Does the diff call `getTexture`? Is the result checked before use, and does the UI still
> work when it is nil?

If the answer to the second is "the button is invisible", that is a failure, not a
fallback. Prefer text we draw ourselves over art we hope is there.

---

## R6 — One rule lives in one place

**Cost so far: the talk cooldown existed twice and immediately diverged.**

Two surfaces — the wheel and the context menu — each had their own copy of "how much does
talking give and how often". The wheel's questions bypassed the cooldown entirely.

> Does the diff add a second implementation of an existing rule? Trust maths, cooldowns,
> gating thresholds and program switches belong in exactly one function.

---

## R7 — Every file announces itself

**Cost so far: an hour arguing about whether a file loaded.**

A Lua file that throws while loading registers none of its event handlers and fails
completely silently.

> Does every new file log a `ready` line on `OnGameStart`? Does it `require` the vanilla
> classes it uses rather than assuming globals are loaded?

`ISScrollingListBox` and `ISButton` were both assumed. Either being nil at load kills the
file including its own `ready` line — the exact signal you would use to diagnose it.

---

## R8 — Extend, never replace

Wrapping is mandatory for anything vanilla or upstream:

```lua
local original = ISEquippedItem.createChildren
function ISEquippedItem:createChildren()
    original(self)
    ...
end
```

> Does the diff assign over a vanilla or Bandits function without calling the original?
> Would a second mod wrapping the same function still work, in either order?

The one deliberate exception in this codebase is `ScenesRelationsBanditPatch.lua`, and it
says why in its own header.

---

## R9 — Handler order is part of the contract

**Cost so far: nearly shipped a guard that could never fire.**

Files in the same directory load alphabetically, and event handlers run in registration
order. `ScenesRelationsEvents.lua` sorts before `ScenesRelationsGuard.lua`, so a guard
registered as its own `OnHitZombie` handler would have run *after* the penalty was already
applied.

> Do two of our files handle the same event? Which registers first, and does the diff
> depend on an order that alphabetical loading actually produces?

---

## R10 — Data and identifiers in declarative files

- Item ids must resolve. `tools/lint.sh` checks this against 6,359 definitions — run it.
- A comment line in a Bandits `.txt` must never contain both a colon and an equals sign;
  the parser at `BanditCustom.lua:146` has no comment syntax and will read it as a field.
- A clan can never spawn more NPCs at once than it has distinct definitions
  (`BanditServerSpawner.lua:450-468`).

---

## R11 — Say what is not built

An option that silently does nothing is indistinguishable from a bug. Anything unfinished
must announce itself through `SR.Wheel.NotYet(...)` so there is one call site to delete
when it lands.

> Does the diff add a control that does nothing? Does it say so to the player?

---

## R12 — Look for prior art before building something new

**Cost so far: unmeasured, and that is the point — we do not know how much of what we wrote
already existed, done better, in a mod somebody has been maintaining for a year.**

Asked for in these words:

> *"antes de implementar una nueva solución de algo nuevo se pueda mirar el workshop a ver
> que hay similar creado, leer rápidamente similares y obtener información que sea de
> utilidad de que usan."*

Before writing a **new mechanism** — not a tweak, a mechanism — spend the cheap minutes
first:

1. **Local first, and it is usually enough.** `vendor/` already holds Bandits and Week One,
   two shipped mods by an author with far more Build 42 hours than us. `pzserver/media/` is
   the engine itself. Both are greppable in under a second and cost nothing to consult.
2. **Then the Workshop**, via `tools/workshop.py search`, for mods solving the same problem.
   Read what they *call*, not how they format.
3. **Write down what you found**, in `docs/CAPABILITY-MAP.md` under the question it answers,
   with the file:line. A finding nobody can look up later was not worth the minutes.

### What this is and is not

It is **corroboration**, and corroboration is the point. Two independent codebases choosing
the same method is much stronger evidence than one vanilla callsite — and it is exactly what
would have caught R2's bag bug, since Week One had the right answer sitting in `vendor/` the
whole time.

It is **not** a style survey. The code shipped on 2026-08-05 was well formatted and wrong.
Copying somebody's naming conventions prevents nothing.

And R1 still applies to everything it turns up. **Vendored mod code is not a verification
source** — Bandits has carried a broken `isNPC()` for as long as we have been reading it.
Prior art tells you *where to look*; the engine tells you what is true.

> Does the diff introduce a new mechanism? Is there a note saying what prior art was checked
> and what it uses — or a stated reason none applies?

---

## The review output

Findings only, most severe first, each with:

- **file:line**
- **what breaks**, as a concrete scenario with inputs
- **the rule number** it violates
- the evidence — a grep result, a log line, a vanilla callsite

No praise. No style notes unless they change meaning. If a finding cannot be stated as
"this input produces this wrong output", it is not a finding.

**Verify before reporting.** A reviewer that invents a bug costs exactly as much as code
that contains one — every claim here needs the same grep discipline R1 demands of the
code.
