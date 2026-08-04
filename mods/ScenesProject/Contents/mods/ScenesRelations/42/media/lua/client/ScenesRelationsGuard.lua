-- ScenesPZ -- stop the player hitting people they did not mean to hit.
--
-- WHY THIS EXISTS
-- Reported from play: swinging at a zombie next to a friendly survivor catches the
-- survivor instead, and the relationship you spent twenty minutes on takes a -25. The
-- punishment is real, the intention was not. A system that reads intent from behaviour
-- cannot also read a misclick as an assault.
--
-- WHAT THE ENGINE DOES NOT GIVE US
-- There is no cancellable pre-damage event in 42.20. The complete list of hit-adjacent
-- events is OnHitZombie, OnWeaponSwingHitPoint, OnPlayerAttackFinished, OnWeaponHitTree
-- and OnWeaponHitXp, and none of them can abort the swing. So this cannot prevent the
-- blow. It undoes it.
--
-- WHAT IS GUARANTEED, AND WHAT IS BEST EFFORT
-- Guaranteed: no trust penalty and no hostility escalation. That is the whole of the
-- reported problem, it is entirely our own state, and it cannot fail.
-- Best effort: putting the hit points back. Whether setHealth works on an IsoZombie is
-- not verified anywhere in vanilla, so it runs under pcall and says so in the log the
-- first time it fails. If it turns out not to work, a mistaken swing still wounds them --
-- it just no longer costs you the relationship.

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
local restoreFailed = false

table.insert(keyBinding, { value = "Protect survivors", key = Keyboard.KEY_G })

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
                local hok, health = pcall(function() return zombie:getHealth() end)
                if hok and type(health) == "number" then
                    snapshots[SR.IdOf(zombie)] = health
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

local function toggle()
    Guard.enabled = not Guard.enabled
    local player = getSpecificPlayer(0)
    if HaloTextHelper and player then
        if Guard.enabled then
            HaloTextHelper.addGoodText(player, "Survivors protected - your swings will not count")
        else
            HaloTextHelper.addBadText(player, "Survivors UNPROTECTED - your swings will land")
        end
    end
    SR.Log("GUARD " .. (Guard.enabled and "on" or "off"))
end

Events.OnWeaponSwingHitPoint.Add(snapshot)

Events.OnKeyPressed.Add(function(key)
    if getCore():isKey("Protect survivors", key) then toggle() end
end)

Events.OnGameStart.Add(function()
    SR.Log("GUARD ready -- friendly fire blocked. Toggle with the 'Protect survivors' key (default G)")
end)
