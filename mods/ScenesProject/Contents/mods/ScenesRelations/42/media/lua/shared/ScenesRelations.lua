-- ScenesPZ Relations -- a trust layer over the Bandits framework.
--
-- WHY THIS EXISTS
-- Bandits models the entire social state of an NPC with four booleans on its brain:
-- clan, hostile, loyal, hostileP. There is no state between "friendly" and "will kill
-- you", so relationships flip instead of developing, and the player never sees it coming.
--
-- This module keeps trust as a number and remembers what caused each change. It stores
-- that record under its own key on the NPC entity (see STORAGE below), so a Bandits
-- update cannot collide with us and we cannot corrupt their save data.

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
-- The record lives on the NPC entity, exactly where Bandits keeps its own brain
-- (BanditBrain.Get is `zombie:getModData().brain`). Three reasons this is right:
--   * no collision -- one record per entity, guaranteed
--   * it saves and loads with the world, for free
--   * it dies with the NPC, so the store cannot grow without bound
--
-- Do NOT key a global table by BanditUtils.GetCharacterID. That id is derived from
-- getPersistentOutfitID() (BanditUtils.lua:632), so two NPCs wearing the same outfit
-- share an id. It identifies an appearance, not an individual.
function SR.Get(bandit)
    if not bandit then return nil end
    local modData = bandit:getModData()
    if not modData then return nil end
    if not modData.scenesRel then
        modData.scenesRel = { trust = 0, memory = {} }
    end
    return modData.scenesRel
end

--- Label for logs only. Not unique -- see the warning above.
function SR.KeyOf(bandit)
    if not bandit then return "?" end
    local ok, id = pcall(BanditUtils.GetCharacterID, bandit)
    return (ok and id) and tostring(id) or "?"
end

function SR.Tier(bandit)
    local record = SR.Get(bandit)
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

    table.insert(record.memory, { delta = delta, reason = reason or "unknown" })
    while #record.memory > SR.MEMORY_CAP do
        table.remove(record.memory, 1)
    end

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
