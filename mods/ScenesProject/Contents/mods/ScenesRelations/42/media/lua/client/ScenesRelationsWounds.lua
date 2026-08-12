-- ScenesPZ -- bleeding, and what somebody uses to stop it.
--
-- THE QUESTION THAT PRODUCED THIS
--   "como se curan los NPC y si desarrollaste lo mismo que hay en la salud del jugador,
--    donde el NPC puede ser mordido en diferentes partes del cuerpo... vi que morian por que
--    se desangraban"
--
-- THE HONEST ANSWER FIRST, BECAUSE IT SHAPES EVERYTHING BELOW
-- No. There are no body parts. A Bandits NPC's entire injury model is one float --
-- getHealth, roughly 0..2.6 -- and three lines in BanditUpdate:
--
--   * below 0.7 they bleed, at 0.00005 per tick, forever (ManageHealth, :449-467 in 42.20 --
--     the line range here used to read :491-501, which is a different function; re-checked
--     against the pinned copy on 10-08 and corrected, see the note on BLEED_FLOOR);
--   * below 0.4 a healing flag is set, but ONLY when the task queue holds nothing but
--     movement (`if not BanditBrain.HasActionTask(brain)`, :952 and :955);
--   * the Bandage action that flag queues sets health to a flat 1.2 and COSTS NOTHING
--     (ZABandage.lua:50). No item is consumed. No inventory is checked.
--
-- `getBodyDamage()` does answer on an IsoZombie, so the vanilla structure is reachable --
-- but nothing in Bandits ever writes to it, and whether the engine PROCESSES it for a
-- zombie is unproven. Building bites-per-limb on that assumption is exactly the mistake
-- this project has paid for twice, so the wound lives on the brain where we control it, and
-- a probe is queued to settle the vanilla question before stage 3 leans on it.
--
-- WHY THEY BLED TO DEATH NEXT TO YOU, AND IT WAS OUR FAULT
-- The 04-08 log has this line three times:
--
--   AUTO Benjamin Morgan | stuck on Bandage@nil,nil for 3 sweeps -- queue cleared
--
-- Our own watchdog was cancelling their heal, mid-heal, every twenty seconds. Bandage sits
-- at the head of the queue while it works, which the first watchdog read as "stuck". Fixed
-- in the 04-08 second pass -- Bandage is not in the STALLABLE set and never will be -- but
-- it is worth recording that the reported symptom was a bug we introduced, not a gap in
-- Bandits.
--
-- WHAT THIS FILE CHANGES, AND WHAT IT DELIBERATELY DOES NOT
-- It wraps ZABandage.onComplete so that healing COSTS something and its quality depends on
-- what they had. Their onStart, their animation, their sound and the task itself are
-- untouched -- we change the outcome, not the act.
--
--   sterile dressing   full restore
--   proper bandage     nearly full
--   clean rag          most of a restore
--   dirty rag          less, and they will want to change it
--   nothing at all     they tear their own clothing: a little, and dirty
--
-- That last line is the point of the whole exercise: "ellos deberian de poder rasgar telas
-- de las camisetas por ahi y curarse". Nobody should ever simply run out of options and
-- bleed to death with a shirt on.
--
-- NO ITEM IS INVENTED ANYWHERE HERE
-- Dressings are ranked by `item:getBandagePower()`, which is how vanilla itself decides
-- something is a bandage (`> 0`, ISHealthPanel.lua:1154) and how it separates a proper
-- bandage from a rag (`>= 2`, ISHealthPanel.lua:1722). Sterility is `item:isAlcoholic()`,
-- the same flag ISApplyBandage.lua:119 passes through. So this works for every current and
-- future dressing in the game and for modded ones, without a list to go stale.
--
-- AND WHY brain.infection IS NOT TOUCHED
-- It would be the obvious home for "this rag is filthy". It is also the counter Bandits
-- turns into a Zombify task at 100 (BanditUpdate.lua:509). A dirty bandage must not turn
-- somebody into a zombie. Wound state is ours and stays ours.
--
-- ------------------------------------------------------------------------------------
-- THE 10-08 SECOND PASS: WINDOWS CUT BOTH WAYS, AND THE CUT NOW BLEEDS
--
-- REPORTED: "el tema de que un NPC pase por una ventana rota no le estaba haciendo dano,
-- ahora lo activo y funciono solo cuando salio, pero no cuando entro por la ventana rota
-- de nuevo. Debe hacerle dano cada que entra o salga. A parte de eso debe aplicarle un
-- efecto de sangrado que solo se puede curar vendandose."
--
-- Both halves were true, and the first half had a structural cause rather than a tuning one.
-- Everything that could cut somebody ran on a clock that is slower than a crossing:
--
--   * Wounds.CheckGlass samples once per autonomy sweep -- EveryOneMinute, about six real
--     seconds (ScenesRelationsAutonomy.lua:1870). A crossing takes about one. It catches an
--     NPC who LINGERS in a smashed frame and misses almost every NPC who walks through one.
--   * The OpenWindow hook further down was written to close that gap and cannot. Bandits
--     queues OpenWindow at exactly one site and that site is guarded by `not
--     object:isSmashed()` -- vendor/Bandits/mods/Bandits/42.20/media/lua/client/
--     BanditUpdate.lua:672, task at :677-678. A window with glass still in it never produces
--     an OpenWindow task at all, so the hook could only ever fire on a window that got
--     smashed BETWEEN the task being queued and it completing. That is a race, not a path.
--
-- AND THERE IS NO ACTION TO WRAP FOR THE CROSSING ITSELF. Bandits does not queue a task to
-- climb a window; it changes engine state directly:
--
--     ClimbThroughWindowState.instance():setParams(bandit, object)
--     bandit:changeState(ClimbThroughWindowState.instance())
--     bandit:setBumpType("ClimbWindow")
--
-- vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:684-686. There is no
-- ZAClimbWindow in their ZombieActions folder to hook, and the second crossing -- back in
-- through a window that is already open -- queues nothing whatsoever. That is exactly the
-- reported asymmetry: going out happened to coincide with something we could see, coming
-- back in was invisible by construction.
--
-- So the crossing is measured where it actually happens: the RISING EDGE of
-- ClimbThroughWindowState, sampled on a fast lane of this module's own. The edge is what
-- makes it symmetric -- the engine enters that state to go out and enters it again to come
-- back, so one test covers both directions and neither needs a task to exist.
--
-- BLEEDING IS OURS BECAUSE BODY PARTS ARE NOT REACHABLE. BodyPart:setBleeding is per limb;
-- Bandits models a whole person as one float. That gap is recorded in docs/TODO.md and is
-- not closed here. The bleed is a field on our wound record, drained by us, and cleared in
-- exactly one place: a completed Bandage. "Solo se puede curar vendandose", literally.

require "ScenesRelations"

local SR = ScenesRelations

SR.Wounds = SR.Wounds or {}
local Wounds = SR.Wounds

-- Health restored, as a fraction of what that person can hold. Their own action snaps to a
-- flat 1.2, which for a tough survivor is a downgrade and for a frail one is a full heal --
-- a fraction treats everybody as themselves.
local RESTORE = {
    sterile    = 1.00,
    bandage    = 0.95,
    clean      = 0.80,
    dirty      = 0.55,
    improvised = 0.40,
}

-- Health taken by walking through a window that still has glass in it. Small on purpose:
-- this should be a reason to open the window properly, not an execution.
local GLASS_DAMAGE = 0.25

-- Sweeps before the same person can be cut again. Without it, an NPC loitering on a window
-- square would be shredded once every six seconds.
local CUT_COOLDOWN = 10

--- Our wound record. On the brain rather than SR.Mood because a wound is not a mood -- it
--- outlives the moment, and it has to survive the cell unloading the way their health does.
---
--- FIELDS
---   dressing     what is currently tied round it, or nil for nothing
---   day          SR.Today() when that dressing went on
---   bleeding     true while an untreated cut is losing them blood
---   bleedDay     SR.Today() when the bleed started -- for the log and the panel only, NOT
---                for any bound: SR.Today() floors world age to whole DAYS, so a difference
---                of anything under 24 h reads as exactly 0. See bleedSweeps.
---   bleedSweeps  autonomy sweeps this person has spent bleeding IN RANGE. The bound is
---                counted in sweeps precisely because it is the same motor that does the
---                draining, so the two can never disagree about how long this has gone on.
---   bodyParts    per-body-part wound state, keyed by BodyPartType index (0-16):
---                { scratches = 0, cuts = 0, deepWounds = 0, bites = 0,
---                  bleeding = false, fractures = 0, health = 100, bandaged = false }
---                ADDITIVE -- the global fields above still drive the AI decisions; this
---                table exists so the health panel can colour body parts and list wounds.
---
--- Older brains were saved with only the first two fields. Every read below is nil-safe on
--- purpose so a save from before this change loads as "not bleeding" rather than throwing.
function Wounds.Of(brain)
    if not brain.scenesWound then
        brain.scenesWound = { dressing = nil, day = nil,
                              bleeding = nil, bleedDay = nil, bleedSweeps = nil,
                              bodyParts = {} }
    elseif not brain.scenesWound.bodyParts then
        brain.scenesWound.bodyParts = {}
    end
    return brain.scenesWound
end

--- All 17 BodyPartType indices that glass can lodge in or that combat can wound. Excludes
--- Head (glass in the eye is death) and Neck (insta-bleed) for glass, but kept in the set for
--- combat wounds. Ordered as the engine defines them.
local ALL_BODY_PARTS = {
    BodyPartType.Hand_L, BodyPartType.Hand_R,
    BodyPartType.ForeArm_L, BodyPartType.ForeArm_R,
    BodyPartType.UpperArm_L, BodyPartType.UpperArm_R,
    BodyPartType.Torso_Upper, BodyPartType.Torso_Lower,
    BodyPartType.Head, BodyPartType.Neck,
    BodyPartType.Groin,
    BodyPartType.UpperLeg_L, BodyPartType.UpperLeg_R,
    BodyPartType.LowerLeg_L, BodyPartType.LowerLeg_R,
    BodyPartType.Foot_L, BodyPartType.Foot_R,
}

--- Ensure a body part entry exists in our tracking and return it. The wound table lives on
--- the brain and is the same one Wounds.Of returns -- this is a convenience, not a second
--- store.
local function ensurePart(wound, partType)
    local parts = wound.bodyParts
    if not parts[partType] then
        parts[partType] = { scratches = 0, cuts = 0, deepWounds = 0, bites = 0,
                            bleeding = false, fractures = 0, health = 100, bandaged = false }
    end
    return parts[partType]
end

--- Record a wound on a specific body part in our own per-part tracking. The engine exposes
--- no per-part wound data for IsoZombie, so this is the sole source of truth for the health
--- panel's body part display.
local function recordWound(wound, partType, kind)
    local p = ensurePart(wound, partType)
    if kind == "cut" then p.cuts = p.cuts + 1; p.bleeding = true
    elseif kind == "scratch" then p.scratches = p.scratches + 1
    elseif kind == "deep" then p.deepWounds = p.deepWounds + 1; p.bleeding = true
    elseif kind == "bite" then p.bites = p.bites + 1; p.bleeding = true
    elseif kind == "fracture" then p.fractures = p.fractures + 1
    end
end

--- Clear bleeding on all body parts (called when a bandage completes). The global wound
--- fields are cleared separately; this only touches the per-part table.
function Wounds.ClearBodyBleeding(brain)
    local wound = brain and brain.scenesWound
    if not wound or not wound.bodyParts then return end
    for _, p in pairs(wound.bodyParts) do
        if p.bleeding then p.bleeding = false end
    end
end

--- Mark all wounded body parts as bandaged. Called when a dressing goes on -- the NPC just
--- finished wrapping themselves, so every wounded part got attention.
function Wounds.MarkBodyBandaged(brain, kind)
    local wound = brain and brain.scenesWound
    if not wound or not wound.bodyParts then return end
    for pt, p in pairs(wound.bodyParts) do
        if p.scratches > 0 or p.cuts > 0 or p.deepWounds > 0 or p.bites > 0
           or p.fractures > 0 or p.bleeding then
            p.bandaged = true
            p.bleeding = false
        end
    end
end

-- Absolute health at which Bandits starts draining somebody. Not a ratio: their bleed test is
-- absolute, so ours is too, or a frail survivor would be judged healthy while bleeding out.
--
-- THE CITATION WAS WRONG AND IS CORRECTED HERE. It read "ManageHealth, BanditUpdate.lua:491",
-- which in 42.20 is inside RemoveWindowFromPathing, not ManageHealth. Re-checked while working
-- on the bleed: ManageHealth begins at
-- vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:449, the `health < 0.7`
-- test is at :456 and the `setHealth(health - 0.00005)` drain at :465, the whole block behind
-- SandboxVars.Bandits.General_BleedOut at :453. The VALUE was right; only the line was stale.
local BLEED_FLOOR = 0.7

-- In-game hours before somebody will try dressing a wound again. Without it, a survivor
-- still under the floor after an improvised dressing would re-dress every few seconds and
-- burn every rag they own.
--
-- IT IS COARSER THAN IT LOOKS, AND THE BLEED HAD TO BE TOLD ABOUT IT. `SR.Today()` returns
-- `math.floor(getWorldAgeHours() / 24)` -- whole days (shared/ScenesRelations.lua:64-70) --
-- so `(SR.Today() - wound.day) * 24` can only ever be 0, 24, 48... The test below is
-- therefore not "two hours have passed" but "the calendar day has turned". That is fine for
-- rationing rags; it would be fatal for a bleed whose only cure is a bandage, because
-- somebody cut ten seconds after dressing a wound could not re-dress until tomorrow and
-- would drain the whole time. So NeedsDressing answers `true` for a bleed BEFORE it reaches
-- this gate. Not fixed here: SR.Today() belongs to shared/ScenesRelations.lua.
local REDRESS_HOURS = 2

-- BLEEDING -----------------------------------------------------------------------------

-- The lowest condition anything in this file will drive somebody to. Glass and the bleed
-- both stop here: neither is meant to be an execution, and something has to be left for the
-- zombie or the fall that actually kills them. Was a bare 0.05 inside applyGlassCut; named
-- so the two paths cannot drift apart.
local HEALTH_FLOOR = 0.05

-- Condition lost per autonomy sweep while bleeding.
--
-- THE ARITHMETIC. CheckGlass is called once per NPC per sweep from ScenesRelationsAutonomy,
-- and that sweep is EveryOneMinute -- one IN-GAME minute, about six real seconds
-- (ScenesRelationsAutonomy.lua:1870, and the header above it states the six). So 0.02 per
-- sweep is about 0.2 of condition per real minute. From a healthy 2.0 that is
-- (2.0 - 0.7) / 0.02 = 65 sweeps, roughly six and a half real minutes, before they reach
-- 0.7 and Bandits' own drain joins in (ManageHealth,
-- vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:456 and :465).
--
-- Deliberately slower than it could be. The point is a person who visibly needs a bandage
-- and goes looking for one, not a person who dies on the way to the rag.
local BLEED_PER_SWEEP = 0.02

-- One log line per bleeding person per this many sweeps. 5 x ~6 s = about half a real minute,
-- which is often enough to watch a bleed progress in console.txt and rare enough that two
-- bleeding companions do not bury every other line in the file. Start and stop always print.
local BLEED_LOG_EVERY = 5

-- THE BOUND, AND WHY IT EXISTS RATHER THAN A HOPEFUL COMMENT ---------------------------
--
-- `bleeding` is a remembered decision whose clear hangs off the NPC reaching a completed
-- Bandage. That is the exact shape of the four latches this project has already paid for
-- (mood.sheltering, mood.rejoining, mood.wanting, mood.posture), and every one of them had a
-- clear -- they broke because the clear could not be REACHED. So the clear is traced in full
-- at scenesBandageComplete, and the paths that can block it are these:
--
--   1. the NPC is on a program we do not wrap. FreeActivity is reached from Companion.Main
--      (ScenesRelationsCompanion.lua:284) and Looter.Main (:486) only. Somebody on Bandit,
--      Hunter or any other program never consults NeedsDressing at all.
--   2. rung SURVIVE or FIGHT: scenesMain hands those back to Bandits untouched
--      (ScenesRelationsCompanion.lua:235 and :238), so a companion in a long fight never
--      reaches the bandage decision.
--   3. the task queue never empties, so Main never runs -- Bandits only calls a program's
--      Main on an empty queue, which is the whole re-entry motor this decision rides on.
--   4. Wounds.Install failed, so ZombieActions.Bandage.onComplete is still theirs and the
--      clear is not wired up at all.
--
-- 2 and 3 end on their own. 1 and 4 do not, and an unbounded latch there would be a person
-- who bleeds for the rest of the save. So the bleed also stops after this many sweeps SPENT
-- IN RANGE -- 100 x ~6 s is about ten real minutes of being visible to the sweep and never
-- completing a bandage. A healthy path clears this in a sweep or two, so reaching the bound
-- is itself evidence of one of the four cases above, which is why it logs loudly when it
-- trips: the bound doubles as the detector for its own reason to exist.
local BLEED_MAX_SWEEPS = 100

--- Should this person stop and deal with a wound right now?
---
--- THIS EXISTS BECAUSE THEIR OWN TRIGGER IS UNREACHABLE. The healing flag is gated on
--- `if not BanditBrain.HasActionTask(brain)` (BanditUpdate.lua:952), which is false whenever
--- the queue holds anything that is not Move or GoTo. With the autonomy ladder giving people
--- something to do, that is almost always. The 04-08 log is the proof: John Jones was opened
--- in the health panel at `condition 0.02 / 1.80` -- two hundredths of a point from dead,
--- and infected -- and there is not one `dressed with` line in the entire run.
---
--- So the companion program queues the Bandage task itself. Their action, their animation,
--- their sound; only the decision to start is ours, because theirs cannot fire.
---
--- A BLEED ANSWERS TRUE BEFORE EITHER GATE BELOW, and that ordering is the whole reason the
--- bleed can ever be cured. Both gates would otherwise refuse the one bandage that clears it:
--- the health floor because a cut person is usually still well above 0.7, and REDRESS_HOURS
--- because it is really "wait until tomorrow" (see the note on that constant). A latch whose
--- clear is suppressed by the latch itself is the defect this project has paid for four times.
function Wounds.NeedsDressing(zombie, brain)
    local wound = brain.scenesWound
    if wound and wound.bleeding then return true end

    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return false end
    if now >= BLEED_FLOOR then return false end

    if wound and wound.day then
        local hours = (SR.Today() - wound.day) * 24
        if hours < REDRESS_HOURS then return false end
    end

    return true
end

--- Whether this person is walking around with something filthy tied round their arm.
--- Read by the companion program in stage 3, when washing arrives.
function Wounds.WantsCleanDressing(brain)
    local wound = brain and brain.scenesWound
    if not wound then return false end
    return wound.dressing == "dirty" or wound.dressing == "improvised"
end

-- DRESSINGS ----------------------------------------------------------------------------

--- Is this the dirty variant of a rag?
---
--- The one place a name is inspected, and it is bounded: `Base.RippedSheetsDirty` is a real
--- item (scripts/generated/items/normal.txt:8048 names it as the ReplaceOnUse of the clean
--- one) and the Dirty suffix is the convention the whole family follows. Everything else
--- about ranking goes through getBandagePower, which needs no names at all.
local function isDirty(item)
    local ok, name = pcall(function() return item:getFullType() end)
    if not ok or type(name) ~= "string" then return false end
    return string.find(name, "Dirty") ~= nil
end

--- The best thing this person has to tie round a wound, and what kind it is.
---
--- Returns item, kind, or nil when they have nothing. Ranked, never listed:
--- getBandagePower is the engine's own answer to "is this a bandage and how good".
local function bestDressing(zombie)
    local inventory = zombie:getInventory()
    if not inventory then return nil end

    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or not items then return nil end

    local best, bestKind, bestScore

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local power = 0
        pcall(function() power = item:getBandagePower() or 0 end)

        if power > 0 then
            local sterile = false
            pcall(function() sterile = item:isAlcoholic() == true end)

            local kind
            if sterile then kind = "sterile"
            elseif power >= 2 then kind = "bandage"
            elseif isDirty(item) then kind = "dirty"
            else kind = "clean" end

            -- Sterility outranks raw power: a clean dressing on an open wound is worth more
            -- than a slightly thicker filthy one, which is also why the dirty branch exists
            -- at all rather than everything being sorted by one number.
            local score = power + (sterile and 10 or 0) - (kind == "dirty" and 5 or 0)
            if not bestScore or score > bestScore then
                best, bestKind, bestScore = item, kind, score
            end
        end
    end

    return best, bestKind
end

--- Would this person tie a filthy rag on rather than bleed?
---
--- "si son NPC arriesgados pueden ponerse una tela sucia si no ven una tela limpia."
--- brain.rnd[1] is ZombRand(2) -- the only one of the five still unspoken for, and a coin
--- flip is exactly the shape of this trait. Half of them accept the risk; the same half,
--- every time.
local function takesRisks(brain)
    if type(brain.rnd) ~= "table" or not brain.rnd[1] then return false end
    return brain.rnd[1] == 1
end

-- THE WRAP -----------------------------------------------------------------------------

local vanillaBandageComplete

--- Healing that costs something.
---
--- Runs in place of their onComplete. Theirs is two lines -- setHealth(1.2) and the visual
--- bandage -- and both are reproduced here with the amount decided by what was actually
--- spent. The visual is kept because it is the only outward sign any of this happened.
local function scenesBandageComplete(zombie, task)
    local brain = BanditBrain.Get(zombie)
    if not brain then return vanillaBandageComplete(zombie, task) end

    local name = tostring(brain.fullname)
    local wound = Wounds.Of(brain)

    -- THE ONLY PLACE A BLEED IS EVER CLEARED. Not by time, not by health recovering, not by
    -- the sweep giving up on them -- the request was "solo se puede curar vendandose" and this
    -- is that sentence in code. The one other writer is the BLEED_MAX_SWEEPS bound in
    -- bleedTick, which is a bug detector rather than a cure and says so when it fires.
    --
    -- DONE HERE, ABOVE THE setHealth pcall, ON PURPOSE. The wrap decides how much condition
    -- the dressing is worth; it does not decide whether the dressing happened. The Bandage
    -- task has already completed by the time this runs, so if setHealth throws below they are
    -- still bandaged and must not go on bleeding because our arithmetic failed.
    if wound.bleeding then
        wound.bleeding, wound.bleedDay, wound.bleedSweeps = nil, nil, nil
        Wounds.ClearBodyBleeding(brain)
        SR.Log(string.format("WOUND %s stopped bleeding -- a dressing went on", name))
    end

    local max = tonumber(brain.health) or 2
    local before = max
    pcall(function() before = zombie:getHealth() end)

    local item, kind = bestDressing(zombie)

    -- Nothing to hand. Rather than the framework's free full heal, they tear up what they
    -- are wearing: enough to stop the bleeding, dirty, and something they will want to
    -- replace. Nobody bleeds to death with a shirt on.
    if not item then
        kind = "improvised"
    elseif kind == "dirty" and not takesRisks(brain) then
        -- Cautious people do not tie filth onto an open wound when filth is all they have.
        -- They improvise from clean clothing instead: worse at stopping blood, better at
        -- not killing them.
        kind = "improvised"
        item = nil
    end

    local restore = (RESTORE[kind] or 0.4) * max
    local healed = math.min(max, math.max(before, restore))

    local ok, err = pcall(function()
        zombie:setHealth(healed)
        -- Their own visual, kept. task.bpi is set by their onStart, so this only runs when
        -- the task really came through their pipeline.
        if task.bpi then
            local parts = { BodyPartType.Torso_Upper, BodyPartType.UpperArm_L,
                            BodyPartType.UpperArm_R, BodyPartType.LowerLeg_L,
                            BodyPartType.LowerLeg_R }
            zombie:addVisualBandage(parts[(task.bpi % #parts) + 1], true)
        end
    end)
    if not ok then
        SR.Log("WOUND could not dress " .. name .. ": " .. tostring(err))
        return true
    end

    if item then
        local inventory = zombie:getInventory()
        pcall(function() inventory:Remove(item) end)
    end

    wound.dressing = kind
    wound.day = SR.Today()
    Wounds.MarkBodyBandaged(brain, kind)

    SR.Log(string.format("WOUND %s dressed with %s | %.2f -> %.2f / %.2f | risky=%s",
        name, kind, before, healed, max, tostring(takesRisks(brain))))

    return true
end

-- GLASS --------------------------------------------------------------------------------

--- The window on this square if it still has glass in it, or nil.
---
--- `isSmashed() and not isGlassRemoved()` is vanilla's own test for exactly this -- it is
--- the isValid of ISRemoveBrokenGlass (line 6), the action a player takes precisely so they
--- can climb through without being cut.
---
--- RETURNS THE WINDOW RATHER THAN A BOOLEAN because the crossing test below has to ask it one
--- more question -- which way it faces -- to know whether it is the window being climbed or
--- an unrelated one on the same tile.
---
--- KNOWN LIMIT, STATED RATHER THAN GUESSED AT: `square:getWindow()`
--- (pzserver/media/lua/client/DebugUIs/Scenarios/Trailer3Scenario_Building.lua:381-382)
--- returns ONE window, and a corner tile can carry both a north and a west one. This has
--- always been true of this file; it is recorded here rather than fixed because fixing it
--- means walking getObjects() per square per sample, and the miss it causes is a corner
--- window that goes uncut, not a wrong cut.
local function smashedWindowOn(square)
    if not square then return nil end
    local ok, window = pcall(function() return square:getWindow() end)
    if not ok or not window then return nil end

    local smashed, removed = false, true
    local read = pcall(function()
        smashed = window:isSmashed()
        removed = window:isGlassRemoved()
    end)
    if not read then return nil end

    if smashed and not removed then return window end
    return nil
end

--- Is there broken glass in the frame on this square? The original predicate, unchanged in
--- meaning, kept because the sweep and the OpenWindow hook only ever needed a yes or no.
local function glassOnSquare(square)
    return smashedWindowOn(square) ~= nil
end

--- Which way a window faces, or nil if it will not say.
---
--- `getNorth()` on an IsoWindow is vanilla and appears wherever the game has to know which
--- two tiles a wall separates -- pzserver/media/lua/server/BuildingObjects/ISWoodenWall.lua:109
--- and .../ISBuildIsoEntity.lua:326 both compare it directly.
local function windowFacesNorth(window)
    local ok, north = pcall(function() return window:getNorth() end)
    if not ok or type(north) ~= "boolean" then return nil end
    return north
end

--- The square holding the window this person is climbing through, or nil if there is no glass
--- left in it.
---
--- WHICH TILE HOLDS THE WINDOW, AND HOW THAT WAS ESTABLISHED. A window belongs to ONE square
--- and sits on that square's north or west edge, so the two tiles it joins are the square
--- itself and its N or W neighbour. That is not inferred -- it is exactly what vanilla does in
--- reverse: AdjacentFreeTileFinder.FindWindowOrDoor takes the window's square and offers the
--- player `gridSquare` and `gridSquare:getAdjacentSquare(IsoDirections.N)` when the window is
--- north, `gridSquare` and its W neighbour when it is not
--- (pzserver/media/lua/shared/Util/AdjacentFreeTileFinder.lua:231-268).
---
--- Inverted, from the climber's tile C, the windows that touch C are:
---   * the one on C itself -- it joins C to N(C) or to W(C);
---   * the one on S(C) IF it faces north -- N(S(C)) is C;
---   * the one on E(C) IF it faces west -- W(E(C)) is C.
--- Three lookups, no direction needed, and it answers the same for both halves of a crossing:
--- whichever side of the frame the climber is standing on when we sample, the other side is
--- one of the three. That symmetry is the point -- "cada que entra o salga" is one test, not
--- two.
---
--- The orientation test is what keeps it honest. Without it, a window on the west edge of the
--- tile south of C -- which does not touch C at all -- would read as the one being climbed.
local function crossingGlassSquare(zombie)
    local ok, here = pcall(function() return zombie:getSquare() end)
    if not ok or not here then return nil end

    if smashedWindowOn(here) then return here end

    local okS, south = pcall(function() return here:getAdjacentSquare(IsoDirections.S) end)
    if okS and south then
        local window = smashedWindowOn(south)
        if window and windowFacesNorth(window) == true then return south end
    end

    local okE, east = pcall(function() return here:getAdjacentSquare(IsoDirections.E) end)
    if okE and east then
        local window = smashedWindowOn(east)
        if window and windowFacesNorth(window) == false then return east end
    end

    return nil
end

--- Cut an NPC and log it. Shared by the sweep checker, the OpenWindow hook and the climb
--- watcher so all three produce the same line, the same wound and the same cooldown.
---
--- THE 10-08 SESSION: BODY PARTS ARE REACHABLE. The first version claimed they were not, and
--- built its own bleeding on brain.scenesWound. Bandits already uses getBodyDamage on NPCs
--- (ZASmack.lua:358-359) and addVisualBandage (ZABandage.lua:50-51). The engine's body part
--- pipeline processes IsoZombie fully.
---
--- Now glass cuts use the engine's system: health reduction, glass lodged in a random body
--- part, and bleeding on that part. The old wound.bleeding is kept as a fallback for cases
--- where body parts are unreachable (cell unloaded mid-crossing, etc).
---
--- RANDOM DEEP SHARD. A low probability that glass goes deep enough to need tweezers
--- (generateDeepShardWound). Borrowed from vanilla's own glass shard mechanic in
--- ISRemoveGlass.lua and AReallyCDDAy.lua:85. Probability is deliberately low -- most
--- crossings should be painful but not permanently debilitating.
local GLASS_DEEP_SHARD_CHANCE = 0.05  -- 5% chance per cut

-- Body parts glass can lodge in. Excludes head (glass in the eye is death) and neck
-- (insta-bleed). Matches the plausible parts for "dragged my arm through a broken frame."
local GLASS_PARTS = {
    BodyPartType.Hand_L, BodyPartType.Hand_R,
    BodyPartType.ForeArm_L, BodyPartType.ForeArm_R,
    BodyPartType.UpperArm_L, BodyPartType.UpperArm_R,
    BodyPartType.Torso_Upper, BodyPartType.Torso_Lower,
}

local function applyGlassCut(zombie, brain, mood, square, why)
    local max = tonumber(brain.health) or 2
    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return end

    local hurt = math.max(HEALTH_FLOOR, now - GLASS_DAMAGE)
    local set = pcall(function() zombie:setHealth(hurt) end)
    if not set then
        SR.Log("WOUND could not cut " .. tostring(brain.fullname) .. " -- setHealth threw")
    end

    -- Try the engine's body part system. If getBodyDamage throws (cell unload, rare),
    -- fall back to our own wound.bleeding. The body part pipeline is the preferred path
    -- but returns nil on IsoZombie -- the engine exposes no per-part data for NPCs.
    local partUsed, shardDeep = false, false
    local bd = nil
    pcall(function() bd = zombie:getBodyDamage() end)
    if bd then
        local partType = GLASS_PARTS[1 + (ZombRand and ZombRand(#GLASS_PARTS) or 0)]
        local okBp, bp = pcall(function() return bd:getBodyPart(partType) end)
        if okBp and bp then
            pcall(function() bp:setBleedingTime(10) end)
            pcall(function() bp:setHaveGlass(true) end)
            if ZombRand and ZombRand(100) < (GLASS_DEEP_SHARD_CHANCE * 100) then
                pcall(function() bp:generateDeepShardWound() end)
                shardDeep = true
            end
            partUsed = true
        end
    end

    -- Always track the wound in our own per-part table so the health panel can display it.
    -- The engine body part pipeline is unreachable for IsoZombie (getBodyDamage returns nil),
    -- so this is the sole source of body part information for the panel.
    local wound = Wounds.Of(brain)
    wound.dressing = nil

    local glassPart = GLASS_PARTS[1 + (ZombRand and ZombRand(#GLASS_PARTS) or 0)]
    recordWound(wound, glassPart, "cut")

    -- Keep the global bleeding field for the AI decisions (NeedsDressing, bleedTick, etc.);
    -- the per-part bleeding is additive visual detail.
    if not wound.bleeding then
        wound.bleeding = true
        wound.bleedDay = SR.Today()
        wound.bleedSweeps = 0
    end
    mood.cutAt = CUT_COOLDOWN

    local said = pcall(function() Bandit.Say(zombie, "HIT") end)
    if not said then
        SR.Log("WOUND Bandit.Say(HIT) threw for " .. tostring(brain.fullname))
    end

    SR.Log(string.format(
        "WOUND %s cut on broken glass at %d,%d | %.2f -> %.2f / %.2f | %s%s%s",
        tostring(brain.fullname), square:getX(), square:getY(), now, hurt, max,
        why, partUsed and " (body part)" or "", shardDeep and " deep-shard" or ""))
end

--- Drain somebody who is bleeding, once per autonomy sweep.
---
--- IT LIVES IN A FILE WHOSE OTHER SWEEP FUNCTION IS CALLED CheckGlass, and that is deliberate
--- rather than untidy. ScenesRelationsAutonomy already calls Wounds.CheckGlass once per NPC
--- per sweep with the brain and the mood in hand (ScenesRelationsAutonomy.lua:1462-1464); a
--- second registration walking the same NPCs to ask one more question about the same people
--- would be pure waste, and the call site belongs to another module that this change does not
--- touch. So the drain is invoked from there, in its own function, with its own log.
---
--- ONLY IN RANGE. That sweep skips anybody past NPC_RANGE (ScenesRelationsAutonomy.lua:1307),
--- so a bleeding person who wanders off neither drains nor advances the bound, and picks up
--- exactly where they left off when they come back. That is the right lifetime: we are not
--- simulating people we cannot see, and freezing both halves together means the bound still
--- measures what it claims to -- sweeps spent bleeding WHERE WE COULD HAVE HELPED.
local function bleedTick(zombie, brain)
    local wound = brain.scenesWound
    if not wound or not wound.bleeding then return end

    local name = tostring(brain.fullname)
    wound.bleedSweeps = (wound.bleedSweeps or 0) + 1

    local ok, now = pcall(function() return zombie:getHealth() end)
    if ok and type(now) == "number" and now > HEALTH_FLOOR then
        local drained = math.max(HEALTH_FLOOR, now - BLEED_PER_SWEEP)
        local set = pcall(function() zombie:setHealth(drained) end)
        if not set then
            SR.Log("WOUND could not drain " .. name .. " -- setHealth threw")
        elseif (wound.bleedSweeps % BLEED_LOG_EVERY) == 0 then
            SR.Log(string.format("WOUND %s still bleeding | %.2f -> %.2f | sweep %d of %d",
                name, now, drained, wound.bleedSweeps, BLEED_MAX_SWEEPS))
        end
    end

    -- THE BOUND. Not a cure and never described as one -- see BLEED_MAX_SWEEPS for the four
    -- ways the real clear can be unreachable. Reaching this means one of them happened, so the
    -- line says so in words somebody reading console.txt on another machine can act on.
    if wound.bleedSweeps >= BLEED_MAX_SWEEPS then
        wound.bleeding, wound.bleedDay, wound.bleedSweeps = nil, nil, nil
        Wounds.ClearBodyBleeding(brain)
        SR.Log(string.format(
            "WOUND %s bled for %d sweeps without ever completing a Bandage -- bound reached, "
            .. "bleed dropped. Check their program and whether Main is being reached at all",
            name, BLEED_MAX_SWEEPS))
    end
end

--- Cut them if they are standing in a broken frame, and bleed them if they already are.
---
--- Called from the autonomy sweep, which already holds the brain, the mood and the square,
--- so this costs one getWindow per NPC per sweep and no second pass over anything.
---
--- WHAT THE 10-08 FIRST PASS CLAIMED, AND WHY THE CLAIM WAS WRONG. It said the OpenWindow
--- hook below "catches the moment they open the window, which is the single most likely
--- crossing". It does not, and the reason is in Bandits: OpenWindow is queued at one site,
--- under `not object:isSmashed()`
--- (vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:672, task at :677-678).
--- A window with glass in it never produces that task. The hook is kept because a window CAN
--- be smashed between the task being queued and completing, but that is a race and not the
--- crossing path. The crossing path is the climb watcher at the bottom of this file.
---
--- WHAT THIS FUNCTION IS ACTUALLY FOR, THEN: an NPC who LINGERS in a smashed frame -- which
--- the six-second sample is well suited to and the one-second climb watcher would miss, since
--- somebody standing still enters no state at all. The two are complements, not rivals.
---
--- THE BLEED TICK RIDES HERE. Above the glass test on purpose: the early return below fires
--- for everybody who is not standing in glass, which is nearly everybody, and a bleeding
--- person standing in a corridor still has to bleed.
function Wounds.CheckGlass(zombie, brain, mood, square)
    bleedTick(zombie, brain)

    if not glassOnSquare(square) then
        mood.cutAt = nil
        return false
    end

    -- Already bled for this one recently.
    if mood.cutAt and mood.cutAt > 0 then
        mood.cutAt = mood.cutAt - 1
        return false
    end

    applyGlassCut(zombie, brain, mood, square, "sweep")
    return true
end

-- OPEN-WINDOW HOOK ----------------------------------------------------------------------
--
-- THIS COMMENT USED TO SAY THIS HOOK WAS THE MAIN CROSSING PATH. IT IS NOT, and the correction
-- matters more than the code under it. The old text read: "Wrapping OpenWindow.onComplete
-- catches it at the one moment every window crossing shares". Every window crossing does NOT
-- share it. Bandits queues OpenWindow at exactly one place, and that place is inside
-- `elseif not object:IsOpen() and not object:isSmashed() ...`
-- (vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:672, the task itself at
-- :677-678). A window with glass still in it is smashed by definition, so it never produces an
-- OpenWindow task, so this hook's glass test is false almost every time it runs.
--
-- WHY IT IS KEPT ANYWAY. There is one sequence it does catch and nothing else does: the window
-- was intact when the task was queued and something smashed it -- the player, a zombie, another
-- NPC -- while the 25-unit action played out. Then the glass is there, the NPC finishes opening
-- the frame, and this is the only code looking. Cheap, correct, and unreachable by the climb
-- watcher, which fires on the state change and not on the task.
--
-- WHY NOT ZASmashWindow. SmashWindow is a deliberate act that already implies the glass is
-- gone; OpenWindow is the one where an unaware NPC walks into a frame that still has teeth.
local vanillaOpenWindowComplete

local function scenesOpenWindowComplete(zombie, task)
    -- Run the original first -- the window must actually open.
    local result = vanillaOpenWindowComplete(zombie, task)

    -- Now check: was there glass on this square that we should have cut them for?
    -- We read the square and the window AFTER the original toggles it, so a window
    -- that was intact before opening will now be IsOpen() and never was smashed.
    -- But a window that was ALREADY smashed when they arrived will still read smashed,
    -- and if the glass was never removed, they should have been cut.
    --
    -- The sweep checker and this hook share one cooldown (mood.cutAt), so a frame caught by
    -- both of them only bleeds once. The climb watcher deliberately does NOT honour that
    -- cooldown -- see the note at its call to applyGlassCut for why -- but it does SET it, so
    -- a cut it applies still suppresses these two for the next CUT_COOLDOWN sweeps.
    local brain = BanditBrain.Get(zombie)
    local mood = brain and SR.Mood(zombie)
    -- `mood` is nil when the entity has no modData. It never has been in play, but this runs
    -- inside somebody else's onComplete with no pcall around it, so a nil index here would
    -- take their action down with it.
    if brain and mood then
        local square = zombie:getSquare()
        if glassOnSquare(square) and not (mood.cutAt and mood.cutAt > 0) then
            applyGlassCut(zombie, brain, mood, square, "window-open")
        end
    end

    return result
end

-- THE CLIMB WATCHER ----------------------------------------------------------------------
--
-- THIS IS THE PATH THAT ACTUALLY CUTS PEOPLE, and it exists because there is nothing to wrap.
-- Bandits crosses a window by changing engine state, not by queueing a task
-- (vendor/Bandits/mods/Bandits/42.20/media/lua/client/BanditUpdate.lua:684-686), and there is
-- no ZAClimbWindow in their ZombieActions folder. Coming back in through a window that is
-- already open queues nothing at all -- which is precisely the reported asymmetry, "funciono
-- solo cuando salio, pero no cuando entro por la ventana rota de nuevo".
--
-- So the crossing is read from the state itself. `isCurrentState(ClimbThroughWindowState
-- .instance())` is vanilla and is used in exactly this form at
-- pzserver/media/lua/client/Tutorial/Steps.lua:1564 and :1570; Steps.lua:891 writes the same
-- test as `getCurrentState() == ClimbThroughWindowState.instance()`.
--
-- VANILLA ONLY EVER CALLS IT ON getPlayer(). Every one of those three lines is on the player
-- object. An IsoZombie is a different class and "the method is on the class" has already cost
-- this project a session once -- getSeeNearbyCharacterDistance existed and was not callable.
-- So the first call decides for the session and the answer is remembered, exactly the way
-- masterIsRunning does it in ScenesRelationsAutonomy.lua:487-504. A missing method degrades to
-- the sweep and the OpenWindow hook, which is what shipped before this change, and it logs
-- ONCE -- a line per NPC per 200 ms would bury console.txt in a minute.

local climbStateCallable

local function isClimbingWindow(zombie)
    if climbStateCallable == false then return false end

    local ok, climbing = pcall(function()
        return zombie:isCurrentState(ClimbThroughWindowState.instance())
    end)
    if not ok then
        if climbStateCallable == nil then
            SR.Log("WOUND isCurrentState(ClimbThroughWindowState) is not callable on an "
                .. "IsoZombie -- window crossings fall back to the sweep and the OpenWindow "
                .. "hook for the rest of the session")
        end
        climbStateCallable = false
        return false
    end

    climbStateCallable = true
    return climbing == true
end

-- HOW OFTEN TO LOOK, AND THE ARITHMETIC BEHIND IT. A crossing is about one second: Bandits
-- hands the character to ClimbThroughWindowState and the engine carries it through. At 200 ms
-- that is 1000 / 200 = 5 samples per crossing, so the state cannot begin and end unseen unless
-- the entire crossing does. The 800 ms lane in ScenesRelationsAutonomy would give barely one
-- sample and a rising edge sampled once is a coin toss, which is why this module gets a lane
-- of its own rather than borrowing that one.
local CLIMB_TICK_MS = 200

-- The floor between two cuts on the same person, in milliseconds.
--
-- THE EDGE ALONE IS ALMOST ENOUGH AND THIS IS THE SECOND GUARD. A cut needs a rising edge,
-- which needs a not-climbing sample in between, which is already 200 ms of the state genuinely
-- being over. This adds a floor of 600 ms -- three samples -- so a flicker in the state cannot
-- read as a second crossing. It cannot swallow a real one: a crossing takes ~1 s to finish and
-- the return leg needs the NPC to land, be re-decided and face the frame again, so two genuine
-- rising edges are seconds apart, not tenths. It is a timestamp compared against a clock that
-- only moves forwards WITHIN A SESSION, so nothing about it can stick -- see climbCutMs for
-- why "within a session" is doing real work in that sentence.
local CLIMB_RECUT_MS = 600

-- Maximum time (ms) the climb state is allowed to persist before forcing the cut.
-- A window climb takes about 1 second from changeState() to the visible landing.
-- ClimbThroughWindowState can remain active for seconds after the animation ends
-- while the engine finalizes position transitions, causing the cut to be delayed.
-- BOTH OF THESE ARE FILE-LOCALS AND NEITHER IS A FIELD ON SR.Mood, and the second one is a bug
-- that was written and then caught before it shipped. SR.Mood lives on the entity's modData,
-- which is SAVED (shared/ScenesRelations.lua:202-207 -- and its own comment says posture is
-- "meaningless after a reload", which is the same argument).
--
--   climbSeen   who is inside ClimbThroughWindowState right now. A per-sample boolean has no
--               business surviving a reload.
--   climbCutMs  when we last cut somebody mid-climb, by getTimestampMs().
--
-- WHY climbCutMs ESPECIALLY MUST NOT PERSIST. Written on SR.Mood first. Every vanilla use of
-- getTimestampMs keeps it on a transient object -- an action, a cursor, a UI element
-- (pzserver/media/lua/client/TimedActions/ISInventoryTransferAction.lua:253 and :775,
-- .../Vehicles/TimedActions/ISHorn.lua:10 and :16) -- and not one of them saves it, so whether
-- the clock is epoch-based or since-process-start is a question the engine has never had to
-- answer in Lua. If it restarts near zero, a saved stamp from the previous session is larger
-- than `now`, `now - stamp` is negative, negative is less than 600, and every crossing reads as
-- "just cut them" -- the feature silently dead after every reload, which is exactly the class of
-- defect this project keeps paying for. Keeping the stamp in the session makes the question
-- irrelevant instead of answered by guesswork. ScenesRelationsAutonomy.lua:454, :464 and :469
-- keeps lastSwingMs on a file-local for the same reason.
--
-- BOTH ARE PRUNED IN THE SAME PASS at the bottom of watchClimbs: any id the live cache no
-- longer lists is dropped, so neither table can outgrow the NPCs actually in the world.
local climbSeen = {}
local climbCutMs = {}

local lastClimbMs = 0

-- Shared cut-application extracted so both the falling-edge path and the
-- timeout path produce the same guard check, recut floor and log line.
-- Called with the closured zombie, the bandit id and the entry table.
local function doClimbCut(zombie, id, entry)
    local brain = BanditBrain.Get(zombie)
    local mood = brain and SR.Mood(zombie)
    if not brain or not mood then return end
    if brain.hostile or brain.hostileP then return end
    if SR.IsStillOurs and not SR.IsStillOurs(zombie) then return end

    local last = climbCutMs[id]
    local nowMs = getTimestampMs()
    local recent = last and (nowMs - last) < CLIMB_RECUT_MS
    if not recent then
        climbCutMs[id] = nowMs
        applyGlassCut(zombie, brain, mood, entry.square, "window-climb")
    end
end

local function watchClimbs()
    local now = getTimestampMs()
    if now - lastClimbMs < CLIMB_TICK_MS then return end
    lastClimbMs = now

    -- The probe already answered no once. Nothing below can start working again, so stop
    -- paying for the walk.
    if climbStateCallable == false then return end
    if not BanditZombie or not BanditZombie.GetAllB then return end

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            -- THE STATE IS SAMPLED BEFORE ANYTHING ELSE IS LOOKED UP, and that ordering is
            -- what keeps a 200 ms lane affordable. Nearly every sample is "not climbing", and
            -- that answer costs one engine call -- no brain fetch, no modData, no square walk.
            -- The expensive half only runs on the frame somebody actually starts a crossing.
            local isClimb = isClimbingWindow(zombie)

            if isClimb and not climbSeen[id] then
                -- RISING EDGE. Just started crossing. Remember where glass was AND
                -- where the NPC is standing -- if the climb is cancelled (blocked by
                -- a zombie, a player or an obstacle on the other side), the position
                -- won't change and we skip the cut.
                local bx, by = zombie:getX(), zombie:getY()
                climbSeen[id] = { square = crossingGlassSquare(zombie),
                                  sx = bx, sy = by }

            elseif not isClimb and climbSeen[id] then
                -- FALLING EDGE. The engine released ClimbThroughWindowState.
                -- Only apply the cut if the NPC actually moved -- a cancelled climb
                -- (blocked exit, stuck on furniture) leaves them on the same tile.
                local entry = climbSeen[id]
                climbSeen[id] = nil

                if entry.square then
                    local ex, ey = zombie:getX(), zombie:getY()
                    local dx, dy = ex - (entry.sx or ex), ey - (entry.sy or ey)
                    local moved = (dx * dx + dy * dy) > 0.09  -- 0.3^2, ~one third of a tile
                    if moved then
                        doClimbCut(zombie, id, entry)
                    end
                end
            end
        end
    end

    -- Drop anybody the live cache no longer lists, from both tables. See the note above them.
    -- Setting an EXISTING key to nil during pairs() is the one mutation Lua 5.1 permits mid
    -- traversal, which is why this is written as a delete and never as an insert.
    for id, _ in pairs(climbSeen) do
        if bandits[id] == nil then climbSeen[id] = nil end
    end
    for id, _ in pairs(climbCutMs) do
        if bandits[id] == nil then climbCutMs[id] = nil end
    end
end

-- INSTALL ------------------------------------------------------------------------------

function Wounds.Install()
    if vanillaBandageComplete then return true end

    local ok = true

    if not ZombieActions or not ZombieActions.Bandage
       or type(ZombieActions.Bandage.onComplete) ~= "function" then
        SR.Log("WOUND could not install -- ZombieActions.Bandage.onComplete is not there")
        ok = false
    else
        vanillaBandageComplete = ZombieActions.Bandage.onComplete
        ZombieActions.Bandage.onComplete = scenesBandageComplete
    end

    -- The OpenWindow hook covers the one race the climb watcher cannot: a window smashed
    -- while the open action was already playing. See the block above it for why it is NOT the
    -- crossing path, which the first version of this comment got wrong. Bandits' ZAOpenWindow
    -- exists (vendor/Bandits/mods/Bandits/42.20/media/lua/shared/ZombieActions/ZAOpenWindow.lua:19),
    -- and if it ever doesn't, glass still works through the watcher and the sweep.
    if ZombieActions and ZombieActions.OpenWindow
       and type(ZombieActions.OpenWindow.onComplete) == "function"
       and not vanillaOpenWindowComplete then
        vanillaOpenWindowComplete = ZombieActions.OpenWindow.onComplete
        ZombieActions.OpenWindow.onComplete = scenesOpenWindowComplete
    end

    return ok
end

-- REGISTERED ONCE, AT FILE SCOPE. Not inside Install and not inside OnGameStart: this file is
-- read once per session, so one registration here is one handler. Registering from inside
-- another handler is how a mod ends up running the same sweep four times and degrading the
-- save, and Install is called from OnGameStart.
Events.OnTick.Add(watchClimbs)

Events.OnGameStart.Add(function()
    if Wounds.Install() then
        SR.Log(string.format(
            "WOUND ready -- healing costs a dressing; every window crossing costs blood "
            .. "(climb watcher every %d ms, both directions); a cut bleeds %.2f per sweep "
            .. "until a Bandage completes, bound %d sweeps; %d body part slots tracked",
            CLIMB_TICK_MS, BLEED_PER_SWEEP, BLEED_MAX_SWEEPS, #ALL_BODY_PARTS))
    end
end)
