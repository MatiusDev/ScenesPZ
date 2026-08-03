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

-- The one way trust climbs: fight the dead where they can see you do it.
--
-- Small on purpose. OnHitZombie fires per SWING, not per kill, so this accrues faster
-- than it reads. At +2 a neutral stranger reaches "friendly" in thirteen swings -- a few
-- zombies of shared work, not one lucky hit. There is no kill-based alternative:
-- Events.OnZombieDead carries no attacker argument, so the engine cannot tell us who
-- landed the blow.
local HELP_REWARD = 2

-- 12 tiles, squared. Same geometry Bandits uses in BanditPlayer.CheckFriendlyFire
-- (BanditPlayer.lua:97) -- squared so there is no sqrt in a per-hit loop.
local WITNESS_RADIUS_SQ = 144

local function isBandit(character)
    return character ~= nil and character:getVariableBoolean("Bandit")
end

-- Bandits attacking each other, and NPC-on-NPC hits, are not our business. Only a real
-- human player moves trust.
--
-- Do NOT add an isNPC() guard here. That method does not exist in 42.20 -- it appears
-- zero times across the 2,680 Lua files in pzserver/media/lua/. Calling it throws
-- "Object tried to call nil", which killed this handler on every single hit for two
-- play sessions (110 stack traces in logs/console.txt) and made it look as though
-- trust simply never moved.
--
-- Bandits has the identical defect at BanditPlayer.lua:91, so their CheckFriendlyFire
-- is dead in 42.20 as well. Copying that line is exactly how we inherited the bug.
--
-- instanceof alone is sufficient: every Bandits NPC is an IsoZombie flagged with the
-- "Bandit" boolean, so it can never satisfy this test in the first place.
local function isRealPlayer(character)
    return character ~= nil and instanceof(character, "IsoPlayer")
end

--- Every bandit close enough to the player, and able to see them, that `accept` allows.
--- Reuses the caches Bandits already maintains rather than scanning the cell ourselves:
--- Cache is id -> IsoZombie, CacheLightB is a light record with .id .x .y .brain
--- (read at BanditPlayer.lua:94-100).
---
--- Both the punishment and the reward are "who was watching?", so they share this. What
--- differs is only who qualifies, which is what `accept` decides.
--- Returns how many bandits it touched, and how many of those crossed a tier. Callers log
--- on the second number: a tier change is an event, a couple of points is bookkeeping.
local function adjustNearby(attacker, delta, reason, accept, quiet)
    local cache, witnesses = BanditZombie.Cache, BanditZombie.CacheLightB
    if not cache or not witnesses then return 0, 0 end

    local attackerX, attackerY = attacker:getX(), attacker:getY()

    local seen, changed = 0, 0
    for _, witness in pairs(witnesses) do
        local dx, dy = witness.x - attackerX, witness.y - attackerY
        if dx * dx + dy * dy < WITNESS_RADIUS_SQ and accept(witness) then
            local other = cache[witness.id]
            if other and other:CanSee(attacker) then
                local before, after = SR.Adjust(other, delta, reason, quiet)
                if before ~= after then
                    SR.Apply(other)
                    changed = changed + 1
                end
                seen = seen + 1
            end
        end
    end
    return seen, changed
end

--- Whose side is this witness on?
---
--- Joining someone REPLACES your allegiance, it does not add to it. Checking birth clan
--- first was wrong and the 2026-08-03 log shows exactly how: every TLOU_Survivors NPC
--- shares one clan id, so two sworn companions still grieved for a stranger the player
--- struck, purely because they had been spawned from the same list. Trust fell from 76 to
--- 56 over a fight that had nothing to do with them.
---
--- A person who has thrown in with you judges by the group they chose. Their old clan is
--- where they came from, not who they answer to.
local function inSameGroup(witness, victim)
    if not witness or not victim then return false end

    if witness.loyal then
        return victim.loyal == true
            and witness.master ~= nil
            and witness.master == victim.master
    end

    return witness.clan ~= nil and witness.clan == victim.clan
end

--- Who is hurt by seeing this. Not everyone who can see it: only the victim's own people.
--- Nobody earns credit for a beating they were the target of, and a stranger from another
--- clan going down is not their loss to feel.
local function kinOf(victimBrain)
    local victimId = victimBrain and victimBrain.id
    return function(witness)
        return witness.id ~= victimId and inSameGroup(witness.brain, victimBrain)
    end
end

--- Killing zombies in front of someone who is already trying to kill you does not make
--- them reconsider. Earning peace back is a separate feature that first has to know who
--- made them hostile -- see the note on SR.Apply. Until then, a hostile NPC is outside
--- the reward path entirely, so trust cannot drift positive while the flag says enemy.
local function isNotHostile(witness)
    local brain = witness.brain
    return brain ~= nil and not brain.hostile and not brain.hostileP
end

-- One event, and everything depends on WHO was hit.
--
-- The first version asked only "is the victim a bandit?", which meant defending yourself
-- from a raider in front of a friendly cost you both of them. That is backwards, and it
-- was visible in the 2026-08-03 log: two survivors penalising each other as witnesses
-- while the player fought hostiles beside them.
--
-- A bystander does not classify by species. It reads intent. Swinging at something that
-- is trying to kill people is the same act whether the target is dead or alive, and it is
-- the opposite of swinging at someone who was standing there peacefully.
Events.OnHitZombie.Add(function(zombie, attacker)
    if not isRealPlayer(attacker) then return end

    local victimBrain = nil
    if isBandit(zombie) then victimBrain = BanditBrain.Get(zombie) end
    local victimIsThreat = victimBrain == nil
        or victimBrain.hostile
        or victimBrain.hostileP

    if victimIsThreat then
        -- A walking corpse, or a person who had already chosen violence. Either way the
        -- player is dealing with a threat, and anyone friendly watching benefits.
        --
        -- Quiet: this fires on every swing of every fight. Only tier crossings are worth
        -- a line, and SR.Adjust still prints those.
        local _, promoted = adjustNearby(attacker, HELP_REWARD, "fought beside", isNotHostile, true)
        if promoted > 0 then
            SR.Log(promoted .. " gained ground for fighting beside the player")
        end
        return
    end

    -- Someone peaceful. This is the only case in the whole module that costs anything.
    local before, after = SR.Adjust(zombie, HIT_PENALTY, "attacked")
    if before ~= after then SR.Apply(zombie) end

    -- The audience, narrowed to the victim's own people. A witness from another clan
    -- watching a stranger get hit has no stake in it; a witness watching one of their own
    -- has every stake.
    --
    -- This used to record the memory and stop there, on the assumption that Bandits
    -- escalated witnesses itself in BanditPlayer.CheckFriendlyFire. The 2026-08-03 log
    -- disproved it: that function dies on the missing isNPC() and never sets a flag.
    local seen = adjustNearby(attacker, WITNESS_PENALTY, "saw one of their own attacked",
        kinOf(victimBrain))
    if SR.DEBUG and seen > 0 then
        SR.Log(seen .. " of their group lost trust")
    end
end)
