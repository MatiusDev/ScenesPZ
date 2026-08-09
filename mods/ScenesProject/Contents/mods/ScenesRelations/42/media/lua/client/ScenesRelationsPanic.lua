-- ScenesPZ -- your own people should not frighten you.
--
-- REPORTED: "mi personaje detecta los NPC como zombies, entonces cuando están tan cerca me
-- hacen sentir miedo, o el sentimiento cuando uno ve varios zombies."
--
-- WHY IT HAPPENS, AND WHY IT IS NOT A BUG IN OUR CODE
-- A Bandits NPC *is* an `IsoZombie`. That is the whole trick the framework is built on -- it
-- gets pathing, animation, combat and the horde system for free by being one. The engine's
-- panic model counts zombies near the player and does not ask any of them whose side they are
-- on, so a survivor standing next to you reads exactly like a corpse standing next to you.
--
-- UPSTREAM WROTE THIS AND TURNED IT OFF
-- `PanicHandler` in Bandits 42.20 client/BanditPlayer.lua:132 is the same idea, complete, and
-- dead on the next line:
--
--     local PanicHandler = function(player)
--         if isServer() then return end
--         if true then return end  -- Disabled for now
--
-- We do not uncomment other people's code -- that is the "extend, never replace" rule, and a
-- vendored edit would evaporate the next time `deps.py update` runs. This is our own handler
-- doing the same job, and if Slayer ever enables his the two agree rather than fight: both
-- restore the original value when a hostile is near, so whichever runs second wins with the
-- same answer.
--
-- WHAT IT DOES NOT DO
-- It does not make you fearless. A hostile bandit or a real zombie inside the radius restores
-- panic immediately -- the calm is only for a space occupied entirely by your own people.

require "ScenesRelations"

local SR = ScenesRelations

-- Set once, the first time we touch it, and never re-read while suppressed -- otherwise we
-- would eventually cache our own zero and lose the real value for good.
local originalIncrease = nil

--- Is every "zombie" within panic range one of ours?
---
--- `BanditZombie.CacheLight` is the framework's own registry of live NPCs, the same one
--- `PanicHandler` reads. `brain.hostile` and `brain.hostileP` are Bandits' two hostility flags
--- -- general and player-specific -- and an entry with no brain is a real zombie.
---
--- `getSeeNearbyCharacterDistance()` is the engine's own notion of how far "nearby" is for a
--- character, which is the number the panic model itself is scaled to. Borrowed from upstream
--- rather than invented so the calm radius matches the fear radius exactly.
local function onlyFriendsNear(player)
    local cache = BanditZombie and BanditZombie.CacheLight
    if not cache then return false end

    local px, py = player:getX(), player:getY()
    local radius = player:getSeeNearbyCharacterDistance() + 2.0

    local sawFriend = false
    for _, z in pairs(cache) do
        local dist = BanditUtils.DistToManhattan(z.x, z.y, px, py)
        if dist <= radius then
            if z.brain and not z.brain.hostile and not z.brain.hostileP then
                sawFriend = true
            else
                -- One hostile is enough. Nothing below can make this safe again.
                return false
            end
        end
    end

    return sawFriend
end

--- Suppress while surrounded by friends, restore the moment anything else turns up.
local function sweep()
    local player = getSpecificPlayer(0)
    if not player then return end

    local ok, err = pcall(function()
        local bodyDamage = player:getBodyDamage()
        if not bodyDamage then return end

        if originalIncrease == nil then
            originalIncrease = bodyDamage:getPanicIncreaseValue()
        end

        if onlyFriendsNear(player) then
            bodyDamage:setPanicIncreaseValue(0.0)
            player:getStats():set(CharacterStat.PANIC, 0)
        else
            bodyDamage:setPanicIncreaseValue(originalIncrease)
        end
    end)

    if not ok and SR.DEBUG then
        SR.Log("PANIC handler threw: " .. tostring(err))
    end
end

-- Every ten in-game minutes rather than every tick. Panic climbs over seconds, not frames, and
-- a per-frame call that throws is how this project learned about 1,553 exceptions in one
-- session.
Events.EveryTenMinutes.Add(sweep)

Events.OnGameStart.Add(function()
    SR.Log("PANIC ready -- your own people no longer read as a horde")
end)
