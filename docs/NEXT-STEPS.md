# Where we are, what is next

Updated 2026-08-03. Read this first in a new session, together with `CLAUDE.md`.

## State

| Mod | id | Status |
|---|---|---|
| ScenesDoctor | `scenesDoctor` | Working. Loads clean, instruments by prefix (`Bandit`, `BWO`, `Scenes`). Verified in a real game run — 1,080 CALL + 72 MEM samples. |
| ScenesRelations | `scenesRelations` | Core written, lints clean. **Never run in game.** Trust store + tiers + decay. No event wiring yet. |
| TLOUFactions | `tlouFactions` | Loads. Three clans, two bandits, vanilla gear only. Parked while we do B. |

Upstream pinned in `deps.lock.json`. Run `./tools/deps.py check` before touching `vendor/`.

## Decisions already made — do not relitigate

- **Build on Bandits, do not fork it.** Slayer ships fixes same-day (Bandits and The Ark both updated 2026-08-02). There is no public repo, so there is nowhere to send a PR. Contribution channel is his Discord.
- **Order of work: B then A.** B = the relations/social system (does not exist in the ecosystem). A = TLOU scenes with missions. Missions without relationships are fetch quests.
- **Week One should be disabled while developing.** Its newest version folder is 42.18 against a 42.20 game; every error in the last run came from it. It is a reference, not a dependency.
- **Relation records live on the entity** (`bandit:getModData().scenesRel`), never in a global table keyed by `BanditUtils.GetCharacterID` — that id comes from `getPersistentOutfitID()` and identifies an outfit, not an individual.

## Next task: wire events (step A of B)

Trust never moves on its own right now. `SR.Adjust` has no callers.

1. Have `pz-research` map the real damage/interaction events across the 2,680 files in
   `pzserver/media/lua/`. **Do not guess event names** — a wrong one fails silently, the
   handler simply never fires and there is no error.
2. Already confirmed by reading `vendor/Bandits/.../client/BanditZombie.lua:193`:
   `Events.OnZombieUpdate`, `Events.OnZombieDead`.
3. Wire: player attacks a bandit → `SR.Adjust(bandit, -N, "attacked")`; player helps →
   positive. Call `SR.Apply` when the tier changes.
4. Run it in game, confirm `SREL|` lines in `console.txt`.

## Integration surface (all verified in Bandits 42.20)

```lua
BanditBrain.Get(zombie)                    -- read state (zombie:getModData().brain)
Bandit.SetProgram(zombie, prog, params)    -- change role
Bandit.SetProgramStage(zombie, stage)      -- jump within a behavior
Bandit.AddTask(zombie, task)               -- queue an action
Bandit.AddTaskFirst(zombie, task)          -- interrupt: "do this now"
Bandit.SetHostile / SetHostileP            -- the four booleans
Bandit.Say(zombie, phrase, force)          -- speech, 14 tiles, cooldown via brain.speech
BanditZombie.GetAllB()                     -- cached bandits (light entries)
BanditZombie.GetInstanceById(id)           -- light entry -> real IsoZombie
```

## Open findings on Bandits, not yet acted on

- `BanditUtils.AreEnemies` runs 460,361 times per minute. Pure function, not a leak — an
  O(n²) caller. Performance lead.
- Lua heap grew +18,225 KB/min in the last run. Source unidentified; Week One is
  uninstrumented and is where the errors are.
- `BanditPermanent.Check` opens with `if true then return end` — dead, disabled.
- `lua/client/error.txt` is a 1,581-line macOS crash dump shipped to the Workshop.
