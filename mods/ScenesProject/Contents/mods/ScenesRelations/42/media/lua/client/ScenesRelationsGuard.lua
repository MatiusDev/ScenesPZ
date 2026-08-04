-- ScenesPZ -- stop the player hitting people they did not mean to hit.
--
-- WHY THIS EXISTS
-- Reported from play: swinging at a zombie next to a friendly survivor catches the
-- survivor instead, and the relationship you spent twenty minutes on takes a -25. The
-- punishment is real, the intention was not. A system that reads intent from behaviour
-- cannot also read a misclick as an assault.
--
-- WHAT CHANGED AFTER THE FIRST VERSION
-- The first attempt only skipped the trust penalty, and the feedback was that this misses
-- the point: the fear is not losing a relationship, it is KILLING somebody by accident
-- mid-fight. Deciding to hurt an ally has to be a deliberate act. So the guard now tries
-- to stop the damage rather than merely forgive it.
--
-- THE INVINCIBILITY ATTEMPT, AND WHY IT IS GONE
-- The second version made protected NPCs invincible for the few frames the player's swing
-- was landing. It did not work, and it failed in the worst possible way: setInvincible
-- never threw, so the log said "absorbed a hit" while the survivor bled and eventually
-- died. Reported from play as exactly that.
--
-- The likely reason is that OnWeaponSwingHitPoint fires AFTER the engine has applied
-- damage, not before. Everything hung off that event was therefore a fraction of a second
-- too late: the health snapshot recorded the already-reduced value, and restoring to it
-- was a no-op. setInvincible is removed rather than kept "just in case" -- a lever that
-- does nothing is worse than no lever, because it looks like protection.
--
-- WHAT ACTUALLY WORKS, AND WHY WE KNOW
-- getHealth and setHealth are real on a Bandits NPC: Bandits itself calls
-- bandit:setHealth(health - 0.00005) every tick for bleed-out (BanditUpdate.lua:500).
-- The API was never the problem. The problem was feeding it a value captured too late.
--
-- So health is now sampled on a slow tick that has nothing to do with swings, which means
-- it cannot be poisoned by the ordering of an event we do not control. On a player hit the
-- survivor is put back to the highest health we have seen recently. Sampling that lags by
-- up to a minute also undoes a zombie bite taken in that window -- an inaccuracy that
-- errs toward the ally living, which is the entire point of the button.
--
-- MY OWN RULE, BROKEN
-- The previous version restored only `if before then` and said nothing when there was no
-- snapshot, so a total failure printed the same cheerful line as a success. That is R7 in
-- docs/CODE-REVIEW-RULES.md -- every path announces itself -- and it cost a session. Every
-- branch below logs what it actually did, with the numbers.

require "ScenesRelations"

ScenesRelations = ScenesRelations or {}
local SR = ScenesRelations

SR.Guard = SR.Guard or {}
local Guard = SR.Guard

-- ON means friendly fire is blocked. Default ON, per the request: interaction is the
-- point, and hitting the people you are trying to recruit should be the deliberate act
-- rather than the accidental one.
--
-- Session state on purpose, not saved. A protection that silently stayed off from some
-- forgotten session three days ago is worse than no protection, because you would not
-- know to check.
Guard.enabled = true

-- Tiles. How far from the player we bother sampling health.
local WATCH_RANGE = 20

-- id -> the healthiest we have recently seen this survivor. Deliberately not captured
-- from any swing event: see the header.
local lastKnown = {}

local function healthOf(zombie)
    local ok, health = pcall(function() return zombie:getHealth() end)
    if ok and type(health) == "number" then return health end
    return nil
end

local function isProtected(zombie)
    if not zombie or not zombie:getVariableBoolean("Bandit") then return false end
    local brain = BanditBrain.Get(zombie)
    if not brain then return false end
    -- Somebody actively trying to kill you is not protected. The guard exists for
    -- accidents, not for pacifism.
    return not (brain.hostile or brain.hostileP)
end

--- Remembers how healthy every nearby protected survivor is.
---
--- On a slow tick on purpose. The whole failure of the previous version was hanging this
--- on a swing event whose ordering relative to damage we do not control and cannot check
--- from Lua. A sample taken a few seconds before the swing is stale; a sample taken after
--- it is worthless, and worthless is what we had.
function Guard.Watch()
    if not Guard.enabled then return end

    local player = getSpecificPlayer(0)
    if not player then return end
    if not BanditZombie or not BanditZombie.GetAllB then return end

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    local px, py = player:getX(), player:getY()
    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie and isProtected(zombie) then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            if dx * dx + dy * dy <= WATCH_RANGE * WATCH_RANGE then
                local zid = SR.IdOf(zombie)
                local health = healthOf(zombie)
                if zid and health then
                    -- Highest recently seen, not latest. A survivor healing is real; a
                    -- survivor lower than we remember is either a zombie bite -- which we
                    -- are content to undo -- or the very hit we are about to reverse.
                    local best = lastKnown[zid]
                    if not best or health > best then lastKnown[zid] = health end
                end
            end
        end
    end
end

--- True when this hit should be treated as if it never happened.
---
--- Called by ScenesRelationsEvents at the top of its OnHitZombie handler rather than from
--- a handler of our own. Both files listen to the same event and Events sorts first
--- alphabetically, so a competing handler would apply the penalty before we could stop it.
function Guard.Blocks(zombie, attacker)
    if not Guard.enabled then return false end
    if not attacker or not instanceof(attacker, "IsoPlayer") then return false end
    if not isProtected(zombie) then return false end

    local brain = BanditBrain.Get(zombie)
    local name = tostring(brain and brain.fullname)
    local id = SR.IdOf(zombie)
    local now = healthOf(zombie)
    local best = id and lastKnown[id]

    -- Every branch says what it did, with numbers. The previous version printed the same
    -- reassuring line whether it had healed the survivor or done nothing at all, which is
    -- how a total failure survived a whole play session.
    if not now then
        SR.Log(string.format("GUARD %s | trust kept, but getHealth failed -- the wound stands", name))
    elseif not best then
        -- Never sampled: they walked in and got hit inside the same minute. Take the
        -- current value so the NEXT hit in this fight is covered.
        lastKnown[id] = now
        SR.Log(string.format("GUARD %s | trust kept, no health sample yet (%.3f) -- this "
            .. "first wound stands, later ones will not", name, now))
    elseif now >= best then
        SR.Log(string.format("GUARD %s | trust kept, no damage to undo (%.3f)", name, now))
    else
        local ok = pcall(function() zombie:setHealth(best) end)
        if ok then
            SR.Log(string.format("GUARD %s | healed %.3f -> %.3f, trust kept", name, now, best))
        else
            SR.Log(string.format("GUARD %s | trust kept, but setHealth failed at %.3f", name, now))
        end
    end

    return true
end

--- Public: the sidebar button owns this now. No keybinding -- vanilla already claims
--- every letter except K, and burning a key on something you touch twice a session is
--- the wrong trade.
function Guard.Toggle()
    Guard.enabled = not Guard.enabled
    -- Turning it off must take effect immediately: no stale samples to heal anyone back
    -- to after the player has decided they mean it.
    if not Guard.enabled then lastKnown = {} end
    local player = getSpecificPlayer(0)
    if HaloTextHelper and player then
        if Guard.enabled then
            HaloTextHelper.addGoodText(player, "Survivors protected - you cannot hurt them")
        else
            HaloTextHelper.addBadText(player, "Survivors UNPROTECTED - you can kill them")
        end
    end
    SR.Log("GUARD " .. (Guard.enabled and "on" or "off"))
end

-- Sampling only. Nothing here is attached to a swing, which is the whole fix.
Events.EveryOneMinute.Add(Guard.Watch)

Events.OnGameStart.Add(function()
    SR.Log("GUARD ready -- friendly fire undone by healing. Toggle on the SAFE button")
end)
