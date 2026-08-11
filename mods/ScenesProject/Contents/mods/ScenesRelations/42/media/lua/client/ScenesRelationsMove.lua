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

    -- A DIFFERENT FLOOR IS NOT A WALL. This used to answer BLOCK_SOLID, which reads as "nothing
    -- can be done here" and poisons the telemetry this exists to collect -- `getZ()` is a float
    -- that dips mid-staircase, so an NPC on a stair could report a wall where there were stairs.
    -- Unknown is the honest answer: we did not look.
    if math.floor(bz) ~= math.floor(tz) then return nil end

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

-- WHICH OPENING TO HEAD FOR --------------------------------------------------------------
--
-- REPORTED, twice, in these words:
--   "el NPC se atasca demasiado para salir de una casa y seguirme, sigue sin poder saltar
--    muros y vallas"
--   "Los NPC que logran llegar hasta mi, rodean todo los edificios, misma razon por la cual
--    le cuesta salir de los edificios rapido."
--
-- WHAT THE TELEMETRY SAID, AND WHY IT REDIRECTED THE FIX. Two sessions of `blocked by` counts
-- came back 10 solid, 6 clear, 2 locked, 2 hop, 0 door. Sixteen of twenty jams are things no
-- fence-climb and no door-toggle can touch, and the round that added ClimbFence/ToggleDoor to
-- the watchdog proved it: ClimbFence fired ONCE in a full session and ToggleDoor never.
-- `clear` is the loudest number on that list -- it means Move.WhatBlocks walked the straight
-- line, found nothing, and the NPC was stuck anyway. WhatBlocks is blind to that case BY
-- CONSTRUCTION: the obstacle was not on the straight line, because the NPC was never going to
-- travel in a straight line. It was going around a building.
--
-- THE THING WE ALREADY HAD AND WERE NOT USING. Bandits knows how to cross a window. Its
-- collision handler, on bumping one:
--   vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:683-686
--     elseif object:canClimbThrough(bandit) then
--         ClimbThroughWindowState.instance():setParams(bandit, object)
--         bandit:changeState(ClimbThroughWindowState.instance())
-- and for a SHUT window, four lines above, it queues its own open:
--   vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:677-680
--     elseif not object:isPermaLocked() and not BanditBrain.HasTaskType(brain, "OpenWindow")
--         local task = {action="OpenWindow", anim="WindowOpen", time=25, ...}
--
-- So the crossing machinery exists, works, and is upstream's to maintain. What was missing is
-- that NOTHING EVER ROUTED THE NPC TO AN OPENING. The engine pathfinder solves "get to the
-- player" by walking around the house, because around IS a valid path and it has no reason to
-- prefer a window over it. One fact, three symptoms: slow to leave, circling buildings, and
-- looking like it cannot use openings at all.
--
-- THIS FUNCTION IS ROUTE SELECTION AND NOTHING ELSE. It picks the opening and hands back a
-- square to stand on. It does not climb, does not smash, does not queue, does not touch
-- ClimbThroughWindowState, and does not write a single field anywhere. Bandits' own bump
-- handler does the crossing once the NPC is standing there. Extend, never replace.

--- What kind of crossing the caller is being pointed at. `break` is REPORTED, never queued --
--- see the tier table below.
Move.OPEN_DOOR   = "door"
Move.OPEN_WINDOW = "window"
Move.OPEN_BREAK  = "break"

-- THE ORDER, AS THE USER SPECIFIED IT, and how four spoken tiers became four numbers:
--
--   "Entering: door first (locked or not) -> next EXTERIOR door -> nearest window -> break in."
--
-- Tier 1 and 2 are both DOORS, which is the "locked or not" part: a locked exterior door still
-- beats every window, because it may be openable from the inside, because Bandits may resolve
-- it on the bump, and because the user asked for it. Splitting locked into its own tier only
-- decides which door wins when there are two, and an unlocked one should always win that.
--
-- "Next EXTERIOR door" is NOT a tier. It is this same query re-asked with the first door in
-- `opts.exclude`. It has to work that way: this function holds no state (requirement 5), so
-- the memory of "we already tried that one" belongs to the caller, which is the only place
-- that knows whether the attempt actually failed. See the exclude note on the signature.
local TIER_DOOR        = 1   -- exterior door, open or shut-and-unlocked
local TIER_DOOR_LOCKED = 2   -- exterior door, shut and locked -- still beats any window
local TIER_WINDOW      = 3   -- exterior window we can cross or that Bandits will open
local TIER_BREAK       = 4   -- LAST RESORT: reported as a kind, never acted on here

local TIER_KIND = {
    Move.OPEN_DOOR,     -- [TIER_DOOR]
    Move.OPEN_DOOR,     -- [TIER_DOOR_LOCKED]
    Move.OPEN_WINDOW,   -- [TIER_WINDOW]
    Move.OPEN_BREAK,    -- [TIER_BREAK]
}

--- Tiles. How far from the NPC we will look for a way through the shell.
---
--- THE ARITHMETIC, because this is the most expensive thing in the file. The scan is a disc,
--- not a box: the loop runs over a 21 x 21 = 441 bounding box but only touches squares where
--- dx*dx + dy*dy <= 100, which is pi * 10^2 ~= 314 grid lookups. The dx/dy test is pure Lua
--- arithmetic and costs nothing, so 127 of the 441 never reach the engine at all.
---
--- WHY 10 AND NOT 8. `Loot.SEARCH` is 8 and that is deliberately one room. This is a whole
--- house: from a back bedroom the front door can sit 12 tiles away, and the entire point is to
--- find the exit on the PLAYER'S side rather than the nearest one. 10 covers a typical house
--- and a facade seen from outside; larger buys little and multiplies the object scan.
---
--- THIS IS NOT A PER-SWEEP QUERY. 314 squares of `getObjects()` is fine on a stall and wrong
--- several times a second. Ask it when the NPC is actually stuck.
Move.OPENING_RADIUS = 10

local function dist2d(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

--- The square on the far side of an edge object.
---
--- Doors, windows and window frames are NORTH/WEST edge objects: they belong to the square
--- whose north or west boundary they occupy. That is why the same wall reads differently on
--- opposite facades -- a window in a house's NORTH wall lives on the INTERIOR tile, and a
--- window in its SOUTH wall lives on the EXTERIOR tile, because that wall is the north edge of
--- the tile outside. Every test below is written to be symmetric for exactly this reason; an
--- earlier sketch that filtered candidate squares by `sq:getBuilding() == building` would have
--- silently missed every south and east facade opening in the game.
---
--- `obj:getNorth()` on a door: server/BuildingObjects/ISWoodenWall.lua:110.
--- Vanilla calls it generically on window objects too, in the function this file leans on:
--- shared/Util/AdjacentFreeTileFinder.lua:435 (`privGetNorth`).
--- `square:getAdjacentSquare(IsoDirections.N)`: shared/Util/AdjacentFreeTileFinder.lua:235,
--- and `.W` at :252.
local function otherSide(square, obj)
    local ok, adj = pcall(function()
        local dir = obj:getNorth() and IsoDirections.N or IsoDirections.W
        return square:getAdjacentSquare(dir)
    end)
    if not ok then return nil end
    return adj
end

--- Does this edge object cross the outer shell of `shell`, and can a person stand on both
--- sides of it?
---
--- EXTERIORITY IS DECIDED BY GEOMETRY, ON PURPOSE. Exactly one side outdoors IS the definition
--- of "this edge is the building's skin", and it needs no method we cannot read.
--- `square:isOutside()`: client/ISUI/ISGeneratorInfoWindow.lua:49, and vanilla gates a whole
--- action on it at shared/Farming/TimedActions/ISPlowAction.lua:158.
--- (Upstream asks the simpler form of the same question at
--- vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:912,
--- `bandit:getSquare():isOutside()`. The line first written here was :941, which is a closing
--- `end` -- I opened the file, saw it, and corrected it. A citation nobody can follow is R1
--- theatre, exactly as the note above `classify` already says.)
--- `square:getBuilding()`: client/ISUI/ISWorldObjectContextMenu.lua:1694 -- vanilla's own way
--- of drawing a building boundary, and already how `Loot.FindContainer` bounds its scan.
---
--- The engine methods `isExterior()` and `isExteriorDoor(character)` were considered and are
--- NOT called here. They appear ZERO times across the 2,680 Lua files in pzserver/media/, so
--- nothing in this repository can tell us what they MEAN -- an in-game probe proved they are
--- callable, which is a different claim. Using an unreadable method to decide the top tier of
--- the ordering is the exact shape of mistake that cost this project two sessions on
--- `isNPC()` and `getTarget()`. If they are ever wanted, they belong here as a confirming log
--- line, not as the decider.
---
--- BOTH SIDES MUST BE STANDABLE, and this guard earns its keep on its own: it is what stops an
--- NPC upstairs being routed out of a first-floor window. The square outside a first-floor
--- window has no floor, so `canStand()` is false and the candidate never scores. Same guard
--- rejects windows onto solid fill and onto the void at a map edge.
--- `square:canStand()`: shared/Util/AdjacentFreeTileFinder.lua:67 and :381.
local function crossesShell(square, obj, shell)
    local other = otherSide(square, obj)
    if not other then return false end

    local ok, crosses = pcall(function()
        if not square:canStand() then return false end
        if not other:canStand() then return false end
        if square:isOutside() == other:isOutside() then return false end
        return square:getBuilding() == shell or other:getBuilding() == shell
    end)
    if not ok then return false end
    return crosses == true
end

--- What tier this object is worth, and a phrase for the log. nil when it is not an opening.
---
--- Every predicate has a vanilla callsite, which is the bar R1 sets:
---   instanceof(obj, "IsoDoor" / "IsoWindow" / "IsoWindowFrame" / "IsoThumpable")
---                                    server/BuildRecipeCode/buildRecipeCode.lua:110
---   thumpable:isDoor() / :isWindow()  server/BuildRecipeCode/buildRecipeCode.lua:110
---   door:IsOpen()                     server/BuildRecipeCode/buildRecipeCode.lua:27
---   door:isLocked()                   client/DebugUIs/AdminContextMenu.lua:80
---   door:isBarricaded()               shared/Moveables/ISMoveableSpriteProps.lua:907
---   obj:canClimbThrough(character)    client/ISUI/ISButtonPrompt.lua:817, :830, :840
---                                     client/TimedActions/ISClimbThroughWindow.lua:6
---   obj:getBarricadeForCharacter(c)   client/ISUI/ISButtonPrompt.lua:821
---   window:isSmashed()                client/ISUI/ISButtonPrompt.lua:822
--- The window branch is vanilla's own order of questions at ISButtonPrompt.lua:816-826: climb
--- through if you can, otherwise the only thing left to offer is a smash.
---
--- KNOWN SOFT SPOT, written down rather than hidden. "window shut" assumes Bandits' OpenWindow
--- will succeed on the bump, and that is only checked against `isPermaLocked()` upstream
--- (BanditUpdate.lua:679) -- a getter that appears nowhere in pzserver/media/, so this file
--- does not call it. If such a window turns out not to open, the NPC bumps and nothing
--- happens, which is exactly today's behaviour and therefore no regression; the caller's
--- `exclude` list is how it moves on. The `why` string says "shut" so the log can tell that
--- case apart from a window that was already crossable.
local function classifyOpening(obj, zombie)
    local ok, tier, why = pcall(function()
        local isDoor = instanceof(obj, "IsoDoor")
            or (instanceof(obj, "IsoThumpable") and obj:isDoor() == true)

        if isDoor then
            if obj:isBarricaded() then return TIER_BREAK, "door barricaded" end
            if obj:IsOpen() then return TIER_DOOR, "door already open" end
            if obj:isLocked() then return TIER_DOOR_LOCKED, "door locked" end
            return TIER_DOOR, "door shut, unlocked"
        end

        local isWindow = instanceof(obj, "IsoWindow")
            or instanceof(obj, "IsoWindowFrame")
            or (instanceof(obj, "IsoThumpable") and obj:isWindow() == true)
        if not isWindow then return nil end

        if obj:canClimbThrough(zombie) then return TIER_WINDOW, "window crossable now" end
        if obj:getBarricadeForCharacter(zombie) then return TIER_BREAK, "window barricaded" end
        if instanceof(obj, "IsoWindow") and not obj:IsOpen() and not obj:isSmashed() then
            return TIER_WINDOW, "window shut"
        end
        return TIER_BREAK, "window will not open"
    end)
    if not ok then return nil end
    return tier, why
end

--- Has the caller already tried and rejected this opening?
---
--- Reads `ox/oy/oz` when present and `x/y/z` otherwise, and the fallback is the whole point:
--- a result table from this function carries BOTH -- `x,y,z` is the square to stand on and
--- `ox,oy,oz` is the opening. A caller that pushes the result straight into its exclude list
--- (the obvious thing to do) would otherwise be excluding the standing square, which is not
--- the thing that failed and which can serve a second opening. Preferring `ox` makes the
--- obvious call the correct one, and a hand-built `{x=,y=,z=}` still works.
local function isExcluded(list, x, y, z)
    if not list then return false end
    for i = 1, #list do
        local e = list[i]
        if e then
            local ex = e.ox or e.x
            local ey = e.oy or e.y
            local ez = e.oz or e.z
            if ex == x and ey == y and ez == z then return true end
        end
    end
    return false
end

--- The opening this NPC should head for to get from where it is to where it wants to be.
---
--- Returns nil, or a table:
---   { x, y, z,          -- the square to STAND ON. Not the opening. See below.
---     kind,             -- Move.OPEN_DOOR | Move.OPEN_WINDOW | Move.OPEN_BREAK
---     why,              -- a phrase for console.txt: "door locked", "window shut", ...
---     ox, oy, oz,       -- the opening's own square, for logging and for opts.exclude
---     leaving }         -- true when the NPC is getting OUT, false when getting IN
---
--- `opts` is optional: `{ radius = Move.OPENING_RADIUS, exclude = { {x=,y=,z=}, ... } }`.
--- `exclude` holds OPENING squares (ox, oy, oz) the caller has already tried and which did not
--- work -- that, and only that, is how the user's "next EXTERIOR door" tier is reached. It is
--- matched on the opening and not on the standing square, because one standing square can
--- serve two openings.
---
--- IT REFUSES CHEAPLY, AND THAT IS HALF THE DESIGN.
--- The gate is `zsq:getBuilding() == tsq:getBuilding()`, and it answers "there is no shell
--- between these two points" for both of the common cases at once:
---   * both outdoors  -> getBuilding() is nil on each, nil == nil, refused;
---   * same building  -> the same IsoBuilding on each, refused.
--- Only a genuine mismatch costs anything. When it does mismatch, `shell = zb or tb` picks the
--- building whose skin must be crossed FIRST: the NPC's own when it is inside (it has to get
--- out before anything else is true), the target's when it is not.
---
--- WHY THE COST IS "DISTANCE THERE PLUS DISTANCE ON", not distance to the opening. The user's
--- rule for leaving is "the exterior door nearest the player", and a plain nearest-to-me score
--- gives the opposite: the back door, two tiles away, followed by a walk around the whole
--- house -- which is the reported symptom, reproduced by the fix meant to remove it. Summing
--- both legs is the actual journey, and it returns the user's answer in his own case (back
--- door 2 + 18 = 20 loses to front door 8 + 2 = 10) while also doing the right thing on the
--- way in, where both legs matter.
---
--- ONE FLOOR ONLY. The scan runs at `floor(zombie:getZ())`. An NPC on a different floor from
--- the shell it needs to cross gets nil and keeps using the pathfinder; stairs are not this
--- function's job and guessing at them is how you get a companion off a balcony. The target's
--- Z is deliberately NOT required to match, so an NPC outside can still be routed through the
--- ground-floor door nearest a player who is upstairs.
---
--- WHAT THE CALLER MUST RE-CHECK AFTER ARRIVING -- R13, and the reason this is a pure query.
--- This answers about the world as it is RIGHT NOW. By the time the NPC is standing on that
--- square the door may have been opened, closed, locked or smashed by anyone, and the NPC may
--- not even have arrived: a Bandits move task guarantees only that it ENDED. So:
---   * ask again on arrival, do not cache the answer across a walk;
---   * never queue a crossing action off this result -- there is nothing to queue, Bandits'
---     bump handler owns the crossing and it re-evaluates the object itself;
---   * `kind == Move.OPEN_BREAK` is a REPORT. Nothing here smashes anything. The caller decides
---     whether breaking in is acceptable for this NPC, and it is last for a reason.
---
--- HOW THIS WIRES INTO Move.GoAndDo. The opening is the WALK leg and only the walk leg:
---
---   local opening = SR.Move.FindOpening(zombie, px, py, pz)
---   local point   = opening or { x = px, y = py, z = pz }
---   local tasks   = SR.Move.GoAndDo(zombie, point, arriveTask, { run = true })
---
--- GoAndDo returns the walk OR the action, never both, and re-measures from scratch every time
--- the calling program re-runs -- which happens on an empty queue, and that free re-entry is
--- the motor. Standing on the opening square is not the goal, so on the sweep where GoAndDo
--- reports `arrived` the caller should simply drop the opening and aim at the real target
--- again: the next step out of that square walks into the door or window, and Bandits crosses
--- it. Do NOT put this behind a one-shot latch. `ScenesRelationsIdle.goGet` did exactly that
--- on 2026-08-08 -- a `mood.wanting` flag whose whole purpose was to prevent a second call --
--- and the behaviour died silently the moment its primitive started returning work in
--- installments.
function Move.FindOpening(zombie, tx, ty, tz, opts)
    opts = opts or {}

    local cell = getCell()
    if not cell then return nil end

    -- `character:getSquare()`: shared/Foraging/ISForageAction.lua:6.
    local zsq = zombie:getSquare()
    if not zsq then return nil end

    local okTarget, tsq = pcall(function()
        return cell:getGridSquare(math.floor(tx), math.floor(ty), math.floor(tz))
    end)
    if not okTarget or not tsq then return nil end

    local okBuilding, zb, tb = pcall(function()
        return zsq:getBuilding(), tsq:getBuilding()
    end)
    if not okBuilding then return nil end

    -- No shell between us. Costs two engine calls and stops here, which is the common case.
    if zb == tb then return nil end

    local shell = zb or tb
    local leaving = zb ~= nil

    local radius = opts.radius or Move.OPENING_RADIUS
    local r2 = radius * radius

    local zx, zy = math.floor(zombie:getX()), math.floor(zombie:getY())
    local z = math.floor(zombie:getZ())
    local ftx, fty = math.floor(tx), math.floor(ty)

    -- TOO FAR IN TO CHOOSE YET, and this guard is worth as much as the building gate.
    --
    -- ENTERING only. An NPC thirty tiles from the house has no business picking a door: the
    -- facade nearest IT is very unlikely to be the facade nearest the target, the disc reaches
    -- ten tiles so it would very likely find nothing anyway, and the walk it is already doing
    -- brings it into range for free. Re-asking when it arrives costs nothing, because the
    -- caller re-asks on every re-entry (see the GoAndDo note on the signature). Without this
    -- the "no opening" line below fires on every sweep for every distant building, and a log
    -- nobody can read is the same as no log.
    --
    -- radius * 2 = 20 tiles: far enough that the shell is plausibly in the disc, near enough
    -- that the choice is about this building rather than about the street.
    --
    -- LEAVING is never distance-gated. The NPC is inside the shell, so the shell is within
    -- `radius` by construction, and the whole complaint is that it is slow to get out.
    if not leaving and dist2d(zx, zy, ftx, fty) > radius * 2 then return nil end

    local bestTier, bestCost, bestSquare, bestObj, bestWhy

    for dx = -radius, radius do
        for dy = -radius, radius do
            if dx * dx + dy * dy <= r2 then
                local sq = cell:getGridSquare(zx + dx, zy + dy, z)
                if sq and not isExcluded(opts.exclude, zx + dx, zy + dy, z) then
                    local objects = sq:getObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local obj = objects:get(i)
                            -- classifyOpening first: it rejects grass, walls and furniture on
                            -- one or two instanceof calls, where crossesShell costs eight
                            -- engine calls. Order matters at 314 squares.
                            local tier, why = classifyOpening(obj, zombie)
                            if tier and crossesShell(sq, obj, shell) then
                                local cost = dist2d(zx, zy, zx + dx, zy + dy)
                                    + dist2d(zx + dx, zy + dy, ftx, fty)
                                if not bestTier or tier < bestTier
                                    or (tier == bestTier and cost < bestCost) then
                                    bestTier = tier
                                    bestCost = cost
                                    bestSquare = sq
                                    bestObj = obj
                                    bestWhy = why
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if not bestSquare then
        -- Only reachable AFTER the building gate passed, so this is rare and worth a line:
        -- it is the difference between "we never looked" and "we looked and there is no way
        -- through within `radius`".
        SR.Log(string.format("OPEN no opening within %d tiles -- %s building at %d,%d,%d",
            radius, leaving and "leaving" or "entering", zx, zy, z))
        return nil
    end

    -- WHERE TO STAND, AND WHY IT IS NOT THE OPENING'S OWN SQUARE. An NPC pathed onto a window
    -- tile is an NPC stuck in the frame -- caps/npc-window-stuck.png and
    -- caps/npc-window-stuck_2.png are that, twice.
    -- `AdjacentFreeTileFinder.FindWindowOrDoor` (shared/Util/AdjacentFreeTileFinder.lua:231)
    -- is the function vanilla wrote for this precise question: it takes the edge object, works
    -- out which side is which from `getNorth()` (`privGetNorth`, :434) and refuses any square
    -- you cannot stand on (`privTrySquareWindow`, :402).
    --
    -- IT PICKS THE NEAR SIDE BY ROOM, NOT BY DISTANCE, and I traced both branches of it
    -- (north :234-:250, west :251-:268) rather than assuming it:
    --   * leaving  -- the NPC is indoors, `playerSq:getRoom()` is that room, and only the
    --     INDOOR side of the door matches it. We stop just inside the door, which is right:
    --     the next step out of that square walks into it and Bandits opens it.
    --   * entering -- the NPC is outdoors, `getRoom()` is nil there, and `nil == nil` matches
    --     the OUTDOOR side. Same code, opposite answer, both correct.
    -- The distance tie-break at :286 only chooses between equals.
    --
    -- FALLBACK, and it is not decoration: FindWindowOrDoor dereferences
    -- `playerObj:getCurrentSquare():getRoom()` at :237 with no nil check, so an NPC caught
    -- between squares throws rather than returns nil. `FindClosest` (:193) is the wall-aware
    -- neighbour finder with no such dependency, and because its wall test refuses to cross the
    -- opening it also lands on the near side.
    local okStand, stand = pcall(function()
        return AdjacentFreeTileFinder.FindWindowOrDoor(bestSquare, bestObj, zombie)
    end)
    if not okStand or not stand then
        local okNear, near = pcall(function()
            return AdjacentFreeTileFinder.FindClosest(bestSquare, zombie)
        end)
        stand = (okNear and near) or nil
    end
    if not stand then return nil end

    local result = {
        x = stand:getX(),
        y = stand:getY(),
        z = stand:getZ(),
        kind = TIER_KIND[bestTier],
        why = bestWhy,
        ox = bestSquare:getX(),
        oy = bestSquare:getY(),
        oz = bestSquare:getZ(),
        leaving = leaving,
    }

    SR.Log(string.format("OPEN %s via %s (%s) at %d,%d,%d -- stand %d,%d,%d, cost %.1f",
        leaving and "leaving" or "entering", result.kind, tostring(result.why),
        result.ox, result.oy, result.oz, result.x, result.y, result.z, bestCost))

    return result
end

Events.OnGameStart.Add(function()
    SR.Log("MOVE ready -- one walk-then-act primitive, GoAndDo, shared across the mod")
end)
