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

    -- WHERE SOMEBODY STANDS TO OPEN A DRAWER. Bandits' own, and it takes the bandit as an
    -- argument -- `square:DistToProper(bandit)`, Bandits/42.20/.../BanditUtils.lua:1081 -- so
    -- unlike vanilla's
    -- AdjacentFreeTileFinder it is already designed to be handed an IsoZombie.
    check("BanditUtils.GetAccessSquare exists", function()
        return type(BanditUtils) == "table" and type(BanditUtils.GetAccessSquare) == "function"
    end)

    -- IS THERE A WALL IN THE WAY. Without this an NPC 0.6 tiles from a cupboard through a
    -- partition reaches through it. Taken from BWOAPrograms.GoAndDo, which gates every one of
    -- The Ark's walk-then-act decisions on it.
    check("LosUtil.lineClearCollide exists", function()
        return type(LosUtil) == "table" and type(LosUtil.lineClearCollide) == "function"
    end)

    -- THE SHARED WALK-THEN-ACT PRIMITIVE. All four things below are what
    -- `SR.Move.GoAndDo` (ScenesRelationsMove.lua) is built on. `GetAccessSquare` and
    -- `lineClearCollide` above were already covered; these two were not, because before this
    -- file no caller asked the engine directly -- they went through `zombie:getCell()` and a
    -- copy of the same logic instead.

    -- WHETHER THE PRIMITIVE EVEN NEEDS TO DETOUR. `square:isNotBlocked(false)` decides
    -- between standing on the target square itself and asking `GetAccessSquare` for a
    -- neighbour -- confirmed against `pzserver/media/lua/shared/Foraging/forageSystem.lua:1695`,
    -- which reads the same call the same way.
    check("a live grid square responds to isNotBlocked(false)", function()
        local player = getSpecificPlayer(0)
        local square = player and player:getSquare()
        if not square then return false, "no player square available yet" end
        local ok, blocked = pcall(function() return square:isNotBlocked(false) end)
        return ok and type(blocked) == "boolean", tostring(blocked)
    end)

    -- WHERE THE PRIMITIVE RESOLVES COORDINATES INTO A SQUARE. `getCell()` -- the global,
    -- the same one `BWOAPrograms.GoAndDo` calls -- not `zombie:getCell()`, which is what every
    -- caller used before this file existed.
    check("getCell() returns the loaded cell", function()
        return type(getCell) == "function" and getCell() ~= nil
    end)

    -- DOORS -- the block-6 probes. Everything below is asked because the RESEARCH could not
    -- settle it, and the difference between the two kinds of answer is the whole point of
    -- having this harness.
    --
    -- `isLocked`, `IsOpen`, `isBarricaded` and `ToggleDoor` are all PROVEN: vanilla Lua calls
    -- them and `ToggleDoor` takes an IsoGameCharacter rather than an IsoPlayer
    -- (shared/TimedActions/ISOpenCloseDoor.lua:31), so a Bandits task action can use it.
    --
    -- `isExterior` / `isExteriorDoor` are NOT. They exist on the compiled class, and ZERO
    -- vanilla Lua files call either one. That is the exact shape of
    -- `getSeeNearbyCharacterDistance`, which was copied out of dead vendored code, has zero
    -- engine callsites, and cost this project a full session -- the lesson being that a method
    -- nothing calls has been verified by nobody. The user's whole entry ordering ("the next
    -- EXTERIOR door, then the nearest window") rests on this one question, so it gets answered
    -- by the engine in play rather than by a decompiler here.
    --
    -- Finding a real door to ask is the awkward part: there is no "give me a door" API, so this
    -- walks a small square around the player and takes the first one. No player, or no door
    -- within reach, is reported as a SKIP rather than a pass -- a check that goes green because
    -- it found nothing to test is worse than no check.
    local function findDoorNearPlayer()
        local player = getSpecificPlayer(0)
        if not player then return nil, "no player yet" end
        local square = player:getSquare()
        local cell = square and square:getCell()
        if not cell then return nil, "no cell" end

        local px, py, pz = player:getX(), player:getY(), player:getZ()
        for dx = -6, 6 do
            for dy = -6, 6 do
                local sq = cell:getGridSquare(px + dx, py + dy, pz)
                if sq then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        if obj and instanceof(obj, "IsoDoor") then return obj end
                    end
                end
            end
        end
        return nil, "no IsoDoor within 6 tiles -- stand near a house and reload to test"
    end

    check("a door answers IsOpen / isLocked / isBarricaded", function()
        local door, why = findDoorNearPlayer()
        if not door then return false, "SKIPPED: " .. tostring(why) end
        local ok = pcall(function()
            return door:IsOpen(), door:isLocked(), door:isBarricaded()
        end)
        return ok, ok and nil or "one of the three threw"
    end)

    check("PROBE door:isExterior() is callable from Lua", function()
        local door, why = findDoorNearPlayer()
        if not door then return false, "SKIPPED: " .. tostring(why) end
        local ok, value = pcall(function() return door:isExterior() end)
        SR.Log(string.format("PROBE door | isExterior ok=%s value=%s",
            tostring(ok), tostring(value)))
        return ok, ok and nil or "not reachable from Lua -- the entry ordering needs a geometric fallback"
    end)

    check("PROBE door:isExteriorDoor(character) is callable from Lua", function()
        local door, why = findDoorNearPlayer()
        if not door then return false, "SKIPPED: " .. tostring(why) end
        local player = getSpecificPlayer(0)
        local ok, value = pcall(function() return door:isExteriorDoor(player) end)
        SR.Log(string.format("PROBE door | isExteriorDoor ok=%s value=%s",
            tostring(ok), tostring(value)))
        return ok, ok and nil or "not reachable from Lua -- try isExterior() or go geometric"
    end)

    -- THE OBSTACLE CLASSIFIER. Every predicate it uses has a vanilla Lua callsite, which is the
    -- bar R1 sets -- but "the method exists" and "the method answers for THIS receiver" are
    -- different claims, and only the second one matters. `isHoppable` is called on an IsoObject
    -- in shared/Moveables/ISMoveablesAction.lua:12; we call it on whatever a grid square hands
    -- back, which is not guaranteed to be the same thing.
    check("SR.Move.WhatBlocks exists", function()
        return type(SR.Move) == "table" and type(SR.Move.WhatBlocks) == "function"
    end)

    check("WhatBlocks runs the obstacle predicates without throwing", function()
        local player = getSpecificPlayer(0)
        if not player then return false, "SKIPPED: no player yet" end

        -- NOT a zero-length line. The first version asked about the player's own square, and a
        -- zero-length line is CLEAR, so `WhatBlocks` returned before reaching a single predicate
        -- -- the check passed identically whether the classifier worked or not, which is the
        -- worst kind of green.
        --
        -- Eight tiles in each of four directions instead. Standing anywhere indoors or near a
        -- street, at least one of those lines crosses a wall, a door or a fence, so `classify`
        -- runs against real objects the engine built. That is the only question worth asking
        -- here: a method proven on an IsoObject in vanilla is not thereby proven on whatever a
        -- grid square hands back.
        local px, py, pz = player:getX(), player:getY(), player:getZ()
        local kinds = {}
        for _, d in ipairs({ {8, 0}, {-8, 0}, {0, 8}, {0, -8} }) do
            local ok, kind = pcall(function()
                return SR.Move.WhatBlocks(player, px + d[1], py + d[2], pz)
            end)
            if not ok then
                return false, "threw: " .. tostring(kind)
            end
            kinds[#kinds + 1] = tostring(kind)
        end

        SR.Log("PROBE blocks | E/W/N/S = " .. table.concat(kinds, ", "))
        return true
    end)

    -- The vanilla adjacency finder, and the one we would use instead of GetAccessSquare. Vanilla
    -- calls it for DOORS as well as windows despite the name
    -- (client/ISUI/ISWorldObjectContextMenu.lua:2552), and nothing inside it is player-only --
    -- but "nothing inside it is player-only" is a reading, and this is the machine that can
    -- actually run it.
    check("AdjacentFreeTileFinder.FindWindowOrDoor exists", function()
        return type(AdjacentFreeTileFinder) == "table"
           and type(AdjacentFreeTileFinder.FindWindowOrDoor) == "function"
    end)

    -- THE PRIMITIVE ITSELF. If this is missing, every one of Loot.Search, Loot.FetchBag, and
    -- ScenesRelationsIdle's goGet silently queues nothing.
    check("SR.Move.GoAndDo exists", function()
        return type(SR.Move) == "table" and type(SR.Move.GoAndDo) == "function"
    end)

    -- WHAT IS WORTH CARRYING. The 05-08 run filled three survivors with 6kg of nothing and they
    -- never searched again, because the filler pass took whatever was in front of it.
    check("SR.Loot.IsWorthTaking says yes to tinned beans", function()
        return SR.Loot and SR.Loot.IsWorthTaking(item("Base.TinnedBeans")) == true
    end)

    check("SR.Loot.IsWorthTaking says yes to a schoolbag", function()
        return SR.Loot and SR.Loot.IsWorthTaking(item("Base.Bag_Schoolbag")) == true
    end)

    -- A shirt is the shape of the problem: harmless, plentiful, and it eats the budget.
    check("SR.Loot.IsWorthTaking says no to a T-shirt", function()
        return SR.Loot and SR.Loot.IsWorthTaking(item("Base.Tshirt_WhiteLongSleeve")) == false
    end)

    -- The per-item weight cap is only as good as this returning a real number.
    check("getActualWeight returns a number", function()
        local tin = item("Base.TinnedBeans")
        local w = tin and tin:getActualWeight()
        return type(w) == "number" and w > 0, tostring(w)
    end)

    -- Putting a bag on a live NPC. Sets the model; the drop list is a separate call.
    check("Bandit.ApplyVisuals exists", function()
        return type(Bandit) == "table" and type(Bandit.ApplyVisuals) == "function"
    end)

    -- HOW MUCH A BAG ACTUALLY HOLDS. `Loot.CarryBudget` adds this to the carry ceiling, so a
    -- survivor with a 35-capacity framepack fills up later than one with a schoolbag. The chain
    -- is item -> getItemContainer() -> getMaxWeight(), taken from a real bag in vanilla at
    -- DebugUIs/Scenarios/FenrisScenario.lua:409. NOT `getCapacity()`, which is real but belongs
    -- to fluid containers (Fluids/ISFluidBar.lua:27) -- the R2 mistake wearing a different hat.
    check("a schoolbag exposes getItemContainer():getMaxWeight()", function()
        local bag = item("Base.Bag_Schoolbag")
        local container = bag and bag:getItemContainer()
        local max = container and container:getMaxWeight()
        return type(max) == "number" and max > 0, tostring(max)
    end)

    -- THE PANIC SUPPRESSOR'S THREE ASSUMPTIONS. Every one of them would fail silently: a nil
    -- stat id sets nothing, a missing accessor throws inside a pcall we would never read.
    check("CharacterStat.PANIC exists", function()
        return type(CharacterStat) == "table" and CharacterStat.PANIC ~= nil,
            tostring(CharacterStat and CharacterStat.PANIC)
    end)

    check("getBodyDamage():getPanicIncreaseValue() returns a number", function()
        local player = getSpecificPlayer(0)
        local bd = player and player:getBodyDamage()
        local v = bd and bd:getPanicIncreaseValue()
        return type(v) == "number", tostring(v)
    end)

    check("BanditUtils.DistToManhattan exists", function()
        return type(BanditUtils) == "table" and type(BanditUtils.DistToManhattan) == "function"
    end)

    -- THE ONE THAT WAS MISSING, and its absence cost a whole play session. The first panic
    -- handler used `player:getSeeNearbyCharacterDistance()`, copied from the upstream handler
    -- that ships switched off. It threw on the first sweep -- `Object tried to call nil in
    -- onlyFriendsNear` -- because that method has ZERO callsites in all 2,680 files under
    -- pzserver/media/lua/. It exists only inside dead vendored code.
    --
    -- A NEGATIVE ASSERTION USED TO LIVE HERE, AND IT HAD TO GO. It called the method inside a
    -- `pcall` and passed when the call failed -- which it did, and the check reported `ok`.
    --
    -- But `pcall` only stops the error from reaching US. The engine still prints its own Java
    -- trace underneath, so every single startup put this in console.txt:
    --
    --     Lua fail. Message: Tried to call nil
    --         se.krka.kahlua.vm.KahluaUtil.fail(KahluaUtil.java:96)
    --         Lua((MOD:ScenesPZ Relations)).getSeeNearbyCharacterDistance is still absent ...
    --
    -- A stack trace that reads exactly like a crash, in the one file this project has for
    -- debugging client code, which is read by hand on another machine. It was found by the user
    -- asking "why are there errors in console.txt" -- the assertion was manufacturing the alarm
    -- it was meant to prevent.
    --
    -- Deleted rather than repaired because there is nothing to repair: you cannot ask a Java
    -- binding whether it exists without calling it. And the value was never high -- the method
    -- appearing in some future build would not change our code, because PANIC_RADIUS in
    -- ScenesRelationsPanic.lua is a constant we now own on purpose. The lesson that mattered is
    -- in that file's comments and in docs/CODE-REVIEW-RULES.md, where it costs nothing to keep.

    -- The registry the panic sweep reads. Empty is fine and normal; missing is not.
    check("BanditZombie.CacheLight is a table", function()
        return type(BanditZombie) == "table" and type(BanditZombie.CacheLight) == "table"
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
