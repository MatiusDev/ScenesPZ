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
local TIRED = 0.55
local REST_RECOVERY = 0.25
local REST_TIME = 300

-- Who sits down because that is who they are. brain.rnd[4] is ZombRand(1000), fixed at
-- spawn, and unused by anything else -- rnd[2] is bravery and rnd[3] is taste in hats. One
-- person in five is the sort to sit when nothing is happening, and it is the same one every
-- time, which is the whole point of reading a stable field instead of rolling a die.
local function isIdler(brain)
    if type(brain.rnd) ~= "table" or not brain.rnd[4] then return false end
    return (brain.rnd[4] % 100) < 20
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
local function restTasks(bandit, brain)
    local tired = enduranceOf(brain) < TIRED

    if tired or isIdler(brain) then
        -- The positive endurance is the important half. It is applied by their loop when
        -- the task completes (BanditUpdate.lua:1822-1824), which makes sitting the only
        -- thing in the entire framework that gives endurance back.
        SR.Log(string.format("COMP %s sits down (%s) | endurance %.2f",
            tostring(brain.fullname),
            tired and "tired" or "just the sort", enduranceOf(brain)))

        return { { action = "Sleep", anim = "Sit", time = REST_TIME,
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

    -- A BAG BEATS ANYTHING IT WOULD HOLD. Asked for directly, and it is also simply true:
    -- three items is not a scavenging trip.
    if not SR.Loot.HasBag(brain) then
        local bag = SR.Loot.FindBag(bandit)
        if bag then
            mood.fetchingBag = bag.itemType
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
            SR.Log(string.format("COMP %s searches %d,%d | in=%d out=%d",
                name, spot.x, spot.y, mood.insiders or 0, mood.outsiders or 0))
            return { status = true, next = "Main", tasks = SR.Loot.Search(bandit, mood, spot) }
        end
    end

    -- NOTHING TO DO. Not their fidget loop.
    local tasks = restTasks(bandit, brain)
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
