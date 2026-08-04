# Stage 01 — durable memory

**Status: DONE.** The memory test passed in a real session on 2026-08-04: an NPC's record
survived its cell unloading and came back intact under the same id.

This is the stage the whole mod rests on. Everything else is a feature; this decides
whether an NPC can know you at all.

## The problem

The trust record lived in `bandit:getModData()`. The engine destroys the entity when its
cell unloads, and the record went with it. The scene that breaks is the premise: you fight
beside somebody for half an hour, walk eight blocks away, come back, and they have never
met you.

## Deliverables

### 1. The sharded store

`ScenesRelations/42/media/lua/shared/ScenesRelationsStore.lua`. Thirty-two global ModData
tables, `ScenesRelC0`..`ScenesRelC31`, keyed by `math.floor(math.abs(id) % 32)`. Claimed in
`OnInitGlobalModData`, mirrored on `OnReceiveGlobalModData` for multiplayer clients.
`ModData.transmit` fires only when `isClient() or isServer()`, so singleplayer sends no
packets for something that changes once per melee swing.

Thirty-two, not one, because ModData is serialised as a unit and one table holding every
survivor you have ever met would be rewritten in full on every save.

### 2. Keying, and why the id question is already answered

The key is `BanditUtils.GetCharacterID`, the same number Bandits keys its own clusters by.

That is not a guess. `BanditUpdate.lua:1983-1991` re-banditizes any zombie *not* flagged
`Bandit` whose id **is** present in the cluster, and turns back into an ordinary zombie any
flagged one whose id is **absent**. That branch is the only way an NPC survives a reload in
Bandits at all, so the entire framework already depends on the id being stable across the
cycle. Keying off the same number means their code breaks first, and far more loudly, if it
ever stops being true.

The fuzzy fallback in `docs/DESIGN-MEMORY.md` — recognise by name plus traits plus clan —
stays designed and unbuilt. It exists so that a failed probe does not kill the premise.

### 3. Reading must not create

`SR.Peek` reads and returns `nil` for a stranger. `SR.Get` creates. Only `SR.Adjust` calls
`SR.Get`.

The distinction is bigger than it looks. A record means *one survivor the player has met*.
If merely looking at somebody minted a record, the save would grow with every zombie the
engine ever spawned rather than with everyone who matters.

### 4. Emotion left the store

Posture moved to `SR.Mood(bandit)`, on the entity. The PRD splits emotion from memory:
emotion changes constantly and decays, memory changes only on events and never does.
Posture is emotion — meaningless after a reload — and keeping it in a permanent store would
have minted a record for every NPC that was ever startled near the player.

### 5. Episodes are dated

`{ day, delta, reason }`. `SR.Today()` is `getGameTime():getWorldAgeHours() / 24` floored —
monotonic, no month-end reset, and what vanilla itself ages the world with
(`ISButtonPrompt.lua:520`). Nothing reads `day` yet. It is stamped now because stage 02
ranks by it and a field added later cannot be backfilled for events that already happened.

### 6. Migration

Automatic and one-way. An existing entity record is moved to the store on first touch and
the original cleared, so there is never a second version of the truth.

## Done when

Test 10 in `docs/TEST-RUNS.md` passes: an NPC's `id` and `trust` come back unchanged after
its cell unloads and reloads, and `known=true`.

## Deliberately not in this stage

No new behaviour of any kind. Same trust maths, same tiers, same events. If anything about
how the mod *plays* changed, this stage did something it should not have.
