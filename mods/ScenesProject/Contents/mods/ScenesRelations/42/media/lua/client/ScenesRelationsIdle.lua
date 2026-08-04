-- ScenesPZ -- stage 03, first slice. Survivors who want things.
--
-- WHY THIS EXISTS
-- An NPC that only fights and follows is a turret with a name. Pillar 4 of the PRD says
-- they have lives that do not include you, and until now they visibly did not -- which is
-- why the whole thing still read as green no matter how good the trust maths got.
--
-- WHERE THIS SITS NOW
-- This was stage 03 on its own. Play testing showed that adding idle behaviour without an
-- arbitration layer above it just gives an NPC one more thing to be doing while it dies,
-- so it became rung 5 of the ladder in ScenesRelationsAutonomy.lua. It only ever acts when
-- that ladder says nothing more important is happening.
--
-- WHAT THIS SLICE DOES, AND WHAT IT DOES NOT
-- Does: sees something on the ground it would want, walks over, picks it up, wears it.
-- Does not: loot containers, remember a dropped possession, or trade. Those are the rest
-- of stage 03 and they get built once this one is confirmed working in a real session.
-- Half a stage that works beats a whole stage that has never run.
--
-- WHY IT IS WIRING RATHER THAN BUILDING
-- Every verb already exists as a Bandits task action -- ZAPickUp, ZAEquip, ZALootItems,
-- ZATakeFromContainer -- and only ZPThief and ZPBandit reference any of them. Nothing in
-- the framework decides that an ordinary survivor might want something. The missing piece
-- was a reason, not a mechanism.
--
-- TASTE IS A TRAIT, NOT A DIE ROLL
-- Whether somebody is the sort of person who picks up a hat comes from brain.rnd, five
-- integers fixed at spawn (BanditServerSpawner.lua:375). The one who takes every hat takes
-- every hat, every time, and you learn that about him. A per-tick random would make them
-- all the same person behaving inconsistently, which is the opposite of the goal.
--
-- THE RULE THAT MATTERS MOST
-- None of this may ever interrupt a fight or an order. An NPC that wanders off after a cap
-- while something is biting the player is worse than an NPC with no inner life at all. The
-- idle check is therefore strict: an empty task queue, no zombies nearby, and not fleeing.

require "ScenesRelations"
require "ScenesRelationsAutonomy"

local SR = ScenesRelations

-- Tiles. Only NPCs near the player matter -- nobody is watching the ones that are not, and
-- scanning the whole cache would be waste on a per-minute tick.
local NPC_RANGE = 30

-- Tiles. How far an NPC will notice something worth having. Small on purpose: spotting a
-- cap from across the street reads as radar, not as curiosity.
local SIGHT = 6

-- Tiles. Any zombie this close and the NPC has better things to do.
local DANGER = 12

--- Fixed at spawn, same answer every time for the same person.
---
--- brain.rnd[3] is ZombRand(100). Roughly a third of survivors care about clothes at all,
--- and of those, which body location they are drawn to is also theirs for life.
local function tasteOf(brain)
    if type(brain.rnd) ~= "table" or not brain.rnd[3] then return nil end
    local roll = brain.rnd[3]
    if roll >= 33 then return nil end          -- most people are not magpies
    if roll < 11 then return "Hat" end
    if roll < 22 then return "Back" end        -- bags
    return "Jacket"
end

--- Same cache and the same shape ScenesRelationsThreat already reads
--- (CacheLightZ, entries carrying x and y). Two files asking the same question of the
--- game should ask it the same way, and this is the cheap cache Bandits keeps for exactly
--- this purpose rather than a full enumeration on a per-minute tick.
local function zombiesNear(x, y)
    local cache = BanditZombie and BanditZombie.CacheLightZ
    if not cache then return 0 end

    local count = 0
    for _, zombie in pairs(cache) do
        local dx, dy = zombie.x - x, zombie.y - y
        if dx * dx + dy * dy <= DANGER * DANGER then count = count + 1 end
    end
    return count
end

--- Truly free, not merely between two things. Bandits programs only run when the task
--- queue is empty, so this is the whole question -- get it wrong and an NPC abandons a
--- fight for a hat.
local function isIdle(zombie, brain)
    if brain.hostile or brain.hostileP then return false end
    if BanditBrain.HasTask(brain) then return false end

    local mood = SR.Mood(zombie)
    if not mood then return false end
    if mood.wanting then return false end                -- already after something

    -- The ladder decides what somebody is doing; this file only fills the bottom rung.
    -- Keeping a second opinion here is how two systems start disagreeing about the same
    -- survivor -- R6 in docs/CODE-REVIEW-RULES.md, and the talk cooldown already proved it.
    if SR.Autonomy and mood.rung and mood.rung < SR.Autonomy.IDLE then return false end

    -- Fallback for the sweep before autonomy has ever seen this NPC.
    if mood.posture == "flee" then return false end
    return zombiesNear(zombie:getX(), zombie:getY()) == 0
end

--- The nearest ground item matching this person's taste, or nil.
---
--- getWorldObjects is the vanilla way to read what is lying on a square
--- (ISSearchManager.lua:493), and getBodyLocation is how a garment says where it goes
--- (Trailer1Scenario.lua:111). Nothing here needs a list of item ids, which is also how it
--- avoids inventing one.
local function findWanted(zombie, location)
    local cell = zombie:getCell()
    if not cell then return nil end

    local zx, zy, zz = math.floor(zombie:getX()), math.floor(zombie:getY()), zombie:getZ()
    local best, bestDistSq

    for dx = -SIGHT, SIGHT do
        for dy = -SIGHT, SIGHT do
            local distSq = dx * dx + dy * dy
            if distSq <= SIGHT * SIGHT and (not bestDistSq or distSq < bestDistSq) then
                local square = cell:getGridSquare(zx + dx, zy + dy, zz)
                if square then
                    local objects = square:getWorldObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local item = objects:get(i):getItem()
                            if item then
                                local ok, loc = pcall(function() return item:getBodyLocation() end)
                                if ok and loc == location then
                                    best = { itemType = item:getFullType(), loc = loc,
                                             x = square:getX(), y = square:getY(),
                                             z = square:getZ() }
                                    bestDistSq = distSq
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

--- Walk there, then pick it up. Task shapes copied from the only place in Bandits that
--- builds them (BanditPrograms.lua:58), not invented.
local function goGet(zombie, want)
    local dist = BanditUtils.DistTo(zombie:getX(), zombie:getY(), want.x + 0.5, want.y + 0.5)

    if dist > 0.9 then
        Bandit.AddTask(zombie, BanditUtils.GetMoveTask(0, want.x, want.y, want.z,
            "Walk", dist, false))
    end

    Bandit.AddTask(zombie, {
        action = "PickUp", anim = "LootLow", itemType = want.itemType,
        x = want.x, y = want.y, z = want.z, cnt = 1,
    })
end

--- Putting it on. Bandits dresses an NPC through brain.clothing plus ApplyVisuals
--- (Bandit.lua:178, called from banditize at BanditServerSpawner.lua:420). The Equip task
--- action is for weapons and would not do this.
local function wearIt(zombie, brain, want)
    brain.clothing = brain.clothing or {}
    brain.clothing[want.loc] = want.itemType
    BanditBrain.Update(zombie, brain)

    local ok, err = pcall(function() Bandit.ApplyVisuals(zombie, brain) end)
    if not ok then
        SR.Log("IDLE could not apply visuals: " .. tostring(err))
        return false
    end

    SR.Log(string.format("IDLE %s put on %s", tostring(brain.fullname), want.itemType))
    return true
end

--- Has the thing left the ground? That is how we know the pick-up finished, without
--- needing a completion callback the task system does not offer.
local function stillOnGround(zombie, want)
    local cell = zombie:getCell()
    if not cell then return true end
    local square = cell:getGridSquare(want.x, want.y, want.z)
    if not square then return false end

    local objects = square:getWorldObjects()
    if not objects then return false end
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item and item:getFullType() == want.itemType then return true end
    end
    return false
end

local function sweep()
    local player = getSpecificPlayer(0)
    if not player then return end
    if not BanditZombie or not BanditZombie.GetAllB then return end

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    local px, py = player:getX(), player:getY()

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            if dx * dx + dy * dy <= NPC_RANGE * NPC_RANGE then
                local brain = BanditBrain.Get(zombie)
                local mood = brain and SR.Mood(zombie)

                if brain and mood then
                    if mood.wanting then
                        -- Already sent for something. Finish it, or give up if the queue
                        -- emptied without the item leaving the ground -- unreachable, or
                        -- somebody else took it first.
                        if not BanditBrain.HasTask(brain) then
                            if not stillOnGround(zombie, mood.wanting) then
                                wearIt(zombie, brain, mood.wanting)
                            else
                                SR.Log(string.format("IDLE %s gave up on %s",
                                    tostring(brain.fullname), mood.wanting.itemType))
                            end
                            mood.wanting = nil
                        end
                    elseif isIdle(zombie, brain) then
                        local taste = tasteOf(brain)
                        if taste then
                            local want = findWanted(zombie, taste)
                            if want then
                                mood.wanting = want
                                goGet(zombie, want)
                                SR.Log(string.format("IDLE %s wants %s at %d,%d",
                                    tostring(brain.fullname), want.itemType,
                                    want.x, want.y))
                            end
                        end
                    end
                end
            end
        end
    end
end

-- An in-game minute is about six real seconds. Slow enough that a square scan per
-- interested NPC is nothing, fast enough that picking something up does not look like a
-- decision made an hour ago.
Events.EveryOneMinute.Add(sweep)

Events.OnGameStart.Add(function()
    SR.Log("IDLE ready -- about a third of survivors care about what they wear")
end)
