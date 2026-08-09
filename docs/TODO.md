# TODO — noticed in play, not scheduled yet

Things spotted during testing that are real but belong to no open stage. Each one gets a
line here rather than derailing whatever is being built. Nothing is picked up from this
list until a stage claims it.

---

## `brain.scenesCarry` should become The Ark's `permaInv` — after block A

**Blocked on purpose, not forgotten.** Block A is being tested on the gaming PC; changing the
storage model before that run would mean the test measures something altered blind.

The Ark (`vendor/TheArk`, vendored 2026-08-05) solved this problem before us and better. Full
comparison with file:line in `docs/CAPABILITY-MAP.md` under *"I want an NPC to keep the things
it picked up"*. Three concrete gaps in ours:

1. **We store types, he stores state** — `cooked`, `dirtiness`, `bloodLevel`, `wetness`, the
   whole nutrition block. A half-drunk bottle comes back full for us.
2. **No partial use.** His `Use()` decrements `size` and scales every nutrition field
   proportionally (`BWOAPermaInv.lua:71`). We cannot represent eating half a tin.
3. **We never sync.** He calls `Bandit.ForceSyncPart` on every mutation
   (`BWOAPermaInv.lua:3-9`). That is a real multiplayer defect in our code under principle 3,
   and the smoke test cannot see it because it never runs client Lua.

Separate and smaller, from the same read: `Loot.GoalOf` counts a tin of beans as food even
with no opener. `BWOAItems.GetItemClass` splits `food` from `food_packaged` by asking
`item:getOpeningRecipe() or item:getDoubleClickRecipe()` (`BWOAItems.lua:9`), and uses
`item:isFood() and not item:isPoison()` where we use `instanceof(item, "Food")` — his excludes
poison, ours does not.

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

## They stand at fences and windows because Bandits never climbs them

**Photographed twice** — `caps/npc-window.png`, `caps/npc-fence.png`: a survivor standing at
a barrier, bat raised, going nowhere, with the player on the other side.

**The cause is upstream and it is a comment.** `ClimbFence` is a real task action with a
working handler, and Bandits builds it in exactly two places — `BanditUpdate.lua:606` and
`:715` — and **both are commented out**:

```lua
--[[local task = {action="ClimbFence", anim="ClimbFenceEnd", lock=true}
--[[local task = {action="ClimbFence", anim="ClimbWindow", lock=true}
```

So no Bandits NPC ever deliberately climbs anything. They rely entirely on the engine's
pathing to carry them over, and when it cannot, they stand there until something clears the
queue.

**What we do today:** the watchdog notices the movement task is not progressing and empties
the queue. `STUCK_SWEEPS` dropped from 3 to 2 on 04-08, so that is now about twelve seconds
rather than eighteen — better, still visible, and still a workaround. The 04-08 log caught
it seven times: `stuck on GoTo` ×3, `stuck on Move` ×4.

**The real fix, not yet built:** when the watchdog clears a stalled `Move`/`GoTo`, look at
what is between the NPC and the destination and queue the climb explicitly. The action and
its animations already exist; only the decision is missing. Worth reading why Slayer
disabled it before turning it back on — a `lock=true` climb that fails would be unclearable
by `Bandit.ClearTasks`, which may be exactly why it is commented.

---

## Fear is simulated, and stage 06 has to live with that

`PROBE stat VERDICT FROZEN` (04-08). The engine binds `getStats()` on an NPC but never ticks
it — twelve stats, ten sweeps, no movement. Every emotional value this mod will ever have
must be written by us, on `SR.Mood`.

Not a bug — a scope fact, recorded because stage 06 was written assuming the probe might go
the other way and halve it. It did not.

## Loot.FetchBag has no attempt cap

`Loot.Search` counts approaches and gives up after `MAX_APPROACHES`; `Loot.FetchBag` does not.
Since the 08-08 refactor both go through `SR.Move.GoAndDo`, which returns `{}, false` when the
target square has no free neighbour at all -- a bag dropped in a corner boxed in by furniture.
`ScenesRelationsCompanion.lua:363` and `:383` then queue nothing, `mood.doing` stays set, and the
program re-decides the same thing every time the task queue drains.

Not a crash and not per-frame -- a Bandits program only runs on an empty queue -- but it is an
NPC stuck on an unreachable bag, logging the same line forever. Give it the same cap
`Loot.Search` has. Found in review 2026-08-08, deliberately not fixed in that commit to keep the
diff to the regression.

## Firearm discipline and the "let's keep it quiet" group flag

Asked for 2026-08-09, deliberately deferred until building entry works.

An NPC with a gun fires it first. Wanted instead:

- **As a companion, mirror the player's weapon class.** If the player is on melee, they are on
  melee. Autonomy to open fire returns only when they are far enough away that the noise is
  their problem, not yours.
- **As a free NPC, choose freely.**
- **A talk option that sets a GROUP flag, not a per-NPC one.** "No hagamos ruido" said to one
  survivor must reach every companion nearby, and must keep reaching anyone who joins later,
  until they leave the player's radius. The explicit requirement: never walk NPC to NPC
  repeating it.
- **Later, NPC-to-NPC propagation**: one survivor tells another to holster, and the line only
  fires when the receiver is actually carrying a firearm.

Bandits already ships `ZAShoot`, `ZAAim`, `ZARack`, `ZALoad`, `ZAUnload`, `ZAEquip` and
`ZAUnequip`, so the mechanism exists; what is missing is the decision layer and the flag.

## Free NPCs are still too idle

Asked for 2026-08-09. Non-companion NPCs mostly stand around. With looting, movement and
autonomy now working, they should loot on their own initiative, clear zombies, and shelter in
buildings. Blocked by the same pathing/entry problem as everything else -- an autonomous NPC
that cannot get through a door will just fail more visibly than one standing still.

Worth mining The Ark for the domestic half: it ships 27 actions that are almost all
settlement life -- Cook, Eat, SitInChair, SleepLong, UseRadio, CleanFloor, ToggleTorch,
PlayVHS, TurnOven, PlayPiano. None of them help with entry, but they are exactly what "idle"
should look like once the NPC is inside.
