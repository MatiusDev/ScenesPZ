-- ScenesPZ -- when a Bandits NPC decides a zombie is worth walking to.
--
-- WHY THIS EXISTS
-- BanditUtils.GetClosestZombieLocation (BanditUtils.lua:840-866) has no distance limit.
-- It walks the whole BanditZombie.CacheLightZ table -- which BanditZombie.lua:110 fills
-- from cell:getZombieList(), every zombie in the loaded cell -- and returns the nearest
-- one at any range. BanditUtils.GetTarget then takes that result as the unconditional
-- baseline target, so an NPC always has somewhere to run as long as one zombie is
-- loaded anywhere nearby. That is why they sprint off across the map instead of holding
-- position.
--
-- Note that ZPBandit.Main sets config.hearDist = 5 right before calling GetTarget. That
-- looks like a detection radius and is not one: hearDist is read only inside
-- GetClosestPlayerLocation (BanditUtils.lua:815-826) and has no effect on zombies.
--
-- HOW
-- Wrap, never replace (principle 4). The original still runs and still does the work; we
-- only discard a result that is further away than a threat can justify. When we do, the
-- caller sees the same "nothing found" shape the original returns on an empty cache, so
-- ZPBandit.Main falls through to its own Shrug branch (ZPBandit.lua:227). That branch is
-- theirs, not ours -- we are choosing between paths their program already has.
--
-- SCOPE WARNING
-- Every program that targets zombies goes through this function, Companion and
-- CompanionGuard included. A companion will not chase a zombie beyond ENGAGE_RANGE
-- either. That is intended at this range, but it is a wider blast radius than anything
-- else in this mod, so it lives in its own file and can be deleted on its own.

require "BanditUtils"

ScenesRelations = ScenesRelations or {}
local SR = ScenesRelations

-- Tiles. A zombie closer than this reaches you in a few seconds, so reacting reads as
-- defence rather than hunting. Set to 8 by the user on 2026-08-03. The witness radius in
-- ScenesRelationsEvents.lua is 12, deliberately wider -- noticing something is not the
-- same as committing to a fight over it.
local ENGAGE_RANGE = 8

-- Same shape GetClosestZombieLocation builds when it finds nothing (BanditUtils.lua:841-846).
-- Rebuilt per call: GetTarget writes fx/fy onto the result it returns, so a shared table
-- would leak state between NPCs.
local function noTarget()
    return { dist = math.huge, x = false, y = false, z = false, id = false }
end

-- Guard against double wrapping. Without it a second load would nest the wrapper inside
-- itself; harmless today, but this file is meant to survive being reloaded during tuning.
if not SR.engagementWrapped then
    SR.engagementWrapped = true

    local originalGetClosestZombieLocation = BanditUtils.GetClosestZombieLocation

    BanditUtils.GetClosestZombieLocation = function(character, config)
        local result = originalGetClosestZombieLocation(character, config)
        if not result or result.dist > ENGAGE_RANGE then
            return noTarget()
        end
        return result
    end
end
