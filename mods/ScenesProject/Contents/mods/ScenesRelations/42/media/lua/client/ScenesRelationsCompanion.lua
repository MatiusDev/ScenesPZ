-- ScenesPZ -- our companion behaviour, wrapped around theirs.
--
-- ASKED FOR IN THESE WORDS
--   "Vamos a pisar algunos de los comportamientos de ZPCompanion... este mod debe reutilizar
--    algunos de esos comportamientos y sobreescribir los que tenga y no nos sirvan."
--
-- HOW THIS OVERRIDES WITHOUT REPLACING
-- ZombiePrograms.Companion.Main is captured once and kept. Our function decides only the
-- cases we have an opinion about and hands everything else back to theirs, unchanged. So
-- their combat, their weapon handling, their guardposts, their vehicle logic and their
-- follow-the-master fallback all still run, and still get fixed when Slayer fixes them.
--
-- That is the difference between overriding and replacing, and it is worth being strict
-- about: a full reimplementation of Main would be about 400 lines of theirs that we would
-- own forever, in order to change maybe forty.
--
-- WHAT WE TAKE OVER, AND WHY EACH ONE
--
-- 1. SEARCHING A HOUSE. Theirs cannot: BanditPrograms.Container.Loot is dead code (see
--    ScenesRelationsLoot.lua) and the whole block calling it is commented out. This is not
--    a preference, it is a gap.
--
-- 2. FINDING A BAG FIRST. brain.bag is set at spawn and there has never been any way to
--    acquire one. Somebody with no bag fills up in three items, so the bag is worth more
--    than anything it would carry -- it changes what every future search is worth.
--
-- 3. KILLING QUIETLY INDOORS. Their combat picks a firearm whenever one is loaded and in
--    range. Inside a house that is how a cleared building becomes a busy one.
--
-- 4. STANDING AROUND. This is the one that was reported as a bug and is really a design
--    gap: "si yo me siento ellos se quedan quietos". When the master stops, their Main
--    falls through to BanditPrograms.Idle, which is a bag of nervous fidget animations --
--    ChewNails, Sneeze, WipeBrow. So a companion in a secured house looks like it is
--    waiting for a bus.
--
--    The rule asked for is a limit on mirroring: "debe haber un limite de cosas que ellos
--    deben replicar, no es necesario que sea absolutamente todo... sentarse unicamente si
--    realmente se sienten cansados o por autonomia propia". So they do NOT copy you
--    sitting. They sit when they are tired, or because that is who they are, and otherwise
--    they watch the way trouble would come from.
--
-- THE ONE THING THIS FILE DOES NOT DECIDE
-- Which rung somebody is on. That is ScenesRelationsAutonomy, and it also owns the
-- indoor/outdoor threat measurement this file reads. Two modules measuring the same street
-- is R6, and the threat module already made that mistake once. Everything here reads
-- SR.Mood and never counts a zombie itself.

require "ScenesRelations"
require "ScenesRelationsAutonomy"
require "ScenesRelationsLoot"
require "BanditPlayer"

local SR = ScenesRelations

SR.Companion = SR.Companion or {}

-- Tiles. Inside this, a companion is "with you" and may do something other than close the
-- gap. ZPCompanion walks in until it is within 1, which is why one has never been seen
-- doing anything at all while you stand still.
local FREE_RADIUS = 7

-- brain.endurance is 0..1, spawns at 1.00 (BanditServerSpawner.lua:314) and -- this is the
-- part that matters -- ONLY EVER DECREASES. Bandit.UpdateEndurance is called from exactly
-- one place, BanditUpdate.lua:1823, applying task.endurance, and every program in the
-- framework passes 0.00 or a negative. Nothing in Bandits gives it back.
--
-- So a raw threshold would make tiredness permanent: run once, sit forever. Resting has to
-- restore it, which the same mechanism does for free -- a positive task.endurance is
-- applied by their own loop when the task completes.
-- BEING TIRED IS NOW REQUIRED, AND IT WAS NOT BEFORE. The 04-08 log:
--
--   23x  COMP John Jones sits down (just the sort) | endurance 1.00
--
-- Twenty-one of the thirty-eight sits in that run happened at FULL endurance, several of
-- them outdoors -- `outdoors ... head=Sleep@nil,nil` is in the census. The idler branch
-- ignored endurance entirely, so one survivor in five simply sat down whenever nothing was
-- happening, anywhere. Reported as "se sienta demasiado, incluso cuando no estamos en la
-- casa. Creo que una de las condiciones para que el se quiera sentar es que se encuentre
-- cansado", which is exactly right.
--
-- So tiredness gates every sit. Being the lazy sort only moves WHERE the line is.
local TIRED = 0.55           -- anybody gives in below this
local IDLER_TIRED = 0.80     -- the lazy sort gives in sooner, but still has to be tired
local OUTDOOR_TIRED = 0.25   -- sitting down in the open takes real exhaustion

local REST_RECOVERY = 0.25
local REST_TIME = 300

-- Reading is longer and restores more: it is the one thing here somebody does because they
-- want to rather than because their legs gave out.
local READ_TIME = 600
local READ_RECOVERY = 0.35

-- Who sits down sooner because that is who they are. brain.rnd[4] is ZombRand(1000), fixed
-- at spawn. One person in five, and the same one every time -- the whole point of reading a
-- stable field instead of rolling a die.
local function isIdler(brain)
    if type(brain.rnd) ~= "table" or not brain.rnd[4] then return false end
    return (brain.rnd[4] % 100) < 20
end

-- Who reads. rnd[5] is ZombRand(10000) and was the last unallocated slot; a quarter of
-- survivors will sit down with a book if they happen to be carrying one.
local function isReader(brain)
    if type(brain.rnd) ~= "table" or not brain.rnd[5] then return false end
    return (brain.rnd[5] % 100) < 25
end

--- Something to read, or nil. `instanceof(item, "Literature")` is vanilla's own test
--- (ISInventoryPaneContextMenu.lua:329) and covers books, magazines and skill manuals
--- without naming any of them.
local function bookInBag(zombie)
    local inventory = zombie:getInventory()
    if not inventory then return nil end
    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or not items then return nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and instanceof(item, "Literature") then return item end
    end
    return nil
end

local function enduranceOf(brain)
    local value = tonumber(brain.endurance)
    if not value then return 1 end
    return value
end

-- QUIET KILLS --------------------------------------------------------------------------

--- Put the melee weapon in their hands.
---
--- Their combat sets `firing = true` only when `bandit:isPrimaryEquipped(gun)`
--- (BanditUpdate.lua:1123). Equipping the melee weapon therefore makes the quiet choice the
--- only choice, without touching their targeting at all -- we change what is in the hand,
--- they decide what to do with it.
---
--- Returns a task, or nil when there is nothing to change.
local function quietWeaponTask(bandit, brain)
    local weapons = Bandit.GetWeapons(bandit)
    if not weapons or not weapons.melee then return nil end
    if weapons.melee == "Base.BareHands" then return nil end

    local ok, equipped = pcall(function() return bandit:isPrimaryEquipped(weapons.melee) end)
    if not ok or equipped then return nil end

    return { action = "Equip", itemPrimary = weapons.melee, time = 60 }
end

-- RESTING ------------------------------------------------------------------------------

--- What somebody does when the master has stopped and there is nothing to do.
---
--- The replacement for falling through to BanditPrograms.Idle, which fidgets. Note what is
--- deliberately absent: any reading of whether the PLAYER is sitting. Mirroring the player
--- is ZPCompanion's job and it correctly covers movement -- sprint, sneak, aim, limp. Where
--- to put your body when nothing is happening is a decision about yourself.
local function restTasks(bandit, brain, mood)
    local endurance = enduranceOf(brain)

    -- Where the line sits depends on where THEY are and who they are, but there is always a
    -- line. Nobody sits down at full endurance any more, and nobody sits down in the open
    -- unless they are genuinely spent.
    local threshold
    if not mood.indoors then
        threshold = OUTDOOR_TIRED
    elseif isIdler(brain) then
        threshold = IDLER_TIRED
    else
        threshold = TIRED
    end

    if endurance < threshold then
        -- The positive endurance is the important half. It is applied by their loop when
        -- the task completes (BanditUpdate.lua:1822-1824), which makes resting the only
        -- thing in the entire framework that gives endurance back.
        --
        -- The lazy sort gets an anim that looks occupied rather than blank. Sit, SitAction,
        -- SitMaking and SitRubHands are all real -- ZPCamper uses all four -- so this is
        -- flavour taken from what exists, not a new animation.
        local anim = isIdler(brain) and "SitRubHands" or "Sit"

        SR.Log(string.format("COMP %s sits down | endurance %.2f < %.2f | %s%s",
            tostring(brain.fullname), endurance, threshold,
            mood.indoors and "indoors" or "outdoors",
            isIdler(brain) and ", the lazy sort" or ""))

        return { { action = "Sleep", anim = anim, time = REST_TIME,
                   endurance = REST_RECOVERY } }
    end

    -- Not tired, not the sitting sort: watch the way trouble would come from. This is what
    -- "no es necesario que sea absolutamente todo" leaves room for -- they are still doing
    -- something, it is just not a copy of you.
    local ok, closest = pcall(function() return BanditUtils.GetClosestZombieLocation(bandit) end)
    if ok and closest and closest.dist and closest.dist < 24 then
        return { { action = "FaceLocation", x = closest.x, y = closest.y, time = 100 } }
    end

    return nil
end

-- THE WRAPPER --------------------------------------------------------------------------

local vanillaMain

local function scenesMain(bandit)
    local brain = BanditBrain.Get(bandit)
    local mood = brain and SR.Mood(bandit)

    -- Anything we cannot read is theirs. Never guess about a companion.
    if not brain or not mood or not mood.rung then return vanillaMain(bandit) end

    local rung = mood.rung
    local name = tostring(brain.fullname)

    -- SURVIVING is not ours. Their flee logic and our shelter module already own it, and a
    -- third opinion during the one moment that matters is the worst place for one.
    if rung == SR.Autonomy.SURVIVE then return vanillaMain(bandit) end

    -- FIGHTING is theirs too -- but indoors we change what is in the hand first.
    if rung == SR.Autonomy.FIGHT then
        if mood.indoors then
            -- Bounded, and this matters more than it looks. Their combat re-equips the
            -- primary itself whenever an enemy comes into range (BanditUpdate.lua:1126,
            -- `switch = true`). Insisting every time Main runs would be two systems pulling
            -- at the same hands forever, and an NPC that never swings at anything. Two
            -- attempts per building is a preference; a permanent one would be a deadlock.
            mood.quietTries = mood.quietTries or 0
            if mood.quietTries < 2 then
                local task = quietWeaponTask(bandit, brain)
                if task then
                    mood.quietTries = mood.quietTries + 1
                    SR.Log(string.format("COMP %s goes quiet indoors (try %d) | in=%d out=%d",
                        name, mood.quietTries, mood.insiders or 0, mood.outsiders or 0))
                    return { status = true, next = "Main", tasks = { task } }
                end
            end
        else
            -- Outside again: next building gets a fresh pair of attempts.
            mood.quietTries = nil
        end
        return vanillaMain(bandit)
    end

    local master = BanditPlayer.GetMasterPlayer(bandit)
    if not master then return vanillaMain(bandit) end

    local dist = BanditUtils.DistTo(bandit:getX(), bandit:getY(), master:getX(), master:getY())

    -- Too far to be doing anything but closing the gap. Their follow code is at the bottom
    -- of Main and is correct; the ladder has already made sure they reach it.
    if dist > FREE_RADIUS then return vanillaMain(bandit) end

    -- FINISHING A BAG PICKUP. Checked before starting anything new, and only once the item
    -- is genuinely theirs -- somebody else may have taken it first, or the walk may have
    -- been cleared by the ladder. Wearing a bag they do not have would put a rucksack on a
    -- model with nothing in it, which is worse than not looting at all because it is
    -- invisible until you wonder why they still fill up in three items.
    if mood.fetchingBag then
        local pending = mood.fetchingBag
        mood.fetchingBag = nil

        local inventory = bandit:getInventory()
        local ok, held = pcall(function()
            return inventory and inventory:getItemCountFromTypeRecurse(pending) or 0
        end)

        if ok and held and held > 0 then
            SR.Loot.WearBag(bandit, brain, pending)
        else
            SR.Log(string.format("COMP %s did not get the %s -- somebody else took it",
                name, pending))
        end
        return { status = true, next = "Main", tasks = {} }
    end

    -- Whatever we were on is over: either it finished, or the ladder cleared it and moved
    -- the intention to mood.unfinished on its way past. Being asked again IS the signal --
    -- Main only runs on an empty queue.
    mood.doing = nil
    SR.Autonomy.ForgetIfStale(mood)

    -- BLEEDING BEATS EVERYTHING ELSE THEY MIGHT WANT.
    --
    -- Their own healing trigger cannot fire while the ladder is running -- it is gated on
    -- the queue holding nothing but movement -- and the 04-08 log shows what that costs:
    -- John Jones opened in the health panel at `condition 0.02 / 1.80`, infected, and not
    -- one `dressed with` line in the whole session. So the decision to start is ours. The
    -- action, the animation and the sound stay theirs.
    if SR.Wounds and SR.Wounds.NeedsDressing(bandit, brain) then
        SR.Log(string.format("COMP %s stops to dress a wound", name))
        return { status = true, next = "Main", tasks = { { action = "Bandage" } } }
    end

    -- GOING BACK TO WHAT THEY WERE DOING. The stage's own done-criterion, in its words:
    -- "a survivor interrupted while looting kills the zombie and returns to the container".
    -- The ladder set this aside when it escalated; nothing else remembers it.
    if mood.unfinished then
        local job = mood.unfinished
        mood.unfinished, mood.unfinishedAt = nil, nil

        local back = BanditUtils.DistTo(bandit:getX(), bandit:getY(), job.x + 0.5, job.y + 0.5)
        -- Only if it is still nearby. Walking back across a street to a drawer reads as
        -- obsession, not memory, and the ladder would only interrupt them again on the way.
        if back < 15 then
            if job.kind == "search" then
                mood.doing = job
                SR.Log(string.format("COMP %s goes back to the %s at %d,%d",
                    name, job.kind, job.x, job.y))
                return { status = true, next = "Main", tasks = SR.Loot.Search(bandit, mood, job) }
            elseif job.kind == "bag" and not SR.Loot.HasBag(brain) then
                mood.doing = job
                mood.fetchingBag = job.itemType
                SR.Log(string.format("COMP %s goes back for the %s at %d,%d",
                    name, tostring(job.itemType), job.x, job.y))
                return { status = true, next = "Main", tasks = SR.Loot.FetchBag(bandit, job) }
            end
        else
            SR.Log(string.format("COMP %s gives up on the %s -- %.1f tiles away now",
                name, tostring(job.kind), back))
        end
    end

    -- A BAG BEATS ANYTHING IT WOULD HOLD. Asked for directly, and it is also simply true:
    -- three items is not a scavenging trip.
    if not SR.Loot.HasBag(brain) then
        local bag = SR.Loot.FindBag(bandit)
        if bag then
            mood.fetchingBag = bag.itemType
            -- Recorded so the ladder can set it aside rather than lose it if something
            -- interrupts the walk. `kind` is what makes it resumable; the coordinates are
            -- what make it the SAME bag rather than any bag.
            mood.doing = { kind = "bag", itemType = bag.itemType,
                           x = bag.x, y = bag.y, z = bag.z }
            SR.Log(string.format("COMP %s wants a bag -- %s at %d,%d",
                name, bag.itemType, bag.x, bag.y))
            return { status = true, next = "Main", tasks = SR.Loot.FetchBag(bandit, bag) }
        end
    end

    -- SEARCHING. Only with nothing inside and nobody working on the walls -- the ladder has
    -- already put them on FIGHT if either were true, so reaching here IS the calm case.
    -- "si entramos en sigilo y no hay zombies golpeando la puerta, la actividad es lootear."
    if mood.indoors and SR.Loot.HasRoom(bandit) then
        local spot = SR.Loot.FindContainer(bandit, mood)
        if spot then
            mood.doing = { kind = "search", x = spot.x, y = spot.y, z = spot.z }
            SR.Log(string.format("COMP %s searches %d,%d | in=%d out=%d",
                name, spot.x, spot.y, mood.insiders or 0, mood.outsiders or 0))
            return { status = true, next = "Main", tasks = SR.Loot.Search(bandit, mood, spot) }
        end
    end

    -- READING. Deliberately BELOW searching and above resting, because that is the order
    -- asked for: "aun asi deberian de lootear o buscar cosas... que se siente y encole
    -- otras actividades como lotear... leer un libro si les gusta la lectura". Sitting is
    -- meant to read as a personality, not as a substitute for having one -- so a lazy
    -- survivor still empties the cupboards first and only then puts their feet up.
    --
    -- Indoors only. Reading a paperback in the middle of a street is not a character trait,
    -- it is a bug report waiting to happen.
    if mood.indoors and isReader(brain) and bookInBag(bandit) then
        SR.Log(string.format("COMP %s sits down with a book | endurance %.2f",
            name, enduranceOf(brain)))
        return { status = true, next = "Main", tasks = {
            { action = "Sleep", anim = "SitAction", time = READ_TIME,
              endurance = READ_RECOVERY },
        } }
    end

    -- NOTHING TO DO. Not their fidget loop.
    local tasks = restTasks(bandit, brain, mood)
    if tasks then return { status = true, next = "Main", tasks = tasks } end

    return vanillaMain(bandit)
end

--- Install once, and only over the function we actually captured.
---
--- Guarded because load order across mods is not something we control: if ZPCompanion has
--- not been read yet there is nothing to wrap, and wrapping our own wrapper on a second
--- call would make every decision run twice.
function SR.Companion.Install()
    if vanillaMain then return true end
    if not ZombiePrograms or not ZombiePrograms.Companion
       or type(ZombiePrograms.Companion.Main) ~= "function" then
        SR.Log("COMP could not install -- ZombiePrograms.Companion.Main is not there")
        return false
    end

    vanillaMain = ZombiePrograms.Companion.Main
    ZombiePrograms.Companion.Main = scenesMain
    return true
end

Events.OnGameStart.Add(function()
    if SR.Companion.Install() then
        SR.Log("COMP ready -- wraps ZPCompanion.Main: search, bags, quiet indoors, real rest")
    end
end)
