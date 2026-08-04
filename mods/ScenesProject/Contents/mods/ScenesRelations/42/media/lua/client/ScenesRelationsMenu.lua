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

-- SUPERSEDED BY THE WHEEL, KEPT FOR ONE BUILD
-- ScenesRelationsWheel.lua is the real interface now: hold a key near somebody instead of
-- clicking a moving target through a list of unrelated entries. This file survives as a
-- fallback for exactly one test cycle, because there is no hot reload here and a wheel
-- that fails to open would otherwise leave no way to recruit anyone at all. Delete it once
-- the wheel is confirmed working.
--
-- It no longer decides anything. Both surfaces render SR.Actions.List, so they cannot
-- disagree about who agrees to what.

require "ScenesRelations"
require "ScenesRelationsActions"
require "BanditCompatibility"

local SR = ScenesRelations

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
--- Pure rendering now: every decision comes from SR.Actions.List.
local function fillMenu(playerID, context)
    local player = getSpecificPlayer(playerID)
    if not player then return end

    local zombie = zombieUnderCursor()
    if not zombie then return end

    local list, brain, trust, tier = SR.Actions.List(player, zombie)
    if not list then return end

    -- The trust number is in the label on purpose. There is no hot reload here: reading
    -- it in game beats quitting, copying console.txt to the other machine and grepping.
    local root = context:addOption("[wheel] " .. SR.Actions.Header(brain, trust, tier))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)

    for _, action in ipairs(list) do
        if action.available then
            menu:addOption(action.label, player, action.run, zombie)
        else
            -- Shown greyed rather than hidden. A missing option reads as a bug; a refused
            -- one reads as a person, and tells the player exactly what is still missing.
            local denied = menu:addOption(string.format("%s  (%s)",
                action.label, tostring(action.reason)))
            denied.notAvailable = true
        end
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(fillMenu)
