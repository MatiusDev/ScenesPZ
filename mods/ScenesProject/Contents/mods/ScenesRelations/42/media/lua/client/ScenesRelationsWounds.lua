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
--   * below 0.7 they bleed, at 0.00005 per tick, forever (ManageHealth, :491-501);
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
function Wounds.Of(brain)
    if not brain.scenesWound then
        brain.scenesWound = { dressing = nil, day = nil }
    end
    return brain.scenesWound
end

-- Absolute health at which Bandits starts draining somebody (ManageHealth,
-- BanditUpdate.lua:491). Not a ratio: their bleed test is absolute, so ours is too, or a
-- frail survivor would be judged healthy while bleeding out.
local BLEED_FLOOR = 0.7

-- In-game hours before somebody will try dressing a wound again. Without it, a survivor
-- still under the floor after an improvised dressing would re-dress every few seconds and
-- burn every rag they own.
local REDRESS_HOURS = 2

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
function Wounds.NeedsDressing(zombie, brain)
    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return false end
    if now >= BLEED_FLOOR then return false end

    local wound = brain.scenesWound
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

    SR.Log(string.format("WOUND %s dressed with %s | %.2f -> %.2f / %.2f | risky=%s",
        name, kind, before, healed, max, tostring(takesRisks(brain))))

    return true
end

-- GLASS --------------------------------------------------------------------------------

--- Is there broken glass in the frame on this square?
---
--- `isSmashed() and not isGlassRemoved()` is vanilla's own test for exactly this -- it is
--- the isValid of ISRemoveBrokenGlass (line 6), the action a player takes precisely so they
--- can climb through without being cut.
local function glassOnSquare(square)
    if not square then return false end
    local ok, window = pcall(function() return square:getWindow() end)
    if not ok or not window then return false end

    local smashed, removed = false, true
    pcall(function()
        smashed = window:isSmashed()
        removed = window:isGlassRemoved()
    end)
    return smashed and not removed
end

--- Cut an NPC and log it. Shared by both the sweep checker and the OpenWindow hook so the
--- two paths produce the same line and the same cooldown.
local function applyGlassCut(zombie, brain, mood, square, why)
    local max = tonumber(brain.health) or 2
    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return end

    local hurt = math.max(0.05, now - GLASS_DAMAGE)
    pcall(function() zombie:setHealth(hurt) end)

    Wounds.Of(brain).dressing = nil
    mood.cutAt = CUT_COOLDOWN

    pcall(function() Bandit.Say(zombie, "HIT") end)

    SR.Log(string.format("WOUND %s cut on broken glass at %d,%d | %.2f -> %.2f / %.2f | %s",
        tostring(brain.fullname), square:getX(), square:getY(), now, hurt, max, why))
end

--- Cut them if they are standing in a broken frame.
---
--- Called from the autonomy sweep, which already holds the brain, the mood and the square,
--- so this costs one getWindow per NPC per sweep and no second pass over anything.
---
--- WHAT THE 10-08 SESSION CHANGED. The sweep runs about every six seconds, so an NPC that
--- crosses a window entirely between two sweeps is not caught. The OpenWindow hook below
--- catches the moment they open the window, which is the single most likely crossing; the
--- sweep catches the rest -- an NPC that loiters on a smashed frame, or that pathfinds
--- through one the engine already knows about.
function Wounds.CheckGlass(zombie, brain, mood, square)
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
-- THE GAP THE SWEEP CANNOT CLOSE. CheckGlass samples every ~6 s and catches an NPC who
-- LINGERS on a smashed frame. But the common case is: NPC reaches a window, Bandits queues
-- OpenWindow (time=60, ~1 s), they open it, and the engine pathfinds them through in under
-- a second. If that whole sequence happens between two sweeps, the cut is never applied.
--
-- Wrapping OpenWindow.onComplete catches it at the one moment every window crossing shares:
-- the completion of the OpenWindow task. At that point the window HAS been toggled, so we
-- check the square they are about to cross -- BEFORE the engine carries them through.
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
    -- The sweep checker and this hook share one cooldown (mood.cutAt), so a crossing
    -- caught by both paths only bleeds once.
    local brain = BanditBrain.Get(zombie)
    if brain then
        local mood = SR.Mood(zombie)
        local square = zombie:getSquare()
        if glassOnSquare(square) and not (mood.cutAt and mood.cutAt > 0) then
            applyGlassCut(zombie, brain, mood, square, "window-open")
        end
    end

    return result
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

    -- The OpenWindow hook catches window crossings the sweep-based CheckGlass misses.
    -- Bandits' ZAOpenWindow exists (verified in 42.20 media/lua/shared/ZombieActions/),
    -- and if it ever doesn't, glass still works through the sweep alone.
    if ZombieActions and ZombieActions.OpenWindow
       and type(ZombieActions.OpenWindow.onComplete) == "function"
       and not vanillaOpenWindowComplete then
        vanillaOpenWindowComplete = ZombieActions.OpenWindow.onComplete
        ZombieActions.OpenWindow.onComplete = scenesOpenWindowComplete
    end

    return ok
end

Events.OnGameStart.Add(function()
    if Wounds.Install() then
        SR.Log("WOUND ready -- healing costs a dressing; broken glass costs blood; window-open hook catches crossings the sweep misses")
    end
end)
