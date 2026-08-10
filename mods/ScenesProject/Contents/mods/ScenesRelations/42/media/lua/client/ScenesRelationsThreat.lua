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

-- How far an NPC will look for a way inside. Every tile searched is a getGridSquare call
-- inside a sweep that already runs per NPC, so this stays small on purpose.
local SHELTER_SEARCH = 8

-- Tiles. How close to the shelter square counts as arrived, whatever the queue's head
-- says next. A queued task guarantees only that it ENDED, never that anyone got there
-- (rule 4) -- position is the one thing a Smack or a claim denial cannot fake. Loose
-- enough to cover pathing stopping a step short of a non-walkable window tile, tight
-- enough that "still five tiles out" can never read as arrived.
local ARRIVAL_RADIUS = 1.5
local ARRIVAL_RADIUS_SQ = ARRIVAL_RADIUS * ARRIVAL_RADIUS

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
---
--- Returns wx, wy, wz on success (the spot assess() must keep watching), or nil on
--- failure -- a single nil, so `if not seekShelter(...)` at the caller still works.
local function seekShelter(zombie, brain)
    local wx, wy, wz, alreadyOpen = findWindow(zombie)
    if not wx then return nil end

    -- Explicit time on the window task. The handler's onWorking waits for getBumpType()
    -- to match task.anim (ZAOpenWindow.lua:10); with no anim it may never match, and the
    -- generic loop force-completes at time <= 0 (BanditUpdate.lua:1759,1804). The timer
    -- is the contract we rely on, not the animation.
    if not alreadyOpen then
        Bandit.AddTaskFirst(zombie, SR.Own(SR.GOAL.SHELTER,
            {action = "OpenWindow", x = wx, y = wy, z = wz, time = 60}))
    end
    Bandit.AddTaskFirst(zombie, SR.Own(SR.GOAL.SHELTER,
        {action = "GoTo", x = wx, y = wy, z = wz, walkType = "Run"}))

    if SR.DEBUG then
        SR.Log(string.format("THREAT %s -> shelter at %d,%d (%s)",
            tostring(brain.fullname), wx, wy, alreadyOpen and "open" or "closed"))
    end
    return wx, wy, wz
end

--- One pass over every friendly NPC the ladder has put on rung 1, bounded to the same
--- radius that gates whether mood.rung is fresh (F3). Autonomy only ever writes mood.rung
--- inside its own `masterDist <= NPC_RANGE` guard and never clears it on the way out, so
--- an NPC who wandered past that radius keeps whatever rung it last held -- possibly
--- SURVIVE, forever, unwatched by the module that could update it. Reading SR.Autonomy's
--- own NPC_RANGE, rather than a second number of this file's own, is what R6 exists to
--- enforce: one module owns the bound, everyone else reads it.
---
--- There is no decision left to make here otherwise. Fear already weighed the numbers
--- against a single fixed limit -- see ScenesRelationsAutonomy.fearLimit for why it is no
--- longer a per-NPC roll and the arithmetic behind the number. This file only owns the
--- VERB.
local function assess()
    local cache, bandits = BanditZombie.Cache, BanditZombie.CacheLightB
    if not cache or not bandits then return end
    if not SR.Autonomy then return end

    local player = getSpecificPlayer(0)
    if not player then return end
    local px, py = player:getX(), player:getY()
    local rangeSq = SR.Autonomy.NPC_RANGE * SR.Autonomy.NPC_RANGE

    for _, light in pairs(bandits) do
        local brain = light.brain
        if brain and not brain.hostile and not brain.hostileP then
            local ldx, ldy = light.x - px, light.y - py
            if ldx * ldx + ldy * ldy <= rangeSq then
                local zombie = cache[light.id]
                -- Mood, not the trust record. Posture is transient and belongs to the
                -- entity; asking for the record here would create a permanent one for
                -- every NPC that ever saw a zombie near the player.
                local mood = zombie and SR.Mood(zombie)

                if mood and mood.rung == SR.Autonomy.SURVIVE then
                    -- Has the route actually been ACHIEVED, not merely ended (rule 4)?
                    -- Position answers what the queue cannot: a single-task route to an
                    -- already-open window finishes inside one sweep (F1) -- the head no
                    -- longer matches what was queued not because anything went wrong, but
                    -- because it succeeded. Checking distance to the shelter square first
                    -- catches that; the old head-only check could not, and re-queued a
                    -- route to the same window every sweep forever -- confirmed in play:
                    -- `head=Smack@...` on a survivor whose census still read
                    -- `rung=survive`, standing still and being eaten because
                    -- mood.sheltering was a permanent latch that never let this file look
                    -- again.
                    --
                    -- A denied claim (F2) is the other false "gone." claimSpot rejecting a
                    -- contested window makes Autonomy push its own wait task
                    -- (Autonomy.WAIT_ACTION/WAIT_ANIM) -- that is patience, not
                    -- displacement, and re-asserting into the same denial every sweep is
                    -- how two frightened NPCs starve each other forever. The wait task
                    -- force-completes on its own (BanditUpdate.lua:1759,1804, the same
                    -- generic timer this file already relies on for OpenWindow above), so
                    -- treating it as "still on route" is temporary by construction, not a
                    -- new permanent latch.
                    local onRoute = false
                    if mood.shelterX then
                        local zx, zy = zombie:getX(), zombie:getY()
                        local sdx, sdy = zx - mood.shelterX, zy - mood.shelterY
                        local arrived = (sdx * sdx + sdy * sdy) <= ARRIVAL_RADIUS_SQ
                        local head = brain.tasks and brain.tasks[1]
                        local waiting = head ~= nil
                            and head.action == SR.Autonomy.WAIT_ACTION
                            and head.anim == SR.Autonomy.WAIT_ANIM

                        if arrived or waiting then
                            onRoute = true
                        else
                            onRoute = head ~= nil
                                and head.x == mood.shelterX and head.y == mood.shelterY
                                and (head.action == "GoTo" or head.action == "OpenWindow")
                        end
                    end

                    -- Assert once on arrival, and re-assert exactly when the route is gone
                    -- or displaced -- never on a bare timer. This can fire at most once per
                    -- sweep (assess runs once per EveryOneMinute).
                    if not mood.sheltering or (mood.shelterX and not onRoute) then
                        mood.sheltering = true
                        mood.posture = "flee"

                        local threat = countZombiesNear(light.x, light.y)
                        -- SR.Autonomy's own count (F6): that module already computes this
                        -- every sweep, on the same FRIEND_RANGE, including the player. This
                        -- file used to recompute it on a different radius that never
                        -- counted the player, so the same NPC in the same sweep logged two
                        -- disagreeing numbers -- exactly what this file's own header
                        -- (R6) exists to stop.
                        local friends = mood.friends or 0

                        -- Phrase keys are not free text. These are the only ones used here
                        -- that appear in Bandits' own Say calls; "PANIC" and "COVER" read
                        -- better and do not exist. Bandit.Say also self-limits to 14 tiles
                        -- from the player (Bandit.lua:1171), so this cannot become noise
                        -- from across the map.
                        local wx, wy, wz = seekShelter(zombie, brain)
                        if wx then
                            mood.shelterX, mood.shelterY, mood.shelterZ = wx, wy, wz
                            Bandit.Say(zombie, "INSIDE")
                            SR.Log(string.format(
                                "THREAT %s | survive -> shelter | zombies=%d friends=%d",
                                tostring(brain.fullname), threat, friends))
                        else
                            -- Nowhere to go. Standing and fighting is not courage here, it
                            -- is the only option left, and it should look like that. No
                            -- shelter coordinates to watch, so this does not retry every
                            -- sweep -- onRoute above only re-checks when mood.shelterX is
                            -- set.
                            mood.shelterX, mood.shelterY, mood.shelterZ = nil, nil, nil
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
                    mood.shelterX, mood.shelterY, mood.shelterZ = nil, nil, nil
                end
            end
        end
    end
end

-- An in-game minute is about 6 real seconds at DayLength = 4, measured. Slow for combat,
-- but this decides posture, not swings -- Bandits still handles every individual attack.
-- Anything faster means a full cache sweep several times a second.
Events.EveryOneMinute.Add(assess)
