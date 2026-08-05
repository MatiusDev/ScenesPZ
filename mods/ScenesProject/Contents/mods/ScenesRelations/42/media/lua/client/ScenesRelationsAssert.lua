-- ScenesPZ -- assumptions, checked against the real engine, once per game start.
--
-- WHY THIS EXISTS
-- On 2026-08-05 a single wrong method survived THREE play sessions. `isBag(item)` asked
-- `item:getBodyLocation() == "Back"`. That method is real, has 107 callsites in
-- pzserver/media/lua/, and returns exactly what you expect -- on clothing. A bag is an
-- InventoryContainer and has no BodyLocation at all, so the predicate answered `false` for
-- every rucksack in the game, politely, forever.
--
-- Four reported symptoms came out of it. None of the existing safety nets caught any of them:
--
--   * `luac -p` compiles a wrong answer as happily as a right one;
--   * the headless smoke test never executes media/lua/client/, which is most of this mod;
--   * `tools/lint.sh` verifies item IDS resolve, not that a method applies to them;
--   * R1 asks for a real callsite, and there WAS one -- on a T-shirt.
--
-- Every one of those runs somewhere other than the game. This one runs INSIDE it, on objects
-- the engine built, which is the only place the question can actually be answered.
--
-- WHAT BELONGS HERE
-- Assumptions we would be unable to see failing. An assertion is worth writing when a wrong
-- answer would be SILENT -- a predicate returning false, an accessor returning nil, a method
-- that exists on the class next door. Things that throw are already loud and need no help.
--
-- WHAT DOES NOT BELONG HERE
-- Behaviour. Whether a survivor decides to loot a room is a design question answered by
-- playing, not by an assertion. This file only checks that the engine is shaped the way the
-- code believes it is shaped.
--
-- HOW IT FAILS
-- It does not. Every check is wrapped, a broken check reports itself as a failure rather than
-- taking the mod down with it, and nothing here mutates game state -- the items are built in
-- memory, examined, and dropped. A diagnostic that can break the thing it diagnoses is worse
-- than no diagnostic.

require "ScenesRelations"

local SR = ScenesRelations

local passed, failed = 0, 0

--- One assumption, one line, and the line says what was expected either way.
---
--- `detail` is printed on failure only, and it should name the value actually seen. A failure
--- reading `ASSERT FAIL bag is an InventoryContainer` sends somebody back to the source; one
--- reading `... | got nil` tells them what happened.
local function check(name, fn)
    local ok, result, detail = pcall(fn)

    if not ok then
        failed = failed + 1
        SR.Log(string.format("ASSERT FAIL %s | threw: %s", name, tostring(result)))
        return
    end

    if result then
        passed = passed + 1
        SR.Log(string.format("ASSERT ok   %s", name))
    else
        failed = failed + 1
        SR.Log(string.format("ASSERT FAIL %s%s", name,
            detail and (" | got " .. tostring(detail)) or ""))
    end
end

--- A real item, built the way Bandits builds them.
---
--- BanditCompatibility.InstanceItem rather than InventoryItemFactory directly: it is what
--- every Bandits action uses, so an item that cannot be made here is an item their code could
--- not have made either, and that is worth knowing on its own.
local function item(itemType)
    return BanditCompatibility.InstanceItem(itemType)
end

-- THE ASSUMPTIONS ---------------------------------------------------------------------
--
-- Every id below is verified in pzserver/media/scripts/generated/:
--   Base.Bag_Schoolbag            container.txt:49   (CanBeEquipped = base:back)
--   Base.Tshirt_WhiteLongSleeve   clothing.txt:17770 (BodyLocation  = base:tshirt)
--   Base.TinnedBeans              food.txt:4381

local function run()
    -- WHAT A BAG IS. The bug of 2026-08-05, written down so it cannot come back quietly.
    check("a schoolbag can be instantiated", function()
        return item("Base.Bag_Schoolbag") ~= nil
    end)

    check("a schoolbag is an InventoryContainer", function()
        local bag = item("Base.Bag_Schoolbag")
        return bag and instanceof(bag, "InventoryContainer") or false
    end)

    check("a schoolbag reports canBeEquipped()", function()
        local bag = item("Base.Bag_Schoolbag")
        local where = bag and bag:canBeEquipped()
        return where ~= nil and where ~= "", tostring(where)
    end)

    -- THE NEGATIVE THAT COST THREE SESSIONS. This one passes by proving the OLD predicate
    -- wrong: a bag has no body location. If a future build ever gives it one, this line flips
    -- and tells us the ground moved.
    check("a schoolbag has NO getBodyLocation (why the old isBag failed)", function()
        local bag = item("Base.Bag_Schoolbag")
        local loc = bag and bag:getBodyLocation()
        return (loc == nil or loc == ""), tostring(loc)
    end)

    check("a T-shirt DOES have getBodyLocation", function()
        local shirt = item("Base.Tshirt_WhiteLongSleeve")
        local loc = shirt and shirt:getBodyLocation()
        return loc ~= nil and loc ~= "", tostring(loc)
    end)

    -- THE PREDICATE ITSELF, not a copy of it. Testing a duplicate of a rule proves the
    -- duplicate works, which is how a wrong rule survives a test suite.
    check("SR.Loot.IsBag says yes to a schoolbag", function()
        return SR.Loot and SR.Loot.IsBag(item("Base.Bag_Schoolbag")) == true
    end)

    check("SR.Loot.IsBag says no to a T-shirt", function()
        return SR.Loot and SR.Loot.IsBag(item("Base.Tshirt_WhiteLongSleeve")) == false
    end)

    check("SR.Loot.IsFood says yes to tinned beans", function()
        return SR.Loot and SR.Loot.IsFood(item("Base.TinnedBeans")) == true
    end)

    -- WHERE AN NPC'S POSSESSIONS LIVE. Bandits stores them on the brain and materialises them
    -- through this function; anything added to a live inventory without calling it is
    -- invisible at death. Its absence would be silent in exactly the same way.
    check("Bandit.UpdateItemsToSpawnAtDeath exists", function()
        return type(Bandit) == "table" and type(Bandit.UpdateItemsToSpawnAtDeath) == "function"
    end)

    -- WHERE SOMEBODY STANDS TO OPEN A DRAWER. Vanilla-owned, and only ever called with an
    -- IsoPlayer before this mod, so its presence is worth confirming rather than assuming.
    check("AdjacentFreeTileFinder.Find exists", function()
        return type(AdjacentFreeTileFinder) == "table"
           and type(AdjacentFreeTileFinder.Find) == "function"
    end)

    SR.Log(string.format("ASSERT ---- %d ok, %d FAILED ----", passed, failed))

    -- Said twice on purpose. A failure buried among a thousand other lines is a failure
    -- nobody reads, and console.txt is the only debugger this project has.
    if failed > 0 then
        SR.Log(string.format(
            "ASSERT %d ASSUMPTION(S) BROKEN -- the engine is not shaped the way the code "
            .. "thinks. Fix these before trusting any behaviour above.", failed))
    end
end

-- After OnGameStart, not on it. Item instantiation needs the script manager loaded, and
-- OnGameStart is the earliest point where every mod's scripts are guaranteed parsed. One tick
-- of delay costs nothing and removes a whole class of ordering question.
Events.OnGameStart.Add(function()
    local fired = false
    local function once()
        if fired then return end
        fired = true
        Events.OnTick.Remove(once)

        local ok, err = pcall(run)
        if not ok then
            SR.Log("ASSERT harness itself threw: " .. tostring(err))
        end
    end
    Events.OnTick.Add(once)
end)
