-- ScenesPZ Relations -- a trust layer over the Bandits framework.
--
-- WHY THIS EXISTS
-- Bandits models the entire social state of an NPC with four booleans on its brain:
-- clan, hostile, loyal, hostileP. There is no state between "friendly" and "will kill
-- you", so relationships flip instead of developing, and the player never sees it coming.
--
-- This module keeps trust as a number and remembers what caused each change. It never
-- writes into the Bandits brain -- it keeps its own store keyed by character id, so a
-- Bandits update cannot collide with us and we cannot corrupt their save data.

ScenesRelations = ScenesRelations or {}
local SR = ScenesRelations

SR.MIN, SR.MAX = -100, 100
SR.MEMORY_CAP = 12          -- bounded on purpose: an unbounded log in a mod that runs
                            -- for hours is exactly how you ship a memory leak.
SR.DEBUG = false

-- Trust bands. Ordered high to low; Tier() returns the first band the value reaches.
SR.TIERS = {
    { name = "ally",     min =  60 },
    { name = "friendly", min =  25 },
    { name = "neutral",  min = -10 },
    { name = "wary",     min = -40 },
    { name = "hostile",  min = -100 },
}

local function store()
    -- ModData.getOrCreate is the vanilla persistence API
    -- (pzserver/media/lua/client/Foraging/forageClient.lua:7).
    local data = ModData.getOrCreate("ScenesRelations")
    data.actors = data.actors or {}
    return data
end

--- Stable per-NPC key. Bandits assigns these; we only read them.
function SR.KeyOf(bandit)
    if not bandit then return nil end
    local id = BanditUtils.GetCharacterID(bandit)
    return id and tostring(id) or nil
end

function SR.Get(bandit)
    local key = SR.KeyOf(bandit)
    if not key then return nil end
    local actors = store().actors
    if not actors[key] then
        actors[key] = { trust = 0, memory = {} }
    end
    return actors[key]
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
function SR.Adjust(bandit, delta, reason)
    local record = SR.Get(bandit)
    if not record then return nil, nil end

    local before = SR.Tier(bandit)
    record.trust = math.max(SR.MIN, math.min(SR.MAX, record.trust + delta))

    table.insert(record.memory, { delta = delta, reason = reason or "unknown" })
    while #record.memory > SR.MEMORY_CAP do
        table.remove(record.memory, 1)
    end

    local after = SR.Tier(bandit)
    if SR.DEBUG or before ~= after then
        SR.Log(string.format("%s: %+d (%s) -> trust %d [%s]",
            SR.KeyOf(bandit), delta, reason or "unknown", record.trust, after))
    end
    return before, after
end

--- Push our trust tier down into the Bandits brain. This is the ONLY place we write
--- to their state, so there is exactly one line to audit if their API changes.
function SR.Apply(bandit)
    local tier = SR.Tier(bandit)
    if tier == "hostile" or tier == "wary" then
        Bandit.SetHostile(bandit, true)
    else
        Bandit.SetHostile(bandit, false)
    end
    return tier
end

--- Trust drifts toward neutral when nothing happens, so a single bad moment is not
--- permanent and a single gift does not buy a friend forever.
function SR.Decay(bandit, amount)
    local record = SR.Get(bandit)
    if not record or record.trust == 0 then return end
    local step = math.min(amount or 1, math.abs(record.trust))
    SR.Adjust(bandit, record.trust > 0 and -step or step, "decay")
end

function SR.Log(msg)
    print("SREL| " .. tostring(msg))
end
