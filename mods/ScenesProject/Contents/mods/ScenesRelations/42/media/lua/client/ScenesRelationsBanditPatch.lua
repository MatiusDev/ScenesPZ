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
