-- ScenesPZ -- what a survivor does when the dead show up.
--
-- THE SCENARIO THIS IMPLEMENTS
-- Zombies approach. Each NPC weighs how many are coming against how many friends it has.
-- Outnumbered, the cautious ones break for a window and the brave ones cover them. Even,
-- everybody fights. This is the first behaviour in the mod that is a *decision* rather
-- than a reaction, and it is the floor the settlement is meant to stand on.
--
-- WHY THIS IS BUILDABLE AND "IS THAT ZOMBIE HUNTING ME" IS NOT
-- There is no verified way to ask whether a zombie has targeted someone --
-- zombie:getTarget() appears zero times in 42.20's Lua. But danger does not actually need
-- that question. How many are near, and how many of us are there, is fully measurable
-- from caches Bandits already maintains. Counting is honest; guessing an API is not.
--
-- HOW IT COEXISTS WITH BANDITS
-- We never switch anyone's program. We push one task to the front of a queue their
-- program owns (Bandit.AddTaskFirst). When it drains, their program takes over again
-- exactly as before. So the worst failure mode is an NPC that walks to a window and then
-- resumes what it was doing -- visible, harmless, and reversible by deleting this file.
--
-- KNOWN LIMIT, ON PURPOSE
-- Doors are not broken down yet. The Destroy action takes an `idx` parameter whose
-- meaning is not verified, and inventing it is how this project has lost sessions before.
-- Windows only, until Destroy is read properly.
--
-- WHO IS IN CHARGE, SETTLED 04-08
-- This file and ScenesRelationsAutonomy both used to decide what a frightened survivor
-- does, on their own numbers, at the same cadence. The log proved it: THREAT lines saying
-- "flee" for three survivors while AUTO said nothing about any of them, because the two
-- modules were watching different radii and reporting to nobody. That is R6 in
-- docs/CODE-REVIEW-RULES.md, and it is also why several of them piled onto one window --
-- fifteen tiles is a wide net, and everybody it caught was sent to the same place.
--
-- The ladder now owns the decision. This file owns only the VERB -- where the nearest way
-- inside is and how to get there -- and it runs only for survivors the ladder has already
-- put on rung 1. Fleeing to a window is what surviving looks like; deciding to survive is
-- not this file's job any more.

require "ScenesRelations"
require "ScenesRelationsAutonomy"

local SR = ScenesRelations

-- Tiles. Deliberately wider than ENGAGE_RANGE (8): you should see trouble coming before
-- you are close enough to swing at it, or fleeing is never an option.
local DANGER_RADIUS = 15
local DANGER_RADIUS_SQ = DANGER_RADIUS * DANGER_RADIUS

-- Who counts as "us". Someone across the street is not backup.
local GROUP_RADIUS_SQ = 144  -- 12 tiles

-- How far an NPC will look for a way inside. Every tile searched is a getGridSquare call
-- inside a sweep that already runs per NPC, so this stays small on purpose.
local SHELTER_SEARCH = 8

-- Odds are per NPC and stable: brain.rnd is rolled once at spawn
-- (BanditServerSpawner.lua:375), so the same survivor is always the one who stands and
-- fights. That consistency is what makes them read as individuals rather than dice.
local BRAVE_MIN_ROLL = 5   -- rnd[2] is ZombRand(10), so roughly half are brave

--- Reads the stable per-NPC roll. Falls back to cautious: an NPC we cannot read should
--- not be the one we ask to hold the line.
local function isBrave(brain)
    local rnd = brain and brain.rnd
    if type(rnd) ~= "table" or type(rnd[2]) ~= "number" then return false end
    return rnd[2] >= BRAVE_MIN_ROLL
end

local function countZombiesNear(x, y)
    local cache = BanditZombie.CacheLightZ
    if not cache then return 0 end
    local n = 0
    for _, zombie in pairs(cache) do
        local dx, dy = zombie.x - x, zombie.y - y
        if dx * dx + dy * dy < DANGER_RADIUS_SQ then n = n + 1 end
    end
    return n
end

local function countFriendsNear(x, y, selfId)
    local cache = BanditZombie.CacheLightB
    if not cache then return 0 end
    local n = 0
    for _, other in pairs(cache) do
        if other.id ~= selfId then
            local brain = other.brain
            if brain and not brain.hostile and not brain.hostileP then
                local dx, dy = other.x - x, other.y - y
                if dx * dx + dy * dy < GROUP_RADIUS_SQ then n = n + 1 end
            end
        end
    end
    return n
end

--- Nearest window an NPC could get through. Prefers one already open -- climbing through
--- a standing window is quiet, and smashing one is what draws the horde you were running
--- from in the first place.
--- Returns x, y, z, alreadyOpen.
local function findWindow(zombie)
    local square = zombie:getSquare()
    if not square then return nil end
    local cell = square:getCell()
    if not cell then return nil end

    local cx, cy, cz = zombie:getX(), zombie:getY(), zombie:getZ()
    local bestDist, bx, by, bOpen = math.huge, nil, nil, false

    for dx = -SHELTER_SEARCH, SHELTER_SEARCH do
        for dy = -SHELTER_SEARCH, SHELTER_SEARCH do
            local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
            if sq then
                local window = sq:getWindow()
                if window then
                    local dist = dx * dx + dy * dy
                    local open = window:IsOpen() or window:isSmashed()
                    -- An open window beats a closer closed one: the tiebreak is on time
                    -- to get inside, not on distance walked.
                    local better = (open and not bOpen) or (open == bOpen and dist < bestDist)
                    if better then
                        bestDist, bx, by, bOpen = dist, cx + dx, cy + dy, open
                    end
                end
            end
        end
    end

    if not bx then return nil end
    return bx, by, cz, bOpen
end

--- Sends an NPC to the nearest window and through it. Two tasks, queued in front of
--- whatever its program wanted: walk there, then deal with the window.
local function seekShelter(zombie, brain)
    local wx, wy, wz, alreadyOpen = findWindow(zombie)
    if not wx then return false end

    -- Explicit time on the window task. The handler's onWorking waits for getBumpType()
    -- to match task.anim (ZAOpenWindow.lua:10); with no anim it may never match, and the
    -- generic loop force-completes at time <= 0 (BanditUpdate.lua:1759,1804). The timer
    -- is the contract we rely on, not the animation.
    if not alreadyOpen then
        Bandit.AddTaskFirst(zombie, {action = "OpenWindow", x = wx, y = wy, z = wz, time = 60})
    end
    Bandit.AddTaskFirst(zombie, {action = "GoTo", x = wx, y = wy, z = wz, walkType = "Run"})

    if SR.DEBUG then
        SR.Log(string.format("THREAT %s -> shelter at %d,%d (%s)",
            tostring(brain.fullname), wx, wy, alreadyOpen and "open" or "closed"))
    end
    return true
end

--- One pass over every friendly NPC the ladder has put on rung 1.
---
--- There is no decision left to make here. Fear already weighed the numbers against this
--- person's own limit, and that limit is derived from the same brain.rnd[2] this file used
--- to read for bravery -- so the brave still hold and the cautious still break, by exactly
--- the same field, decided in exactly one place.
local function assess()
    local cache, bandits = BanditZombie.Cache, BanditZombie.CacheLightB
    if not cache or not bandits then return end
    if not SR.Autonomy then return end

    for _, light in pairs(bandits) do
        local brain = light.brain
        if brain and not brain.hostile and not brain.hostileP then
            local zombie = cache[light.id]
            -- Mood, not the trust record. Posture is transient and belongs to the entity;
            -- asking for the record here would create a permanent one for every NPC that
            -- ever saw a zombie near the player.
            local mood = zombie and SR.Mood(zombie)

            if mood and mood.rung == SR.Autonomy.SURVIVE then
                -- Once. Re-queuing a route to the same window every sweep is how an NPC
                -- ends up walking to a latch forever, which is the bug this whole session
                -- is about. They keep the tasks they were given until the rung changes.
                if not mood.sheltering then
                    mood.sheltering = true
                    mood.posture = "flee"

                    local threat = countZombiesNear(light.x, light.y)
                    local friends = countFriendsNear(light.x, light.y, light.id)

                    -- Phrase keys are not free text. These are the only ones used here
                    -- that appear in Bandits' own Say calls; "PANIC" and "COVER" read
                    -- better and do not exist. Bandit.Say also self-limits to 14 tiles
                    -- from the player (Bandit.lua:1171), so this cannot become noise from
                    -- across the map.
                    if seekShelter(zombie, brain) then
                        Bandit.Say(zombie, "INSIDE")
                        SR.Log(string.format(
                            "THREAT %s | survive -> shelter | zombies=%d friends=%d brave=%s",
                            tostring(brain.fullname), threat, friends,
                            tostring(isBrave(brain))))
                    else
                        -- Nowhere to go. Standing and fighting is not courage here, it is
                        -- the only option left, and it should look like that.
                        mood.posture = "fight"
                        Bandit.Say(zombie, "OUTSIDE")
                        SR.Log(string.format(
                            "THREAT %s | survive but cornered, no way inside | zombies=%d friends=%d",
                            tostring(brain.fullname), threat, friends))
                    end
                end
            elseif mood then
                -- Off rung 1: they may look for shelter again next time they need it.
                mood.sheltering = nil
                mood.posture = nil
            end
        end
    end
end

-- An in-game minute is about 6 real seconds at DayLength = 4, measured. Slow for combat,
-- but this decides posture, not swings -- Bandits still handles every individual attack.
-- Anything faster means a full cache sweep several times a second.
Events.EveryOneMinute.Add(assess)
