# Stage 03 — autonomy

**Status: designed, not built. Replaces the direction of the idle-life slice, which becomes
the lowest rung of the ladder below.**

## The insight this stage exists because of

From play, and it is the most useful thing anybody has said about this mod:

> *"Muchas de las cosas que he mencionado, he visto que las tiene, pero no ordenan bien su
> cola de actividades y no las priorizan, algunos hasta se buguean abriendo una ventana y
> se quedan abriéndola, y terminan siendo mordidos por la espalda."*

That reframes the whole problem. **Bandits already has the behaviours.** It has 49 task
actions and 8 programs; survivors already loot, climb, open windows, shelter and fight.
What they do not have is anybody deciding **which of those matters most right now**, and
the visible symptom is not a missing feature — it is an NPC still working the window latch
while something eats it.

So this stage builds no new verbs. It builds the thing that chooses between them.

## The ladder

One question, asked on a slow tick: what rung is this person on? The highest rung whose
condition is true wins, and moving **up** a rung clears the task queue outright.

| Rung | Fires when | What it does |
|---|---|---|
| 1. Survive | cornered, badly hurt, or fear over their limit | break away, get behind a door, stay there until it is quiet |
| 2. Fight | a threat is close and they are not too afraid of it | engage — and *stop* when it is dealt with |
| 3. Obey | the player gave an order and they accepted it | follow, hold, come here |
| 4. Errand | they want something specific — a bandage, their dropped bag | go get it, abandoning it if a higher rung fires |
| 5. Idle | nothing else | the hat, the backpack, the cupboard: the existing slice |

**Clearing the queue is the whole mechanism.** `Bandit.ClearTasks` already exists and
Bandits uses it itself when an NPC turns (`BanditUpdate.lua`, the Zombify branch). Without
that call a new intention just queues behind the old one — which is exactly the reported
bug: an NPC finishing a window animation it decided on ten seconds and one emergency ago.

## Emotion is the input, not decoration

> *"Entonces las emociones deben servir en las decisiones de los NPC."*

Fear is what moves somebody between rungs, and it is the reason two survivors in the same
corridor do different things. The pieces already exist and are unconnected:

- `brain.rnd` gives five stable integers per NPC — `ScenesRelationsThreat.lua` already uses
  `rnd[2]` for bravery. That is the *disposition*: how easily this person frightens.
- The current threat appraisal already counts zombies and friends nearby. That is the
  *situation*.
- `SR.Mood` is where the running fear value belongs — transient, on the entity, decaying,
  exactly as the PRD's emotion-versus-memory table requires.

Whether the engine can supply fear directly is answered by the `PROBE stat VERDICT` line in
the current build. If it reads `FROZEN`, we own the number entirely.

## What each rung has to produce, concretely

**Mirroring, while following.** Run when the player runs, crouch when the player crouches,
fight when the player fights — unless too afraid. Bandits already reads exactly these
signals: `isSprinting`, `isSneaking`, `isAiming` and distance, at `ZPCompanion.lua:36-48`.
This is the cheapest visible win in the stage and should be built first.

**Breaking away.** Cornered means outnumbered inside a radius, and the answer is to run in
*a direction* — away from the mass, not toward a computed safe tile that may be through
them. Then a door, then quiet.

**Regrouping.** After the danger passes, if the player is visible, come back. This is what
makes fleeing feel like a decision instead of a despawn.

**Abandoning.** Sometimes they do not come back. High fear and low trust and they are gone
for good, and the relationship record remembers that they left. That possibility is what
gives the trust number teeth.

**Finishing what was interrupted.** A survivor jumped mid-loot kills the zombie and then
**goes back to looting**. The dropped intention is remembered on `SR.Mood`, not re-derived.

**A watchdog.** If an NPC has been on the same task longer than that task could plausibly
take, clear it. That single rule is the direct fix for the window bug, and it is worth
having regardless of how good the ladder gets.

## Why the engagement range stays at 8 for now

Noted from play: the range should eventually be larger, but only once killing zombies stops
being their only priority. That ordering is right, and it is a real dependency — widening
the range today just means they chase further. The range moves when rung 2 reliably yields
to rung 1 and rung 3.

## Second pass — what the 04-08 log corrected

The ladder shipped, was played, and the log disagreed with it in four places. All four are
fixed; they are written down because three of them are mistakes a reasonable person makes
twice.

**1. The watchdog was cancelling good work, not catching stuck NPCs.** It fired on `Smack`
mid-swing, on `Bandage` mid-heal, and on `Time` — which is a deliberate wait. It never once
fired on `OpenWindow`, the bug it was built for. The flaw was the premise: an unchanged
fingerprint at the head of the queue was read as "not progressing", when for most task
actions it is what working correctly looks like. Now it arms only on tasks that complete by
*getting somewhere* (a whitelist taken from `shared/ZombieActions/`), and it additionally
requires that the NPC has not physically moved. Standing still is the honest signal.

**2. Fear ratcheted and never came down.** It only decayed when nothing at all was nearby,
so on a populated street it climbed monotonically until everybody broke. `fear=82/86` off a
*single* zombie is in the log. It is now a decaying average — `fear * 0.6 + situational` —
which settles where the situation justifies and falls as soon as it improves.

**3. `brain.health` is the spawn maximum, not live health.** Written once at
`BanditServerSpawner.lua:332`, never updated. The hurt term of the fear model was reading a
per-person constant, and the wheel's "how are you holding up" had the same bug — a frail
survivor said "I'm hurt. Badly." while untouched. Live condition is `bandit:getHealth()`,
and what matters is its ratio to that person's own maximum.

**4. FIGHT outranked every order the player had ever given.** Any zombie within ten tiles
put an NPC on rung 2, so crossing a street meant abandoning you. In the player's words:
*"digamos yo iba a ver un vehiculo, y pasabamos por varios zombies y su prioridad de matar
era mayor a la de irnos por el objetivo mio."*

The last one had a second, deeper cause that is **not our bug**, and it is the most useful
thing this session found. In `ZPCompanion.Main`, a companion within 20 tiles of its master
that sees any enemy within 8 walks *to that enemy* and returns from the program — it never
reaches the follow-the-master code at the bottom of the same function. A companion crossing
a street with zombies in it is structurally unable to be following you, no matter what our
ladder decides.

So rung 2 is now conditional, and rung 3 does something instead of merely ranking:

| Situation | Rung |
|---|---|
| anything within 4 tiles | FIGHT — it is on them, there is nothing to decide |
| master is swinging, threat within 8 | FIGHT — joining a fight you started is the point |
| master sprinting, or distance growing, or past the 12-tile leash | OBEY, and **we assert the follow task ourselves** |
| no master at all | FIGHT within 8 — no competing instruction exists |

Asserting the follow means pushing `BanditUtils.GetMoveTaskTarget` — the framework's own
call, the one at the bottom of `ZPCompanion.Main` — with the player as the tracked target.
It tracks the character rather than a coordinate, which is why *"no saben donde estoy"* stops
being possible: they follow you, not the tile you were standing on.

## Contention: one person per window

Reported from play: two survivors walking to the same window, and one of them standing in
the open with its back turned while the other worked the latch.

A claim registry keyed on `x,y,z` — the first NPC with an exclusive task there (`OpenWindow`,
`SmashWindow`, `ClimbFence`, `Destroy`, `Unbarricade`, `TakeFromContainer`) holds it, and
anyone else gets a real `Time` wait task so they visibly queue instead of crowding the tile.
Claims expire after six sweeps so an NPC that dies mid-climb cannot lock a window shut for
everybody.

Half of that problem was upstream of the registry, though: the threat module was casting a
fifteen-tile net and sending everyone it caught to the nearest window. It now runs only for
survivors the ladder has already put on rung 1, and only once per episode.

## Instrumentation

The 04-08 log has `AUTO` lines for exactly one survivor out of four, because transitions were
the only thing logged and the other three never transitioned. Sitting quietly on a rung made
them invisible — which is the same as having no data about the behaviour we most wanted to
judge.

There is now a census line every five sweeps, one per NPC in range:

```
AUTO census | Benjamin Morgan | rung=obey fear=12/86 hp=0.72 z=1@6.2 friends=0 master=3.1 head=Move@10750,10280
```

Every number the ladder used to reach its decision, plus what the NPC is actually doing.
Anything unexplainable in play should be explainable from one of these lines.

## Done when

- A companion sprints when you sprint and crouches when you crouch.
- Surrounded, one breaks off, gets behind a door, and comes back when it is quiet.
- A survivor interrupted while looting kills the zombie and returns to the container.
- Two survivors in the same situation do not always make the same choice, and the same
  survivor mostly makes the same one twice.
- Nobody is ever seen working a window latch while being bitten.

## How it is tested

The last criterion is the one that fails, and it is the one to watch for. Everything else
is a feature; an NPC that cannot notice it is in danger is the bug this stage exists for.

1. Recruit a companion. Sprint, then sneak. Watch it match you.
2. Lead it into six or more zombies in the open. It should break away, not trade blows.
3. Follow it. It should end up behind a door, and it should find you again afterwards.
4. Drop a bag near a survivor mid-loot, then bring a zombie. Kill order: zombie, then bag.
5. Watch any survivor near a window for a full minute with zombies around.

## Deliberately not in this stage

No trading, no errands the player can accept, no group formations. Rung 4 exists in the
ladder so the arbitration is built to accommodate it, but its content is stage 07.
