# TODO — noticed in play, not scheduled yet

Things spotted during testing that are real but belong to no open stage. Each one gets a
line here rather than derailing whatever is being built. Nothing is picked up from this
list until a stage claims it.

---

## Bandits do not reanimate

**Seen:** an NPC killed by a bite stays dead. It should stand back up after whatever delay
the sandbox is configured for, exactly as a player corpse does.

**What is already known:** Bandits has the machinery. `ZAZombify` is a task action, and
`BanditUpdate.lua` queues `{action="Zombify", anim="Faint", lock=true, time=200}` when
`brain.infection >= 100`. So turning exists, and it is driven by their own infection model
rather than by the vanilla reanimation timer.

**The question to answer first:** does an NPC killed outright by a zombie ever accumulate
infection, or does infection only rise on a bite that was survived? If the latter, the fix
is a death hook, not a tuning change.

**Why it matters:** a survivor who dies and stays a corpse is a prop. One who gets up is a
consequence, and it is what makes losing somebody land.

---

## Corpses do not hold a horde

**Seen:** zombies bite an NPC, kill it, and immediately switch to the player. Nobody stays
to feed.

**Wanted:** some of the horde stays on the body -- as many as fit, or up to a cap around
30 -- with their attention on the corpse. The rest come for the player.

**Why it matters, in the author's words:** sacrificing an NPC to a horde should work. Right
now killing one buys nothing, because the whole horde arrives anyway. That is a tactic the
game appears to offer and does not.

**What to check first:** whether vanilla has a feeding-on-a-corpse state at all, or whether
the distraction has to be built from a target override. `brain.eatBody` exists on the
Bandits brain, which hints the state exists for NPCs eating bodies -- worth reading before
designing anything.

---

## ~~Two systems both decide posture~~ — CLOSED 2026-08-04

The 04-08 log made it visible instead of theoretical: `THREAT ... -> flee` fired forty-odd
times for three survivors on a fifteen-tile radius, while `AUTO` said nothing about any of
them. Two modules watching different radii, reporting to nobody, sending everyone they
caught to the same window — which is also where "van 2 al mismo tiempo a abrir la misma
ventana" came from.

The ladder now owns the decision. `ScenesRelationsThreat.lua` runs only for survivors
already on rung 1 and owns only the verb: find the nearest way inside, go through it, once.

---

## A companion cannot follow you past a zombie — upstream, worked around

**Where it lives:** `ZPCompanion.Main`. A companion within 20 tiles of its master that sees
any enemy within 8 walks *to that enemy* and returns from the program — it never reaches the
follow-the-master code at the bottom of the same function. So a companion crossing a street
with zombies in it is structurally unable to be following you. This is the whole of
"cuando yo salía corriendo, no salian corriendo detras de mi".

**What we did:** did not touch their file. `ScenesRelationsAutonomy` asserts a
target-tracking follow task itself when the master is plainly disengaging, so the engage
branch is never asked.

**Why it stays on this list:** the workaround is ours to maintain forever, and it fights the
program rather than cooperating with it. Worth reporting upstream to Slayer with the two
line numbers; a leash guard on that branch would fix it for everybody.

---

## `BanditPrograms.Container.Loot` is dead code — reported upstream material

**Not a tuning problem, a crash.** `BanditPrograms.lua:524` reads `enemyCharacter:getX()`
and `:541` reads `endurance`. Neither is a parameter of that function (`bandit, object,
container`) nor a local in it. Both are undefined globals, so the first call throws.

That is why the entire looting block in `ZPCompanion.Main` (lines 120-215) is commented
out. It is not disabled pending tuning — it is disabled because it crashes. No Bandits
companion has ever looted a house.

We wrote our own (`ScenesRelationsLoot.lua`, `ZombieActions.ScenesLoot`) rather than repair
theirs, because their `ZALootItems` takes the ENTIRE contents of every container on the
square and ours must not. Worth sending Slayer the two line numbers regardless.

---

## Companions no longer pick things up off the floor

`ScenesRelationsIdle.lua` only acts on rung 5, and a companion with a master never leaves
rung 3. So the hat-picking behaviour — "si ven un sombrero en el suelo haya una probabilidad
de que lo guste, lo recoja y se lo ponga" — is currently only visible on survivors who are
NOT following you.

Not a regression from any one change; it is what the ladder implies. The fix is to let the
companion program offer the same want-something check before it falls through to resting,
routed through the Idle module rather than duplicated (R6). Small, but it needs the search
behaviour confirmed in play first so there is one new thing being judged at a time.

---

## Fear is simulated, and stage 06 has to live with that

`PROBE stat VERDICT FROZEN` (04-08). The engine binds `getStats()` on an NPC but never ticks
it — twelve stats, ten sweeps, no movement. Every emotional value this mod will ever have
must be written by us, on `SR.Mood`.

Not a bug — a scope fact, recorded because stage 06 was written assuming the probe might go
the other way and halve it. It did not.
