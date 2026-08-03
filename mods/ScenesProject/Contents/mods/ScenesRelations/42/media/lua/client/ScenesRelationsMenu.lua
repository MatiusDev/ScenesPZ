-- ScenesPZ -- the player's side of the relationship: what you can ask an NPC to do.
--
-- WHY THIS EXISTS
-- Bandits already ships "Join Me!" (BanditMenu.lua:214), but it only appears on NPCs
-- running the Looter program, and the debug spawn menu hardcodes the Bandit program
-- (BanditMenu.lua:176) regardless of what the clan says. So on a debug-spawned NPC there
-- is no way to ask for anything at all, which left the trust number with nothing to gate.
--
-- This adds our own entry on any non-hostile bandit and puts trust in front of it. Their
-- menu still works untouched where it applies; ours simply also applies where theirs
-- does not.
--
-- WE DECIDE, THEY EXECUTE
-- The actual program switch is BanditMenu.SwitchProgram (BanditMenu.lua:145). It sets
-- brain.master, replaces brain.program, calls BanditBrain.Update and then syncs with
-- Bandit.ForceSyncPart. Reimplementing that would mean owning their multiplayer sync
-- forever, and ZPCompanion does nothing at all without brain.master
-- (ZPCompanion.lua:26). So we only choose whether the call happens.
--
-- Note that Bandits offers Join Me only on Looters. Nothing in SwitchProgram requires
-- it -- the program table is overwritten wholesale -- so a Bandit-program NPC can be
-- promoted the same way. That is what makes debug-spawned NPCs testable.

require "ScenesRelations"
require "BanditMenu"
require "BanditCompatibility"

local SR = ScenesRelations

-- The "friendly" tier boundary from SR.TIERS. Roughly thirteen swings of fighting
-- alongside someone at HELP_REWARD = 2, starting from a neutral stranger. Deliberately
-- not reachable by standing near them: it has to be earned by doing something.
local FOLLOW_MIN_TRUST = 25

--- An NPC is usually mid-step when you right-click it, so the square under the cursor is
--- often not the one it occupies. Same widening Bandits uses at BanditMenu.lua:188-200:
--- the clicked square first, then south, then west.
local function zombieUnderCursor()
    local square = BanditCompatibility.GetClickedSquare()
    if not square then return nil end

    local zombie = square:getZombie()
    if zombie then return zombie end

    local south = square:getS()
    if south then
        zombie = south:getZombie()
        if zombie then return zombie end
    end

    local west = square:getW()
    if west then
        zombie = west:getZombie()
        if zombie then return zombie end
    end

    return nil
end

--- Adds our submenu. Signature is fixed by Events.OnPreFillWorldObjectContextMenu.
local function fillMenu(playerID, context)
    local player = getSpecificPlayer(playerID)
    if not player then return end

    local zombie = zombieUnderCursor()
    if not zombie or not zombie:getVariableBoolean("Bandit") then return end

    local brain = BanditBrain.Get(zombie)
    if not brain then return end

    -- Someone actively trying to kill you does not take requests. Same gate Bandits puts
    -- on its own menu at BanditMenu.lua:210.
    if brain.hostile or brain.hostileP then return end

    local record = SR.Get(zombie)
    local trust = record and record.trust or 0

    -- The trust number is in the label on purpose. There is no hot reload here: reading
    -- it in game beats quitting, copying console.txt to the other machine and grepping.
    local root = context:addOption(string.format("%s  [%s %d]",
        tostring(brain.fullname), SR.Tier(zombie), trust))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)

    local program = brain.program and brain.program.name

    -- Dismissal is never gated. Trust decides who will follow you, not who is allowed to
    -- stop -- a companion you cannot release is a prisoner, not an ally.
    if program == "Companion" or program == "CompanionGuard" then
        menu:addOption("Leave me", player, BanditMenu.SwitchProgram, zombie, "Looter")
        return
    end

    if trust >= FOLLOW_MIN_TRUST then
        menu:addOption("Follow me", player, BanditMenu.SwitchProgram, zombie, "Companion")
    else
        -- Shown greyed rather than hidden. A missing option reads as a bug; a refused one
        -- reads as a person, and tells the player exactly what the relationship needs.
        local denied = menu:addOption(string.format("Follow me  (needs %d trust)",
            FOLLOW_MIN_TRUST))
        denied.notAvailable = true
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(fillMenu)
