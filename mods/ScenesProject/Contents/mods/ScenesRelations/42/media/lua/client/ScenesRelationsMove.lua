-- ScenesPZ -- one function for "walk there, then do it," because four places wrote that
-- decision separately and the same bug shipped in two of them.
--
-- WHY THIS EXISTS
-- A Bandits move task guarantees it ENDED, never that it ARRIVED. A blocked path, a door, a
-- shove from a zombie, or the autonomy ladder clearing the queue (ScenesRelationsAutonomy.lua)
-- all end a move early. Queue the move and the action that depends on it in the SAME task
-- list, and the action fires with stale coordinates the moment the move is cut short. This is
-- R13 in docs/CODE-REVIEW-RULES.md.
--
-- It already shipped here twice. The original Loot.Search queued the move and the search
-- together -- the fix, and the exact symptom it produced ("lotea desde el mismo punto"), are
-- documented at length right above Loot.Search in ScenesRelationsLoot.lua. ScenesRelationsIdle
-- .lua's goGet() had the same shape: it queued a move AND an unconditional PickUp, and
-- `ZombieActions.PickUp.onComplete` (vendor/Bandits/mods/Bandits/42.20/media/lua/shared/ZombieActions/ZAPickUp.lua:14) has no
-- distance check of its own -- it reads the item off `task.x, task.y, task.z` regardless of
-- where the zombie actually ended up, so a move cut short let it grab the item from wherever
-- it lies, silently, from however far the walk got interrupted.
--
-- Upstream solved this once. `BWOAPrograms.GoAndDo`
-- (vendor/TheArk/mods/BanditsWeekOneTheArk/42.20/media/lua/shared/BWOAPrograms.lua:99) is
-- called 35 times across 27 of The Ark's actions and none of them has this bug, because the
-- function never returns both tasks: it measures distance FRESH every time the calling
-- program re-runs -- which only happens on an empty queue -- and hands back either the walk
-- or the action, never both. This file is that function, ported so every ScenesPZ caller
-- shares it instead of re-deriving it (and re-deriving its bug) on its own.
--
-- THE RULE THIS LEAVES BEHIND, AND IT IS BIGGER THAN ANY ONE CALLER
-- A task cannot check its own preconditions, so anything a task depends on must be true when
-- it is QUEUED, not when it was planned. Walk, re-decide, arrive, act -- never walk-and-act in
-- the same breath.

require "ScenesRelations"

ScenesRelations = ScenesRelations or {}
local SR = ScenesRelations

SR.Move = SR.Move or {}
local Move = SR.Move

--- Walk to `point` and then run `task` on arrival -- or just walk. Never both in the same
--- returned list; see the header above for why that distinction is the entire point.
---
--- `point` is `{x=, y=, z=}`. `task` is the action table to queue once the NPC is standing
--- close enough to it -- it is returned untouched, never inspected, so it can be any Bandits
--- task shape. `opts` is optional: `{ precision = 0.7, checkCollision = true, run = false }`.
---
--- Mirrors `BWOAPrograms.GoAndDo` step for step:
---   1. Resolve the square at `point`. Nothing there -> give up (see the failure note below).
---   2. Resolve the STANDING square: the target square itself when
---      `square:isNotBlocked(false)` (Foraging/forageSystem.lua:1695 is the vanilla file this
---      method was confirmed against), otherwise `BanditUtils.GetAccessSquare(square, zombie)`
---      (Bandits/42.20/.../BanditUtils.lua:1056) -- it takes the NPC and returns the closest
---      free neighbour by `square:DistToProper(bandit)` (:1081), rejecting any square with a
---      wall between (`gridSquare:isWallTo(testSquare)`, :1071).
---      The version folder is part of the citation on purpose: vendor/Bandits ships 42.12
---      through 42.20 side by side, the game loads only the one matching its build, and the
---      same function sits 17 lines earlier in 42.18. A bare line number is ambiguous here.
---   3. Collision: `LosUtil.lineClearCollide(...)` returns TRUE when the straight line to the
---      standing square is blocked. Close in a straight line is not the same as close -- an
---      NPC on the far side of a partition can be within `precision` of a spot it cannot
---      touch, and would otherwise act through the wall.
---   4. Distance beyond `precision`, OR blocked: queue the walk. Otherwise: queue `task`.
---
--- Returns `tasks, arrived`.
---   - `{ moveTask }, false` -- still walking.
---   - `{ task }, true`      -- arrived; `task` is exactly what was passed in.
---   - `{}, false`           -- the square could not be resolved at all (bad coordinates, or
---     no free neighbour). This is the one case `BWOAPrograms.GoAndDo` itself does not name
---     with a second value; an empty table with `arrived = false` is the honest reading of it,
---     and every caller here already treats an empty `tasks` as "nothing to queue this sweep."
---
--- Callers pass `tasks` straight to `Bandit.AddTask`, or return it upward the way
--- `Loot.Search` and `Loot.FetchBag` already do -- both patterns exist in this mod today and
--- neither needs to change to use this.
-- WHERE THE PLAYER ACTUALLY WENT ---------------------------------------------------------
--
-- REPORTED, and it is the observation that produced this whole approach: "yo trepé un muro alto
-- para pasar al otro lado, el NPC de una tomó la opción de rodearlo... debería ver por cuál
-- camino fue el jugador."
--
-- WHY THIS IS CHEAP AND COMPARING ROUTES IS NOT. The obvious way to decide between climbing and
-- walking around is to compute both routes and take the shorter. That is not affordable:
-- `pathToLocation` is not a query, it COMMITS the character
-- (pzserver/media/lua/client/TimedActions/WalkToTimedAction.lua:42), and resolution takes several
-- ticks of `update()` returning Working. Evaluating two candidates means visibly starting and
-- stopping the NPC once per candidate -- which is the "se queda quieto, no sabe qué hacer"
-- symptom this project has spent a week removing, reintroduced deliberately.
--
-- The player's route needs none of that. It ALREADY HAPPENED. Somebody walked it, the engine
-- already solved it, and it is known to be passable because a body went through it. Remembering
-- it costs one table.
--
-- WHAT THIS DOES NOT DO. It does not prove the trail is SHORTER than going around -- that
-- comparison still needs a real pathfind. It uses a cheaper rule instead: prefer the trail when
-- the straight line to the player is blocked. That is a heuristic, and it is written down as one.
--
-- 44% OF JAMS ARE NOT ON THE STRAIGHT LINE. From the 10-08 log, the watchdog's own numbers:
-- 12 `solid`, 11 `clear`, 1 `locked`, 1 `hop`. `clear` means the NPC was stuck for two sweeps
-- without moving while the straight line to its target was open -- so whatever stopped it was
-- never on that line, and `WhatBlocks` cannot see it by construction. A trail of squares the
-- player really walked is the one thing that routes around an obstacle nobody can name.

-- Tiles between crumbs. Too fine and the trail is a memory of jitter; too coarse and it cuts the
-- corner the player took deliberately -- which is the whole point when that corner was a wall.
local CRUMB_SPACING = 2.0

-- How much trail to keep. Twelve crumbs at two tiles is roughly a street: far enough to cover
-- being left behind, short enough that following it never looks like archaeology.
local CRUMB_MAX = 12

-- How many of the newest crumbs `TrailTarget` will test. Each test walks a line of squares and
-- the caller runs every 800 ms, so this is the knob that keeps the trail cheap.
local TRAIL_SCAN = 4

local trail = {}

--- Remember where the player is, if they have moved far enough to be worth a crumb.
---
--- Called from the fast tick, which already runs and already holds the player. Cheap on purpose:
--- one distance test, and an append that happens only every couple of tiles.
function Move.DropCrumb(player)
    if not player then return end
    local x, y, z = player:getX(), player:getY(), player:getZ()

    local last = trail[#trail]
    if last then
        local dx, dy = x - last.x, y - last.y
        local movedFar = (dx * dx + dy * dy) >= (CRUMB_SPACING * CRUMB_SPACING)
        -- A floor change always earns a crumb whatever the horizontal distance. Stairs are
        -- exactly the case where two points are close in x and y and not reachable from each
        -- other, and a trail that skips them would aim an NPC at the ceiling.
        local changedFloor = math.floor(z) ~= math.floor(last.z)
        if not movedFar and not changedFloor then return end
    end

    trail[#trail + 1] = { x = x, y = y, z = z }
    while #trail > CRUMB_MAX do table.remove(trail, 1) end
end

--- The best crumb for this NPC to head for, or nil to just go straight at the player.
---
--- Returns the NEWEST crumb the NPC can see in a straight line -- newest because it is the
--- furthest along the player's route, and straight-line-visible because there is no point aiming
--- at a waypoint we already know is walled off. Walking to it puts the NPC where the player
--- stood, and from there the next leg is the one the player themselves walked.
---
--- nil when the trail is empty, or when no crumb is reachable, or when the NPC is already at the
--- newest one -- in all three cases the caller should do what it did before.
function Move.TrailTarget(zombie)
    if #trail == 0 then return nil end

    local zx, zy = zombie:getX(), zombie:getY()

    -- Only the freshest few. Each candidate costs a `WhatBlocks`, which walks a line of squares,
    -- and this runs from the 800 ms tick -- twelve candidates per companion is a real per-second
    -- cost for crumbs that are increasingly stale anyway. The newest reachable one is what we
    -- want; if none of the last four is reachable, the trail is not the answer to this jam.
    local oldest = math.max(1, #trail - TRAIL_SCAN + 1)

    for i = #trail, oldest, -1 do
        local crumb = trail[i]
        local dx, dy = crumb.x - zx, crumb.y - zy
        -- Already standing on it: this crumb and every older one are behind us.
        if (dx * dx + dy * dy) > (CRUMB_SPACING * CRUMB_SPACING) then
            if Move.WhatBlocks(zombie, crumb.x, crumb.y, crumb.z) == nil then
                return crumb.x, crumb.y, crumb.z, i
            end
        end
    end

    return nil
end

--- How many crumbs are held. Diagnostics only.
function Move.TrailSize()
    return #trail
end

--- Forget the route.
---
--- Nothing did this, and a trail is not the kind of state that ages gracefully. It survives a
--- save and a reload, so a companion could be sent to a square remembered from a previous
--- session, in a building that may since have burned down. It also survives the player dying and
--- a new character starting somewhere else entirely, which would aim every companion at a corpse
--- across the map.
function Move.ForgetTrail()
    trail = {}
end

Events.OnGameStart.Add(Move.ForgetTrail)

-- WHAT IS IN THE WAY ---------------------------------------------------------------------
--
-- REPORTED, and the reason this exists: "los NPC se siguen trabando mucho entre los objetos...
-- se quedan caminando contra una pared, una ventana, una valla."
--
-- WHY BANDITS DOES NOT ALREADY FIX IT. `ManageCollisions`
-- (vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:520) is a REACTIVE bump
-- handler and it has three holes, each of which we watched happen in play:
--
--   1. it returns immediately unless the active task is `Move` or `GoTo` (:533), so a collision
--      during anything else is seen by nobody;
--   2. it scans `square:getObjects()` for a fence, window or door -- and a plain map WALL is not
--      an IsoObject at all, it is a square-level collision flag. The loop finds nothing and
--      returns silently, every tick, forever;
--   3. it holds no state. Nothing counts collisions, nothing escalates, nothing gives up.
--
-- Meanwhile `ZAMove.onWorking` keeps returning "not done" while collided, so the walk animation
-- plays into the wall indefinitely. That is the whole of the reported symptom.
--
-- It is also `local`, so it cannot be extended -- only replicated. And the behaviour it is
-- replicating is native: vanilla zombies cross fences and doors from the engine, with no Lua
-- surface at all beyond a sandbox probability. Bandits rebuilt it object type by object type,
-- and the wall never got a branch because natively it never needed one.
--
-- SO WE ASK BEFORE WALKING INSTEAD OF AFTER BUMPING. `LosUtil.lineClearCollide` is a pure query
-- -- unlike `pathToLocation`, which COMMITS the character (WalkToTimedAction.lua:42) and is why
-- comparing two candidate routes would make an NPC visibly start and stop once per candidate.
--
-- THE HONEST LIMIT: no engine call answers "what is blocking this line". LosUtil returns a
-- boolean. So this walks the line itself and classifies what it finds -- the same classification
-- Bandits does, moved to a place that runs before the first step rather than after the collision.
--
-- Every predicate below has vanilla Lua callsites, which is the bar R1 sets:
--   instanceof(obj, "IsoDoor")   server/BuildRecipeCode/buildRecipeCode.lua:110
--   door:IsOpen()                server/BuildRecipeCode/buildRecipeCode.lua:27
--                                  (both corrected: the lines first cited here were
--                                   ISWorldObjectContextMenu.lua:2176 and :2203, and neither
--                                   showed what it claimed -- :2176 tests IsoThumpable, and
--                                   :2203 is reached with windows and curtains as well as
--                                   doors. The claims were true; the audit trail was not, and
--                                   a citation nobody can follow is R1 theatre.)
--   door:isLocked()              client/DebugUIs/AdminContextMenu.lua:80
--   door:isBarricaded()          shared/Moveables/ISMoveableSpriteProps.lua:907
--   obj:isHoppable()             shared/Moveables/ISMoveablesAction.lua:12
--   obj:isTallHoppable()         client/TimedActions/ISClimbOverFence.lua:69

Move.BLOCK_DOOR   = "door"      -- shut, unlocked: openable
Move.BLOCK_LOCKED = "locked"    -- shut and locked: this way is closed
Move.BLOCK_HOP    = "hop"       -- a low fence: climbable
Move.BLOCK_TALL   = "tall"      -- a tall fence: climbable, slower
Move.BLOCK_SOLID  = "solid"     -- something we cannot act on, including a plain wall
-- NOT an obstacle: "we did not look". Kept distinct from nil, and that distinction is
-- load-bearing -- a caller that treats "clear" and "unknown" the same will do the wrong thing
-- on stairs, which is exactly where it matters most.
Move.BLOCK_UNKNOWN = "unknown"

--- Classify one object. Returns a Move.BLOCK_* constant, or nil if it is not an obstacle.
local function classify(obj)
    local ok, kind = pcall(function()
        local isDoor = instanceof(obj, "IsoDoor")
            or (instanceof(obj, "IsoThumpable") and obj:isDoor() == true)

        if isDoor then
            if obj:IsOpen() then return nil end          -- already open, not in the way
            if obj:isBarricaded() then return Move.BLOCK_SOLID end
            if obj:isLocked() then return Move.BLOCK_LOCKED end
            return Move.BLOCK_DOOR
        end

        if obj:isTallHoppable() then return Move.BLOCK_TALL end
        if obj:isHoppable() then return Move.BLOCK_HOP end
        return nil
    end)
    return ok and kind or nil
end

--- The first thing standing between two points, and where it is.
---
--- Returns kind, x, y, z -- or nil when the line is clear, and Move.BLOCK_SOLID with no
--- coordinates when the line is blocked by something that is not an object we can act on. That
--- second case IS the wall, and reporting it as "solid" rather than as "clear" is the whole
--- difference from what happens today.
---
--- Walks the line in whole tiles. Bounded by the distance it was asked about, so a long journey
--- costs proportionally more -- callers pass targets that are already within a search radius.
function Move.WhatBlocks(zombie, tx, ty, tz)
    local cell = getCell()
    if not cell then return nil end

    local bx, by, bz = zombie:getX(), zombie:getY(), zombie:getZ()

    -- A DIFFERENT FLOOR IS NOT A WALL, AND IT IS NOT A CLEAR LINE EITHER. This first answered
    -- BLOCK_SOLID, which reads as "nothing can be done here"; the second version answered nil,
    -- which reads as "the way is clear" -- and that one is worse, because callers act on it.
    --
    -- Concretely, it defeated a rule three lines of this file exist to serve: `DropCrumb` always
    -- drops a crumb on a floor change, precisely so a companion can follow somebody upstairs.
    -- With nil here, `assertFollow` reads the line to a master one floor up as CLEAR, never asks
    -- for the trail, and walks at a point through the ceiling. The stair crumb could never be
    -- reached by the only thing that wanted it.
    if math.floor(bz) ~= math.floor(tz) then return Move.BLOCK_UNKNOWN end

    local okClear, blocked = pcall(function()
        return LosUtil.lineClearCollide(
            math.floor(bx), math.floor(by), math.floor(bz),
            math.floor(tx), math.floor(ty), math.floor(tz), false)
    end)
    -- A throw is treated as CLEAR, matching the rest of this file: falling back to walking is
    -- always safe, and inventing an obstacle would stop journeys that were fine.
    if not okClear or not blocked then return nil end

    local z = math.floor(bz)

    --- Everything on one square, first classifiable object wins.
    ---
    --- KNOWN LIMIT, written down rather than hidden: this does not ask whether the object faces
    --- the direction of travel. Doors and fences are north/west EDGE objects, so a square can
    --- carry a fence that runs across a completely different boundary. Bandits gates its own
    --- equivalent on `bandit:isFacingObject(object, 0.5)`
    --- (vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:573).
    ---
    --- Left out deliberately for now: nothing ACTS on this classification yet, so the cost of
    --- being wrong is one mislabelled log line rather than an NPC climbing a fence that was
    --- never in its way. It has to be added before anything acts, and that is the first thing
    --- the next pass does.
    local function scan(x, y)
        local square = cell:getGridSquare(x, y, z)
        if not square then return nil end
        local objects = square:getObjects()
        for j = 0, objects:size() - 1 do
            local kind = classify(objects:get(j))
            if kind then return kind end
        end
        return nil
    end

    -- BOTH ENDPOINTS ARE SCANNED, and they are the two most likely squares to hold the blocker.
    --
    -- The first version started at step 1 and stopped at `floor(steps)`, so it scanned NEITHER.
    -- The NPC's own square was skipped -- and Bandits checks that one FIRST (BanditUpdate.lua:544)
    -- precisely because a fence or door is an edge object belonging to the tile you are standing
    -- on. The target square was cut off by the truncation. For a two-tile move it sampled exactly
    -- one square, and it was neither the one the NPC was on nor the one it was going to.
    --
    -- Worse, a separate `steps < 1` guard returned BLOCK_SOLID before any of this ran -- and that
    -- branch is reachable ONLY when the two tiles are adjacent, which is to say only in the door,
    -- window and fence case. The single most important input answered "an impassable wall".
    local sx, sy = math.floor(bx), math.floor(by)
    local ex, ey = math.floor(tx), math.floor(ty)

    local kind = scan(sx, sy)
    if kind then return kind, sx, sy, z end

    local dx, dy = ex - sx, ey - sy
    local steps = math.max(math.abs(dx), math.abs(dy))

    if steps >= 1 then
        for i = 1, steps do
            local x = sx + math.floor(dx * i / steps + 0.5)
            local y = sy + math.floor(dy * i / steps + 0.5)
            kind = scan(x, y)
            if kind then return kind, x, y, z end
        end
    elseif ex ~= sx or ey ~= sy then
        kind = scan(ex, ey)
        if kind then return kind, ex, ey, z end
    end

    -- The line is blocked and nothing on it is an object we can act on. A map wall.
    return Move.BLOCK_SOLID
end

function Move.GoAndDo(zombie, point, task, opts)
    opts = opts or {}

    local precision = opts.precision
    if precision == nil then precision = 0.7 end

    local checkCollision = opts.checkCollision
    if checkCollision == nil then checkCollision = true end

    local run = opts.run or false

    local tasks = {}

    local okSquare, square = pcall(function()
        return getCell():getGridSquare(point.x, point.y, point.z)
    end)
    if not okSquare or not square then return tasks, false end

    local okStand, standSquare = pcall(function()
        if square:isNotBlocked(false) then return square end
        return BanditUtils.GetAccessSquare(square, zombie)
    end)
    if not okStand or not standSquare then return tasks, false end

    local bx, by, bz = zombie:getX(), zombie:getY(), zombie:getZ()
    local ax, ay, az = standSquare:getX(), standSquare:getY(), standSquare:getZ()

    local collide = false
    if checkCollision then
        local okCollide, blocked = pcall(function()
            return LosUtil.lineClearCollide(
                math.floor(bx), math.floor(by), math.floor(bz),
                math.floor(ax), math.floor(ay), math.floor(az),
                false)
        end)
        -- A throw here is treated as "not blocked" rather than "act anyway" -- see the note
        -- on `run` above the return: falling back to WALKING is always safe, falling back to
        -- ACTING on a failed check is exactly the bug this file exists to remove.
        collide = okCollide and blocked or false
    end

    local dist = BanditUtils.DistTo(bx, by, ax + 0.5, ay + 0.5)

    if dist > precision or collide then
        local walkType = run and "Run" or "Walk"
        -- The walk inherits the goal of the action it is a walk TOWARDS. A caller stamps
        -- the action it wants performed; the journey to it belongs to the same objective, and
        -- tagging only one of the two would leave half a plan unattributed in the queue.
        tasks[1] = SR.Own(task and task.srGoal,
            BanditUtils.GetMoveTask(0, ax, ay, az, walkType, dist, false))
        return tasks, false
    end

    tasks[1] = task
    return tasks, true
end

Events.OnGameStart.Add(function()
    SR.Log("MOVE ready -- one walk-then-act primitive, GoAndDo, shared across the mod")
end)
