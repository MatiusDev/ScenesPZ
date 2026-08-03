# NPC behaviour plan

Started 2026-08-03. The staged plan for making Bandits NPCs behave like people instead
of a friend/killer switch. Read `docs/BANDITS-API.md` first for what already exists;
this file is only about what we add and in what order.

Each stage names **what it proves**. A stage that proves nothing is not a stage, it is a
feature we guessed at. Nothing moves forward until the previous stage has been seen in a
real log — every session on the gaming PC is expensive and there is no hot reload.

## Ground rules, learned the hard way

1. **Grep `pzserver/media/` before writing any identifier.** Not the wiki, not upstream
   code. `isNPC()` and `getTarget()` both look obvious and both appear **zero times** in
   the 2,680 vanilla Lua files of 42.20. The first one silently killed `OnHitZombie` for
   two full play sessions.
2. **Vendored upstream code is not a verification source.** Bandits carries the same
   `isNPC()` defect at `BanditPlayer.lua:91`, which is exactly how we inherited it.
   Their `CheckFriendlyFire` is dead in 42.20 — anything we assumed it handled, it does
   not.
3. **Wrap, never replace.** Every change so far is a wrapper that still calls the
   original. Overwriting a Bandits function makes us mutually exclusive with every other
   mod that touches it.
4. **A comment that states an assumption must state how it was checked.** Two of our
   bugs were correct-sounding comments whose premise had never been verified.

## Verified levers

Confirmed by reading 42.20 source. Line numbers are Bandits 42.20 unless noted.

| Lever | Where | What it does |
|---|---|---|
| `Bandit.IsHostile(z)` | `Bandit.lua:604` | returns `brain.hostile or brain.hostileP` |
| Player targeting gate | `BanditUtils.lua:962` | player is only targeted when `IsHostile` |
| Zombie targeting | `BanditUtils.lua:840` | **no range limit** — we wrap it |
| `config.hearDist` | `BanditUtils.lua:815` | players only, **no effect on zombies** |
| Program switch | `BanditMenu.SwitchProgram` | global fn on a global table, wrappable |
| "Join Me!" gate | `BanditMenu.lua:214` | requires `program.name == "Looter"` |
| Spawn hostility | `BanditServerSpawner.lua:397` | `brain.hostile = not spawn.friendly` |
| Debug spawn program | `BanditMenu.lua:176` | hardcodes `"Bandit"`, ignores clan flags |
| Per-NPC seed | `brain.rnd` | 5 stable ints, free per-individual variation |

Known caveat: `Bandit.SetHostile` (`Bandit.lua:588`) has its `BanditBrain.Update` call
commented out, so the flag lives only in the client-side brain mirror. Our `trust` value
is stored in `getModData()` and does persist. Expect the number to survive a reload and
the flag possibly not.

## Do not use

- `character:isNPC()` — does not exist in 42.20. Use `instanceof(c, "IsoPlayer")`.
- `zombie:getTarget()` — does not exist in 42.20 Lua. We have **no verified way** to ask
  whether a zombie is chasing someone. Any "feels threatened" behaviour needs a signal
  found in `pzserver/media/` first, not invented.
- `brain.personality` — flavour only (`alcoholic`, `smoker`, collectors). Useless for
  social logic.
- `brain.id` as an identity key — it comes from `getPersistentOutfitID()` and identifies
  an outfit, so two NPCs in the same clothes share it.

## Stages

### Stage 0 — foundation (DONE, confirmed 2026-08-03)

Trust store on the entity, hit and witness penalties, escalation to hostile, engagement
range. **Proved:** an engine event can move a number that changes what an NPC does.

Observed in `logs/console.txt`:

```
9306369:  -25 (attacked)   -> trust  -25 [wary]
9306369:  -25 (attacked)   -> trust  -50 [hostile]
12452221: -10 (saw attack) -> trust  -10 [neutral]
...
12452221: -10 (saw attack) -> trust  -50 [hostile]
```

The witness crossed to hostile on the fifth observed beating, exactly as predicted. The
NPCs also held position instead of running the map, confirming the engagement cap.

### Stage 1 — a way back up (built 2026-08-03, untested)

Trust could only fall. That alone is strictly worse than vanilla Bandits: a way to lose
allies and none to earn them.

The player hits a **non-bandit** zombie within sight of a non-hostile bandit, and that
bandit gains `HELP_REWARD`. Same `OnHitZombie` event, same proximity cache, opposite
sign — the branch is chosen by whether the victim carries the `Bandit` flag.

Two deliberate constraints:

- **Hostile NPCs are excluded.** Killing zombies in front of someone already trying to
  kill you does not make them reconsider. Earning peace back needs to know who made them
  hostile first, which is a separate feature.
- **The reward logs quietly.** `OnHitZombie` fires per swing, not per kill, so only tier
  crossings print. `SR.Adjust` takes a `quiet` flag for exactly this.

**Proves:** trust is a relationship, not a punishment counter.

**Note what this does and does not do yet.** `SR.Apply` only escalates — nothing acts on
positive trust until stage 2 exists. Expect to see the number climb in the log and the
NPC behave the same. That is correct, not broken.

### Stage 2 — the companion trust gate

Wrap `BanditMenu.SwitchProgram`, refuse promotion to `Companion` below a trust
threshold, keep the original call. Their "Join Me!" still appears — **the NPC refusing
you is the feature.**

Blocked on a `Looter` existing to test against: the debug spawn menu forces the `Bandit`
program, so a Looter only appears from natural spawn of a `wanderer`-without-`assault`
clan (`TLOU_Survivors`).

**Proves:** trust gates access, not just aggression.

### Stage 3 — demotion

Trust falling while an NPC is a companion sends it back to `Looter`. The reverse of
stage 2 through the same seam.

**Proves:** the relationship is live, not a one-time check at the door.

### Stage 4 — trust is not one number

Agreed direction, deliberately undesigned until stages 1-3 produce data.

- **A floor, not a drift.** In an apocalypse a stranger starts below neutral. No time
  decay, ever: it fires ~10x per real minute at `DayLength=4`, and worse, it makes
  *waiting* a strategy.
- **Separate axes.** "You fight well" and "you won't stab me" are different judgements.
  That gap is what makes betrayal coherent instead of random.
- **External propagation.** Another NPC reporting what you did. `brain.clan` and the
  proximity cache already exist; nothing new needs inventing.
- **Per-individual variation.** `brain.rnd` gives 5 stable ints per NPC, free.

### Stage 5 — threat response

Only after a verified "am I in danger" signal exists. Until then, engagement range is
proximity and nothing more. Do not fake this with guessed API names.

## Tuning log

Values we have chosen and why, so the next session does not re-litigate them.

| Value | Where | Set | Reason |
|---|---|---|---|
| `HIT_PENALTY = -25` | `ScenesRelationsEvents.lua` | 2026-08-02 | one hit is a warning, two is a decision |
| `WITNESS_PENALTY = -10` | `ScenesRelationsEvents.lua` | 2026-08-02 | seeing costs less than receiving |
| `WITNESS_RADIUS_SQ = 144` | `ScenesRelationsEvents.lua` | 2026-08-02 | 12 tiles, matches `BanditPlayer.lua:97` |
| `ENGAGE_RANGE = 8` | `ScenesRelationsEngagement.lua` | 2026-08-03 | user's call; close enough to read as defence |
| `HELP_REWARD = 2` | `ScenesRelationsEvents.lua` | 2026-08-03 | per swing, not per kill; ~13 swings to `friendly` |

Resolved 2026-08-03: five observed beatings to flip a witness was confirmed in a real log
and left as is for now — it reads as a person taking a while to give up on you.

Open question: `HELP_REWARD` is measured per swing because `Events.OnZombieDead` carries
no attacker argument, so a slow weapon earns trust faster than a fast one. If that shows
up as gamey in play, the fix is a cooldown per NPC, not a smaller number.

## Missing from base Bandits

Things Week One and The Ark provided that plain Bandits does not, confirmed by grep:

- **No dialogue.** No key handler, no conversation UI anywhere in Bandits' Lua. The `T`
  key belonged to Week One. `Bandit.Say` (`Bandit.lua:1161`) is one-way NPC speech.
  Any talking system is ours to build, and it is the natural home for intent-based trust.

## Cleanup owed before anything ships

- `ScenesRelationsRun.lua` is marked TEMPORARY and must be deleted once its questions are
  answered.
- `SR.DEBUG = true` must go back to `false`.
