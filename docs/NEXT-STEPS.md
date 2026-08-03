# Where we are, what is next

Updated 2026-08-03. Read this first in a new session, together with `CLAUDE.md`.

## State

| Mod | id | Status |
|---|---|---|
| ScenesDoctor | `scenesDoctor` | Working. Loads clean, instruments by prefix (`Bandit`, `BWO`, `Scenes`). Verified in a real game run — 1,080 CALL + 72 MEM samples. |
| ScenesRelations | `scenesRelations` | Trust store + tiers + decay + `OnHitZombie` wiring. Lints clean. **Never run in game.** |
| TLOUFactions | `tlouFactions` | Loads. Three clans, two bandits, vanilla gear only. Parked while we do B. |

Upstream pinned in `deps.lock.json`. Run `./tools/deps.py check` before touching `vendor/`.

## Decisions already made — do not relitigate

- **Build on Bandits, do not fork it.** Slayer ships fixes same-day (Bandits and The Ark both updated 2026-08-02). There is no public repo, so there is nowhere to send a PR. Contribution channel is his Discord.
- **Order of work: B then A.** B = the relations/social system (does not exist in the ecosystem). A = TLOU scenes with missions. Missions without relationships are fetch quests.
- **Week One should be disabled while developing.** Its newest version folder is 42.18 against a 42.20 game; every error in the last run came from it. It is a reference, not a dependency.
- **Relation records live on the entity** (`bandit:getModData().scenesRel`), never in a global table keyed by `BanditUtils.GetCharacterID` — that id comes from `getPersistentOutfitID()` and identifies an outfit, not an individual.

## Done: events wired (commit `b99ebeb`)

`client/ScenesRelationsEvents.lua` hooks `Events.OnHitZombie`. Direct hit −25, witnesses
within 12 tiles who can see the attacker −10. Lints clean, **not yet run in game.**

### Event contract — verified, never guess these

```lua
Events.OnHitZombie.Add(function(zombie, attacker, bodyPart, weapon) end)
-- TARGET first, ATTACKER second. Backwards = trust moves on the wrong entity, silently.
--   pzserver/media/lua/shared/Definitions/DamageModelDefinitions.lua:24  (vanilla)
--   vendor/Bandits/.../client/BanditUpdate.lua:2136                      (Bandits)
Events.OnZombieDead.Add(function(zombie) end)      -- no attacker argument
Events.OnPlayerDeath.Add(function(playerObj) end)
```

**There is no vanilla event for giving an item to a character.** `RequestTrade` /
`AcceptedTrade` / `TradingUI*` are the player-to-player trading window only. Positive
trust from gifts needs another mechanism — do not invent an event name.

`Events.OnZombieUpdate` is real (Bandits uses it at `BanditUpdate.lua:2483`) but appears
nowhere in vanilla Lua. Grep before using any name not already listed here.

## Next task: verify in game, then positive trust

1. Enable ScenesRelations, disable Week One, hit a friendly bandit. Expect `SREL|` lines
   in `console.txt` showing the tier moving neutral → wary → hostile.
2. Confirm whether `OnHitZombie` fires client-side only. Bandits registers it under
   `lua/client/`, which suggests yes — UNCONFIRMED, and it decides where trust logic can
   safely live in multiplayer.
3. Design the positive side. Nothing raises trust yet except decay drifting toward 0.

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
