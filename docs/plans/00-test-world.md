# Stage 00 — a test world

**Status: built, awaiting its first run.**

## The problem

Every stage after this one needs a person standing in front of you. Until now getting one
meant starting a game and waiting for the spawn scheduler to roll a friendly clan, which
costs real minutes per run and produces a different situation every time. Half the value of
a session on the gaming PC was being spent looking for somebody to test on.

Two populations fix it, and they are deliberately different so the log can tell them apart.

## Deliverables

### 1. Survivors holed up in houses

`TLOU_Homesteaders`, clan `2fc3a279-dd87-5ee1-b8d4-1b7ecc4a82fd` in
`TLOUFactions/common/bandits/clans.txt`. Entirely declarative — no Lua.

`defenders = true` is the only flag that reaches `spawnHouse`
(`BanditServerSpawner.lua:1006`). It finds the building under the spawn point,
`generateSpawnPointBuilding` places one NPC per room, and the program becomes `Defend`.
`wanderer` is off so they never fall back to roaming; these people are staying put.

Three NPC definitions ship — `Homesteader_01`, `_02`, `_03` — and the number is not
decorative. `spawnGroup` picks **distinct** definitions from the clan and stops when it runs
out (`BanditServerSpawner.lua:450-468`), so a clan with one definition can never spawn more
than one NPC no matter what `groupMax` says. Three definitions, `groupMax = 3`.

`dayStart = 0`: they are part of the world from the first morning, unlike the raider clans
which start at 1 because they are an escalation.

### 2. One companion at your side on a new game

`TLOUFactions/42/media/lua/server/TLOUFactionsCompanion.lua`. Server code, because it
creates a character in the world and that belongs on the server side even in singleplayer.

On `OnNewGame` it queues one spawn and retries on tick until the cell is ready, capped at
200 attempts so a spawn that can never succeed does not leave a handler running per frame
forever. It calls `BanditServer.Spawner.Clan` — the documented entry point for mods — with
`program = "Companion"` and `loyal = true`.

**It deliberately does not touch trust.** `loyal` is Bandits' mechanical flag: the NPC
follows you and treats your enemies as its own. Trust is our number and starts at zero like
everyone else's. Somebody who walks beside you before deciding what they think of you is a
better opening state than a friend, and it makes the trust system measurable from the first
swing.

## Done when

- A new game starts with exactly one survivor beside the player, following.
- Houses in unexplored areas sometimes contain friendly survivors who stay in them.
- Both appear in `console.txt` as `PROBE` lines with distinguishable clan ids.

## What can go wrong, and what it means

| Symptom | Cause |
|---|---|
| No companion, no `TLOU\|` lines at all | the mod is not loaded, or you loaded a save instead of starting a new game — `OnNewGame` fires only on new games |
| `TLOU\| BanditServer.Spawner unavailable` | mod order: Bandits must load first |
| `TLOU\| companion spawn gave up after 200 ticks` | no free square near the player; try a different spawn town |
| Companion spawns but does not follow | `brain.master` did not take — `ZPCompanion.lua:26` returns immediately without a master |
| Never any house survivors | expected in areas you already explored: `spawnHouse` refuses buildings the player entered in the last 7 in-game days (`BanditServerSpawner.lua:777-786`) |

## Known limit

Multiplayer is out of scope here. On a dedicated server there is no single player to start
beside, and the client has no business spawning anyone, so the handler returns early on
`isClient()`.
