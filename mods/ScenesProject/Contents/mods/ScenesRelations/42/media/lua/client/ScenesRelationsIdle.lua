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
require "ScenesRelationsMove"

local SR = ScenesRelations

-- Tiles. Only NPCs near the player matter -- nobody is watching the ones that are not, and
-- scanning the whole cache would be waste on a per-minute tick.
local NPC_RANGE = 30

-- Tiles. How far an NPC will notice something worth having. Small on purpose: spotting a
-- cap from across the street reads as radar, not as curiosity.
local SIGHT = 6

-- Tiles. Any zombie this close and the NPC has better things to do.
--
-- Was 12, which is most of a street. Reported 09-08: "los NPC nuevos se quedan en idle... solo
-- si hay zombies cerca hace cosas" -- and that is the two halves of the same coin. In a real
-- Knox Country neighbourhood something is almost always within 12 tiles, so the idle rung was
-- gated shut nearly all the time. 8 still keeps the rule that matters (nobody wanders off after
-- a jacket while something is biting) without treating a shambler two houses away as a crisis.
local DANGER = 8

--- Fixed at spawn, same answer every time for the same person. `brain.rnd[3]` is a
--- `ZombRand(100)` chosen once (BanditServerSpawner.lua:375), so the survivor who picks things
--- up always picks things up -- a per-tick roll would make them all the same person behaving
--- inconsistently, which is the opposite of the goal.
---
--- WHY THIS GOT MUCH MORE GENEROUS. The first version gave a taste to a third of survivors and
--- then narrowed that third to ONE of three garment types, so the odds that a given NPC wanted
--- the specific thing you dropped were about one in nine. Reported after a full session:
--- "en ningun momento toma la prenda, los NPC nuevos se quedan en idle". The log agreed
--- completely -- across 1.7 MB there was exactly one `IDLE` line, the startup banner, and not a
--- single `IDLE ... wants ...`.
---
--- Nothing was broken. The behaviour was simply tuned below the threshold of being observable,
--- which for a feature nobody can see is the same as not existing. Two thirds now care, and
--- they care about ALL THREE kinds rather than one, so a dropped jacket is wanted by two
--- survivors in three instead of one in nine.
---
--- This is a TUNING value, not a mechanism: if survivors end up looking like magpies, lower the
--- threshold rather than re-narrowing the categories. Being able to watch it work comes first;
--- restraint is a number, and numbers are cheap to change once the thing is visible.
local function tasteOf(brain)
    if type(brain.rnd) ~= "table" or not brain.rnd[3] then return nil end
    if brain.rnd[3] >= 66 then return nil end
    return true
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
--- The `location` argument is gone: `tasteOf` no longer names a slot, it answers whether this
--- survivor cares about clothes at all, so this looks for any wearable garment on the ground.
local function findWanted(zombie)
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
                                -- ANY wearable garment now, not one named slot. `tasteOf` used
                                -- to return "Hat"/"Back"/"Jacket" and this compared against it,
                                -- which is half of why the whole behaviour was invisible: a
                                -- survivor who wanted hats ignored the jacket at their feet.
                                -- A non-empty BodyLocation IS the test for "this is clothing" --
                                -- proved every startup by the assertion harness, which checks a
                                -- T-shirt has one and a bag does not.
                                local ok, loc = pcall(function() return item:getBodyLocation() end)
                                if ok and loc and loc ~= "" then
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

--- Walk there, then pick it up -- never both queued at once. Task shape copied from the only
--- place in Bandits that builds it (BanditPrograms.lua:58), not invented.
---
--- This used to add the move task and then unconditionally add the pickup task right behind
--- it, regardless of whether the walk actually arrived. `ZombieActions.PickUp.onComplete`
--- (vendor/Bandits/mods/Bandits/42.20/media/lua/shared/ZombieActions/ZAPickUp.lua:14) has no distance check of its own -- it
--- grabs whatever matches `itemType` off `task.x, task.y, task.z` no matter where the NPC is
--- standing when the task runs -- so a move cut short by a shove, a blocked path, or the
--- autonomy ladder clearing the queue let this pick something up from across the room,
--- silently. Same bug class as the one documented at length above `Loot.Search`
--- (ScenesRelationsLoot.lua) and the same fix: `SR.Move.GoAndDo` (ScenesRelationsMove.lua)
--- never returns both tasks. Precision kept at the original 0.9 rather than the primitive's
--- 0.7 default so the walk-vs-act threshold here does not change.
---
--- AND THE CATCH THAT COMES WITH IT. `GoAndDo` only ever queues one leg, so somebody has to
--- call it again for the second one. In Loot that somebody is free: a Bandits program re-runs
--- by itself every time the task queue empties. Here there is no program -- this is a
--- `EveryOneMinute` sweep guarded by a `mood.wanting` latch, and the latch is precisely what
--- stops a second call. Returning `arrived` is how the sweep knows the difference between "it
--- is walking, ask me again" and "the pickup is queued, wait for it."
local function goGet(zombie, want)
    local task = {
        action = "PickUp", anim = "LootLow", itemType = want.itemType,
        x = want.x, y = want.y, z = want.z, cnt = 1,
    }
    local tasks, arrived = SR.Move.GoAndDo(zombie, want, task, { precision = 0.9 })
    for _, t in ipairs(tasks) do
        Bandit.AddTask(zombie, t)
    end
    return arrived, #tasks > 0
end

-- How many empty-queue sweeps we will spend walking at the same item before writing it off.
-- Same reasoning as MAX_APPROACHES in ScenesRelationsLoot.lua: there is no path-failure
-- callback, so an item behind a locked door would otherwise be walked at forever.
local MAX_TRIES = 3

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
                        -- Already sent for something, and the queue has run dry. Three things
                        -- can be true here and they are not the same thing: the item is gone
                        -- from the ground (we have it -- wear it), the walk leg finished and
                        -- the pickup has not been queued yet (ask GoAndDo again), or we have
                        -- asked enough times and it is unreachable.
                        if not BanditBrain.HasTask(brain) then
                            if not stillOnGround(zombie, mood.wanting) then
                                wearIt(zombie, brain, mood.wanting)
                                mood.wanting = nil
                            else
                                mood.tries = (mood.tries or 0) + 1
                                local arrived, queued = goGet(zombie, mood.wanting)
                                if arrived or not queued or mood.tries >= MAX_TRIES then
                                    if not arrived then
                                        SR.Log(string.format("IDLE %s gave up on %s",
                                            tostring(brain.fullname), mood.wanting.itemType))
                                        mood.wanting = nil
                                    end
                                    mood.tries = nil
                                end
                            end
                        end
                    elseif isIdle(zombie, brain) then
                        local taste = tasteOf(brain)
                        if taste then
                            local want = findWanted(zombie)
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
