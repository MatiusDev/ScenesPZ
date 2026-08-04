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
