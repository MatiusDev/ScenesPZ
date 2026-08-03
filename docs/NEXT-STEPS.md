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

## First probe run (2026-08-03) — inconclusive, and why

`logs/console.txt`, 1.5 MB, 131 `SREL|` lines. Four findings:

1. **Week One was still loaded.** `LOG : Mod f:0> loading BanditsWeekOne`. The run was
   believed to be Bandits-only and was not. Loaded: `scenesDoctor`, `Bandits2`,
   `scenesRelations`, `Waterpipes`, `BanditsWeekOne`.
2. **Week One shadows the program set.** All 105 NPC observations were `Inhabitant` (83),
   `Walker` (15), `Babe` (7). None of those exist in Bandits. `Looter` never appeared, so
   `joinMe=false` on all 13 nearby NPCs — the "Join Me!" menu requires
   `program.name == "Looter"` (`BanditMenu.lua:214`). **The companion plan is untestable
   with Week One installed.**
3. **Trust never moved.** Zero non-PROBE `SREL|` lines. `SR.Adjust` never fired.
   `OnHitZombie` wiring is still UNVERIFIED in game.
4. **Time compression measured: ~10x.** `DayLength=4`. Sweeps landed at frames 3520 →
   7514 → 11161, about 3,800 frames ≈ 63 real seconds apart. One in-game minute ≈ 6.3 real
   seconds, so the removed decay would have fired ~10 times per real minute. The 8-24x
   estimate that justified removing it is confirmed.

Brain shape confirmed in the wild: `personality=none set`, `rnd=0,6,81,773,9664`,
`loyal=true permanent=true master=1` on a Week One companion.

## Spawning NPCs on demand — already exists, do not build it

`BanditMenu.lua:236-243` adds a **"Spawn Bandit Clan"** context submenu gated on
`isDebugEnabled() or isAdmin()`, listing every clan from `BanditCustom`. Debug mode also
gives `[DGB] Remove All Bandits` and `[DGB] Show Brain`.

Launch PZ with **`-debug`** (Steam → Properties → Launch Options). No code needed.

## Next task: a clean Bandits-only run

1. Disable Week One **and The Ark** in the in-game mod menu, not just on Steam. Confirm in
   the log that `loading BanditsWeekOne` is absent. Keep `Bandits2`, `scenesRelations`,
   `scenesDoctor`.
2. Launch with `-debug`, spawn a friendly clan, confirm `prog=Looter` and `joinMe=true`
   appear in the probe lines.
3. **Hit that NPC.** A `SREL|` trust line must appear. This is the last unverified piece
   of code we have already written.
4. Save, quit, reload — confirm `trust` survives.

Only after step 3 passes is the companion trust gate worth writing. The design: wrap
`BanditMenu.SwitchProgram` (a global function, `BanditMenu.lua:145`), refuse promotion to
Companion below a trust threshold, keep the original call. Their "Join Me!" still appears;
the NPC refusing you *is* the feature.

## Trust model — direction agreed, not yet designed

Time decay is gone for good: it fired ~10x per real minute, and worse, it made **waiting a
strategy**. Trust moves on events only. Open design, deliberately unbuilt until there is
data:

- A **floor**, not a drift. In an apocalypse a stranger probably starts below neutral.
- **Trust is not one number.** "You fight well" and "you won't stab me" are different, and
  that difference is what makes betrayal coherent instead of random.
- **External sources.** Another NPC reporting what you did — Bandits already gives us
  `brain.clan` and the proximity cache to propagate it without inventing anything.
- `brain.personality` is **flavor only** (`alcoholic`, `smoker`, collectors) — useless for
  this. `brain.rnd` (5 stable ints per NPC) is a free per-individual seed we can use.

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
