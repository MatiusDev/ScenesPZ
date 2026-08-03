-- ScenesPZ Relations -- a trust layer over the Bandits framework.
--
-- WHY THIS EXISTS
-- Bandits models the entire social state of an NPC with four booleans on its brain:
-- clan, hostile, loyal, hostileP. There is no state between "friendly" and "will kill
-- you", so relationships flip instead of developing, and the player never sees it coming.
--
-- This module keeps trust as a number and remembers what caused each change. The record
-- itself lives in our own sharded global ModData (ScenesRelationsStore.lua), never in
-- Bandits' tables, so an update on their side cannot collide with us and we cannot
-- corrupt their save data.

require "ScenesRelationsStore"

ScenesRelations = ScenesRelations or {}
local SR = ScenesRelations

SR.MIN, SR.MAX = -100, 100
SR.MEMORY_CAP = 12          -- bounded on purpose: an unbounded log in a mod that runs
                            -- for hours is exactly how you ship a memory leak.
SR.DEBUG = true          -- ON while we are gathering data. Turn off before shipping.

-- Trust bands. Ordered high to low; Tier() returns the first band the value reaches.
SR.TIERS = {
    { name = "ally",     min =  60 },
    { name = "friendly", min =  25 },
    { name = "neutral",  min = -10 },
    { name = "wary",     min = -40 },
    { name = "hostile",  min = -100 },
}

-- STORAGE
-- The record does NOT live on the NPC entity. It used to, and that was the single biggest
-- risk to the premise: the entity is destroyed when its cell unloads, so an NPC you spent
-- half an hour earning would come back a stranger. See ScenesRelationsStore.lua for the
-- shard layout and for the evidence that Bandits' own framework already depends on the id
-- surviving that cycle.
--
-- On BanditUtils.GetCharacterID: it returns getPersistentOutfitID() with the hat bit
-- cleared (BanditUtils.lua:628-648). The name reads like an outfit template id, and an
-- earlier version of this comment claimed two NPCs in the same clothes would collide.
-- The 2026-08-03 log disproves that: six survivors spawned from the single Survivor_01
-- definition came back with seven distinct ids. The engine randomises the outfit per
-- individual, so the id is per person in practice.

--- The store key. Same number Bandits keys its own clusters by.
function SR.IdOf(bandit)
    if not bandit then return nil end
    local ok, id = pcall(BanditUtils.GetCharacterID, bandit)
    if not ok or type(id) ~= "number" then return nil end
    return id
end

--- Label for logs.
function SR.KeyOf(bandit)
    local id = SR.IdOf(bandit)
    return id and tostring(id) or "?"
end

--- Whole days since the world began. Monotonic, never resets at month end, and cheap --
--- `getWorldAgeHours` is what vanilla itself uses to age the world
--- (ISButtonPrompt.lua:520, WinterIsComing.lua:8). Episodes are stamped with it so that
--- "when" is answerable later without a second source of truth.
function SR.Today()
    local gt = getGameTime()
    if not gt then return 0 end
    local ok, hours = pcall(function() return gt:getWorldAgeHours() end)
    if not ok or type(hours) ~= "number" then return 0 end
    return math.floor(hours / 24)
end

--- Read without creating. Returns nil for an NPC nothing has ever happened with.
---
--- This is the default way to ask. The distinction matters more than it looks: a record
--- is one survivor the player has MET, and the store is permanent. If merely walking past
--- someone minted a record, the save would grow with every NPC the game ever spawned
--- rather than with everyone who matters.
function SR.Peek(bandit)
    return SR.Store.Get(SR.IdOf(bandit))
end

--- Read, creating the record if this is the first thing that has ever happened between
--- the player and this NPC. Only SR.Adjust should need this.
function SR.Get(bandit)
    local id = SR.IdOf(bandit)
    if not id then return nil end

    local record = SR.Store.Get(id)
    if record then return record end

    -- MIGRATION. Saves made before the store existed keep the record on the entity. Move
    -- it once, on first touch, and clear the old copy so there is never a second version
    -- of the truth. Harmless on a new save: the field is simply absent.
    local modData = bandit:getModData()
    local legacy = modData and modData.scenesRel
    if legacy then
        modData.scenesRel = nil
        SR.Store.Put(id, legacy)
        SR.Log(string.format("STORE migrated %d off the entity (trust %s)",
            id, tostring(legacy.trust)))
        return legacy
    end

    record = { trust = 0, memory = {}, met = SR.Today() }
    SR.Store.Put(id, record)
    return record
end

--- Transient state -- posture, and whatever else the appraisal layer needs to remember
--- for the next few seconds. Deliberately NOT in the store.
---
--- The PRD draws the line and this is where it lands in code: emotion changes constantly
--- and decays, memory changes only on events and never decays. Posture is emotion. It is
--- meaningless after a reload, and putting it in the permanent store would mint a record
--- for every NPC that ever got startled near the player -- exactly the unbounded growth
--- SR.Peek exists to prevent. So it lives on the entity and dies with it, which is the
--- correct lifetime for it.
function SR.Mood(bandit)
    local modData = bandit and bandit:getModData()
    if not modData then return nil end
    if not modData.scenesMood then modData.scenesMood = {} end
    return modData.scenesMood
end

function SR.Tier(bandit)
    local record = SR.Peek(bandit)
    if not record then return "neutral" end
    for _, tier in ipairs(SR.TIERS) do
        if record.trust >= tier.min then return tier.name end
    end
    return "hostile"
end

--- Move trust and remember why. Returns oldTier, newTier so callers can react to a change.
---
--- `quiet` suppresses the per-call debug line, never the tier-change line. It exists for
--- sources that fire per swing rather than per event: OnHitZombie runs several times per
--- zombie killed, and at one line per nearby bandit per swing an ordinary fight buries
--- the log we actually have to read on the other machine.
function SR.Adjust(bandit, delta, reason, quiet)
    local record = SR.Get(bandit)
    if not record then return nil, nil end

    local before = SR.Tier(bandit)
    record.trust = math.max(SR.MIN, math.min(SR.MAX, record.trust + delta))

    -- `day` is not read yet. It is stamped now because episodes are ranked by salience
    -- and recency in the next phase (docs/DESIGN-MEMORY.md), and a field added later
    -- cannot be backfilled for events that already happened.
    table.insert(record.memory, {
        day = SR.Today(),
        delta = delta,
        reason = reason or "unknown",
    })
    while #record.memory > SR.MEMORY_CAP do
        table.remove(record.memory, 1)
    end

    -- The record is the table the store handed back, so the mutations above already
    -- landed. Put exists to push the shard in multiplayer; it is a no-op in singleplayer.
    SR.Store.Put(SR.IdOf(bandit), record)

    local after = SR.Tier(bandit)
    if before ~= after or (SR.DEBUG and not quiet) then
        SR.Log(string.format("%s: %+d (%s) -> trust %d [%s]",
            SR.KeyOf(bandit), delta, reason or "unknown", record.trust, after))
    end
    return before, after
end

--- Push our trust tier down into the Bandits brain. This is the ONLY place we write
--- to their state, so there is exactly one line to audit if their API changes.
---
--- Escalation only. We never clear a hostile flag, because we did not necessarily set
--- it: Bandits raises it for its own reasons (raider clans, witnessed friendly fire in
--- BanditPlayer.CheckFriendlyFire) and clearing it would silently disarm their AI.
--- Principle 4 -- extend, never replace. Earning peace back is a separate feature that
--- first has to know who made the NPC hostile.
--- Only "hostile" arms them. "wary" is the middle ground this whole module exists to
--- create -- if it also set the flag, one hit would flip an NPC to lethal and we would
--- have rebuilt the binary we set out to replace.
function SR.Apply(bandit)
    local tier = SR.Tier(bandit)
    if tier == "hostile" then
        Bandit.SetHostile(bandit, true)
    end
    return tier
end

-- NO TIME DECAY. Deliberately removed, not forgotten.
--
-- Trust used to drift toward neutral once per in-game minute. Two things were wrong:
--   * `EveryOneMinute` is an IN-GAME minute. A day is compressed into 1-3 real hours, so
--     it fired roughly 8-24 times per real minute -- trust evaporated in seconds.
--   * Worse, it made WAITING a strategy. Shoot someone, walk away, come back forgiven.
--     A mechanic that rewards doing nothing is not a mechanic.
--
-- What decay tried to solve -- one mistake should not condemn you forever -- is solved
-- by the opposing action instead: helping repairs what hurting broke. Trust moves on
-- events, never on the clock.

function SR.Log(msg)
    print("SREL| " .. tostring(msg))
end
