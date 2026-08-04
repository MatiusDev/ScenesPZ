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
-- HOW, GIVEN THE ENGINE GIVES US NO VETO
-- There is no cancellable pre-damage event in 42.20. The complete list of hit-adjacent
-- events is OnHitZombie, OnWeaponSwingHitPoint, OnPlayerAttackFinished, OnWeaponHitTree
-- and OnWeaponHitXp, and none can abort a swing. What we can do is make the target
-- untouchable for the fraction of a second the player's own swing is landing:
--
--   swing connects  -> protected NPCs nearby become invincible
--   attack finishes -> invincibility cleared
--
-- The window is a few frames wide, so a zombie biting that same survivor is unaffected in
-- any way you could notice. Three independent paths clear the flag, because an NPC left
-- permanently immortal would be a far worse bug than the one being fixed.
--
-- WHAT IS PROVEN AND WHAT IS NOT
-- setInvincible is real and vanilla uses it (DebugContextMenu.lua:1123, Tutorial1.lua:230)
-- -- but always on a PLAYER, never on a zombie. Today's HaloTextHelper result is the
-- reason that distinction gets respect: the Java side rejected addText for an IsoZombie
-- even though the method exists on the shared base class. So every call here is wrapped,
-- reported once on failure, and backed by restoring hit points from a snapshot.
--
-- Guaranteed regardless: no trust penalty and no hostility escalation. That part is our
-- own state and cannot fail.

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

-- Tiles. Only NPCs this close to the player could plausibly be caught by a swing, and
-- snapshotting the whole cache on every swing would be waste.
local SNAPSHOT_RANGE = 3

local snapshots = {}
local shielded = {}
local restoreFailed = false
local shieldFailed = false

--- Puts everyone back the way they were found. Called from three places on purpose: the
--- end of the attack, the start of the next swing, and a slow sweep. Any one of them is
--- enough; all three together mean no plausible failure leaves an immortal NPC behind.
local function unshieldAll()
    for _, zombie in pairs(shielded) do
        pcall(function() zombie:setInvincible(false) end)
    end
    shielded = {}
end

local function isProtected(zombie)
    if not zombie or not zombie:getVariableBoolean("Bandit") then return false end
    local brain = BanditBrain.Get(zombie)
    if not brain then return false end
    -- Somebody actively trying to kill you is not protected. The guard exists for
    -- accidents, not for pacifism.
    return not (brain.hostile or brain.hostileP)
end

--- Health before the swing lands, for everyone close enough to be caught by it.
---
--- OnWeaponSwingHitPoint fires at the moment the swing connects. Whether that is before
--- or after the engine applies damage is NOT verified -- vanilla only uses it for reload
--- bookkeeping (ISReloadWeaponAction.lua:542). If the snapshot turns out to be the
--- post-damage value the restore quietly becomes a no-op, which the log will show; moving
--- this to OnPlayerAttackFinished is then a one-line change.
local function snapshot(character)
    -- Clear first. If the previous attack never reported finishing, this is the line that
    -- stops the flag from sticking.
    unshieldAll()

    if not Guard.enabled then return end
    if not character or not instanceof(character, "IsoPlayer") then return end
    if not BanditZombie or not BanditZombie.GetAllB then return end

    snapshots = {}

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    local px, py = character:getX(), character:getY()
    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie and isProtected(zombie) then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            if dx * dx + dy * dy <= SNAPSHOT_RANGE * SNAPSHOT_RANGE then
                local zid = SR.IdOf(zombie)

                local hok, health = pcall(function() return zombie:getHealth() end)
                if hok and type(health) == "number" then
                    snapshots[zid] = health
                end

                -- The actual protection. Everything else in this file is the fallback for
                -- when this line turns out not to work on an IsoZombie.
                local sok = pcall(function() zombie:setInvincible(true) end)
                if sok then
                    shielded[zid] = zombie
                elseif not shieldFailed then
                    shieldFailed = true
                    SR.Log("GUARD setInvincible is not available on IsoZombie -- falling "
                        .. "back to restoring hit points after the fact")
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

    local id = SR.IdOf(zombie)
    local before = id and snapshots[id]

    if before then
        local ok = pcall(function() zombie:setHealth(before) end)
        if not ok and not restoreFailed then
            restoreFailed = true
            SR.Log("GUARD setHealth is not available on IsoZombie -- accidental hits still "
                .. "wound, but they no longer cost trust")
        end
    end

    local brain = BanditBrain.Get(zombie)
    SR.Log(string.format("GUARD absorbed a hit on %s -- no trust lost",
        tostring(brain and brain.fullname)))
    return true
end

--- Public: the sidebar button owns this now. No keybinding -- vanilla already claims
--- every letter except K, and burning a key on something you touch twice a session is
--- the wrong trade.
function Guard.Toggle()
    Guard.enabled = not Guard.enabled
    -- Turning it off must take effect on the swing already in flight, not the next one.
    if not Guard.enabled then unshieldAll() end
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

Events.OnWeaponSwingHitPoint.Add(snapshot)
Events.OnPlayerAttackFinished.Add(unshieldAll)

-- Last line of defence. If both of the above ever fail to fire, an NPC would otherwise
-- stay immortal for the rest of the session; this costs one empty loop a minute.
Events.EveryOneMinute.Add(unshieldAll)

Events.OnGameStart.Add(function()
    SR.Log("GUARD ready -- friendly fire blocked. Toggle from the left-hand button column")
end)
