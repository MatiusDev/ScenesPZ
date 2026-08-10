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

-- THE FLICKER, AND WHY THE FIX SPLITS IN TWO. Reported: "hay un efecto donde si sucede por un
-- microsegundo y luego desaparece casi de inmediato... pasa muy de vez en cuando al mirar de
-- repente a un NPC." `sweep` below only zeroed the PANIC stat once per pass -- once every
-- ~6 seconds -- and left it alone in between. The engine's own panic tick is not gated by our
-- increase-value multiplier alone; it can add to the raw stat between our passes, so for most
-- of that 6 seconds a value we had already decided to suppress was free to climb back into
-- moodle range and get clamped again on the next pass. That climb-and-clamp is the flash.
--
-- The fix keeps the expensive part -- walking `BanditZombie.CacheLight` -- exactly where it
-- was, and moves only the CHEAP part (write these two numbers) onto a fast event, so the clamp
-- happens every tick instead of once a pass and the value never has room to become visible.
-- DECIDE SLOWLY, APPLY FAST: `sweep` decides and writes `friendlyCache`; `applyCached` below
-- only reads it.
--
-- Declared here for the same lexical-scoping reason as `reported` above -- `sweep` writes it,
-- `applyCached` reads it, and both need it in scope before either is defined.
local friendlyCache = false

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

--- DECIDE. Walks the cache, decides friends-only-or-not, remembers the answer and the one
--- engine value that has to be restored later. Does not touch the player's panic itself --
--- that write belongs to `applyCached` now, so it can happen every tick instead of once a pass.
local function sweep()
    local player = getSpecificPlayer(0)
    if not player then return end

    local ok, err = pcall(function()
        local bodyDamage = player:getBodyDamage()
        if not bodyDamage then return end

        if originalIncrease == nil then
            originalIncrease = bodyDamage:getPanicIncreaseValue()
        end

        friendlyCache = onlyFriendsNear(player)
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
-- than a per-tick call. Not `OnTick` for the DECISION -- the cache walk in `onlyFriendsNear`
-- reads every entry in `BanditZombie.CacheLight`, and a per-frame call that throws is how this
-- project learned about 1,553 exceptions in one session. That cadence must not get cheaper to
-- make below (this file's job) -- fix a flicker, and stay the same cost.
Events.EveryOneMinute.Add(sweep)

--- APPLY. The one thing done at tick rate, and it is small on purpose: read `friendlyCache`
--- and `originalIncrease` -- both already decided by `sweep` -- and write the two engine
--- values. No cache walk, no table, no string built, no log line on the path that runs every
--- tick; `applyCachedBody` is declared once below rather than as a closure inside `applyCached`
--- so calling it through `pcall` allocates nothing per call either.
---
--- `originalIncrease == nil` means `sweep` has not run yet this session -- nothing to apply,
--- nothing to restore to, so this is a no-op until the first pass completes.
--- Tracks what we last wrote to the RATE, so we write it on a transition and not on a tick.
---
--- WHY THIS MATTERS AND IS NOT A MICRO-OPTIMISATION. The rate is a field we do not own. The
--- first version of this fast path wrote `setPanicIncreaseValue` on EVERY tick in both
--- branches, which means that for the whole time suppression is off we would be re-stamping
--- our remembered value over the engine's -- and over any other mod's -- sixty times a second.
--- That is "replace" wearing the clothes of "extend": beta blockers, a trait, or a future
--- Bandits handler writing the same field would be silently undone within a frame and nobody
--- would ever see a stack trace. Rule 4 in CLAUDE.md, and the reason this file exists at all
--- rather than uncommenting Slayer's handler.
---
--- The CLAMP is the opposite case and stays per-tick on purpose: panic is a value we are
--- deliberately holding at zero while you stand among your own people, and the whole point of
--- this change is that it must never have a frame in which it is visible.
local appliedSuppression = nil

local function applyCachedBody(player)
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return end

    if friendlyCache then
        if appliedSuppression ~= true then
            bodyDamage:setPanicIncreaseValue(0.0)
            appliedSuppression = true
        end
        player:getStats():set(CharacterStat.PANIC, 0)
    elseif appliedSuppression ~= false then
        bodyDamage:setPanicIncreaseValue(originalIncrease)
        appliedSuppression = false
    end
end

-- Not the same flag as `reported`, and the difference is the whole point. `reported` silences
-- the LOG; this silences the CALL.
--
-- The first draft of the fast path used `reported` for both, and the message it printed --
-- "suppression is OFF for this session" -- was simply false: nothing turned it off. The handler
-- kept invoking the failing call every single tick for the rest of the session. `pcall` catches
-- the Lua error, but the engine still prints its own Java exception underneath, which is
-- precisely the 1,553-exception log this file's own comment cites as the thing to never do
-- again. A per-tick handler that has already thrown once must STOP, not merely stop complaining.
local fastPathDead = false

local function applyCached(player)
    if fastPathDead then return end
    if not player or originalIncrease == nil then return end

    local ok, err = pcall(applyCachedBody, player)

    if not ok then
        fastPathDead = true

        -- PUT IT BACK BEFORE DYING. This is the half that was missing, and it is the difference
        -- between a feature that switches itself off and a feature that switches the PLAYER's
        -- panic off permanently.
        --
        -- `sweep` no longer writes this field at all -- it only decides. So once the fast path
        -- stops, nobody is left to restore anything. If the throw happens on a tick AFTER we
        -- suppressed, the increase rate is sitting at 0.0, and it stays there for the rest of
        -- the session: panic silently never rises again, with one log line as the only trace.
        -- Nobody would notice until a horde failed to frighten them.
        --
        -- Its own pcall, because the reason we are here is that a call on this object already
        -- threw once -- and a restore that throws must not stop us from marking the path dead.
        if appliedSuppression == true then
            local restored = pcall(function()
                local bodyDamage = player:getBodyDamage()
                if bodyDamage then
                    bodyDamage:setPanicIncreaseValue(originalIncrease)
                end
            end)
            appliedSuppression = restored and false or nil
            if not restored then
                SR.Log("PANIC could not restore the increase rate -- it may be stuck at zero")
            end
        end

        SR.Log("PANIC fast-apply threw, fast suppression is OFF for this session: "
            .. tostring(err))
    end
end

-- `OnPlayerUpdate` fires client-side once per game tick with the player object already in
-- hand -- confirmed by three existing client callers, all in the shape
-- `Events.OnPlayerUpdate.Add(fn)` / `function fn(player)`:
--   pzserver/media/lua/client/Tutorial/Steps.lua:1919,1922
--   pzserver/media/lua/client/erosion/debug/DebugDemoTime.lua:114
--   pzserver/media/lua/client/DebugUIs/Scenarios/FenrisScenario.lua:500
-- Not `OnTick` for the reason line above already gives, but this handler earns the tick rate
-- by doing strictly less than `OnTick` would ask of us: no lookup, no allocation, no log line
-- unless something actually throws.
Events.OnPlayerUpdate.Add(applyCached)

Events.OnGameStart.Add(function()
    SR.Log("PANIC ready -- your own people no longer read as a horde")
end)
