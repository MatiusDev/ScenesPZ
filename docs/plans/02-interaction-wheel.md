# Stage 02 — the interaction wheel

**Status: built, awaiting its first run. Promoted ahead of memory work after play testing.**

## Why this jumped the queue

The roadmap said memory first, interface second, and that ordering came from a real
finding — Rockstar built RDR2's interaction system *because* NPCs already had memory to
express. It is still right.

But play testing produced a different fact: **the right-click menu was blocking every other
test.** Recruiting meant clicking a moving target and then finding our entry below Bandits'
and vanilla's. That is not a preference about polish; an interface you cannot drive makes
everything behind it unmeasurable.

And the precondition the RDR2 lesson actually asks for is already met. Trust moves, it is
durable, and it gates decisions. There *is* something to express. Building the surface now
is consistent with the principle rather than a violation of it.

## Deliverables

### 1. Decisions moved out of the menu

`ScenesRelationsActions.lua`. One function, `SR.Actions.List(player, bandit)`, returns every
action for this person right now — each with a label, whether it is available, and if not,
why. The wheel draws it. The old context menu draws it. Persuasion will draw it as floating
text.

One place decides, several places draw. The previous version had the rules tangled inside
the right-click handler, which is why replacing the interface looked like it meant
rewriting the rules.

### 2. The wheel

`ScenesRelationsWheel.lua`. Hold the key, the wheel opens on the nearest survivor you can
see within 8 tiles, release over a wedge to act.

Three things worth knowing about how it is built:

- **Our own `ISRadialMenu` instance**, not `getPlayerRadialMenu(0)`. Vanilla's shared menu
  is what the emote wheel uses; borrowing it would mean fighting emotes for the same
  object.
- **Release-to-select is ours.** `ISRadialMenu` only acts on a mouse click (line 18) or a
  joypad button release (line 106) — on keyboard, releasing vanilla's emote key just hides
  the wheel. Asking the slice under the cursor ourselves on release is three lines and is
  what makes hold-and-release behave like a wheel. Clicking still works.
- **No aiming at anybody.** The target is chosen by proximity plus line of sight, from the
  cache Bandits already maintains. Line of sight matters: without it you would be talking
  through a wall to somebody in the next room.

Default key **V**, registered in Options → Key Bindings so a collision is a rebind rather
than a code change.

### 3. Talk — the first way in that is not violence

Trust rose well when fighting beside somebody and had no other path at all. Now it does.

`+4` trust, cooldown half an in-game hour (roughly three real minutes). Available to a
complete stranger on purpose — the PRD is explicit that nobody trusts you on sight, so
conversation has to be the entry. Refused at the `hostile` tier: somebody who has decided
you are dangerous is past talking.

Deliberately slower than fighting beside them. What you risk for a person outranks what you
say to them, and that hierarchy should stay visible.

### 4. Refused actions are shown, not hidden

`Follow me (needs 25 trust)` stays on the wheel, inert. Hiding it would make the
relationship invisible — the player would never learn that following is four conversations
away rather than impossible.

### 5. Feedback lands on the player

`HaloTextHelper.addGoodText(player, …)`. Every vanilla callsite passes a player, and
whether the Java side accepts an `IsoZombie` is still unproven. When that probe comes back
positive, one function in `ScenesRelationsActions.lua` moves and everything above the NPC's
head starts working.

### 6. No sound for Talk, on purpose

`Bandit.SoundTab` holds sixteen phrase keys (`Bandit.lua:4-19`) and none of them is a
greeting. Forcing `SPOTTED` would sound wrong. Silence is better than the wrong voice line.

### 7. Added after the first run of the wheel

Play testing approved the wheel and found three things wrong with it. All three are in
scope for this stage because they are the same surface.

**Labels were invisible until hovered.** `ISRadialMenu` only draws a slice's text when the
cursor is already over it, so finding out what the wheel offered meant hovering each wedge
in turn. We now draw the action name inside every wedge ourselves, plus an icon per action
using only texture paths that appear verbatim in `ISEmoteRadialMenu.lua:57-80`.

One risk stated plainly: the Java side draws the wedges and does not expose where slice
zero begins, so the label positions are computed. If they read one wedge out of step it is
two constants — `FIRST_SLICE_ANGLE` and `CLOCKWISE`.

**The trust number left the wheel** and became `ScenesRelationsPanel.lua`, a Sims-style
window on a key: one row per person, a bar running the full -100..100 with a line at zero.
The full range matters — a bar that only grew rightwards from empty would make *distrusted*
look identical to *unknown*, and those are very different situations. It reads the durable
store rather than the world, so it lists people whose cell is unloaded, which makes it the
first honest view of whether stage 01 actually worked.

**Accidental hits no longer cost the relationship.** `ScenesRelationsGuard.lua`, default on,
toggled by a key. There is no cancellable pre-damage event in 42.20 — the complete list is
`OnHitZombie`, `OnWeaponSwingHitPoint`, `OnPlayerAttackFinished`, `OnWeaponHitTree`,
`OnWeaponHitXp`, and none can abort a swing — so this cannot prevent the blow, it undoes
it. Skipping the trust penalty is guaranteed and is the whole of the reported problem;
restoring hit points is best effort, since `setHealth` on an `IsoZombie` is unverified.

The guard check lives inside `ScenesRelationsEvents.lua` rather than in a handler of its
own: both files listen to `OnHitZombie` and Events sorts first alphabetically, so a
competing handler would apply the penalty before the guard could stop it.

### 8. Making the memory test possible at all

`ScenesRelationsMemoryTest.lua`. Stage 01's test was written as "walk ten blocks away",
which was simply wrong — a cell is 300 by 300 tiles, so ten blocks unloads nothing, and
doing it properly costs minutes of walking per attempt. Reported as impractical.

Two key presses now teleport the player 700 tiles out and back, using the same `teleportTo`
vanilla's debug tools use. It does not fake the unload; it triggers the real one. The
verdict is read from the store by id and printed in words, and it deliberately reports
"is a body with that id loaded" as a *separate* line — an NPC that wandered off is not the
same finding as an NPC that forgot you.

## Done when

- Holding V near a survivor opens a wheel showing their name and trust.
- Releasing over a wedge performs it; releasing over nothing closes it harmlessly.
- Talking raises trust and cannot be spammed.
- Trust reaches 25 and `Follow me` stops being greyed out, in one continuous session,
  without touching the right-click menu once.
- `ScenesRelationsMenu.lua` can then be deleted.

## Kept for exactly one build

The right-click menu still works and now renders the same list. There is no hot reload
here: a wheel that fails to open would otherwise leave no way to recruit anybody. It goes
the moment the wheel is confirmed.
