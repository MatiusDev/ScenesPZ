-- ScenesPZ -- compatibility patch for a live defect in Bandits 42.20.
--
-- This is the only file in the mod that replaces upstream behaviour instead of extending
-- it. It exists for a specific, verified crash and should be deleted the day Slayer fixes
-- it. Keep it separate so that deleting it is one command.
--
-- THE DEFECT
-- BanditPlayer.CheckFriendlyFire (BanditPlayer.lua:91) reads:
--
--     if not instanceof(attacker, "IsoPlayer") or attacker:isNPC() then return end
--
-- isNPC() does not exist in Build 42.20 -- zero occurrences across the 2,680 Lua files in
-- pzserver/media/lua/. Lua short-circuits `or`, so the call only happens when the attacker
-- IS a real player: exactly when the function matters. It throws every time.
--
-- WHAT THAT ACTUALLY COSTS -- two separate things, and only one of them is about us
--
-- 1. The error propagates out of BanditUpdate.lua:2197, so EVERYTHING after that line in
--    their OnHitZombie never runs. That tail is the ranged locational damage system:
--    headshots killing instantly, neck/groin/torso doing extra damage, clothing defence
--    being rolled (BanditUpdate.lua:2199-2245). Shooting an NPC with a firearm has been
--    silently missing its entire damage model. This has nothing to do with our mod and is
--    the real reason to patch.
--
-- 2. CheckFriendlyFire's own body turns every friendly witness within 12 tiles instantly
--    hostile and switches them to the Bandit program (BanditPlayer.lua:104-107).
--
-- WHY WE DO NOT RESTORE THE SECOND PART
-- That instant flip is precisely the binary this mod exists to replace: one hit and a
-- person becomes a killer, with nothing in between. ScenesRelations already owns that
-- decision and reaches it through trust, over several witnessed attacks. Restoring their
-- version would not add a feature, it would overrule ours on the first swing and make the
-- whole gradient decorative.
--
-- So this is deliberately not a faithful repair. It is a repair of the crash and a
-- takeover of the responsibility. Under SR.DEBUG it logs every escalation it declined, so
-- the log shows exactly where Bandits would have flipped someone and our gradient did not.

require "ScenesRelations"
require "BanditPlayer"

local SR = ScenesRelations

BanditPlayer.CheckFriendlyFire = function(bandit, attacker)
    local brain = BanditBrain.Get(bandit)
    if not brain then return end

    -- Their guards, kept verbatim in meaning. Attacking someone already hostile is fair.
    if brain.hostile or brain.hostileP then return end

    -- The corrected line. instanceof alone is sufficient: every Bandits NPC is an
    -- IsoZombie flagged "Bandit", so it can never satisfy this test.
    if not instanceof(attacker, "IsoPlayer") then return end

    -- Where their escalation loop was. Intentionally absent -- see the header.
    if SR.DEBUG then
        SR.Log(string.format("PATCH declined Bandits escalation on %s (trust decides)",
            tostring(brain.fullname)))
    end
end

-- Announced at load so a log can prove the patch is present. A silent patch is
-- indistinguishable from a patch that never loaded.
SR.Log("PATCH BanditPlayer.CheckFriendlyFire replaced -- upstream isNPC() crash, 42.20")

-- TURNING IS SWITCHED OFF, ON PURPOSE AND TEMPORARILY ---------------------------------
--
-- ASKED FOR: "como un zombie muerde a un NPC de una comienza a convertirse y realmente se
-- convierte muy rapido, el sistema para jugadores es diferente... Como el sistema de dano a
-- NPC no esta terminado, no hagamos que los NPC se conviertan a zombie de momento."
--
-- The diagnosis is right and the numbers say why. Bandits has no incubation at all: a bite
-- writes brain.infection, ManageHealth then adds 0.001 per tick unconditionally, and at 100
-- it queues Zombify (BanditUpdate.lua:504-514). There is no sickness, no fever, no
-- deterioration -- just a counter and then a corpse that gets up. The player's model is a
-- multi-day illness. Ours is a stopwatch.
--
-- It also caused the second half of the reported bug. Zombify.onComplete calls BanditRemove
-- (ZAZombify.lua:16-24), which unmakes the NPC -- but the caches and our own sweeps can lag
-- a frame behind that, so a survivor who had already turned kept being issued orders to come
-- back to the player. Two bugs, one root.
--
-- One flag turns the whole block off, which is the cheapest possible intervention and the
-- easiest to undo: delete this file section when the wound model in
-- docs/plans/wounds-and-healing.md reaches stage 2 and can express getting sick.
Events.OnGameStart.Add(function()
    if not SandboxVars or not SandboxVars.Bandits then
        SR.Log("PATCH could not reach SandboxVars.Bandits -- turning is still on")
        return
    end

    if SandboxVars.Bandits.General_Infection then
        SandboxVars.Bandits.General_Infection = false
        SR.Log("PATCH NPC turning disabled -- their infection model is a stopwatch, not an illness")
    end
end)

--- Whether this entity is still one of ours to command.
---
--- Cheap and worth calling before issuing any order. GetAllB and the light caches can hold
--- an entry for a frame or two after BanditRemove has unmade somebody, and giving marching
--- orders to a thing that is now just a zombie is how the log filled with follow requests
--- for a survivor who had already turned.
function SR.IsStillOurs(zombie)
    if not zombie then return false end
    local ok, flagged = pcall(function() return zombie:getVariableBoolean("Bandit") end)
    if not ok or not flagged then return false end
    return BanditBrain.Get(zombie) ~= nil
end
