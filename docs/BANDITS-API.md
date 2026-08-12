# Bandits API — the levers that already exist

Reference for anyone building on the Bandits framework. **Read this before writing NPC
behavior.** Most things you are about to build already exist here under a different name.

Extracted from `vendor/Bandits/mods/Bandits/42.20/media/lua/` — the version pinned in
`deps.lock.json`. Run `./tools/deps.py check` before trusting any line number below; on
DRIFT this document is stale and must be re-derived, not patched from memory.

Every claim carries a `file:line`. Paths are relative to
`vendor/Bandits/mods/Bandits/42.20/media/lua/`. If a line number does not match what you
find, the file moved under you — stop and report it rather than guessing.

## How to read an entry — and why the format changed

**A name and a line number is not enough, and this document proved it.**

On 2026-08-05 we shipped a bug where nothing an NPC looted survived, because
`Bandit.UpdateItemsToSpawnAtDeath` was never called. That function was already listed here,
accurately, at line 251 — as a bare name in a comma-separated list under *Weapons*. It was a
directory entry. Nothing said what it means, that the brain is the store, or that skipping it
makes everything you added invisible. An index you can search and still get wrong is a
catalogue, not a reference.

So an entry that carries a **contract** now says three things:

| Field | Answers |
|---|---|
| **Signature + `file:line`** | where it is |
| **What it does** | in one sentence, in terms of state, not of code |
| **What breaks if you skip it** | the silent failure — this is the field that was missing |

The third field is only worth writing where the failure is *silent*. Something that throws
announces itself. Bare name lists stay bare where the name genuinely is the whole story, and
are backfilled into full entries as work touches them — never in a big-bang rewrite that
nobody would read.

---

## 0. The mental model

Bandits NPCs are **`IsoZombie` instances** flagged with `zombie:getVariableBoolean("Bandit")`.
Everything vanilla does to zombies applies to them, including `Events.OnHitZombie` and
`Events.OnZombieDead`.

Two layers drive them:

```
PROGRAM (the role)  ->  returns TASKS  ->  TASK QUEUE (the actions)
  a state machine          {status,           executed one at a time
  keyed by stage            next,             by a 3-state dispatcher
                            tasks}
```

- The **program** only runs when the task queue is empty (`client/BanditUpdate.lua:1889`).
- A program stage function returns `{status, next, tasks}`; the dispatcher then calls
  `Bandit.SetProgramStage(bandit, res.next)` and enqueues `res.tasks`.
- Tasks are **plain serializable tables**. You never write behavior code in a task; you
  describe what should happen and the handler does it.

Consequence for us: to change what an NPC *does*, queue tasks. To change what it *is*,
set a program. Do not write per-tick logic that fights the queue.

### The three-state dispatcher, with line numbers

**Written down because three reviews in a row re-derived it**, each one opening a 2,200-line
vendored file to find the same branch layout. `ProcessTask` is `client/BanditUpdate.lua:1751-1833` (span from
[`VENDOR-INDEX.md`](VENDOR-INDEX.md); `:1753` was cited here for two rounds and is the first
statement, not the declaration):

| State | Line | What happens |
|---|---|---|
| *(unset)* | `:1753` | `if not task.state then task.state = "NEW" end` — so an unprocessed task carries `state == nil`, not `"NEW"`. Any test against `"WORKING"` must be nil-safe. |
| `NEW` | `~:1790` | calls `onStart`; on true, `task.state = "WORKING"` |
| `WORKING` | `:1801-1808` | `task.time = task.time - 1 / ((getAverageFPS() + 0.5) * 0.01666667)` — about **1 per frame**, so ~60 units/second at 60 fps and ~30 at 30 fps. Calls `onWorking`. `done or task.time <= 0` promotes to `COMPLETED`. |
| `COMPLETED` | `:1812-1830` | plays `task.sound`, then **`Bandit.UpdateEndurance(bandit, task.endurance)` at `:1820`**, then `onComplete` at `:1824`, then `Bandit.RemoveTask` at `:1828`. |

**Four consequences that keep costing us, in one place:**

1. **`task.endurance` is paid ONLY in the COMPLETED branch** (`:1820`). A task cancelled at 99%
   pays nothing. This is why a 7.5-second rest that gets interrupted recovers zero endurance.
2. **`onComplete` is called ONLY from the COMPLETED branch** (`:1824`). Neither
   `Bandit.ClearTasks` (`shared/Bandit.lua:369-382`) nor `Bandit.RemoveTask`
   (`shared/Bandit.lua:361-367`) calls it — both are a bare `table.remove` / table rebuild.
3. Therefore **a `Move` thrown away mid-flight leaks its pathfinder.** `ZAMove.onComplete` is
   the entire cleanup — `finder:cancel()`, `finder:reset()`, `setPath2(nil)`
   (`shared/ZombieActions/ZAMove.lua:45-51`) — and it never runs. `onStart` then calls
   `pathToLocation` **and** `update()` (`:9-10`) while `onWorking` calls `update()` again
   (`:34`), so the next Move takes two advancement steps on its first frame. That is a
   companion that visibly runs too fast, on a stale route. Diagnosed from play on 2026-08-10.
4. `ZAGoTo.onComplete` is `return true` and nothing else (`ZAGoTo.lua:53-55`) — it releases no
   pathfinder. `GetMoveTaskTarget` only emits `GoTo` in multiplayer (`BanditUtils.lua:1026-1031`),
   so this is latent, not live, in singleplayer.

---

## 1. Task actions — 49 of them

**Dispatcher**: `client/BanditUpdate.lua:1753` `ProcessTask(bandit, task)`. It is the only
consumer of `task.action`. Handlers live one per file in `shared/ZombieActions/ZA*.lua`,
registered as `ZombieActions.<Name>`.

### Fields every task accepts

Read by the dispatcher itself, so they work on any action:

| Field | Behavior | Ref |
|---|---|---|
| `action` | required — selects the handler | `BanditUpdate.lua:1755` |
| `state` | internal: `NEW → WORKING → COMPLETED`, auto-set | `BanditUpdate.lua:1756` |
| `time` | defaults to 1000 on NEW; decremented per tick; `<=0` force-completes | `BanditUpdate.lua:1759,1804` |
| `lock` | survives `Bandit.ClearOtherTasks` | `Bandit.lua:413` |
| `anim` | bump animation; handlers poll `getBumpType() ~= task.anim` to detect the end | `BanditUpdate.lua:1790` |
| `sound`, `soundDistMax` | auto-played on NEW, skipped beyond `soundDistMax` | `BanditUpdate.lua:1771` |
| `endurance` | applied via `Bandit.UpdateEndurance` on COMPLETED | `BanditUpdate.lua:1822` |

**Queue cap is 9.** Exceeding it does not drop the newest task — it **flushes the entire
queue** and prints a `[WARN]` (`Bandit.lua:290-293, 304-307`). Never enqueue in a loop
without checking `Bandit.HasTask`.

### Movement (7)

| Action | Fields | Handler | Does |
|---|---|---|---|
| `GoTo` | `x, y, z, walkType` | `ZAGoTo.lua:4` | Pathfinds to a location |
| `Move` | `x, y, z, walkType, backwards(?)` | `ZAMove.lua:4` | Like GoTo but drives `getPathFindBehavior2()` directly |
| `Turn` | `anim, x, y` | `ZATurn.lua:8` | Waits for anim, then faces (x,y) |
| `FaceLocation` | `x, y, time` | `ZAFaceLocation..lua:5` | Faces a point every tick |
| `ClimbFence` | `anim` | `ZAClimbFence.lua:5` | Hops a fence |
| `VehicleAction` | `vx, vy, vz, partId, subaction(?)` | `ZAVehicleAction.lua:5` | Vehicle part interaction |
| `Sleep` | `anim, x, y, z, facing, eoffset(?)` | `ZASleep.lua:9` | Sleep pose |

### Combat (9)

| Action | Fields | Handler | Does |
|---|---|---|---|
| `Aim` | `anim, x, y` | `ZAAim.lua:5` | Holds aim, sets `Bandit.SetAim(true)` on complete |
| `Shoot` | `anim, eid, time, slot` | `ZAShoot.lua:9` | Full firearm resolution, muzzle flash, alerts zombies in sound radius |
| `Rack` | `anim, slot` | `ZARack.lua:13` | Sets `brain.weapons[slot].racked` |
| `Load` | `anim, slot` | `ZALoad.lua:13` | Refills ammo counters on the brain |
| `Unload` | `anim, slot, drop` | `ZAUnload.lua:13` | Clears the clip, drops the item |
| `Smack` | `weapon, eid, x, y, time` | `ZASmack.lua:474` | Melee — can stick the weapon in the victim |
| `Push` | `eid, x, y, time` | `ZAPush.lua:35` | Shove: knocks down a zombie, staggers a player |
| `Die` | `anim, fire(?)` | `ZADie.lua:4` | Kills the bandit |
| `Zombify` | `anim` | `ZAZombify.lua:4` | Reverts it to a plain zombie |

`eid` is a target entity id. `slot` is a weapon slot on `brain.weapons`.

### Inventory (10)

| Action | Fields | Handler | Does |
|---|---|---|---|
| `PickUp` | `x, y, z, anim, itemType, cnt(?)` | `ZAPickUp.lua:14` | Picks a dropped item off a square |
| `Drop` | `anim, itemType` | `ZADrop.lua:13` | Drops to world |
| `Equip` | `itemPrimary` | `ZAEquip.lua:4` | Two-phase attach → `Bandit.SetHands` |
| `Unequip` | `itemPrimary` | `ZAUnequip.lua:4` | Two-phase detach |
| `PutInContainer` | `anim, x, y, z, itemType` | `ZAPutInContainer.lua:15` | Inventory → container |
| `TakeFromContainer` | `anim, x, y, z, itemType, cnt(?)` | `ZATakeFromContainer.lua:19` | Container → inventory |
| `PlaceItem` | `anim, x, y, z, itemType` | `ZAPlaceItem.lua:14` | Places on a surface |
| `LootItems` | `anim, x, y, z, time` | `ZALootItems.lua:24` | Empties every container on a square |
| `LootWeapons` | `anim, x, y, z, time` | `ZALootWeapons.lua:139` | Finds a weapon upgrade, rebuilds `weapons[slot]`, syncs |
| `TimeItem` | `item(?), left(?), right(?), time` | `ZATimeItem.lua:4` | Temporarily holds a prop item for an animation |

### World interaction (17)

| Action | Fields | Handler |
|---|---|---|
| `OpenWindow` | `anim, x, y, z` | `ZAOpenWindow.lua:14` |
| `SmashWindow` | `anim, x, y, z` | `ZASmashWindow.lua:14` |
| `Unbarricade` | `anim, fx, fy, x, y, z, time, idx` | `ZAUnbarricade.lua:9` |
| `UnbarricadeMetal` | `anim, fx, fy, x, y, z, time, idx` | `ZAUnbarricadeMetal.lua:9` |
| `Destroy` | `anim, x, y, z, idx` | `ZADestroy.lua:9` |
| `GeneratorFix` | `anim, x, y, z` | `ZAGeneratorFix.lua:15` |
| `GeneratorRefill` | `anim, x, y, z` | `ZAGeneratorRefill.lua:4` |
| `GeneratorToggle` | `anim, x, y, z, status` | `ZAGeneratorToggle.lua:14` |
| `LightToggle` | `anim, x, y, z, active` | `ZALightToggle.lua:14` |
| `StoveToggle` | `anim, x, y, z` | `ZAStoveToggle.lua:14` |
| `BuildFloor` | `anim, x, y, sound, time` | `ZABuildFloor.lua:8` |
| `FillWater` | `anim, x, y, z, itemType, time` | `ZAFillWater.lua:4` |
| `WaterFarm` | `anim, x, y, z, itemType` | `ZAWaterFarm.lua:17` |
| `StompPlant` | `anim, x, y, z` | `ZAStompPlant.lua:16` |
| `Wash` | `anim, x, y, z, time` | `ZAWash.lua:19` |
| `CleanBlood` | `anim, x, y, z, itemType, time` | `ZACleanBlood.lua:4` |
| `Fishing` | `x, y` | `ZAFishing.lua:4` |

### Body (4)

| Action | Fields | Handler |
|---|---|---|
| `BuryCorpse` | `anim, x, y, z` | `ZABuryCorpse.lua:25` |
| `FillGrave` | `anim, x, y, z, itemType, time` | `ZAFillGrave.lua:19` |
| `PickUpBody` | `anim, x, y, z, cnt(?)` | `ZAPickUpBody.lua:14` |
| `Bandage` | `anim, x, y` | `ZABandage.lua:26` |

### Waiting (2)

| Action | Fields | Handler | Does |
|---|---|---|---|
| `Time` | `anim` | `ZATime.lua` | Wait for an animation to finish |
| `Single` | `anim` | `ZASingle.lua` | Same pattern, single shot |

---

## 2. Programs — 8 exist

`shared/ZombiePrograms/ZP*.lua`. **Do not grep only for `SetProgram(x, "Name")`** — most
programs are assigned at spawn through `args.program` in
`server/BanditServerSpawner.lua:979-1009`, so that grep finds three and misses five.

| Program | File | Assigned by | Live? |
|---|---|---|---|
| `Bandit` | `ZPBandit.lua` | spawner (assault), menu | yes |
| `Looter` | `ZPLooter.lua` | spawner (wanderer), "Leave Me!" | yes |
| `Companion` | `ZPCompanion.lua` | `clan.companion` at spawn, "Join Me!" menu | yes |
| `Camper` | `ZPCamper.lua` | spawner | yes |
| `Defend` | `ZPDefend.lua` | spawner | yes |
| `Roadblock` | `ZPRoadblock.lua` | spawner | yes |
| `Thief` | `ZPThief.lua` | — no assigning callsite found | **dead** |
| `CompanionGuard` | `ZPCompanionGuard.lua` | — no assigning callsite found | **dead** |

> **Other mods add their own programs and can shadow these entirely.** Measured in a real
> run on 2026-08-03 with Week One installed: 105 NPC observations, all of them
> `Inhabitant` (83), `Walker` (15) or `Babe` (7) — none from the table above. `Looter`
> never appeared, so the "Join Me!" menu below was unreachable. **Any behavior gated on a
> Bandits program name must be tested with Bandits alone before it is trusted.**

`Bandit.SetProgram(zombie, program, programParams)` (`Bandit.lua:566`) always resets
`brain.program = {name=program, stage="Prepare"}`. **`programParams` is accepted and never
stored** — do not use it to pass state; put state on the brain instead.

### Companion — read this before building anything companion-shaped

**It already works and it is already reachable in normal play.** Right-click a bandit:
`client/BanditMenu.lua:208-220` adds a **"Join Me!"** option, gated on

```lua
zombie:getVariableBoolean("Bandit")           -- is a bandit
and not (brain.hostile or brain.hostileP)     -- is not hostile
and brain.program.name == "Looter"            -- is currently a wanderer
```

`BanditMenu.SwitchProgram` (`BanditMenu.lua:145-162`) then does exactly four things:

```lua
brain.master  = BanditUtils.GetCharacterID(player)
brain.program = { name = "Companion", stage = "Prepare" }
BanditBrain.Update(bandit, brain)
Bandit.ForceSyncPart(bandit, { id = brain.id, master = ..., program = ... })
```

A symmetric **"Leave Me!"** reverts to `Looter`.

Stages: `Prepare → Main → Guard → Main`. `Main` (`ZPCompanion.lua:13`) mirrors the master's
walk type (sprint/sneak/aim), takes a free guardpost within 40 tiles, engages hostiles
within 8 tiles while the master is within 20, otherwise follows or idles.

Four traps, all verified:

1. **`SwitchProgram` never touches hostility.** It only *reads* it as a gate. A companion
   is a friendly NPC that stays friendly by default.
2. **In singleplayer `brain.master` is ignored.** `BanditPlayer.GetMasterPlayer`
   (`client/BanditPlayer.lua:44-53`) returns `getSpecificPlayer(0)` unconditionally outside
   Multiplayer. To tell *your* companion from someone else's, compare
   `brain.master == BanditUtils.GetCharacterID(player)` yourself — do not trust the helper.
3. **~250 lines of `ZPCompanion.lua:82-403` are inside a `--[[ ]]` block comment.** Vehicle
   follow, foraging, generator upkeep, farming and housekeeping are written but disabled.
   Read before rebuilding: much of it is a starting point, not a gap.
4. **Companions may not survive leaving the cell.** See §4 — the restore path is dead code.

`CompanionGuard` is superseded: its own `Main` immediately calls
`Bandit.SetProgram(bandit, "Companion", {})`. The live guard behavior is the `Guard`
*stage* of `Companion`. `BanditMenu.lua:217` still tests for the string defensively.

---

## 3. `Bandit.*` — the public API

`shared/Bandit.lua`. Check here before writing a helper; most of what you need exists.

### Tasks
| Function | Line |
|---|---|
| `Bandit.AddTask(zombie, task)` | 286 |
| `Bandit.AddTaskFirst(zombie, task)` — interrupt: "do this now" | 300 |
| `Bandit.GetTask(zombie)` / `HasTask` / `HasTaskType(zombie, type)` | 314 / 324 / 331 |
| `Bandit.HasMoveTask(zombie)` / `HasActionTask(zombie)` | 338 / 345 |
| `Bandit.UpdateTask(zombie, task)` / `RemoveTask(zombie)` | 352 / 361 |
| `Bandit.ClearTasks(zombie)` / `ClearMoveTasks` / `ClearOtherTasks(zombie, exception)` | 369 / 393 / 408 |

### Program and social state
| Function | Line |
|---|---|
| `Bandit.GetProgram(zombie)` / `SetProgram(zombie, name, params)` / `SetProgramStage(zombie, stage)` | 559 / 566 / 578 |
| `Bandit.GetMaster(zombie)` / `SetMaster(zombie, master)` | 542 / 549 |
| `Bandit.SetHostile(zombie, bool)` / `SetHostileP(zombie, bool)` / `IsHostile(zombie)` | 588 / 596 / 604 |

### Physical state
`ForceStationary` / `IsForceStationary` (453/461), `SetSleeping` / `IsSleeping` (483/491),
`SetAim` / `IsAim` (498/506), `SetMoving` / `IsMoving` (513/521), `SetNearFire` /
`IsNearFire` (468/476), `UpdateEndurance(zombie, delta)` (423), `GetInfection` /
`UpdateInfection` (434/443), `HasExpertise(zombie, exp)` (529).

### Weapons
`GetWeapons` (612), `GetBestWeapon` (619), `SetWeapons` (700), `SetHands(zombie, itemType)`
(653), `IsOutOfAmmo` (639), `IsBareHands` (646), `NeedResupplySlot` (693).

### Possessions — where an NPC's things actually live

**The brain is the store. `zombie:getInventory()` is a view.** This is the single most
expensive thing in this document to get wrong, and the bare-name entry it used to have is
why the format changed.

| | |
|---|---|
| **Signature** | `Bandit.UpdateItemsToSpawnAtDeath(zombie, brain)` — `Bandit.lua:712` |
| **What it does** | Calls `zombie:clearItemsToSpawnAtDeath()` (`:717`), then rebuilds the entire drop list from `brain.weapons`, `brain.bag`, `brain.loot` **and** the current live inventory. Upstream's own comment: *"This translates weapons, loot, inventory to actual items to be spawned at bandit death."* |
| **What breaks if you skip it** | Everything you added to the live inventory is invisible. The NPC drops exactly what the spawner gave it and nothing else. Silent — no error, no warning, and only discoverable by killing an NPC you watched loot a house. |

Two consequences that are not obvious from the signature:

1. **A live inventory does not survive a despawn.** Bandits rebuilds the `IsoZombie` from the
   brain when an NPC re-enters range, so anything held only on the old object is gone. Log
   evidence, 04-08 run: Daniel Green went `carrying 1.5 → 5.6`, then reappeared at
   `carrying 1.5` under the same `fullname`. The brain survived; the inventory did not.
   Anything meant to persist must be mirrored into the brain — `ScenesRelationsLoot.lua`
   uses `brain.scenesCarry` for this.
2. **The working template is `ZALootWeapons.lua`.** It writes `brain.weapons`, then calls
   `Bandit.ForceSyncPart` and `Bandit.UpdateItemsToSpawnAtDeath` (`:104-105`). It never
   touches `getInventory()`. When in doubt, copy that order.

Related: `Bandit.SetWeapons` (700) already calls `UpdateItemsToSpawnAtDeath` for you (`:705`).
Nothing else does.

### Speech and appearance
`Bandit.Say(zombie, phrase, force)` (1161) — cooldown via `brain.speech` unless `force`.
`Bandit.SayLocation(bandit, targetSquare)` (1230). `PickVoice` (1150),
`AddVisualDamage` (1259), `ApplyVisuals` (79), `GetCombatWalktype` (1274),
`GetSkinTexture` / `GetHairColor` / `GetHairStyle` / `GetBeardStyle` (1331-1474).

### Sync
`Bandit.ForceSyncPart(zombie, syncData)` (74) — see §4.

### The 16 speech phrases

`BREACH BURN CAR DEAD DEATH DEFENDER_SPOTTED DRAGDOWN HIT INSIDE OUTSIDE RELOADING
ROOM_BATHROOM ROOM_KITCHEN SPOTTED THIEF_SPOTTED UPSTAIRS`

All situational. **None of them is relational** — there is no vocabulary for trust,
gratitude or suspicion. That vocabulary has to be added, not reused.

---

## 4. The brain and how it persists

`BanditBrain.Get(zombie)` → `zombie:getModData().brain` (`BanditBrain.lua:3`).
`BanditBrain.Update(zombie, brain)` (`:8`), `BanditBrain.Remove(zombie)` (`:13`).

**`getModData().brain` is a client-side runtime mirror, not the durable copy.** The
authoritative store is 32 sharded `ModData` tables `"BanditC0".."BanditC31"`, keyed by
`id % 32` (`shared/BanditGMD.lua:10`). `ModData` is engine-persisted, which is how brains
survive save/load and cross the client/server boundary.

Write path:

```
client mutates its mirror
  -> Bandit.ForceSyncPart(zombie, {id = brain.id, <any keys>})   Bandit.lua:74
  -> sendClientCommand 'Commands' 'BanditUpdatePart'
  -> BanditServer.Commands.BanditUpdatePart                      server/BanditServerCommands.lua:68
  -> merges every k,v into the authoritative shard, rebroadcasts
```

`syncData` accepts arbitrary keys; the only requirement is `syncData.id`.

**Our own records deliberately do NOT use this.** `ScenesRelations` writes
`bandit:getModData().scenesRel`, a separate key, so a Bandits update cannot collide with
us and we cannot corrupt their save data. That also means our trust values do not
currently sync in multiplayer — a known, accepted limitation.

### Brain fields

Built by `banditize(zombie, bandit, clan, args)`, `server/BanditServerSpawner.lua:294-432`.

| Field | Type | Default |
|---|---|---|
| `id` | number | `zombie:getPersistentOutfitID()` — **identifies an outfit, not an individual** |
| `fullname` | string | generated |
| `clan`, `cid`, `bid` | id | from the clan profile |
| `program` | `{name, stage}` | `args.program`, stage `"Prepare"` |
| `programFallback` | string | `args.program` |
| `master` | id | `args.pid` |
| `hostile`, `hostileP` | bool | `not clan.spawn.friendly` |
| `loyal` | bool | `args.loyal or false` |
| `permanent` | bool | `args.permanent and true or false` |
| `tasks` | array | `{}` — the task queue |
| `weapons` | table | `{melee, primary={bulletsLeft,...}, secondary={...}}` |
| `loot`, `inventory`, `clothing`, `tint`, `bag` | table | `{}` / profile |
| `health`, `accuracyBoost`, `enduranceBoost`, `strengthBoost` | number | lerped from profile sliders |
| `endurance` | number | `1.00` |
| `infection` | number | `0` |
| `speech`, `sound` | number | `0.00` — speech cooldown timestamps |
| `stationary`, `sleeping`, `aiming`, `moving`, `nearFire`, `eatBody` | bool | `false` |
| `exp` | `{n1,n2,n3}` | expertise slots |
| `personality` | table | ~10 bool flags |
| `rnd` | `{5 numbers}` | per-bandit RNG differentiators |
| `born`, `bornCoords` | number / `{x,y,z}` | spawn time and place |
| `female`, `skin`, `hairType`, `hairColor`, `beardType`, `voice` | number/bool | appearance |

---

## 5. Where everything lives

| Table | File | Purpose |
|---|---|---|
| `Bandit` | `shared/Bandit.lua` | Core public API — §3 |
| `BanditBrain` | `shared/BanditBrain.lua` | Brain accessor and predicates |
| `BanditZombie` | `client/BanditZombie.lua` | Runtime caches: `Cache` (id→IsoZombie), `CacheLightB` (bandits), `CacheLightZ` |
| `BanditPlayer` | `client/BanditPlayer.lua` | Player lookups, `GetMasterPlayer`, `CheckFriendlyFire` |
| `BanditPlayerBase` | `client/BanditPlayerBase.lua` | Player home-base detection used by programs |
| `BanditUtils` | `shared/BanditUtils.lua` | Grab bag: distance/angle math, target acquisition, move-task builders |
| `BanditPrograms` | `shared/BanditPrograms.lua` | Reusable behavior helpers consumed BY program stages — not a state machine |
| `ZombieActions` | `shared/ZombieActions/ZA*.lua` | Task handlers — §1 |
| `ZombiePrograms` | `shared/ZombiePrograms/ZP*.lua` | Program stages — §2 |
| `BanditMenu` | `client/BanditMenu.lua` | Right-click context menu (Join Me! / Leave Me!) |
| `BanditPost` | `client/BanditPost.lua` | Guardpost registry: `At`, `GetClosestFree` |
| `BanditGMD` | `shared/BanditGMD.lua` | Sharded ModData persistence — §4 |
| `BanditServer` | `server/BanditServer*.lua` | Server namespace: `.Commands`, `.Sync`, `.Spawner` |
| `BanditWeapons` / `BanditLoot` / `BanditNames` | `shared/` | Profile → weapons, loot tables, name generation |
| `BanditCompatibility` | `shared/BanditCompatibility.lua` | Cross-version shims — use these instead of raw engine calls |
| `BanditCustom` | `shared/BanditCustom.lua` | Loads clan/bandit profiles from data files |

---

## 6. Known traps

- **Queue overflow flushes everything.** 10th task wipes the queue (`Bandit.lua:290`).
- **`brain.id` is an outfit id**, from `getPersistentOutfitID()`. Two NPCs in the same
  outfit share it. Never use it as an individual identity key.
- **`BanditPermanent.Check` is dead** — `if true then return end`
  (`client/BanditPermanent.lua:8`). It is still called every cache refresh
  (`client/BanditZombie.lua:162`) with no effect. It was meant to restore bandits flagged
  `permanent` to their `bornCoords` when the player returns to a cell. The server handler
  it would call, `BanditServer.Spawner.Restore`, is still live
  (`server/BanditServerSpawner.lua:1150`). **An NPC that leaves the loaded cell is not
  guaranteed to come back.**
- **`CheckFriendlyFire` early-returns when Week One is installed**
  (`client/BanditPlayer.lua:78-81`), delegating to `BWOPlayer.ActivateWitness`. Bandits'
  own witness hostility does not run in that configuration.
- **`programParams` on `SetProgram` is discarded.**
- **`ZPThief` and `ZPCompanionGuard` have no assigning callsite.** Dead.
- **Zero `pcall` in 22,458 lines.** One error in a handler kills the rest of that frame's
  work. Wrap our own entry points.
- **`Bandit.ClearTasks` PRESERVES tasks with `task.lock == true`** (`shared/Bandit.lua:369-382`)
  — it rebuilds the table keeping only those. `Bandit.RemoveTask` ignores lock entirely
  (`:361-367`). So a locked task at the head survives somebody else's clear, and since
  `GenerateTask` **appends** with `table.insert(brain.tasks, task)` (`client/BanditUpdate.lua:1911`)
  rather than inserting first, whatever it queues lands BEHIND the locked one. This is the only
  way to make a task of ours outlive `ManageCombat`. Upstream writes `task.lock = false` itself
  (`client/BanditUpdate.lua:1383`), so mutating that field is an accepted pattern, not a hack.
- **`Bandit.AddTaskFirst` flushes the WHOLE queue past 9 entries, ignoring `lock`**
  (`shared/Bandit.lua:300-307`, `brain.tasks = {}`). Inserting "first" is not safe from a
  locked task's point of view.
- **`ManageCombat` does NOT clear unconditionally.** All four sites are guarded by
  `BanditBrain.HasTaskType` / `HasTaskTypes` / `HasActionTask`
  (`client/BanditUpdate.lua:1181/1196/1205/1212`), and `HasActionTask` excludes `Move`/`GoTo`
  (`shared/BanditBrain.lua:68-76`). That guard is load-bearing: it is why a `Smack` already in
  the queue is not re-cleared every frame. Measured in play, `ManageCombat` stole a follow
  **once** in a full session while our own rung ladder did it 35 times — do not assume upstream
  is the thief without measuring.
- **Bandits' own locked tasks, complete list**, so nothing of ours ever unlocks one of theirs:
  Die (`client/BanditUpdate.lua:282`, `:1721`), Exhausted (`:439`), Zombify (`:476`), GetUp
  (`:2191`, `shared/ZombiePrograms/ZPCamper.lua:86`, `ZPRoadblock.lua:34`).
- **Crossing a window is a STATE CHANGE, not a task.** `ClimbThroughWindowState.instance()` +
  `bandit:changeState(...)` + `setBumpType("ClimbWindow")` (`client/BanditUpdate.lua:684-686`).
  There is no `ZAClimbWindow` in `shared/ZombieActions/` — all 47 files checked. Anything that
  wants to observe a crossing must watch the engine state, not the task queue.
