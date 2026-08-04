-- ScenesPZ -- survivors who search the house they are standing in.
--
-- ASKED FOR IN THESE WORDS
--   "aun no entran a lootear cuando estamos en una casa... Si hay NPC sin mochila, no deben
--    de cargar mucho para que no se saturen de cosas, deben de priorizar encontrar una
--    mochila para poder cargar mas cosas."
--
-- WHY THIS IS NOT A MATTER OF SWITCHING SOMETHING ON
-- The obvious answer was that Bandits already loots and we only had to call it. It does
-- not. `BanditPrograms.Container.Loot` (BanditPrograms.lua:500) is DEAD CODE -- line 524
-- reads `enemyCharacter:getX()` and line 541 reads `endurance`, and neither is a parameter
-- of that function nor a local in it. Both are undefined globals, so the first call throws.
--
-- That is also why the entire looting block in `ZPCompanion.Main` (lines 120-215) is
-- wrapped in `--[[ ]]`. It is not disabled pending tuning. It is disabled because it
-- crashes. Nobody has ever seen a Bandits companion loot a house.
--
-- So this had to be written, not wired.
--
-- WHY A NEW ACTION INSTEAD OF REUSING LootItems
-- `ZALootItems.onComplete` takes EVERYTHING: `predicateAll` returns true for every item and
-- the loop moves the entire contents of every container on the square into the NPC. Two
-- problems with that, and both were called out before it was ever run --
--
--   * "no deben cargar mucho para que no se saturen" -- an NPC with no bag would empty a
--     kitchen into its pockets;
--   * "they must not strip the house the player is about to loot" (03-idle-life.md) -- an
--     NPC that clears every cupboard before you arrive is not a character, it is a tax.
--
-- The task dispatcher is a plain table lookup -- `ZombieActions[task.action]` at
-- BanditUpdate.lua:1794/1807/1826 -- so registering a new action is pure addition and
-- changes nothing about theirs. `ScenesLoot` takes a bounded selection and leaves the rest.
-- Extend, never replace: their action still exists and still does what it always did.
--
-- HOW CARRYING CAPACITY IS MEASURED
-- Per-item weight was avoidable. Adding one item at a time and re-reading
-- `inventory:getCapacityWeight()` against `getMaxWeight()` uses only two calls that vanilla
-- itself uses (ISInventoryPage.lua:1166, :1565) and cannot disagree with the engine about
-- what an item weighs. Somebody with no bag simply hits the ceiling several items sooner,
-- which is exactly the requested behaviour and needs no separate rule.

require "ScenesRelations"

local SR = ScenesRelations

SR.Loot = SR.Loot or {}
local Loot = SR.Loot

-- Fraction of carrying capacity an NPC will fill before it stops. Deliberately short of
-- full: a survivor at 100% is one pickup away from being encumbered, and encumbrance is how
-- a companion stops being able to keep up with you.
local WEIGHT_BUDGET = 0.7

-- Items per container, whatever the weight says. This is the "do not strip the house" rule
-- expressed as a number -- the player should always find something left in a cupboard an
-- NPC has been through.
local TAKE_PER_CONTAINER = 3

-- Tiles. How far an NPC will look for something to search. Small: this is meant to be the
-- room you are both standing in, not a sweep of the building.
local SEARCH = 8

-- Tiles. How far it will go for a bag, which is worth walking further for than a can of
-- beans because it changes what every future search is worth.
local BAG_SEARCH = 12

-- THE ACTION -------------------------------------------------------------------------

ZombieActions = ZombieActions or {}

ZombieActions.ScenesLoot = {}

ZombieActions.ScenesLoot.onStart = function(zombie, task)
    zombie:faceLocationF(task.x, task.y)
    return true
end

ZombieActions.ScenesLoot.onWorking = function(zombie, task)
    zombie:faceLocationF(task.x, task.y)
    if task.time <= 0 then return true end
    if zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end
    return false
end

--- Take a few things, then stop. The counterpart of ZALootItems.onComplete, minus the part
--- where it empties the building.
ZombieActions.ScenesLoot.onComplete = function(zombie, task)
    local cell = getCell()
    if not cell then return true end

    local square = cell:getGridSquare(task.x, task.y, task.z)
    if not square then return true end

    local inventory = zombie:getInventory()
    if not inventory then return true end

    local ok, budget = pcall(function() return inventory:getMaxWeight() * WEIGHT_BUDGET end)
    if not ok or type(budget) ~= "number" then return true end

    local taken = 0

    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local container = objects:get(i):getContainer()
        if container and not container:isEmpty() then
            local items = ArrayList.new()
            container:getAllEvalRecurse(function() return true end, items)

            for j = 0, items:size() - 1 do
                if taken >= TAKE_PER_CONTAINER then break end

                -- Ask the engine after every single item rather than predicting. It owns
                -- what a thing weighs; we only own when to stop asking.
                if inventory:getCapacityWeight() >= budget then break end

                local item = items:get(j)
                if item then
                    container:Remove(item)
                    container:removeItemOnServer(item)
                    inventory:AddItem(item)
                    taken = taken + 1
                end
            end
        end
    end

    local brain = BanditBrain.Get(zombie)
    SR.Log(string.format("LOOT %s took %d from %d,%d | carrying %.1f / %.1f",
        tostring(brain and brain.fullname), taken, task.x, task.y,
        inventory:getCapacityWeight(), inventory:getMaxWeight()))

    return true
end

-- FINDING THINGS ---------------------------------------------------------------------

local function key(x, y, z)
    return string.format("%d,%d,%d", x, y, z)
end

--- Has this NPC already been through this spot? Remembered on SR.Mood rather than the
--- durable record: it is a fact about right now, not about the player, and a survivor
--- finding a room interesting again hours later is correct.
local function alreadySearched(mood, x, y, z)
    return mood.looted and mood.looted[key(x, y, z)]
end

local function markSearched(mood, x, y, z)
    mood.looted = mood.looted or {}
    mood.looted[key(x, y, z)] = true
end

--- Whether this NPC has room for anything at all. Somebody already at their budget should
--- not walk across a room to open a drawer they cannot use.
function Loot.HasRoom(zombie)
    local inventory = zombie:getInventory()
    if not inventory then return false end
    local ok, full = pcall(function()
        return inventory:getCapacityWeight() >= inventory:getMaxWeight() * WEIGHT_BUDGET
    end)
    if not ok then return false end
    return not full
end

--- The nearest container this NPC has not been through, inside the room it is standing in.
---
--- Room-bounded on purpose. `square:getRoom()` is how vanilla asks the same question
--- (ISMenuContextWorld.lua:63) and it keeps a companion searching the house you walked into
--- rather than wandering toward the next building's kitchen.
function Loot.FindContainer(zombie, mood)
    local square = zombie:getSquare()
    if not square then return nil end

    local room = square:getRoom()
    if not room then return nil end          -- outdoors: nothing to search here

    local cell = square:getCell()
    if not cell then return nil end

    local zx, zy, zz = math.floor(zombie:getX()), math.floor(zombie:getY()), zombie:getZ()
    local best, bestDist

    for dx = -SEARCH, SEARCH do
        for dy = -SEARCH, SEARCH do
            local dist = dx * dx + dy * dy
            if dist <= SEARCH * SEARCH and (not bestDist or dist < bestDist) then
                local sq = cell:getGridSquare(zx + dx, zy + dy, zz)
                -- Same room only. A container visible through a doorway belongs to the
                -- next room, and walking to it is how an NPC ends up somewhere you did not
                -- send it.
                if sq and sq:getRoom() == room
                   and not alreadySearched(mood, sq:getX(), sq:getY(), sq:getZ()) then
                    local objects = sq:getObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local container = objects:get(i):getContainer()
                            if container and not container:isEmpty() then
                                best = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
                                bestDist = dist
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

--- Walk there, search it, and remember we did.
function Loot.Search(zombie, mood, spot)
    local dist = BanditUtils.DistTo(zombie:getX(), zombie:getY(), spot.x + 0.5, spot.y + 0.5)
    local tasks = {}

    if dist > 1.6 then
        -- Walk, not Run. Indoors, and the whole point of searching a house is that it is
        -- quiet enough to search a house.
        tasks[#tasks + 1] = BanditUtils.GetMoveTask(0, spot.x, spot.y, spot.z, "Walk", dist, false)
    end

    tasks[#tasks + 1] = {
        action = "ScenesLoot", anim = "Loot", time = 200,
        x = spot.x, y = spot.y, z = spot.z,
    }

    markSearched(mood, spot.x, spot.y, spot.z)
    return tasks
end

-- BAGS -------------------------------------------------------------------------------

--- Does this person have something to carry things in?
---
--- brain.bag is set once at spawn from the bandit definition
--- (BanditServerSpawner.lua:368) and rendered by ApplyVisuals (Bandit.lua:234). An NPC that
--- spawned without one has never had any way to get one -- which is the gap being closed.
function Loot.HasBag(brain)
    if brain and brain.bag and brain.bag.name then return true end
    return false
end

--- The nearest bag lying on the ground.
---
--- Matched by body location, never by item id. `getBodyLocation()` is how a garment says
--- where it goes (Trailer1Scenario.lua:111) and "Back" is the slot Bandits itself checks
--- when attaching things (Bandit.lua:215). Listing bag ids would mean inventing a list that
--- goes stale the first time the game adds a rucksack.
function Loot.FindBag(zombie)
    local cell = zombie:getCell()
    if not cell then return nil end

    local zx, zy, zz = math.floor(zombie:getX()), math.floor(zombie:getY()), zombie:getZ()
    local best, bestDist

    for dx = -BAG_SEARCH, BAG_SEARCH do
        for dy = -BAG_SEARCH, BAG_SEARCH do
            local dist = dx * dx + dy * dy
            if dist <= BAG_SEARCH * BAG_SEARCH and (not bestDist or dist < bestDist) then
                local sq = cell:getGridSquare(zx + dx, zy + dy, zz)
                if sq then
                    local objects = sq:getWorldObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local item = objects:get(i):getItem()
                            if item then
                                local ok, loc = pcall(function() return item:getBodyLocation() end)
                                if ok and loc == "Back" then
                                    best = { itemType = item:getFullType(),
                                             x = sq:getX(), y = sq:getY(), z = sq:getZ() }
                                    bestDist = dist
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

--- Go and get it. The pickup itself is Bandits' own PickUp action; wearing it is a brain
--- field plus ApplyVisuals, the same two steps ScenesRelationsIdle already uses for hats.
function Loot.FetchBag(zombie, want)
    local dist = BanditUtils.DistTo(zombie:getX(), zombie:getY(), want.x + 0.5, want.y + 0.5)
    local tasks = {}

    if dist > 0.9 then
        tasks[#tasks + 1] = BanditUtils.GetMoveTask(0, want.x, want.y, want.z, "Walk", dist, false)
    end

    tasks[#tasks + 1] = {
        action = "PickUp", anim = "LootLow", itemType = want.itemType,
        x = want.x, y = want.y, z = want.z, cnt = 1,
    }

    return tasks
end

--- Put it on. Called once the pickup has drained, so the item is theirs before it is worn.
function Loot.WearBag(zombie, brain, itemType)
    brain.bag = { name = itemType }
    BanditBrain.Update(zombie, brain)

    local ok, err = pcall(function() Bandit.ApplyVisuals(zombie, brain) end)
    if not ok then
        SR.Log("LOOT could not apply the bag: " .. tostring(err))
        return false
    end

    SR.Log(string.format("LOOT %s now carries a %s", tostring(brain.fullname), itemType))
    return true
end

Events.OnGameStart.Add(function()
    SR.Log("LOOT ready -- bounded searching; upstream Container.Loot is dead code and unused")
end)
