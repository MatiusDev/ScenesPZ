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
--   4. Does a trust record survive a cell unload and a save/reload, and does the same NPC
--      come back under the same id? Read the STORE lines: the id and trust printed for a
--      survivor before you walk away must be the same pair printed when you return.
--   5. ANSWERED. HaloTextHelper does NOT accept an IsoZombie -- the Java binding has
--      no such overload. All feedback renders above the player.

require "ScenesRelations"
local SR = ScenesRelations

local PROBE_RANGE = 30          -- tiles. Wide enough to catch NPCs before they matter.
local shapeDumped = false       -- brain shape is dumped once, not every sweep.

-- Stat drift is decided by the probe itself rather than by the player reading a log.
local statBaseline = nil
local statSweeps = 0
local statVerdict = false

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

                    -- Peek, never Get: the probe must not create the records it is
                    -- measuring. "known=false" here is a real answer, not a gap.
                    local record = SR.Peek(zombie)
                    SR.Log(string.format(
                        "PROBE %s | id=%s | prog=%s/%s clan=%s hostile=%s/%s | known=%s trust=%d %s | joinMe=%s | d=%.0f",
                        tostring(brain.fullname),
                        tostring(SR.IdOf(zombie)),
                        tostring(brain.program and brain.program.name),
                        tostring(brain.program and brain.program.stage),
                        tostring(brain.clan),
                        tostring(brain.hostile), tostring(brain.hostileP),
                        tostring(record ~= nil),
                        record and record.trust or 0, SR.Tier(zombie),
                        tostring(offer),
                        math.sqrt(dx * dx + dy * dy)))

                    -- DOES THE ENGINE TICK THEM? A single reading only proves the accessor
                    -- works. The question that decides whether emotion is read or
                    -- simulated is whether the numbers MOVE on their own, so the first
                    -- NPC of every sweep prints three of them. Ten sweeps of identical
                    -- zeros is an answer; ten sweeps of drifting values is the opposite
                    -- answer, and either way it costs one line a minute to find out.
                    if seen == 1 and CharacterStat then
                        -- ANSWERING IT OURSELVES. Asking the player to eyeball whether
                        -- five numbers drifted across a 3 MB log was a bad instruction --
                        -- reported, correctly, as "no sé bien cómo se puede probar". The
                        -- probe now remembers its first reading and states the verdict.
                        local sok, stats = pcall(function() return zombie:getStats() end)
                        if sok and stats then
                            local function stat(name)
                                local ok2, v = pcall(function() return stats:get(CharacterStat[name]) end)
                                return ok2 and string.format("%.3f", v) or "-"
                            end
                            local line = string.format("panic=%s stress=%s thirst=%s hunger=%s endurance=%s",
                                stat("PANIC"), stat("STRESS"), stat("THIRST"),
                                stat("HUNGER"), stat("ENDURANCE"))
                            SR.Log(string.format("PROBE tick | %s | %s",
                                tostring(brain.fullname), line))

                            -- The verdict, so nobody has to compare numbers by hand.
                            -- Ten sweeps of the identical string means the engine does not
                            -- tick these for an NPC and emotion has to be simulated; any
                            -- difference means it does and half of stage 06 disappears.
                            if not statBaseline then
                                statBaseline, statSweeps = line, 0
                            elseif not statVerdict then
                                statSweeps = statSweeps + 1
                                if line ~= statBaseline then
                                    statVerdict = true
                                    SR.Log("PROBE stat VERDICT MOVES -- the engine ticks "
                                        .. "NPC stats. Emotion can be read, not simulated.")
                                elseif statSweeps >= 10 then
                                    statVerdict = true
                                    SR.Log("PROBE stat VERDICT FROZEN -- ten sweeps, no "
                                        .. "change. The engine does not tick these for an "
                                        .. "NPC; emotion must be simulated on SR.Mood.")
                                end
                            end
                        end
                    end

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

                        -- Does an NPC own the player's needs systems, or only look like
                        -- it does? Bandits never calls these on its own zombies and
                        -- reimplements endurance on brain.endurance instead, which
                        -- suggests they do not work -- but suggests is not knows, and
                        -- the whole design of hunger, thirst and panic hangs on it.
                        -- pcall so that a missing method reports instead of throwing.
                        local probes = {"getStats", "getBodyDamage", "getMoodles"}
                        for _, name in ipairs(probes) do
                            local ok, result = pcall(function() return zombie[name](zombie) end)
                            SR.Log("PROBE needs | " .. name .. " ok=" .. tostring(ok)
                                .. " value=" .. tostring(ok and result or "-"))
                        end

                        -- READING STATS. The first version of this probe called
                        -- stats:getPanic(), stats:getThirst() and so on, all six came back
                        -- ok=false, and the conclusion drawn was "the binding does not
                        -- exist for a zombie". That conclusion was wrong and the probe was
                        -- the thing at fault: Build 42 has no such methods AT ALL, not even
                        -- for the player. The real API is a single generic accessor over an
                        -- enum:
                        --
                        --     character:getStats():get(CharacterStat.THIRST)
                        --
                        -- 54 callsites in vanilla, and CharacterStat carries 24 values --
                        -- far more than was being asked for: PANIC, STRESS, ANGER, MORALE,
                        -- SANITY, PAIN, UNHAPPINESS, BOREDOM and the rest.
                        --
                        -- It is also demonstrably not player-only: ISAnimalContextMenu.lua
                        -- calls animal:getStats():get(CharacterStat.HUNGER) on an animal.
                        -- So the accessor lives on the shared base and is bound for
                        -- non-players, which is the opposite of the HaloTextHelper result.
                        local okStats, stats = pcall(function() return zombie:getStats() end)
                        if okStats and stats and CharacterStat then
                            local wanted = {"PANIC", "STRESS", "FATIGUE", "THIRST", "HUNGER",
                                            "ENDURANCE", "PAIN", "ANGER", "MORALE", "SANITY",
                                            "UNHAPPINESS", "BOREDOM"}
                            for _, name in ipairs(wanted) do
                                local enum = CharacterStat[name]
                                local gok, value = pcall(function() return stats:get(enum) end)
                                SR.Log("PROBE stat | " .. name .. " ok=" .. tostring(gok)
                                    .. " value=" .. tostring(gok and value or "-"))
                            end
                        elseif not CharacterStat then
                            SR.Log("PROBE stat | CharacterStat enum is not exposed to Lua here")
                        end

                        -- HALO ON AN NPC: ANSWERED, 2026-08-03. It does not work.
                        -- The probe threw, and the engine said exactly why:
                        --   java.lang.RuntimeException: No implementation found for
                        --   function: addText(class zombie.characters.IsoZombie ...)
                        -- The method exists on the shared base class and vanilla only ever
                        -- passes a player; the Java binding simply has no IsoZombie
                        -- overload. Every message therefore renders above the PLAYER, and
                        -- docs/CAPABILITY-MAP.md now records this as settled rather than
                        -- open. The probe is removed because it threw seven exceptions per
                        -- session to re-learn something we know.
                    end
                end
            end
        end
    end

    if seen > 0 then
        SR.Log(string.format(
            "PROBE sweep: day %d | %d bandits within %d tiles, %d would offer Join Me! | store holds %d records",
            SR.Today(), seen, PROBE_RANGE, joinable, SR.Store.Count()))
    end
end

-- EveryTenMinutes is in-game time, so at default compression this lands near once per
-- real minute. Frequent enough to follow a conversation, quiet enough to read.
Events.EveryTenMinutes.Add(sweep)

Events.OnGameStart.Add(function()
    SR.Log("ScenesPZ Relations active -- PROBE BUILD, debug on, no time decay")
    SR.Log(string.format("PROBE start | world day %d | store holds %d records",
        SR.Today(), SR.Store.Count()))

    -- DayLength sets how much in-game time passes per real second, which is what made
    -- the old per-minute decay fire 8-24 times faster than intended. Logged rather than
    -- looked up: for an existing save it is baked into map_sand.bin, which is binary.
    -- The authoritative measurement is still the timestamps on the PROBE sweep lines.
    if SandboxVars then
        SR.Log("PROBE sandbox | DayLength=" .. tostring(SandboxVars.DayLength))
    end
end)
