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
require "ScenesRelationsMove"

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

-- Tiles. How close the NPC's REAL position has to be, at the moment of taking, to the square
-- it would stand at to reach this container -- not to the container's own square, and not to
-- wherever the walk was PLANNED to end.
--
-- The value is not invented: it is the same tolerance `SR.Move.GoAndDo` uses to decide a walk
-- has arrived (`precision`, ScenesRelationsMove.lua:80). Using anything looser here would make
-- the check written specifically to catch drift after that decision (R13,
-- docs/CODE-REVIEW-RULES.md) MORE forgiving than the walk that produced the drift in the first
-- place -- which defeats the point of re-checking at all.
local REACH = 0.7

-- How many times a container may be refused at the moment of taking before it is written off for
-- good. Small on purpose: a refusal usually means the NPC drifted or is on the wrong side of a
-- wall, and one or two more approaches either fix that or prove it cannot be fixed.
local MAX_REFUSALS = 2

-- WHAT COUNTS AS WHAT ------------------------------------------------------------------
--
-- These live ABOVE the action that uses them, and the placement is not cosmetic. Lua binds
-- a `local` lexically at compile time, so a local declared BELOW a function is not visible
-- inside it -- the name silently becomes a global lookup and evaluates to nil. This table
-- was first written further down the file, which made `WANTS[task.want]` an index into nil
-- and threw EVERY time an NPC finished searching a container.
--
-- Syntax checking cannot catch that; luac compiles it happily. Only reading the file in
-- order, or running it, will.
--
-- Both predicates are the engine's own tests rather than lists of ids, and the bag one was
-- WRONG for the first three test runs. `getBodyLocation()` is a CLOTHING field. A bag is an
-- InventoryContainer and declares itself with `CanBeEquipped = base:back`
-- (media/scripts/generated/items/container.txt:57) -- it has no BodyLocation at all, so the
-- old predicate returned false for every rucksack in the game.
--
-- That one wrong method produced four separate symptoms, all reported from play: bags on the
-- floor were never seen, the goal "bag" could never be satisfied, the priority pass in
-- onComplete never matched, and a bag pulled out of a drawer was treated as filler. The proof
-- is negative and total -- 1,422 SREL lines in the 04-08 run, zero `found what it wanted`.
--
-- The replacement is the engine's own test, copied from ISInventoryPane.lua:967, which is
-- what the inventory UI uses to decide whether a thing can be worn as a container.
local function isBag(item)
    local ok, wearable = pcall(function()
        return instanceof(item, "InventoryContainer")
           and item:canBeEquipped() ~= nil
           and item:canBeEquipped() ~= ""
    end)
    return ok and wearable == true
end

-- `isFood()` over `instanceof(item, "Food")`, and `not isPoison()` because the first version
-- did not have it. The Ark asks exactly this pair (BWOAItems.lua:9) before it will let an NPC
-- pick something up to eat, and bleach is an instance of Food.
local function isFood(item)
    local ok, food = pcall(function() return item:isFood() and not item:isPoison() end)
    return ok and food == true
end

local WANTS = {
    bag = isBag,
    food = isFood,
}

-- IS THIS WORTH CARRYING? --------------------------------------------------------------
--
-- REPORTED: "cogen un monton de cosas que no sirven. Llenan su carry y luego no pueden coger
-- otras cosas."
--
-- Confirmed in the 05-08 log and it is arithmetic, not opinion. John James went from
-- `carrying 0.2` to `carrying 6.3` in THREE items -- two kilos each -- and the budget is 5.6.
-- One drawer of the wrong furniture ends a survivor's scavenging for good, because nothing in
-- this mod ever puts anything down.
--
-- The old filler pass had no opinion at all: it took the first three things in the container.
--
-- WHERE THE SHAPE OF THIS CAME FROM. The Ark never filters, because it never has to -- its
-- programs decide on a specific item first (`FindClosestItemClass("food")`) and `ZACollect`
-- then collects that ONE named type (`item:getFullType() == task.item.ftype`, ZACollect.lua:89)
-- and returns. Deciding and taking are different layers there.
--
-- Ours takes incidental filler by design -- "they must not strip the house" only means
-- something if they are taking more than one named thing -- so the opinion has to live here
-- instead. Same conclusion, different layer, and worth knowing which is which.
--
-- Every test below is one the engine already answers and that upstream already relies on:
-- isFood/isPoison and IsClothing (BWOAItems.lua:3-22), IsWeapon and IsDrainable (Bandit.lua's
-- own loot block), getActualWeight (BWOAPermaInv.lua:22).
local function isWorthTaking(item)
    local ok, worth = pcall(function()
        if isBag(item) then return true end
        if isFood(item) then return true end
        if item:IsWeapon() then return true end
        -- Bandages, disinfectant, painkillers, batteries, tools with uses left. This is the
        -- class the healing stage needs and cannot currently find anywhere.
        if item:IsDrainable() then return true end
        local fluid = item:getFluidContainer()
        if fluid and not fluid:isEmpty() and not fluid:isPoisonous() and not fluid:isTainted() then
            return true
        end
        local power = 0
        local okPower = pcall(function() power = item:getBandagePower() or 0 end)
        if okPower and power > 0 then return true end
        return false
    end)
    return ok and worth == true
end

-- Exported ONLY so the runtime assertions can test the predicate that actually runs, rather
-- than a copy of it. A test against a duplicate of the rule proves the duplicate works --
-- which is exactly the trap that let a wrong isBag survive three play sessions. Nothing in
-- the mod calls these; see ScenesRelationsAssert.lua.
Loot.IsBag = isBag
Loot.IsFood = isFood
Loot.IsWorthTaking = isWorthTaking

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

    -- THE ACTION REFUSES TO REACH -- FOR REAL, NOT FOR THE PLAN. Loot.Search only queues this
    -- once `SR.Move.GoAndDo` (ScenesRelationsMove.lua) decided the NPC was at the right square,
    -- but that decision was made when the task was QUEUED. R13 (docs/CODE-REVIEW-RULES.md) is
    -- exactly this: a queued task guarantees it ENDED, never that it ARRIVED. The ladder, a
    -- fight, a shove, or simply the 200 ticks of "Loot" animation between onStart and onComplete
    -- are all real time in which the NPC's actual position can drift away from the one that was
    -- checked. This is the only place left that runs at the moment of taking, with the NPC's
    -- real position available, so this is where the check has to live.
    --
    -- REPORTED FROM PLAY: "alguien pudo lootear a traves de una pared de un objeto que estaba
    -- en otra habitacion" -- an NPC emptied a container through a wall, into a different room.
    -- Two squares can be one tile apart and still be in different rooms, and distance alone
    -- cannot tell them apart -- that is what the wall check below is for. Both conditions below
    -- have to pass; neither is sufficient on its own.
    --
    -- STEP 1: WHERE WOULD SOMEBODY ACTUALLY STAND. Same rule GoAndDo used to queue this task in
    -- the first place, recomputed here rather than trusted from then: the container's own square
    -- if it is open, otherwise the nearest free neighbour with no wall between it and the
    -- container. `BanditUtils.GetAccessSquare(gridSquare, bandit)` --
    -- vendor/Bandits/mods/Bandits/42.20/media/lua/shared/BanditUtils.lua:1056 -- takes the
    -- container square and the NPC, in that order, and does exactly this
    -- (`gridSquare:isWallTo(testSquare)` at :1071, `isWallTo` confirmed on a live IsoGridSquare
    -- at pzserver/media/lua/server/ISObjectClickHandler.lua:135). `square:isNotBlocked(false)` is
    -- vanilla, confirmed at pzserver/media/lua/shared/Foraging/forageSystem.lua:1695.
    local okStand, standSquare = pcall(function()
        if square:isNotBlocked(false) then return square end
        return BanditUtils.GetAccessSquare(square, zombie)
    end)
    -- A refusal must not be a death sentence for the container. `Loot.Search` marked this spot
    -- when the WALK arrived, before this action ran, so without giving the mark back a single
    -- refusal deletes the furniture from this NPC's world permanently. `Loot.Forget` returns
    -- whether it will be tried again, so the log says which of the two happened.
    local mood = SR.Mood(zombie)
    local function refuse(reason)
        local retry = Loot.Forget(mood, task.x, task.y, task.z)
        SR.Log(string.format("LOOT refused (%s) at %d,%d -- %s",
            reason, task.x, task.y, retry and "will try again" or "written off"))
        return true
    end

    if not okStand or not standSquare then
        SR.Log(string.format("LOOT no standing square -- zombie %.1f,%.1f, target %d,%d",
            zombie:getX(), zombie:getY(), task.x, task.y))
        return refuse("no standing square")
    end

    local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()
    local sx, sy = standSquare:getX(), standSquare:getY()

    -- STEP 2: DISTANCE TO THAT SQUARE, NOT TO THE CONTAINER'S. Measuring straight to the
    -- container (the old check) is why REACH had to be a loose 2.0 -- a diagonal access square
    -- is already 1.4 tiles from the container, before the NPC's own walking slop. Measuring to
    -- the standing square instead means REACH can be the real adjacency tolerance.
    local reach = BanditUtils.DistTo(zx, zy, sx + 0.5, sy + 0.5)
    if reach > REACH then
        SR.Log(string.format(
            "LOOT too far -- zombie %.1f,%.1f vs stand %.1f,%.1f | %.2f > %.1f tiles",
            zx, zy, sx + 0.5, sy + 0.5, reach, REACH))
        return refuse("too far")
    end

    -- STEP 3: NO WALL BETWEEN THE NPC AND THE CONTAINER.
    --
    -- AND THE TARGET HERE IS THE CONTAINER, NOT THE STANDING SQUARE -- the first version got that
    -- wrong and the mistake made the whole step INERT. Step 2 has just established that the NPC
    -- is within 0.7 tiles of the standing square, so flooring both positions gives the SAME tile
    -- in almost every passing case, and the call was asking whether a square can see itself. It
    -- could never refuse anything. What was actually catching the through-wall case was step 1,
    -- inside `GetAccessSquare`'s `isWallTo`
    -- (vendor/Bandits/mods/Bandits/42.20/media/lua/shared/BanditUtils.lua:1071).
    --
    -- Measured against the container's own square it asks the question the report was about:
    -- "alguien pudo lootear a traves de una pared de un objeto que estaba en otra habitacion."
    --
    -- `LosUtil.lineClearCollide(x,y,z,x2,y2,z2,false)` RETURNS TRUE WHEN THE LINE IS BLOCKED --
    -- confirmed at runtime (console.txt: "ASSERT ok LosUtil.lineClearCollide exists",
    -- ScenesRelationsAssert.lua:146-148) and the same call, same polarity, already relied on by
    -- `SR.Move.GoAndDo` (ScenesRelationsMove.lua:103-115). A pcall failure counts as BLOCKED:
    -- refusing one honest take costs a retry, and taking through a wall because the check itself
    -- broke is the bug this exists to remove.
    local okLos, blocked = pcall(function()
        return LosUtil.lineClearCollide(
            math.floor(zx), math.floor(zy), math.floor(zz),
            task.x, task.y, task.z,
            false)
    end)
    if not okLos or blocked then
        SR.Log(string.format("LOOT wall in the way -- zombie %.1f,%.1f,%.1f cannot see %d,%d,%d",
            zx, zy, zz, task.x, task.y, task.z))
        return refuse("wall")
    end

    local inventory = zombie:getInventory()
    if not inventory then return true end

    -- The bag counts. `Loot.CarryBudget` is a table field rather than a local so it can be
    -- called from here, above where it is written -- a `local function` declared below this
    -- point would be invisible to it and would silently evaluate to nil.
    local brain = BanditBrain.Get(zombie)
    local budget = Loot.CarryBudget(zombie, brain)
    if budget <= 0 then return true end

    local taken = 0
    local foundBag = nil

    -- WHAT they took, not just how many. Asked for directly, and for a reason worth writing
    -- down: the only way to audit what an NPC is carrying is to kill it and read the corpse,
    -- and that audit is worthless without a record of what should be there. "sería bueno que
    -- en el log quede que item cogio el NPC para que yo corrobore el inventario y esté todo lo
    -- que tenía el NPC al morir."
    --
    -- No cap is needed here and that is worth stating rather than assuming: the loop already
    -- stops at TAKE_PER_CONTAINER (line 248), so this list cannot grow past a handful and the
    -- concat cannot flood a log that is read by hand on another machine.
    local takenNames = {}

    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local container = objects:get(i):getContainer()
        if container and not container:isEmpty() then
            local items = ArrayList.new()
            container:getAllEvalRecurse(function() return true end, items)

            -- What they came for comes out first. Two passes over the same list rather than
            -- a sort: the wanted pass ignores the per-container cap so a rucksack at the
            -- back of a wardrobe is never missed because three tins were in front of it.
            local wanted = WANTS[task.want]
            local order = wanted and { true, false } or { false }

            for _, first in ipairs(order) do
                for j = 0, items:size() - 1 do
                    local item = items:get(j)
                    local matches = wanted and item and wanted(item) or false

                    if item and matches == first then
                        -- The cap is for incidental hauling, not for the thing they walked
                        -- across a room to find.
                        if not first and taken >= TAKE_PER_CONTAINER then break end

                        -- Ask the engine after every single item rather than predicting. It
                        -- owns what a thing weighs; we only own when to stop asking.
                        if inventory:getCapacityWeight() >= budget then break end

                        -- Filler has to earn its place; the thing they came for does not. A
                        -- goal is a decision already made, and second-guessing it here is how
                        -- an NPC walks across a house for a rucksack and then leaves it.
                        local keep = first or isWorthTaking(item)

                        -- ONE ITEM MUST NOT END THE TRIP. The budget check above only asks
                        -- whether there is room for something -- it says nothing about how big
                        -- that something is, which is how three items ate 6.1 of a 5.6 budget.
                        -- A survivor picks up the tin and leaves the toolbox.
                        if keep and not first then
                            local okW, weight = pcall(function() return item:getActualWeight() end)
                            if okW and type(weight) == "number"
                               and inventory:getCapacityWeight() + weight > budget then
                                keep = false
                            end
                        end

                        if keep then
                            container:Remove(item)
                            container:removeItemOnServer(item)
                            -- Marked as ours the moment it changes hands. Restore() uses this
                            -- to tell what a despawn took from what the spawner put there.
                            item:getModData().scenesLooted = true
                            item:getModData().preserve = true
                            inventory:AddItem(item)
                            taken = taken + 1
                            takenNames[#takenNames + 1] = tostring(item:getFullType())

                            -- A bag out of a drawer is the same find as a bag off the floor,
                            -- and until now only the floor path ever put one on. "se la puse
                            -- en un cajon de las casas y ahi si la cogio, pero no se la
                            -- equipo nunca."
                            if not foundBag and isBag(item) then
                                foundBag = item:getFullType()
                            end

                            if first then
                                SR.Log(string.format("LOOT found what it wanted (%s): %s",
                                    tostring(task.want), tostring(item:getFullType())))
                            end
                        end
                    end
                end
            end
        end
    end

    local brain = BanditBrain.Get(zombie)

    if foundBag and brain and not Loot.HasBag(brain) then
        Loot.WearBag(zombie, brain, foundBag)
    end

    -- MAKING IT REAL. Everything above only moved items into `zombie:getInventory()`, and on
    -- a Bandits NPC that is a VIEW, not the store.
    --
    -- Upstream is unambiguous about this. Bandit.lua:710 -- "This translates weapons, loot,
    -- inventory to actual items to be spawned at bandit death" -- and the first thing
    -- UpdateItemsToSpawnAtDeath does is `zombie:clearItemsToSpawnAtDeath()` (:717) before
    -- rebuilding the list from the brain and the live inventory. Nothing we did called it, so
    -- the drop list stayed frozen at whatever the spawner wrote. That is exactly the report:
    -- "cuando loteo el bolso, lo mate para ver su inventario y solo tenia las cosas con las
    -- que spawnea."
    if brain then
        Loot.Remember(zombie, brain)
        pcall(function() Bandit.UpdateItemsToSpawnAtDeath(zombie, brain) end)
    end

    SR.Log(string.format("LOOT %s took %d from %d,%d [%s] | carrying %.1f / %.1f%s",
        tostring(brain and brain.fullname), taken, task.x, task.y,
        table.concat(takenNames, ", "),
        inventory:getCapacityWeight(), inventory:getMaxWeight(),
        foundBag and (" | BAG " .. foundBag) or ""))

    return true
end

-- KEEPING WHAT THEY PICKED UP ---------------------------------------------------------
--
-- REPORTED: "no queda en su inventario las cosas que recoje... toca revisar como se guarda
-- las cosas y donde quedan."
--
-- The 04-08 log proves it without needing to kill anybody. Daniel Green climbed from
-- `carrying 1.5` to `carrying 5.6` between f:74836 and f:82702, then reappeared at f:139066
-- carrying 1.5 again -- with the same name, so the BRAIN survived the gap and the INVENTORY
-- did not. Bandits despawns an NPC that leaves the player's range and rebuilds the IsoZombie
-- from the brain when it comes back; anything that lived only on the old object is gone.
--
-- So the brain has to hold the list, the same way it already holds `weapons` and `bag`. This
-- stores full types only, not item state -- a half-drunk bottle of water comes back full.
-- ponytail: types only; store condition/uses per item if a survivor's kit ever has to be
-- exact rather than merely present.

--- Write down what this person is carrying that they were not spawned with.
function Loot.Remember(zombie, brain)
    local inventory = zombie:getInventory()
    if not inventory or not brain then return end

    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or not items then return end

    local carry = {}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item:getModData().scenesLooted then
            carry[#carry + 1] = item:getFullType()
        end
    end

    brain.scenesCarry = carry
    BanditBrain.Update(zombie, brain)
end

--- Put it all back after a despawn took it.
---
--- Deliberately all-or-nothing: it acts only when the remembered list is non-empty and the
--- live inventory holds NONE of it, which is the wipe this exists for. A partial reconcile
--- would have to decide whether a missing tin was eaten or lost, and guessing wrong there
--- either duplicates food or deletes it.
function Loot.Restore(zombie, brain)
    local carry = brain and brain.scenesCarry
    if not carry or #carry == 0 then return end

    local inventory = zombie:getInventory()
    if not inventory then return end

    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or not items then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item:getModData().scenesLooted then return end
    end

    local back = 0
    for _, itemType in ipairs(carry) do
        local item = BanditCompatibility.InstanceItem(itemType)
        if item then
            item:getModData().scenesLooted = true
            item:getModData().preserve = true
            inventory:AddItem(item)
            back = back + 1
        end
    end

    if back > 0 then
        pcall(function() Bandit.UpdateItemsToSpawnAtDeath(zombie, brain) end)
        SR.Log(string.format("LOOT %s got %d item(s) back after a respawn",
            tostring(brain.fullname), back))
    end
end

-- WHAT SOMEBODY IS ACTUALLY AFTER -----------------------------------------------------
--
-- ASKED FOR: "le hace falta listar que tipo de cosas utiles son importantes conseguir
-- dependiendo de cada situacion... el mas importante es una mochila... darle actividades o
-- misiones principales al NPC hace que ellos se comporten mejor."
--
-- Right, and it names what was missing precisely. Searching worked but had no PURPOSE: they
-- opened whatever was nearest and took the first three things in it, so from outside it read
-- as fidgeting near furniture rather than looking for anything.
--
-- A goal is one word, decided from what they lack, in a fixed order of desperation. It does
-- two things: it decides what comes out of a container FIRST, and it appears in the log, so
-- "why is he doing that" has an answer you can read.
--
-- FIRST SLICE, HONESTLY BOUNDED. Two goals, both with predicates verified in the engine --
-- `getBodyLocation() == "Back"` for a bag, `instanceof(item, "Food")` for food, which is the
-- test ZPCompanion's own foraging block uses. Weapons, crafting a bag from a sheet, and
-- goals that change with the situation are designed in docs/plans/03-autonomy.md and NOT
-- built: each needs a verb we do not have yet, and inventing one is how this project has
-- lost sessions.

--- Does this person already carry one of these?
local function carries(zombie, test)
    local inventory = zombie:getInventory()
    if not inventory then return false end
    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or not items then return false end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and test(item) then return true end
    end
    return false
end

--- What this person is looking for right now, or nil when they want for nothing.
---
--- Ordered by desperation, and the order IS the design: a bag first, because it is the only
--- one that changes what every later search is worth. Somebody with no bag fills up in three
--- items, so finding food before a bag is finding food you cannot carry.
function Loot.GoalOf(zombie, brain)
    if not Loot.HasBag(brain) then return "bag" end
    if not carries(zombie, isFood) then return "food" end
    return nil
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

--- Undo a mark, so a container refused at the moment of taking can be tried again.
---
--- WHY THIS HAS TO EXIST. `Loot.Search` marks a spot the instant the walk reports arrival --
--- BEFORE the pickup task runs. That was correct while the pickup could not fail. It no longer
--- is: `ScenesLoot.onComplete` now refuses three ways, and every refusal used to land on a
--- container that was already written off, deleting it from `FindContainer`'s answers forever.
---
--- The measurement that makes this urgent, from the last session's log: 67 `gives up` against 14
--- takes, half of which took nothing -- and `LOOT refused` appeared ZERO times in three sessions,
--- because the old `reach > 2.0` gate was too loose to ever fire. The new gate is the first one
--- that can actually reject, and it sits in front of an arrival test already failing five to one.
--- Without this, tightening the check would have quietly switched looting off.
---
--- BOUNDED, because an unbounded retry is its own bug and this file has already learned that
--- once (see MAX_APPROACHES). `mood.approach` cannot serve here -- it is cleared on arrival, and
--- arrival is precisely what precedes a refusal, so it would reset every time and never expire.
--- This is its own counter, and when it runs out the write-off is allowed to stand.
---
--- A table field, not a local, ON PURPOSE: `onComplete` is defined ABOVE this line, and Lua 5.1
--- binds locals lexically -- a local declared here is invisible up there and would silently
--- become a nil global. Table fields resolve at CALL time, which is the documented exemption
--- this file already relies on for `Loot.CarryBudget`.
function Loot.Forget(mood, x, y, z)
    if not mood then return false end
    local k = key(x, y, z)

    mood.refusals = mood.refusals or {}
    mood.refusals[k] = (mood.refusals[k] or 0) + 1

    if mood.refusals[k] > MAX_REFUSALS then
        return false                      -- written off for real now
    end

    if mood.looted then mood.looted[k] = nil end
    return true
end

--- How much this NPC may carry, bag included.
---
--- WHY THIS IS NOT JUST `getMaxWeight()`. In Project Zomboid a worn bag is a SEPARATE
--- container -- a player's rucksack has its own `ItemContainer` and its own capacity, and the
--- main inventory's `getMaxWeight()` does not move when you put one on. Our NPCs put
--- everything in the main inventory, so before this function a survivor who found a 35-capacity
--- framepack could still only carry what a survivor with no bag could. The bag was a picture
--- and a death-drop entry, nothing else.
---
--- Reading the capacity off the item is `item:getItemContainer():getMaxWeight()`. That chain is
--- the one vanilla uses on a real bag -- `part:AddItem("Base.Bag_Military"):getItemContainer()`
--- at DebugUIs/Scenarios/FenrisScenario.lua:409. Not `getCapacity()`: that one exists, but on
--- FLUID containers (Fluids/ISFluidBar.lua:27), which is the R2 mistake all over again.
---
--- `brain.bag` is the store, not `getInventory()` -- the bag is instanced fresh here each time
--- rather than looked up, because the live inventory does not survive a despawn.
-- `bagCapacity(brain)` lived here. It instanced the bag from `brain.bag` and read
-- `getItemContainer():getMaxWeight()` -- verified against a real bag at
-- DebugUIs/Scenarios/FenrisScenario.lua:409, and deliberately NOT `getCapacity()`, which is
-- real but belongs to fluid containers. The measurement was correct; the USE of it was not.
--
-- Its only caller added that capacity to a budget checked against the MAIN inventory, which a
-- worn bag never contributes to. Deleted rather than left unused, because a helper that
-- measures something real is the most tempting kind of dead code to wire back in. It comes
-- back from git the day loot actually goes into the bag -- see Loot.CarryBudget below for why
-- that is a change to the carrying model and not to looting.

--- The weight this NPC is willing to reach before it stops searching.
--- What this NPC may carry before it stops searching.
---
--- THE BAG'S CAPACITY USED TO BE ADDED HERE AND IT WAS A LIE. The budget is checked against
--- `inventory:getCapacityWeight()`, which measures the MAIN inventory -- and in this game a worn
--- bag is a SEPARATE container that contributes nothing to it. So the ceiling was raised by a
--- capacity the thing being measured never gains.
---
--- The arithmetic, from a real session: base 8.0, a duffel adds 18, budget becomes (8+18)*0.7 =
--- 18.2, and the NPC keeps taking until the main inventory reads 18.2 against a real maximum of
--- 8. The log caught it exactly -- `carrying 11.1 / 8.0`, 139% -- and `stops searching -- full`
--- appeared ZERO times in the whole run, because the budget believed there was room in a
--- container nothing was ever put into.
---
--- WHY THE ANSWER IS TO REMOVE IT RATHER THAN TO START USING THE BAG. Putting loot inside the
--- bag does not survive death, and that is not an opinion:
--- `Bandit.UpdateItemsToSpawnAtDeath` builds the corpse with `getAllEvalRecurse`
--- (vendor/Bandits/mods/Bandits/42.20/media/lua/shared/Bandit.lua:727), which FLATTENS -- it
--- walks into containers and then adds every item it found INDIVIDUALLY (:729-731). Items put in
--- a bag in the live inventory would come off the corpse loose regardless. The only construction
--- where contents stay inside is the one upstream does for itself: instance a fresh bag, fill it
--- via `bag:getInventory():AddItem` (:1129), and add THAT as one object (:1140). It is local to
--- that function and there is no getter for the death-drop list, so it cannot be reached.
---
--- Storing loot in the bag is therefore a change to how carrying is modelled, not a change to
--- looting, and it is tracked as such in docs/PLAN-OBJETIVOS.md. Until then the honest ceiling
--- is the one the NPC actually has.
function Loot.CarryBudget(zombie, brain)
    local inventory = zombie:getInventory()
    if not inventory then return 0 end
    local ok, base = pcall(function() return inventory:getMaxWeight() end)
    if not ok or type(base) ~= "number" then return 0 end
    return base * WEIGHT_BUDGET
end

--- Whether this NPC has room for anything at all. Somebody already at their budget should
--- not walk across a room to open a drawer they cannot use.
function Loot.HasRoom(zombie, brain)
    local inventory = zombie:getInventory()
    if not inventory then return false end
    local budget = Loot.CarryBudget(zombie, brain)
    if budget <= 0 then return false end
    local ok, carrying = pcall(function() return inventory:getCapacityWeight() end)
    if not ok or type(carrying) ~= "number" then return false end
    return carrying < budget
end

--- The nearest container this NPC has not been through, anywhere in the building it is
--- standing in.
---
--- BUILDING-bounded, not room-bounded. The first version stopped at `sq:getRoom() == room`,
--- which meant a companion searched the kitchen and then had nothing left to want -- the
--- 04-08 log shows both survivors going through four to six spots and stopping dead. The
--- stage deliverable was always "looting a building they are inside" (03-idle-life.md), and
--- one room is not a building.
---
--- `square:getBuilding()` is how vanilla draws the same boundary
--- (ISWorldObjectContextMenu.lua:1694 compares it against the player's). It still cannot
--- wander next door, which is the property that actually mattered: the search radius stays
--- small and they reach new rooms by walking, so a whole house gets covered without ever
--- scanning a whole house at once.
function Loot.FindContainer(zombie, mood)
    local square = zombie:getSquare()
    if not square then return nil end

    -- Outdoors has no building, and that is the gate: nothing to search out here.
    local building = square:getBuilding()
    if not building then return nil end

    local cell = square:getCell()
    if not cell then return nil end

    local zx, zy, zz = math.floor(zombie:getX()), math.floor(zombie:getY()), zombie:getZ()
    local best, bestDist

    for dx = -SEARCH, SEARCH do
        for dy = -SEARCH, SEARCH do
            local dist = dx * dx + dy * dy
            if dist <= SEARCH * SEARCH and (not bestDist or dist < bestDist) then
                local sq = cell:getGridSquare(zx + dx, zy + dy, zz)
                -- Same building. A container through a doorway is the next room of the
                -- house you are both standing in and is fair game; one across the street
                -- is not, and walking to it is how an NPC ends up somewhere you did not
                -- send it.
                if sq and sq:getBuilding() == building
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

--- Where somebody actually stands to open this. NOT the container's own square.
---
--- REPORTED: "se ve la animacion de como desde el mismo punto lotea todas las cosas o revisa
--- todo los cajones... el deberia acercarse a cada cajon y lotear uno por uno."
---
--- This used to be its own function here, resolving the standing square with
--- `BanditUtils.GetAccessSquare(gridSquare, bandit)` (Bandits/42.20/.../BanditUtils.lua:1056)
--- exactly the way
--- described below -- and REACH (0.7, The Ark's own default) lived here too. Both moved into
--- `SR.Move.GoAndDo` (ScenesRelationsMove.lua) once `Loot.FetchBag` turned out to need the
--- identical decision: `BanditUtils.GetAccessSquare` takes the bandit and returns the free
--- neighbour CLOSEST TO THIS NPC, rejecting any square with a wall between
--- (`gridSquare:isWallTo(testSquare)`, :1071), and it is only consulted when the
--- container square is actually blocked (`square:isNotBlocked(false)`). A container on an open
--- floor tile is stood on, not walked around. See that file for the full derivation.

-- How many times we will re-issue a walk to the same container before writing it off. There is
-- no path-failure callback here, so an unreachable spot would otherwise be chosen, walked at,
-- and chosen again forever -- the one failure mode that one-step-at-a-time introduces and the
-- all-at-once version did not have.
local MAX_APPROACHES = 3

--- ONE STEP, THEN DECIDE AGAIN. Walk if it is far, search if it is here -- never both in the
--- same queue.
---
--- THIS IS THE FIX FOR "lotea desde el mismo punto", and the old version is worth writing down
--- because the mistake is a whole class of mistake. It queued the move AND the search together:
---
---     if dist > 0.9 then tasks[#tasks+1] = GetMoveTask(...) end
---     tasks[#tasks+1] = { action = "ScenesLoot", ... }
---
--- A Bandits task queue does not guarantee that a move ARRIVED, only that it ended. A blocked
--- path, a door, a shove from a zombie, or the ladder clearing the queue all end a move early
--- -- and the very next task was the search, which read `task.x, task.y` off the queue and
--- emptied a drawer on the other side of the room. Standing still, playing the animation,
--- looting at range. Exactly what was reported, out of a queue that looked correct.
---
--- Upstream never had the bug because upstream never writes a queue it cannot verify.
--- `BWOAPrograms.GoAndDo` returns the move OR the action and nothing else, and the program
--- re-runs the moment the queue empties -- so the distance is re-measured ON ARRIVAL instead of
--- predicted at planning time. A program only runs on an empty queue, which is what makes that
--- loop free: walk, re-decide, arrive, act.
---
--- The rule this leaves behind, and it is bigger than looting: a task cannot check its own
--- preconditions, so anything a task depends on must be true when it is QUEUED, not when it
--- was planned. `SR.Move.GoAndDo` (ScenesRelationsMove.lua) is that rule extracted into one
--- function so it cannot drift out of sync between this file and any other caller again.
function Loot.Search(zombie, mood, spot, want)
    local task = SR.Own(SR.GOAL.LOOT, {
        action = "ScenesLoot", anim = "Loot", time = 200,
        x = spot.x, y = spot.y, z = spot.z,
        want = want,
    })
    local tasks, arrived = SR.Move.GoAndDo(zombie, spot, task)

    if not arrived then
        -- The approach cap. There is no path-failure callback here, so an unreachable spot
        -- would otherwise be chosen, walked at, and chosen again forever.
        mood.approach = mood.approach or {}
        local k = key(spot.x, spot.y, spot.z)
        mood.approach[k] = (mood.approach[k] or 0) + 1

        if mood.approach[k] > MAX_APPROACHES then
            -- Written off, not retried. Marking it searched is what takes it out of
            -- FindContainer's answers; without this the same unreachable drawer is chosen every
            -- sweep and the NPC never reaches any other furniture.
            markSearched(mood, spot.x, spot.y, spot.z)
            SR.Log(string.format("LOOT gives up on %d,%d -- could not get there in %d tries",
                spot.x, spot.y, MAX_APPROACHES))
            return {}
        end

        return tasks
    end

    -- Here, and only here, is the square marked. The old code marked it at PLANNING time, so a
    -- container the NPC never reached was remembered as already done.
    markSearched(mood, spot.x, spot.y, spot.z)
    if mood.approach then mood.approach[key(spot.x, spot.y, spot.z)] = nil end

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
--- Uses the same `isBag` as everything else, and that is the whole point of it being one
--- function. The floor search and the drawer search disagreeing about what a bag is once was
--- enough. Listing bag ids would mean inventing a list that goes stale the first time the
--- game adds a rucksack.
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
                            if item and isBag(item) then
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

    return best
end

--- Go and get it. The pickup itself is Bandits' own PickUp action; wearing it is a brain field
--- plus ApplyVisuals, the same two steps ScenesRelationsIdle already uses for hats.
---
--- One step at a time, for the same reason Loot.Search is -- see the long note there. The
--- caller has to know WHICH step it got, because "I am waiting to wear a bag" is only true
--- once the pickup has actually been queued; setting that flag on the walk leg made the next
--- sweep look in an empty inventory and conclude somebody else had taken it.
---
--- Returns the tasks and whether this is the pickup leg. `SR.Move.GoAndDo`'s own
--- `tasks, arrived` shape IS this contract -- `arrived` reads exactly as "this is the pickup
--- leg" -- so there is nothing to translate.
function Loot.FetchBag(zombie, want)
    local task = SR.Own(SR.GOAL.LOOT, {
        action = "PickUp", anim = "LootLow", itemType = want.itemType,
        x = want.x, y = want.y, z = want.z, cnt = 1,
    })
    return SR.Move.GoAndDo(zombie, want, task)
end

--- Put it on. Called once the pickup has drained, so the item is theirs before it is worn.
---
--- REPORTED: "vi que un npc si lo cogio, pero no se la equipo. Luego lo mate, y en el
--- inventario no tenia la mochila."
---
--- Two separate defects behind one sentence, and the second one is the interesting one.
---
--- 1. NOTHING REBUILT THE DROP LIST. This wrote `brain.bag` and stopped. But a bandit's death
---    drop is a list built once and cached -- `zombie:clearItemsToSpawnAtDeath()` then a full
---    rebuild, Bandit.lua:717 -- and `brain.bag` is only read DURING that rebuild (:854, and
---    `addItemToSpawnAtDeath(bag)` at :1141). Set the field, never call the rebuild, and the
---    corpse still drops exactly what the spawner gave it. The container path happened to call
---    the rebuild afterwards for its own reasons; the floor path never did, and the floor path
---    is the one that was tested.
---
--- 2. WORN AND CARRIED ARE THE SAME BAG. `Bandit.UpdateItemsToSpawnAtDeath` sweeps the live
---    inventory (`getAllEvalRecurse`, :727-732) AND instances `brain.bag` separately (:854), so
---    a bag that is both in the inventory and named on the brain drops TWICE. The Ark avoids
---    this whole class of problem by never leaving anything in `getInventory()` at all --
---    `ZACollect` hands the item straight to `BWOAPermaInv` and drops the object. We are not
---    moving to that model tonight, so the narrow version of the same rule: once it is worn it
---    is no longer cargo, so take it out of the inventory.
function Loot.WearBag(zombie, brain, itemType)
    brain.bag = { name = itemType }
    BanditBrain.Update(zombie, brain)

    -- EVERY LOOSE COPY OUT, so that the one we are about to wear is the only one. This used to
    -- remove the bag and stop there -- correct when the bag was pure decoration on the brain,
    -- wrong now that it has to be a real worn object. The wear step below puts exactly one back.
    --
    -- Removing them all is what keeps the death drop honest, and this is now the ONLY thing that
    -- does. `Bandit.UpdateItemsToSpawnAtDeath` builds the corpse from the live inventory
    -- (`getAllEvalRecurse`, Bandits 42.20 Bandit.lua:727) AND instances `brain.bag` separately
    -- (:855). Any copy left loose in the inventory therefore becomes a second bag on the body.
    --
    -- The wear step that used to follow put one back deliberately, and that is precisely what
    -- produced "quedó dos veces con la mochila". It has been removed -- see the block below --
    -- so nothing re-adds it and `brain.bag` is the single source of truth again.
    pcall(function()
        local inventory = zombie:getInventory()
        if not inventory then return end
        local items = inventory:getItems()
        for i = items:size() - 1, 0, -1 do
            local item = items:get(i)
            if item and item:getFullType() == itemType then
                inventory:Remove(item)
            end
        end
    end)

    -- THE BAG NEVER RENDERED BECAUSE APPLYVISUALS WAS RETURNING WITHOUT DOING ANYTHING.
    --
    -- Three attempts went into making a worn bag appear on a live NPC -- setWornItem, then
    -- resetModelNextFrame, then resetModel -- and all three were the wrong question. The answer
    -- is a guard clause at the top of the function we were already calling:
    --
    --     local skin = banditVisuals:getSkinTexture()
    --     if not skin or skin:find("^FemaleBody") or skin:find("^MaleBody") then return end
    --         vendor/Bandits/mods/Bandits/42.20/media/lua/shared/Bandit.lua:83-84
    --
    -- `FemaleBody...` / `MaleBody...` ARE the ordinary body textures. So on any NPC that is
    -- already dressed and already on screen, `Bandit.ApplyVisuals` bails on line 84 and never
    -- reaches the block that pushes an ItemVisual for `brain.bag` (:234-246). Our call returned
    -- cleanly, logged nothing, and did nothing. Not an engine limitation -- a line we never read.
    --
    -- THE WAY THROUGH IS UPSTREAM'S OWN, and it is deliberate rather than a hack. The Ark
    -- re-dresses a living NPC in front of the player -- Emma changes outfit mid-programme -- and
    -- its transform action does exactly this first:
    --
    --     zombie:getHumanVisual():setSkinTextureName("x") -- sic!
    --     Bandit.ApplyVisuals(zombie, brain)
    --         vendor/TheArk/mods/BanditsWeekOneTheArk/42.20/.../ZombieActions/ZATransform.lua:56-57
    --
    -- "x" matches neither `^FemaleBody` nor `^MaleBody`, so the guard passes. ApplyVisuals then
    -- sets the real skin back itself, from `brain.skin` or `brain.skinTexture`. Slayer's own
    -- `-- sic!` is him noting it looks wrong and is meant.
    --
    -- WE RESTORE IT OURSELVES IF IT DOES NOT. Both of ApplyVisuals' restore paths are
    -- conditional, so a brain carrying neither field would leave this NPC wearing a skin called
    -- "x" -- which is not a texture, and the failure would be a permanently broken-looking
    -- survivor rather than a missing bag. Cheap to prevent, expensive to discover in play.
    local ok, err = pcall(function()
        local visual = zombie:getHumanVisual()
        if not visual then error("no HumanVisual on this NPC", 0) end

        local realSkin = visual:getSkinTexture()
        visual:setSkinTextureName("x")

        Bandit.ApplyVisuals(zombie, brain)

        local after = visual:getSkinTexture()
        if realSkin and (not after or after == "x") then
            visual:setSkinTextureName(realSkin)
            SR.Log("LOOT put the skin back by hand -- the brain carried no skin to restore")
        end
    end)
    if not ok then
        SR.Log("LOOT could not apply the bag: " .. tostring(err))
        return false
    end

    -- ACTUALLY PUT IT ON. `ApplyVisuals` pushes an ItemVisual into the model's visual list and
    -- then calls `resetModelNextFrame()` and `resetModel()` (Bandits 42.20 Bandit.lua:280-281),
    -- so the model IS rebuilt -- but a bag is not clothing, and a visual entry alone does not
    -- hang it on anybody's back. Slayer wrote the line that does and left it commented out:
    --
    --     -- bandit:setWornItem(item:canBeEquipped(), item)     Bandit.lua:249
    --
    -- Reported symptom that sent us here: the bag showed up on an NPC that walked out of range
    -- and came back -- because the respawn rebuilds the whole character from the brain -- and
    -- never on one that stayed in view.
    --
    -- `canBeEquipped()` and not `getBodyLocation()`, and that is not a guess. Vanilla resolves
    -- the slot for exactly this case at ISUI/ISInventoryPaneContextMenu.lua:1690 --
    -- `(IsClothing() or IsInventoryContainer()) and getBodyLocation() or canBeEquipped()` --
    -- and an InventoryContainer's BodyLocation is empty, which the assertion harness proves
    -- every startup. So the fallback IS the path a bag takes, and "back" is what it yields.
    --
    -- ATTEMPT TWO, AND THE FIRST ONE FAILED SILENTLY -- worth writing down because the silence
    -- is the lesson. Attempt one instanced a fresh bag and handed it straight to `setWornItem`.
    -- It threw nothing, logged nothing, and rendered nothing: `pcall` returned true because the
    -- inner function had simply run, so even the "will not render" line never printed.
    --
    -- The flaw was ownership. In vanilla you always wear something you already hold --
    -- ISInventoryPaneContextMenu wears an item out of the player's own inventory -- and this was
    -- wearing an object that lived in no container at all, having removed the real one from the
    -- inventory ten lines earlier. So: put it in, then wear THAT.
    --
    -- Wrapped because `setWornItem` is declared on IsoGameCharacter and our receiver is an
    -- IsoZombie -- the R2 shape exactly. The log line now reports which step failed instead of
    -- announcing a generic failure, because "it did not render" was the one thing we already knew.
    -- ATTEMPT TWO AND THREE LIVED HERE, AND THEY ARE GONE BECAUSE THE EXPERIMENT ANSWERED NO.
    --
    -- Attempt two added the bag to the inventory and called `setWornItem` on it. Attempt three
    -- added `resetModel()` afterwards, on the theory that ORDER was the untested variable --
    -- ApplyVisuals resets BEFORE the item is worn, so resetting AFTER might be what was missing.
    --
    -- Both worked, in the only sense the code can check. The log printed
    -- `LOOT Anthony Wright wears the Base.Bag_ALICEpack` with no error, twice over two sessions,
    -- with `resetModel` executing on this exact IsoZombie receiver. The bag was equipped.
    --
    -- IT STILL DID NOT RENDER. Reported after the third attempt: "sigue sin verse la mochila al
    -- equiparla, simplemente no me muestra esa animación ni la mochila, el NPC la recoge del
    -- suelo y de una desaparece."
    --
    -- So the question is settled, and settled NEGATIVELY: forcing a live worn-item redraw on an
    -- already-visible IsoZombie is not reachable from Lua. Vanilla's own bag-wear path
    -- (shared/TimedActions/ISWearClothing.lua:118) calls `setWornItem` and NOTHING else, because
    -- on an IsoPlayer the redraw is native per-frame work; there is no "refresh worn items" entry
    -- point anywhere in the 2,680 engine Lua files. The one path confirmed to render this is the
    -- rebuild Bandits does from the brain on range re-entry (docs/BANDITS-API.md:290) -- which is
    -- exactly why walking away and coming back was always the only thing that worked.
    --
    -- AND KEEPING IT COST SOMETHING REAL, which is why this is a revert and not a shrug.
    -- `Bandit.UpdateItemsToSpawnAtDeath` builds the corpse from the live inventory
    -- (`getAllEvalRecurse`, Bandits 42.20 Bandit.lua:727) AND instances `brain.bag` separately
    -- (:855). A real bag sitting in the inventory therefore became a SECOND bag on the body --
    -- reported as "quedó dos veces con la mochila", and a regression against A4, which had passed
    -- before the wear step existed. The comment that used to sit above the removal block even
    -- said this had to be re-checked once the bag came back. It was, and it failed.
    --
    -- `brain.bag` is the single store again. The bag renders on the next natural rebuild, and the
    -- corpse carries exactly one.
    SR.Log(string.format("LOOT %s now has a %s on the brain (renders on next rebuild)",
        tostring(brain.fullname), itemType))



    -- The bag is on the brain now, so this is the call that puts it on the corpse.
    pcall(function() Bandit.UpdateItemsToSpawnAtDeath(zombie, brain) end)

    SR.Log(string.format("LOOT %s now carries a %s", tostring(brain.fullname), itemType))
    return true
end

Events.OnGameStart.Add(function()
    SR.Log("LOOT ready -- bounded searching; upstream Container.Loot is dead code and unused")
end)
