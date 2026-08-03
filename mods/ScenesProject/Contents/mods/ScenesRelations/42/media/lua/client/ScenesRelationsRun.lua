-- ScenesPZ Relations -- TEMPORARY probe. Delete once the questions below are answered.
--
-- This file implements nothing. It exists so that one play session answers the questions
-- that decide whether a trust-gated companion is buildable at all. A session on the other
-- machine is expensive, and guessing instead of measuring is exactly what produced the
-- wrong decay math.
--
-- QUESTIONS THIS ANSWERS
--   1. Which program do friendly NPCs actually spawn with? "Join Me!" only appears for
--      Looter (BanditMenu.lua:214). If friendlies are Camper/Defend/Roadblock in normal
--      play, the companion plan has nowhere to attach.
--   2. Would "Join Me!" appear on the NPCs actually near the player?
--   3. What is really inside brain.rnd and brain.personality in the wild?
--   4. Does a trust record survive a save and reload?

require "ScenesRelations"
local SR = ScenesRelations

local PROBE_RANGE = 30          -- tiles. Wide enough to catch NPCs before they matter.
local shapeDumped = false       -- brain shape is dumped once, not every sweep.

--- Recreates the exact gate BanditMenu.lua:210-215 uses, so the log reports what the
--- player would really see on a right-click instead of what we assume.
local function wouldOfferJoinMe(brain)
    if not brain then return false end
    if brain.hostile or brain.hostileP then return false end
    return brain.program ~= nil and brain.program.name == "Looter"
end

local function describePersonality(personality)
    if type(personality) ~= "table" then return "none" end
    local flags = {}
    for key, value in pairs(personality) do
        if value then flags[#flags + 1] = key end
    end
    if #flags == 0 then return "none set" end
    table.sort(flags)
    return table.concat(flags, ",")
end

--- One line per nearby bandit. Everything here is read-only.
local function sweep()
    local player = getSpecificPlayer(0)
    if not player then return end
    if not BanditZombie or not BanditZombie.GetAllB then
        SR.Log("PROBE: BanditZombie unavailable -- is Bandits loaded?")
        return
    end

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    local px, py = player:getX(), player:getY()
    local seen, joinable = 0, 0

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            if dx * dx + dy * dy < PROBE_RANGE * PROBE_RANGE then
                local brain = BanditBrain.Get(zombie)
                if brain then
                    seen = seen + 1
                    local offer = wouldOfferJoinMe(brain)
                    if offer then joinable = joinable + 1 end

                    local record = SR.Get(zombie)
                    SR.Log(string.format(
                        "PROBE %s | prog=%s/%s clan=%s hostile=%s/%s | trust=%d %s | joinMe=%s | d=%.0f",
                        tostring(brain.fullname),
                        tostring(brain.program and brain.program.name),
                        tostring(brain.program and brain.program.stage),
                        tostring(brain.clan),
                        tostring(brain.hostile), tostring(brain.hostileP),
                        record and record.trust or 0, SR.Tier(zombie),
                        tostring(offer),
                        math.sqrt(dx * dx + dy * dy)))

                    -- Brain shape, once. Confirms what personality and rnd really hold,
                    -- rather than trusting the spawner source we read offline.
                    if not shapeDumped then
                        shapeDumped = true
                        SR.Log("PROBE shape | personality=" .. describePersonality(brain.personality))
                        if type(brain.rnd) == "table" then
                            SR.Log("PROBE shape | rnd=" .. table.concat(brain.rnd, ","))
                        end
                        SR.Log("PROBE shape | loyal=" .. tostring(brain.loyal)
                            .. " permanent=" .. tostring(brain.permanent)
                            .. " master=" .. tostring(brain.master))
                    end
                end
            end
        end
    end

    if seen > 0 then
        SR.Log(string.format("PROBE sweep: %d bandits within %d tiles, %d would offer Join Me!",
            seen, PROBE_RANGE, joinable))
    end
end

-- EveryTenMinutes is in-game time, so at default compression this lands near once per
-- real minute. Frequent enough to follow a conversation, quiet enough to read.
Events.EveryTenMinutes.Add(sweep)

Events.OnGameStart.Add(function()
    SR.Log("ScenesPZ Relations active -- PROBE BUILD, debug on, no time decay")

    -- DayLength sets how much in-game time passes per real second, which is what made
    -- the old per-minute decay fire 8-24 times faster than intended. Logged rather than
    -- looked up: for an existing save it is baked into map_sand.bin, which is binary.
    -- The authoritative measurement is still the timestamps on the PROBE sweep lines.
    if SandboxVars then
        SR.Log("PROBE sandbox | DayLength=" .. tostring(SandboxVars.DayLength))
    end
end)
