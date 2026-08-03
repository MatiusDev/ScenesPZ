-- ScenesPZ Relations -- the only place engine events are turned into trust changes.
--
-- Client side on purpose: Bandits drives its NPCs from lua/client (BanditUpdate.lua:2485
-- registers this same event there), and the record we write lives on the entity, which
-- the host serialises with the world.
--
-- EVENT CONTRACT -- verified, not guessed
--   Events.OnHitZombie(zombie, attacker, bodyPart, weapon)
--   The TARGET is the first argument and the ATTACKER is the second. Confirmed at two
--   independent callsites:
--     pzserver/media/lua/shared/Definitions/DamageModelDefinitions.lua:24  (vanilla)
--     vendor/Bandits/.../client/BanditUpdate.lua:2136                      (Bandits)
--   Reading that order backwards would move trust on the wrong entity, and nothing would
--   error -- it would just be quietly wrong for the whole session.

require "ScenesRelations"
local SR = ScenesRelations

-- Tuned against SR.TIERS: from a neutral 0 this drops straight to "wary" (-25), and a
-- second blow reaches "hostile" (-50). One hit is a warning, two is a decision.
local HIT_PENALTY = -25

-- Seeing it happen costs less than being on the receiving end.
local WITNESS_PENALTY = -10

-- 12 tiles, squared. Same geometry Bandits uses in BanditPlayer.CheckFriendlyFire
-- (BanditPlayer.lua:97) -- squared so there is no sqrt in a per-hit loop.
local WITNESS_RADIUS_SQ = 144

local function isBandit(character)
    return character ~= nil and character:getVariableBoolean("Bandit")
end

-- Bandits attacking each other, and NPC-on-NPC hits, are not our business. Only a real
-- human player moves trust. Same two guards as BanditPlayer.lua:91.
local function isRealPlayer(character)
    return character ~= nil
        and instanceof(character, "IsoPlayer")
        and not character:isNPC()
end

--- Bandits near the attacker who can actually see them lose trust too.
--- Reuses the caches Bandits already maintains rather than scanning the cell ourselves:
--- Cache is id -> IsoZombie, CacheLightB is a light record with .id .x .y .brain
--- (read at BanditPlayer.lua:94-100).
local function penalizeWitnesses(victim, attacker, delta, reason)
    local cache, witnesses = BanditZombie.Cache, BanditZombie.CacheLightB
    if not cache or not witnesses then return 0 end

    local victimBrain = BanditBrain.Get(victim)
    local victimId = victimBrain and victimBrain.id
    local attackerX, attackerY = attacker:getX(), attacker:getY()

    local seen = 0
    for _, witness in pairs(witnesses) do
        if witness.id ~= victimId then
            local dx, dy = witness.x - attackerX, witness.y - attackerY
            if dx * dx + dy * dy < WITNESS_RADIUS_SQ then
                local other = cache[witness.id]
                if other and other:CanSee(attacker) then
                    SR.Adjust(other, delta, reason)
                    seen = seen + 1
                end
            end
        end
    end
    return seen
end

Events.OnHitZombie.Add(function(zombie, attacker)
    if not isBandit(zombie) or not isRealPlayer(attacker) then return end

    -- The victim. Apply only when the tier actually moved, so we are not writing into
    -- the Bandits brain on every single swing.
    local before, after = SR.Adjust(zombie, HIT_PENALTY, "attacked")
    if before ~= after then SR.Apply(zombie) end

    -- The audience. Deliberately no SR.Apply here: Bandits already decides immediate
    -- hostility for witnesses, our job is to remember that they saw it.
    local seen = penalizeWitnesses(zombie, attacker, WITNESS_PENALTY, "saw attack")
    if SR.DEBUG and seen > 0 then
        SR.Log(seen .. " witnesses lost trust")
    end
end)
