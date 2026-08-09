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

-- Declared here, above `sweep`, on purpose: a `local` written below the function that reads it
-- is invisible to it and silently becomes a nil global. Lua 5.1 lexical scoping, and `luac`
-- compiles it without a word.
local reported = false

--- Is every "zombie" within panic range one of ours?
---
--- `BanditZombie.CacheLight` is the framework's own registry of live NPCs, the same one
--- `PanicHandler` reads. `brain.hostile` and `brain.hostileP` are Bandits' two hostility flags
--- -- general and player-specific -- and an entry with no brain is a real zombie.
---
--- WHY A CONSTANT AND NOT THE ENGINE'S OWN NUMBER. The first version of this copied upstream
--- and called `player:getSeeNearbyCharacterDistance() + 2.0`. It threw on the first sweep:
---
---     PANIC handler threw: Object tried to call nil in onlyFriendsNear
---
--- That method has **zero callsites in all 2,680 files of pzserver/media/lua/**. The only place
--- it appears anywhere is the upstream handler that is switched off -- which is very likely why
--- it is switched off. This is R1 and rule 2 of the pz-lua brief, broken by the author of both:
--- vendored code is not a verification source, and an identifier that only exists in dead code
--- has not been verified by anyone.
---
--- 10 tiles is deliberate rather than measured: close enough that a survivor standing with you
--- is inside it, small enough that somebody across the street does not silence a real horde.
--- If it needs tuning, tune it here -- it is a number we own now, not a number we inherited.
local PANIC_RADIUS = 10.0

local function onlyFriendsNear(player)
    local cache = BanditZombie and BanditZombie.CacheLight
    if not cache then return false end

    local px, py = player:getX(), player:getY()
    local radius = PANIC_RADIUS

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

    -- Once, not once a minute. The throw that killed the first version was worth exactly one
    -- line -- it named the nil call and the function -- and a hundred copies of it would have
    -- buried everything else in a log that is read on another machine.
    if not ok and not reported then
        reported = true
        SR.Log("PANIC handler threw, suppression is OFF for this session: " .. tostring(err))
    end
end

-- SECOND REASON B4 FAILED, and it would have survived the first fix. This was on
-- `EveryTenMinutes`, which is about a real MINUTE of standing next to somebody. Panic climbs
-- continuously, so between two sweeps it walked from calm through "Nervioso" to "Alarmado"
-- exactly as reported -- suppressing the *increase rate* once a minute cannot hold a value that
-- rises every second.
--
-- `EveryOneMinute` is ~6 real seconds: fast enough to catch the climb early, still 10x cheaper
-- than a per-tick call. Not `OnTick` -- this reads a cache and calls into BodyDamage, and a
-- per-frame call that throws is how this project learned about 1,553 exceptions in one session.
Events.EveryOneMinute.Add(sweep)

Events.OnGameStart.Add(function()
    SR.Log("PANIC ready -- your own people no longer read as a horde")
end)
