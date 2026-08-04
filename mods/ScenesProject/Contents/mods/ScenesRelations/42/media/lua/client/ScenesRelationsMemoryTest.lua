-- ScenesPZ -- forces the memory test that walking cannot.
--
-- WHY THIS EXISTS
-- The test that decides whether this mod's premise holds is "does an NPC still know you
-- after its cell unloads". The instructions said to walk ten blocks away. That was wrong:
-- a Project Zomboid cell is 300 by 300 tiles, so ten blocks does not come close to
-- unloading anything, and doing it properly means several minutes of walking per attempt.
-- Reported as impractical, and it was.
--
-- HOW THIS IS DIFFERENT FROM CHEATING THE TEST
-- It does not fake the unload. It teleports the player far enough that the engine unloads
-- the cell for real, exactly as walking would, and teleports back. Same code path, none of
-- the walking. teleportTo is what vanilla's own debug tools use
-- (ISFastTeleportMove.lua:12, DebugContextMenu.lua:1185).
--
-- ONE TRIGGER, NOT TWO
-- The first version needed two presses: leave, wait, come back. That was wrong for a
-- reason that only shows up when you try to use it -- after the first press you are 700
-- tiles from anybody, so there is no NPC to open the wheel on and no way to trigger the
-- second half from the same interface.
--
-- It also asked the player to judge when the cell had unloaded, which is the kind of
-- guessing this test exists to remove. So it now runs itself: leave, wait a fixed number
-- of in-game minutes, come back, print the verdict. Three minutes is far longer than an
-- unload needs at 700 tiles and costs about twenty real seconds.
--
-- THE ANSWER COMES FROM THE STORE, NOT FROM FINDING THE BODY
-- On return it asks the store for the id directly. Whether an entity happens to be
-- standing there is a second, separate question -- an NPC may simply have wandered off --
-- and conflating the two is how you conclude "it forgot me" when it merely walked away.

require "ScenesRelations"

local SR = ScenesRelations

-- Tiles. Comfortably more than one cell in any direction, so the original cell is
-- guaranteed to leave the loaded area.
local AWAY = 700

local pending = nil

-- In-game minutes to stay away. An unload at 700 tiles is immediate; this is slack.
local WAIT_MINUTES = 3
local waited = 0

local function nearestSurvivor(player)
    if not BanditZombie or not BanditZombie.GetAllB then return nil end
    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return nil end

    local px, py = player:getX(), player:getY()
    local best, bestDistSq = nil, 20 * 20

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            local distSq = dx * dx + dy * dy
            if distSq < bestDistSq then best, bestDistSq = zombie, distSq end
        end
    end
    return best
end

local function leave(player)
    local bandit = nearestSurvivor(player)
    if not bandit then
        SR.Log("MEMTEST no survivor within 20 tiles -- stand near one first")
        if HaloTextHelper then
            HaloTextHelper.addBadText(player, "No survivor nearby to test")
        end
        return
    end

    local id = SR.IdOf(bandit)
    local record = SR.Peek(bandit)
    if not record then
        SR.Log("MEMTEST that survivor has no record yet -- talk to them or fight beside "
            .. "them first, otherwise there is nothing to forget")
        if HaloTextHelper then
            HaloTextHelper.addBadText(player, "No relationship yet -- nothing to test")
        end
        return
    end

    pending = {
        id = id,
        trust = record.trust,
        name = record.name or "?",
        x = player:getX(),
        y = player:getY(),
        z = player:getZ(),
    }

    SR.Log(string.format(
        "MEMTEST 1/2 LEAVING | id=%s name=%s trust=%d | store holds %d | home %.0f,%.0f,%.0f",
        tostring(id), pending.name, pending.trust, SR.Store.Count(),
        pending.x, pending.y, pending.z))

    player:teleportTo(pending.x + AWAY, pending.y + AWAY, 0)

    if HaloTextHelper then
        HaloTextHelper.addText(player, "Away. Coming back in " .. WAIT_MINUTES .. " minutes")
    end
end

local function comeBack(player)
    local away = pending
    pending = nil

    player:teleportTo(away.x, away.y, away.z)

    -- The store is the question. Ask it by id, before looking for anybody.
    local record = SR.Store.Get(away.id)
    local known = record ~= nil
    local trustNow = record and record.trust or 0

    SR.Log(string.format(
        "MEMTEST 2/2 BACK | id=%s | known=%s trust=%d (was %d) | store holds %d",
        tostring(away.id), tostring(known), trustNow, away.trust, SR.Store.Count()))

    -- Verdict in plain words, so the log does not need interpreting on the other machine.
    if known and trustNow == away.trust then
        SR.Log("MEMTEST VERDICT PASS -- the record survived the unload intact")
    elseif known then
        SR.Log("MEMTEST VERDICT PARTIAL -- the record survived but the number moved; "
            .. "something else is writing to it")
    else
        SR.Log("MEMTEST VERDICT FAIL -- the record is gone. Either the store is not "
            .. "persisting, or this NPC came back under a different id")
    end

    -- Only now, and separately, is anybody actually standing here. An NPC that wandered
    -- off is not the same finding as an NPC that forgot you.
    local present = false
    if BanditZombie and BanditZombie.GetAllB then
        local ok, bandits = pcall(BanditZombie.GetAllB)
        if ok and type(bandits) == "table" then present = bandits[away.id] ~= nil end
    end
    SR.Log("MEMTEST body with that id currently loaded: " .. tostring(present)
        .. " (false only means they moved, not that they forgot)")

    if HaloTextHelper then
        if known then
            HaloTextHelper.addGoodText(player, "Remembered: " .. away.name .. " " .. trustNow)
        else
            HaloTextHelper.addBadText(player, "Forgotten: " .. away.name)
        end
    end
end

local function tick()
    if not pending then
        Events.EveryOneMinute.Remove(tick)
        return
    end

    waited = waited + 1
    if waited < WAIT_MINUTES then
        SR.Log(string.format("MEMTEST waiting | %d of %d in-game minutes", waited, WAIT_MINUTES))
        return
    end

    Events.EveryOneMinute.Remove(tick)

    local player = getSpecificPlayer(0)
    if player then comeBack(player) end
end

--- Runs the whole test. Offered on the interaction wheel while SR.DEBUG is on, because
--- the wheel already picks exactly what this needs: a survivor standing in front of you
--- that you have a relationship with.
---
--- Not a keybinding: vanilla claims every letter but K, and a diagnostic should not compete
--- with the controls you use to stay alive. Not a console command either -- Build 42 ships
--- no Lua prompt. LuaDebugger.lua is a breakpoint debugger, not somewhere you can type.
function SR.MemTest()
    local player = getSpecificPlayer(0)
    if not player then
        SR.Log("MEMTEST no player")
        return
    end

    if pending then
        SR.Log("MEMTEST already running -- it comes back on its own")
        return
    end

    leave(player)
    if not pending then return end   -- leave() refused: no survivor, or no record yet

    waited = 0
    Events.EveryOneMinute.Add(tick)
end

Events.OnGameStart.Add(function()
    SR.Log("MEMTEST ready -- 'Memory test' on the interaction wheel, while debug is on")
end)
