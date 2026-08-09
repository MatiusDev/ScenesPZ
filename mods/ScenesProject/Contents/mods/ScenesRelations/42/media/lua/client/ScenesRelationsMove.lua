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
-- `ZombieActions.PickUp.onComplete` (vendor/Bandits/.../ZombieActions/ZAPickUp.lua:14) has no
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
        tasks[1] = BanditUtils.GetMoveTask(0, ax, ay, az, walkType, dist, false)
        return tasks, false
    end

    tasks[1] = task
    return tasks, true
end

Events.OnGameStart.Add(function()
    SR.Log("MOVE ready -- one walk-then-act primitive, GoAndDo, shared across the mod")
end)
