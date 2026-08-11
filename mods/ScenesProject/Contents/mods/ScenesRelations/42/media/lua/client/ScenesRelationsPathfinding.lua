-- ScenesPZ -- preemptive routing: check the direct line before queueing a move.
--
-- WHY THIS EXISTS
-- The watchdog (ScenesRelationsAutonomy.lua:1361-1448) already routes an NPC to an opening
-- after it gets stuck -- that is REACTIVE routing and it works. What is missing is PREEMPTIVE
-- routing: before queueing a follow/loot/errand move, check if the direct line is blocked. If
-- it is, route through an opening instead of walking into the obstacle and waiting to get stuck.
--
-- A ROUTE task is a leg, not a purpose -- it walks the NPC to the square next to the door or
-- window, and Bandits' own bump handler does the actual crossing. This is principle 4 -- extend,
-- never replace. We add no crossing verb; the machinery to cross a fence (ClimbThroughWindowState)
-- and to open a window (its own OpenWindow task) already exists at
-- vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:677-686.
--
-- THE COST IS ONE LINE CLEARANCE CHECK PER FOLLOW ASSERTION. WhatBlocks (Move.lua:168) walks
-- the straight line in whole tiles. The check is bounded by the distance from the NPC to the
-- target, which for a follow is the separation from the master -- typically a few tens of tiles.
-- It runs inside the sweep (Events.EveryOneMinute, ~6s) or the fast lane (~800 ms per
-- BanditUpdate tick), and neither cadence is per-frame. If the direct line is clear, which is
-- the common case, nothing else happens -- just one LosUtil call.

require "ScenesRelations"

ScenesRelations = ScenesRelations or {}
local SR = ScenesRelations

SR.Pathfinding = SR.Pathfinding or {}
local Pathfinding = SR.Pathfinding

-- PREEMPTIVE VERSUS REACTIVE --------------------------------------------------------------
--
-- The watchdog (ScenesRelationsAutonomy.lua:1361-1448) fires AFTER the NPC has been walking
-- into the same obstacle for STUCK_SWEEPS (4 sweeps, ~24 seconds). It diagnoses the obstacle,
-- finds an opening, and routes there. It is the safety net and it stays exactly as it is.
--
-- This function fires BEFORE the first step. It asks "is the direct line blocked" rather than
-- "has the NPC been stuck for a while". If yes and the blocker is actionable (door, window,
-- fence), it picks the best opening and hands it back -- the caller queues a ROUTE move to that
-- opening, then the original move from there. Bandits' bump handler does the crossing.
--
-- The two modes are complementary:
--   Preemptive  catches the case the engine pathfinder would route the long way around.
--               The engine's cheapest valid path around a building is the whole perimeter,
--               and nothing tells it to prefer an opening -- so the opening must be chosen
--               before the engine is asked (Move.lua:336-339).
--   Reactive    catches every other case: the opening closed, the route shifted, the NPC
--               got stuck on furniture, or a move task was queued by code that did not call
--               ChooseRoute. The watchdog is the safety net and nothing in this file
--               replaces it.

--- Check whether the direct line from the NPC to `tx,ty,tz` is blocked by an actionable
--- obstacle, and if so find the best opening through the building shell.
---
--- Returns an opening table (same shape as Move.FindOpening, Move.lua:726-736), or nil when:
---   - The direct line is clear (walk normally)
---   - The line is blocked by a solid wall or locked door (cannot act on it; let the engine
---     pathfinder go around)
---   - No viable opening was found within the search radius
---   - The only opening is break tier (declined for preemptive routing -- smashing a window
---     is permanent and not for a companion trying to follow)
---
--- `opts` is optional: `{ exclude = { {x=,y=,z=}, ... } }`. `exclude` holds opening squares
--- the caller knows are unusable. If absent, falls back to `mood.triedOpenings` -- the list
--- the watchdog maintains of openings it already tried and which did not work
--- (ScenesRelationsAutonomy.lua:1376-1379). The fallback prevents the preemptive check from
--- re-picking the same door the watchdog already ruled out.
---
--- WHAT THE CALLER MUST DO WITH THE RESULT -- R13, restated for this caller.
--- An opening is a WHERE, not a HOW. The caller queues a plain Move task to `opening.x,
--- opening.y, opening.z`, and nothing else. The NPC walks there, and the NEXT step out of
--- that square walks into the door or window -- Bandits' own bump handler
--- (BanditUpdate.lua:677-686) does the crossing. The caller should NEVER queue a crossing
--- action off this result and should NEVER cache it across a walk. Ask again on arrival.
---
--- THE ORDERING BELONGS TO FINDOPENING AND IS NOT REPEATED HERE. FindOpening already checks:
---   - Same building? Stop early -- no shell to cross (Move.lua:621).
---   - Too far? Stop early for entering (Move.lua:648).
---   - One floor only (Move.lua:630).
---   - Door first, then window, break last -- the user's explicit tiers (Move.lua:352-375).
--- This function adds only the preemptive check: is the direct line actually blocked, and if
--- so, by something we can act on.
function Pathfinding.ChooseRoute(zombie, tx, ty, tz, opts)
    if not SR.Move or not SR.Move.WhatBlocks or not SR.Move.FindOpening then
        return nil
    end

    -- Step 1: what is in the way?
    -- Move.WhatBlocks (Move.lua:168) walks the straight line from the NPC to the target in
    -- whole tiles. Returns kind, x, y, z (the classification and the blocker's square), or
    -- nil when the line is clear, or BLOCK_SOLID with no coordinates when blocked by a wall.
    local okWhat, kind, bx, by, bz = pcall(SR.Move.WhatBlocks, zombie, tx, ty, tz)
    if not okWhat then return nil end

    -- Direct line is clear -- the common case, and the cheapest one.
    if kind == nil then return nil end

    -- Blockers we cannot act on. A solid (map wall, barricade, grass, furniture -- see
    -- Move.classify, Move.lua:130) and a locked door have no opening to route through from
    -- the outside. Let the engine pathfinder go around; it already knows how, and that is
    -- where the NPC would go anyway.
    if kind == SR.Move.BLOCK_SOLID or kind == SR.Move.BLOCK_LOCKED then
        return nil
    end

    -- THE 11-08 SESSION: FENCES ARE A WATCHDOG JOB, NOT A PREEMPTIVE ONE.
    --
    -- The preemptive fence routing (walk to fence square, hope the bump handler fires)
    -- produced 205 ROUTE lines vs 4 actual climb attempts — a 51:1 ratio of noise to
    -- signal. The engine pathfinder does NOT walk into a fence square; it routes around
    -- it. So the NPC never arrives at the fence, the bump handler never fires, and the
    -- ROUTE becomes a walk-then-retry loop.
    --
    -- Meanwhile the watchdog (reactive) DID fire changeState(ClimbOverFence) 4 times
    -- in the same session. The watchdog already has the climb logic, already fires
    -- correctly, and already handles the obstacleAttempts cooldown. The preemptive
    -- check was duplicating the watchdog's job with worse results.
    --
    -- So BLOCK_HOP and BLOCK_TALL are treated like BLOCK_SOLID here: let the engine
    -- pathfinder decide, and let the watchdog catch the stall. This removes the routing
    -- loop without changing climb behavior.
    if kind == SR.Move.BLOCK_HOP or kind == SR.Move.BLOCK_TALL then
        return nil
    end

    -- Building openings: delegate to FindOpening.

    -- Step 2: which opening to head for?
    -- Build the exclude list. opts.exclude takes precedence; if absent, fall back to
    -- mood.triedOpenings (the watchdog's list of openings that already failed --
    -- Autonomy.lua:1376-1379). The fallback prevents the preemptive check from re-picking
    -- a door the watchdog already tried and rejected while the NPC was stuck.
    local exclude = nil
    if opts and opts.exclude then
        exclude = opts.exclude
    else
        local mood = SR.Mood(zombie)
        if mood then
            exclude = mood.triedOpenings
        end
    end

    local okOpen, opening = pcall(SR.Move.FindOpening, zombie, tx, ty, tz,
        { exclude = exclude })
    if not okOpen then
        SR.Log(string.format("ROUTE %s | FindOpening threw -- %s",
            SR.KeyOf(zombie), tostring(opening)))
        return nil
    end

    if not opening then return nil end

    -- Break tier is declined for preemptive routing. Smashing a window is loud, permanent
    -- and never what a companion trying to follow should do on its own. The caller can still
    -- walk normally; the watchdog (which fires after a confirmed stall) already declines
    -- break on its own (Autonomy.lua:1384), and it is declined here for the same reason.
    if opening.kind == SR.Move.OPEN_BREAK then
        SR.Log(string.format("ROUTE %s | the only way to %d,%d,%d is %s (%s) -- declined",
            SR.KeyOf(zombie), math.floor(tx), math.floor(ty), tostring(opening.kind),
            tostring(opening.why)))
        return nil
    end

    SR.Log(string.format("ROUTE %s | blocked by %s at %d,%d,%d -- routing to the %s at %d,%d (%s) | stand %d,%d,%d",
        SR.KeyOf(zombie), tostring(kind), bx or 0, by or 0, bz or 0,
        tostring(opening.kind),
        opening.ox or opening.x, opening.oy or opening.y, tostring(opening.why),
        opening.x, opening.y, opening.z))

    return opening
end

Events.OnGameStart.Add(function()
    SR.Log("PATHFINDING ready -- preemptive route check before move")
end)
