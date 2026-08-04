# Stage 03 — idle life

**Status: built, and FOLDED INTO [03-autonomy.md](03-autonomy.md) as rung 5.**
The code stands; what changed is its place. Play showed that adding idle behaviour without
an arbitration layer above it just gives an NPC one more thing to be doing while it dies.
Containers, lost possessions and trading are the rest of the stage and wait on this
one being confirmed in a real session.

> *"Les hace falta actividades aleatorias… si ven un sombrero en el suelo haya una
> probabilidad de que lo guste, lo recoja y se lo ponga. Si tiene un sombrero suyo, y se le
> cayó al saltar una valla, que quiera recuperarlo. Que se interesen por lootear cuando
> estén en una casa."*

## The problem

An NPC that only fights and follows is a turret with a name. Pillar 4 of the PRD says they
have lives that do not include you, and right now they visibly do not — which is why the
whole thing still reads as green no matter how good the trust maths gets.

## The good news, verified

This is wiring, not building. Every verb already exists as a Bandits task action:

```
ZAPickUp   ZAEquip   ZADrop   ZALootItems
ZALootWeapons   ZATakeFromContainer
```

Only `ZPThief` and `ZPBandit` reference any of them. Nothing in the framework decides that
an ordinary survivor might want something. **The missing piece is a reason, not a
mechanism.**

## Deliverables

### 1. A wants list, seeded from traits

Each NPC carries a small set of things it would pick up if it saw one. Derived from
`brain.rnd` so it is fixed per person and free to compute — the same seed stage 05 will use
for traits proper.

This is what makes it a character rather than a dice roll. The one who takes every hat
takes every hat, every time, and you learn that about him.

### 2. Notice, want, take, wear

On a slow tick, an idle NPC scans nearby ground for items. If something matches its wants
and it is not busy, it queues `GoTo` → `PickUp` → `Equip`.

**Idle is the hard part, not the queue.** Bandits programs only run when the task queue is
empty, so the whole behaviour is one question: is this person actually free right now, or
merely between two things. Getting that wrong means an NPC that walks away from a fight to
pick up a cap.

### 3. Losing things, and going back for them

The engine already drops carried items in some transitions. When an NPC loses something it
owns, remember where, and let it want that spot back once the immediate danger has passed.

Stored in `SR.Mood`, not the durable record — it is a current intention, not a memory of
the player. Emotion and memory stay separate.

### 4. Looting a building they are inside

`Defend`-program survivors already live in houses as of stage 00. An idle one inside a
building can queue `TakeFromContainer` on nearby containers.

The restraint that matters: **they must not strip the house the player is about to loot.**
An NPC that empties every cupboard before you arrive is not a character, it is a tax. Low
probability, slow cadence, and only while genuinely idle.

## Done when

- Drop a hat in front of a survivor. Some survivors pick it up and put it on; others walk
  past. The same one behaves the same way twice.
- A survivor separated from something it owns goes back for it once things are quiet.
- Survivors inside a house occasionally open containers, without emptying the place.
- None of the above ever interrupts a fight or a follow order.

## How it is tested

1. Recruit a companion with the wheel.
2. Drop a hat, a bag and a weapon on the ground in front of it. Watch.
3. Repeat with a second survivor — the two should not behave identically.
4. Trigger a zombie fight mid-pickup. **It must abandon the item.**
5. Walk into a house with `Defend` survivors and watch them for a few in-game hours.

Step 4 is the one that fails. Everything else is decoration if an NPC can be distracted by
a cap while something is biting the player.

## Deliberately not in this stage

No trading, no giving items to the player, no asking for anything. That is stage 07, and it
needs the wheel proven first.
