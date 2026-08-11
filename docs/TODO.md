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

## Vidrios: corta al salir pero no al entrar, y falta el sangrado (10-08)

**Reportado:** *"funcionó solo cuando salió, pero no cuando entró por la ventana rota de nuevo.
Debe hacerle daño cada que entra o salga. Aparte debe aplicarle un efecto de sangrado que solo
se puede curar vendándose."*

### Por qué corta solo una vez, y es estructural

El hook actual envuelve `ZombieActions.OpenWindow.onComplete`
(`ScenesRelationsWounds.lua:354`). Eso dispara cuando el NPC **abre** la ventana — o sea la
primera vez. Al volver a entrar la ventana **ya está abierta**, no se encola ningún
`OpenWindow`, y el cruce es invisible. El barrido de `CheckGlass` corre cada ~6 s y el cruce
dura ~1 s, así que casi siempre lo pierde.

**Y no existe una acción que envolver.** Bandits no cruza ventanas con una tarea: cambia de
estado del motor —

```lua
ClimbThroughWindowState.instance():setParams(bandit, object)
bandit:changeState(ClimbThroughWindowState.instance())
bandit:setBumpType("ClimbWindow")
```

(`vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:684-686`). No hay
`ZAClimbWindow` en `ZombieActions/` — lo verifiqué, los 47 archivos están listados y no está.

### El hook correcto, con el identificador ya verificado

`character:isCurrentState(ClimbThroughWindowState.instance())` es vanilla y llamable:
`pzserver/media/lua/client/Tutorial/Steps.lua:1564` y `:1570` lo usan tal cual, y
`Steps.lua:891` usa la variante `getCurrentState() ==`. Vanilla solo lo llama sobre
`getPlayer()`, así que **sobre `IsoZombie` va con `pcall` y sonda de una sola vez** — la misma
disciplina que `masterIsRunning`, y por la misma razón que costó una sesión con
`getSeeNearbyCharacterDistance`.

Detectar el **flanco de subida** de ese estado en el carril de 800 ms captura entrada y salida
por igual, porque mide el cruce y no la apertura.

### El sangrado, y por qué no puede ser el del motor

`BodyPart:setBleeding` es por parte del cuerpo, y Bandits modela la salud de un NPC como un
solo float (`zombie:getHealth()`). Ese hueco ya está anotado más abajo — *"quedan inválidos con
la salud al 100%"*. Así que el sangrado va en NUESTRA capa, donde ya existe el vocabulario:

- `Wounds.Of(brain)` ya guarda `{ dressing, day }` (`ScenesRelationsWounds.lua:~100`) → agregar
  `bleeding` y `bleedingSince`.
- Drenar una fracción por barrido mientras `bleeding` esté puesto.
- **Se limpia SOLO en `scenesBandageComplete`** (`:215`), nunca por tiempo ni por salud. Eso es
  literalmente lo pedido: *"solo se puede curar vendándose"*.
- `Wounds.NeedsDressing` (`:118`) hoy solo mira `getHealth() < BLEED_FLOOR`; tiene que devolver
  `true` también con `bleeding` puesto, o el NPC sangra y nunca decide vendarse.

**Ojo con el latch.** `bleeding` es una decisión recordada con un clear que depende de que el
NPC llegue a completar un `Bandage`. Ese es exactamente el patrón que `audit.py` marca y que ya
costó cuatro defectos. Necesita el mismo tratamiento que `mood.rejoining`: o un tope de tiempo,
o la garantía escrita y verificada de que `NeedsDressing` no puede quedar bloqueado por el
propio sangrado.

---

## La mochila de un NPC no es un contenedor — es una calcomanía (10-08)

**Esto es la respuesta real a "el NPC lootea antes de conseguir su bolso" y a "que mantenga
los objetos dentro del bolso".** Las dos peticiones chocan contra el mismo hecho, y hasta que
se resuelva no hay forma honesta de cumplirlas.

Hoy `Loot.WearBag` hace exactamente dos cosas
(`mods/ScenesProject/Contents/mods/ScenesRelations/42/media/lua/client/ScenesRelationsLoot.lua:911-937`):

```lua
brain.bag = { name = itemType }   -- un campo
...
inventory:Remove(item)            -- y el objeto REAL se borra del inventario
```

No queda ningún `ItemContainer` detrás. `ApplyVisuals` dibuja el sprite en la espalda
(`vendor/Bandits/mods/Bandits/42.20/media/lua/shared/Bandit.lua:234`) y ahí termina. Por eso:

- **No se puede "guardar en la mochila"** — no existe el destino. Todo lo que carga un NPC vive
  en `getInventory()`, y por eso todo aparece en el inventario general. No es un bug de orden
  de operaciones; no hay a dónde moverlo.
- **El presupuesto de carga no puede subir por llevar mochila.** `Loot.CarryBudget` sumaba
  `getItemContainer():getMaxWeight()` del bolso y por eso mentía — `carrying 11.1 / 8.0`, 139%,
  está en el log del 09-08. Se quitó por eso (`ScenesRelationsLoot.lua:640-664`).
- **El kit de prueba de seis mochilas no medía nada.** El experimento asumía que capacidades de
  1 a 35 harían divergir la línea `carrying X / Y` entre NPC. No puede: las seis producían el
  mismo techo. Se retiró el 10-08 a pedido del usuario, y con esta razón.

### Qué haría falta para cumplirlo de verdad

`setClothingItem_Back(item)` es vanilla y verificado — nueve callsites en
`pzserver/media/lua/client/DebugUIs/Scenarios/` (p. ej. `Trailer2Scenario.lua:116`). Poner el
objeto real ahí le daría al NPC un `getItemContainer()` de verdad, dos límites separados
(mochila e inventario general) y un destino para guardar. **Pero abre el problema que
`WearBag` ya resolvió una vez a la mala:**

`Bandit.UpdateItemsToSpawnAtDeath` construye el cadáver desde el inventario vivo con
`getAllEvalRecurse` (`Bandit.lua:727-732`, que **aplana** los contenedores) **y además**
instancia `brain.bag` por separado (`Bandit.lua:855`, `addItemToSpawnAtDeath` en `:1141`). Una
mochila que esté en los dos lados cae **dos veces** en el cuerpo — reportado en juego como
"quedó dos veces con la mochila", y la razón por la que hoy se borra del inventario.

Así que el trabajo no es "guardar loot en la mochila". Es **elegir un modelo de persistencia**,
y es el mismo que ya está pendiente arriba (`brain.scenesCarry` → `permaInv` de The Ark). The
Ark evita toda esta clase de problema no dejando nada en `getInventory()`: `ZACollect` entrega
el item directo a `BWOAPermaInv` y destruye el objeto.

**Se hace junto con esa migración, no antes.** Hacerlo suelto significa escribir un tercer
modelo de carga y después tirarlo.

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

## Melee targeting locks onto friendly NPCs (09-08)

Reported: fighting the same zombie as a companion, with the NPC between the player and the
target, the player's swings retarget onto the NPC. The `safe` flag correctly prevents the
DAMAGE -- that part works -- but it does not stop the NPC becoming the aim target, so the
player swings at a body that cannot be hurt while the zombie keeps biting.

Wanted: friendly NPCs are never an aim target while `safe` is on. Zombies and hostile NPCs
still are. With `safe` off, hitting them must work again, targeting included.

Note the shape: this is the engine's target selection, not ours. A Bandits NPC is an IsoZombie,
so it is a legitimate melee target as far as the engine is concerned -- same root as the panic
bug (ScenesRelationsPanic.lua), and probably the same kind of fix: a wrapper that filters
friendlies out of the candidate list rather than trying to undo the choice afterwards.

## NPC endurance drains far too fast, and has no stages (09-08)

Reported: NPC stamina empties much faster than a player's. Wanted: replicate the player model
properly, with every stage visible -- "sin aliento" climbing gradually into "Esfuerzo intenso"
and then "Esfuerzo excesivo" -- rather than a single exhausted state.

Known constraint from earlier work: `PROBE stat VERDICT FROZEN` -- `getStats()` binds on an
IsoZombie but the engine never ticks it, which is why emotion is simulated on `SR.Mood`.
Endurance is likely the same shape, so this means simulating the player's curve rather than
reading a stat. Read how vanilla drives endurance first.

## Companions keep fighting instead of following when the player flees (09-08)

Reported: the player runs to avoid being bitten and the NPC stays behind trading blows.

Wanted rule, and it is narrower than "fight or flee": stay and fight ONLY when actually
trapped -- cannot move AND several zombies on them. Otherwise disengage and follow. Today they
treat any engagement as a reason to stand still.

## Dead NPCs must stay, and turn (09-08)

Reported: NPCs vanish on death. Wanted: the body remains, turns into a zombie after the
sandbox-configured delay, and **is still wearing its bag when it rises** -- so the player can
see that this specific person was infected and died. Permanence is the point.

Related to the wounds plan, where conversion is deliberately switched off; this is the other
half of the same feature.

## Looting still happens too far from the container (09-08)

Reported again after the GoAndDo fix: it is much better -- they walk to the furniture instead
of looting from across the room -- but with two containers close together you cannot tell which
one is being searched. `REACH` is 0.7 tiles, taken from The Ark's own default. Consider
tightening it, and check that the standing square chosen is the one facing the container.

Same session: 56 `gives up on ... could not get there in 3 tries` against 7 `nothing left within
reach`. Still the reachability problem, which is block B.

---

## Resting should use real furniture, and endurance should recover the way it does for a player (09-08)

**Reported:** "cuando un NPC está cansado se sienta donde sea... si está en una casa o cerca de
una casa y hay un objeto de una silla donde por lo general para los jugadores aparece
'descansar', se siente en esos objetos, un sofá o una silla."

Four separate requirements, and they are listed apart because they will not land together:

1. **Sit on a chair or a sofa, not on the tile you happen to be standing on.** Today
   `restTasks` queues `{action = "Sleep", anim = "Sit", ...}` wherever the NPC is. It needs to
   find real sittable furniture first, the same objects that offer a player the rest option.
2. **A chair must restore more endurance than the ground.** Two different recovery values, not
   one.
3. **Sitting on the ground becomes a last resort** — "casi una necesidad, digamos que está
   demasiado exhausto para caminar". So the floor is what you do when you cannot reach a chair
   and cannot keep walking, not the default.
4. **Walking should recover a little endurance**, running should not. Today `brain.endurance`
   only ever decreases; resting is the single thing in the whole framework that gives it back.

The user's own steer on where to look: mirror how vanilla recovers endurance for a player in
the staged exhaustion states. That is the same staged model already owed for the separate
"endurance drains too fast and has no stages" item.

**Depends on:** research into what vanilla treats as sittable and what its recovery numbers
actually are. Do not implement any of the four before that lands — the shape of (2) and (4)
depends entirely on whether vanilla's furniture rest is mechanical or purely cosmetic.

## A friendly NPC standing near you makes YOU get up off the sofa (09-08)

**Reported:** "cuando un NPC se me acerca y yo estoy descansando en un sofá hace que me pare...
esto es por lo general una funcionalidad por defecto del juego, ya que si un zombie está cerca
el PJ lo que hace es levantarse para defenderse, pero esto no debería pasar con los NPC."

**This is the IsoZombie trap again, and it is the third instance.** A Bandits NPC IS an
IsoZombie -- that inheritance is the entire basis of the framework, which is how it gets
pathing, animation, combat and the horde system for free. Every piece of vanilla code that
counts nearby zombies therefore counts your friends. Previous instances:

- the panic moodle rising because your own people read as a horde -- fixed in
  `ScenesRelationsPanic.lua` with our own suppression handler;
- melee auto-target locking onto a friendly NPC -- still open, listed above.

This one is worse than those two because the vanilla behaviour acts on the PLAYER, not on an
NPC, so there may be no seam we own. If the check lives Java-side with no Lua override, the
honest answer may be that it is not fixable and has to be designed around. Record the answer
either way -- a verified "not reachable from Lua" is worth as much as a fix, because it stops
the next session from re-deriving it.

## Fleeing to a window while ALREADY INSIDE the house (09-08) — next Threat pass

**Seen in play, and it is the clearest description of this failure so far:** player and companion
looting house A. A zombie in house B, next door, banging on B's window. The companion walked to
a window OF HOUSE A, opened it, and then stood at it doing nothing -- no longer following, no
longer looting -- until the player killed the zombie, at which point it recovered on its own.

**Two independent defects produced that, and only one of them is already being fixed.**

1. **`seekShelter` never asks whether the NPC is already indoors.** `grep -c indoors
   ScenesRelationsThreat.lua` returns 0. The whole module is written on the assumption that a
   frightened survivor is outside and needs a way in -- "Fleeing to a window is what surviving
   looks like" is in its own header. Inside a house that is not merely useless, it is harmful:
   `findWindow` prefers an ALREADY-OPEN window and `seekShelter` will happily open a closed one,
   so a frightened NPC standing in a secure room walks to the wall and opens a hole in it.
   Worse case, not observed but reachable: `SHELTER_SEARCH` is 8 tiles, so if the zombie's own
   window is nearer and already smashed, "shelter" routes the NPC TOWARD the zombie.

2. **The freeze itself is the F1 re-assert loop** already scheduled for the current pass. Once
   the window is open, `findWindow` keeps choosing it, `seekShelter` queues a bare `GoTo` to a
   square the NPC is already standing on, that completes instantly, and the next sweep does it
   again. From outside that reads as a person standing motionless at a window -- exactly what
   was reported -- and it ends the moment fear drops below the limit and the rung leaves
   SURVIVE, which is exactly what killing the zombie did.

**Third thing the same report exposes: fear has no perception gating.** `grep -c LosUtil
ScenesRelationsAutonomy.lua` returns 0. `scanSurroundings` counts every zombie within
`FEAR_RADIUS = 9` with no line-of-sight test, so a zombie inside another building, behind two
walls, frightens a survivor as much as one in the same room. This is the same missing concept as
the loot-through-wall defect, in the perception layer instead of the action layer, and it is
listed separately under block B as "GetClosestZombieLocation has no distance limit".

**Not a defect of ours, recorded so it is not re-diagnosed:** the user also observed that
Bandits NPCs sometimes fail to climb through a window at all. Upstream limitation.

## The loot filter takes pens and spoons, and the reason is precise (10-08)

**Reported:** "cogen un monton de cosas que no sirven" — and now the log names them, because
`took N` prints the item ids:

```
Base.Pen, Base.BluePen, Base.Spoon, Base.RollingPin, Base.Lipstick, Base.ToiletPaper
```

**Both culprits are our own predicates, and both are technically correct.** `isWorthTaking` asks
the engine five questions. Two of them are far broader than "worth carrying":

| Item | Gets in through | Why |
|---|---|---|
| `Pen`, `BluePen`, `Spoon`, `RollingPin` | `item:IsWeapon()` | all declare `ItemType = base:weapon` in `pzserver/media/scripts/generated/items/weapon.txt`. To the engine a pen IS a weapon. |
| `Lipstick`, `ToiletPaper` | `item:IsDrainable()` | both are `ItemType = base:drainable` in `drainable.txt` — the same class as bandages, disinfectant and batteries. |

So the filter is not buggy. It is asking the wrong questions: the engine's classification is a
statement about MECHANICS, not about value, and we have been treating one as the other.

**What is NOT yet verified, and has to be before anything is written.** The obvious
discriminators need checking against `pzserver/media/` first, and a fabricated getter here fails
silently and costs a restart on the other machine:

- weapon damage — no `getMaxDamage()` / `getMinDamage()` callsite exists anywhere in the engine
  Lua, so the real getter is something else and has to be found;
- `item:getCategory()` is real (`ISInventoryPage.lua:1572`) but the values seen in vanilla are
  "Container", "Clothing", "Literature", "Key" — no weapon/drainable value was observed, so what
  it returns for those is unknown;
- `ItemTag.*` is a real and large namespace (`CONSUMABLE`, `CAN_EAT`, `CROWBAR`, ...) and may be
  the right axis, but which tags exist for medical items was not checked.

**The shape of the answer the user asked for:** "tenemos que hacer un listado de items importantes
para el looteo" — an explicit, declarative priority list, which per principle 2 belongs in
`scripts/` rather than in Lua. That also makes it survivable across game updates, which a
predicate built on engine classifications is not.

## The player-trail idea is sound; the implementation was reverted (10-08)

Reverted 99601e1. The IDEA survives and should be rebuilt — following the route the player
actually walked is the only reachable answer to "yo trepé un muro y el NPC lo rodeó", and it is
the only thing that addresses the 44% of jams where the straight line is clear. What follows is
what a review found, so the next attempt does not rediscover it.

### The two that made it worse than not having it

**1. The cross-floor fix broke the feature it was meant to serve, and regressed the old
behaviour.** `WhatBlocks` was changed to return `BLOCK_UNKNOWN` for a target on another floor.
But `TrailTarget` accepts a crumb only when `WhatBlocks` is nil — so **no cross-floor crumb can
ever be selected**, and the crumb `DropCrumb` exists to create (always one on a floor change) is
exactly the one that is structurally rejected.

Worse, it regressed what worked before. Player upstairs, companion below: `assertFollow` used to
pass the master's own z, and `ZAMove` hands that to `pathToLocation`
(`vendor/Bandits/mods/Bandits/42.20/media/lua/shared/ZombieActions/ZAMove.lua:9`) — the engine
pathfinder, which solves stairs. After the change, whenever a same-floor crumb was available the
companion was never given a cross-floor destination at all.

**The lesson is about the fix, not the bug.** The same predicate was used with INVERTED POLARITY
at two call sites. Fixing one end and not re-deriving the other is precisely what a self-review
cannot catch: the author is blind in the same place twice.

**2. A two-tile pacing limit cycle, invisible to the watchdog.** `TrailTarget` skipped a crumb
within `CRUMB_SPACING` and then **continued to older ones**. The comment claimed "this crumb and
every older one are behind us"; the code never implemented it — no break, no test that a crumb is
ahead. So it returns crumbs the NPC already walked past.

Concretely: player upstairs and still. Companion reaches the stair foot. Next call, that crumb is
within 2 tiles → skipped, newer ones are cross-floor → rejected, and an OLDER crumb 2 tiles
behind is clear → returned. It walks back. Now the first crumb is >2 tiles and clear → walks
forward. Forever.

`watchdog` cannot see it: it requires the NPC to have moved less than `MOVED_EPSILON = 0.6`, and
a pacing NPC moves two tiles. **The safety net is blind to this by construction.**

### The three that would have bitten later

**3. Endurance is charged per COMPLETED task, and short legs complete.** `walkType` and
`endurance` are computed from the distance to the MASTER, then the task is aimed at a CRUMB.
A long Run at a distant master was usually cleared by the next sweep before completing, so it
cost nothing (`BanditUpdate.lua:1819-1821` applies `task.endurance` only in the COMPLETED
branch). A short crumb leg completes in 1-2 s and charges -0.07 every sweep: 0.7/min against a
ceiling of 1.0. At zero, `BanditUpdate.lua:437-444` queues five locked `Exhausted` tasks. About
ninety seconds of following a blocked line locks a companion into the exhaustion animation --
which is the old "después de un rato los veo cansado de nuevo", re-created by the fix.

**4. No distance cap on a crumb candidate.** `WhatBlocks` documents itself as bounded by the
distance asked about, and every previous caller passed a target inside a search radius.
`TrailTarget` was the first that did not.

**5. Crumbs are dropped while the player is in a VEHICLE.** `fastFollow` guards only "player
exists and is not dead". At 800 ms even a slow car exceeds `CRUMB_SPACING`, so a crumb lands
every pass and the 2-tile spacing that `TRAIL_SCAN` and `CRUMB_MAX` were both sized against
silently becomes 10-15 tiles. And the trail's founding premise -- *known passable because a body
walked it* -- is simply false for a route a car took.

### Telemetry note for whoever reads the next log

`blocked by unknown` now has two unrelated causes: the probe did not run, and the target was on
another floor. A cross-floor stuck NPC used to be counted as `clear`. The 10-08 counts (12 solid,
11 clear, 1 locked, 1 hop) predate that and are still good.

### What to keep when rebuilding

- Drop crumbs from the fast tick — it already runs and already holds the player. That part is free
  and correct.
- Keep the narrow claim: the trail is PASSABLE, not SHORTER. Proving shorter needs a pathfind, and
  `pathToLocation` commits the character.
- A crumb must be *ahead*: nearer the master than the NPC currently is. Skipping-and-continuing is
  what created the limit cycle.
- Recompute walk type and endurance from the ACTUAL target, never from the master.
- Cap the candidate distance, skip crumbs laid from a vehicle, and clear the trail on death as

---

## Health panel — Spanish localization (10-08)

**The body part panel is built and working in English.** Labels like "Head", "L Upper Arm",
"Bitten", "Deep wound", "Glass lodged", "Bandage" need Spanish translations matching the
vanilla game's terminology (`Cabeza`, `Brazo superior izq.`, `Mordido`, `Herida profunda`,
`Vidrio incrustado`, `Vendado`).

Not urgent — the panel is fully functional in English. Add to the next UI pass.
  well as on game start.
