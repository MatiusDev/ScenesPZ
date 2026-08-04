-- ScenesPZ -- what matters right now, and fear is what decides it.
--
-- WHY THIS EXISTS, IN THE WORDS THAT PRODUCED IT
--   "no ordenan bien su cola de actividades y no las priorizan, algunos hasta se buguean
--    abriendo una ventana y se quedan abriendola, y terminan siendo mordidos por la espalda"
--
-- Bandits is not missing behaviours. ZPCompanion ALREADY mirrors the player -- Run when you
-- sprint, SneakWalk when you crouch, WalkAim when you aim, Limp when hurt (ZPCompanion.lua
-- :38-56). Survivors already loot, climb, shelter and fight. The catch is one line of
-- framework design: a Bandits program only runs when the task queue is EMPTY. An NPC three
-- tasks deep into a window never reaches the code that would have noticed the zombie behind
-- it. It is not ignoring the situation. It never gets asked.
--
-- So this file adds no verbs. It decides which of the existing ones matters, and clears the
-- queue when something more important turns up.
--
-- WHAT THE 04-08 SESSION CHANGED, AND WHY
-- The first version shipped and the log said three things, all of them corrections:
--
-- 1. THE WATCHDOG WAS EATING GOOD WORK. It fired on `Smack` (mid-swing), on `Bandage`
--    (mid-heal) and on `Time` (a deliberate wait). Those tasks are SUPPOSED to sit at the
--    head of the queue for a while -- a fingerprint that does not change is how they look
--    when they are working correctly. It never once caught an OpenWindow. So the watchdog
--    now only arms on tasks whose completion depends on getting somewhere, and it also
--    requires that the NPC has not physically moved. Standing still is the honest signal
--    for stuck; a repeated signature on its own is not.
--
-- 2. FEAR RATCHETED AND NEVER CAME DOWN. Fear only decayed when NOTHING was near, so in a
--    zombie-populated street it climbed monotonically until everybody broke -- `fear=82/86`
--    off a SINGLE zombie is in the log. It is now a decaying average: it settles at a level
--    the situation justifies and falls the moment the situation improves.
--
-- 3. `brain.health` IS THE SPAWN MAXIMUM, NOT LIVE HEALTH. It is written once at
--    BanditServerSpawner.lua:332 as a Lerp into 1..2.6 and never touched again; the live
--    value is `bandit:getHealth()` (BanditUpdate.lua:955 reads exactly that). The hurt term
--    of the fear model was therefore reading a constant. Fixed, and the same mistake is
--    corrected in the wheel's "how are you holding up".
--
-- AND THE ONE THE PLAYER FELT MOST
--   "A veces era innecesario pelear... si yo salgo corriendo deben continuar corriendo"
--
-- That is upstream, and it is worth stating precisely because it is not our bug. In
-- ZPCompanion.Main, a companion within 20 tiles of its master that sees any enemy within 8
-- walks TO that enemy and RETURNS from the program -- it never reaches the follow-the-master
-- code at the bottom of the function. So a companion crossing a street with zombies in it
-- can never be following you; it is structurally unable to. We do not edit their file. We
-- take the decision away from it: when the master is plainly disengaging, this file asserts
-- a target-tracking move task of its own, and the engage branch is never asked.
--
-- THE LADDER
-- Lower number wins. Moving UP a rung clears the queue so the program re-decides from
-- scratch; drifting back down does not, because finishing what you started is correct.
--
--   1 SURVIVE  cornered, badly hurt, or more afraid than this person can bear
--   2 FIGHT    something is on top of them, or their master is swinging and they will help
--   3 OBEY     they accepted an order and have a master
--   4 ERRAND   they want something specific and are on their way to it
--   5 IDLE     nothing else

require "ScenesRelations"

local SR = ScenesRelations

SR.Autonomy = SR.Autonomy or {}
local Autonomy = SR.Autonomy

Autonomy.SURVIVE, Autonomy.FIGHT, Autonomy.OBEY, Autonomy.ERRAND, Autonomy.IDLE = 1, 2, 3, 4, 5

local RUNG_NAME = { "survive", "fight", "obey", "errand", "idle" }

-- Tiles. Only NPCs near the player are worth thinking about.
local NPC_RANGE = 40

-- Tiles. Something this close is ON them: there is no choice left but to deal with it.
-- Was 10, which meant any zombie in the street outranked every order the player had given.
local ENGAGE_RANGE = 4

-- Tiles. The master is swinging at something and this NPC is close enough to help. Wider
-- than ENGAGE_RANGE on purpose: joining a fight you started is the whole point of a
-- companion, and it is the one case where a distant zombie is still their business.
local ASSIST_RANGE = 8

-- Tiles. Past this a companion has lost its master and catching up is the only task that
-- matters. ZPCompanion switches to Run at 10, so 12 leaves it room to do its own job first.
local LEASH = 12

-- Tiles. What an NPC is frightened by. Wider than ENGAGE_RANGE -- you should be able to be
-- afraid of something you are not yet obliged to fight.
local FEAR_RADIUS = 9

-- Tiles. Who counts as backup.
local FRIEND_RANGE = 12

-- Fear is a decaying average, not an accumulator. Each sweep keeps this fraction of what
-- was there and adds what the situation justifies, so it settles at a level the moment
-- deserves and falls as soon as the moment passes. The old version only ever subtracted
-- when nothing at all was near, which in a populated street meant never.
local FEAR_KEEP = 0.6
local FEAR_PER_ZOMBIE = 6
local FEAR_OUTNUMBERED = 15
local FEAR_HURT = 20

-- Sweeps a task may sit unchanged, WITH THE NPC NOT MOVING, before it counts as stuck.
local STUCK_SWEEPS = 3

-- Tiles. Under this, two positions a sweep apart count as the same place. A working NPC
-- covers several tiles in six seconds; one wrestling a window latch covers none.
local MOVED_EPSILON = 0.6

-- Only these can stall in a way clearing the queue would fix: every one of them completes
-- by getting somewhere or interacting with something at a fixed spot, so an unchanged
-- fingerprint plus an unchanged position means it is not going to finish.
--
-- Everything else is deliberately absent. Smack, Shoot, Bandage, Time, Sleep, Zombify and
-- friends all sit at the head of the queue while working correctly, and the first version
-- cancelled all of them. Names taken from shared/ZombieActions/, not invented.
local STALLABLE = {
    GoTo = true, Move = true,
    OpenWindow = true, SmashWindow = true, ClimbFence = true,
    Destroy = true, Unbarricade = true, UnbarricadeMetal = true,
    PickUp = true, PickUpBody = true,
    TakeFromContainer = true, PutInContainer = true,
    LootItems = true, LootWeapons = true,
}

-- The same set, plus the rule that only one person may work a given spot at a time. Two
-- survivors piling onto the same window was reported from play; it is also how one of them
-- ends up standing in the open with its back turned.
local EXCLUSIVE = {
    OpenWindow = true, SmashWindow = true, ClimbFence = true,
    Destroy = true, Unbarricade = true, UnbarricadeMetal = true,
    TakeFromContainer = true,
}

-- How many sweeps one NPC may hold a spot before others stop deferring to it. Without an
-- expiry, an NPC that dies or wanders off would lock a window shut for everybody.
local CLAIM_SWEEPS = 6

-- Sweeps between census lines. Transitions alone told us nothing about the NPCs that never
-- transitioned -- the whole 04-08 log has AUTO lines for exactly one survivor, because the
-- other three sat quietly on a rung and were therefore invisible.
local CENSUS_EVERY = 5

local claims = {}      -- "x,y,z" -> { id = <npc id>, sweep = <sweep number> }
local sweepNumber = 0
local lastSwingMs = 0

-- The player swinging is a fact we can only learn as it happens. Same event the guard
-- already listens to; two listeners on one event is cheaper than a per-tick poll, and this
-- one only writes a timestamp.
local SWING_MEMORY_MS = 4000

Events.OnWeaponSwingHitPoint.Add(function(character, _)
    if character and instanceof(character, "IsoPlayer") then
        lastSwingMs = getTimestampMs()
    end
end)

local function playerIsFighting(player)
    if getTimestampMs() - lastSwingMs < SWING_MEMORY_MS then return true end
    return player:isAiming() == true
end

-- COUNTING ---------------------------------------------------------------------------

--- Threats near a point: how many, and how far the nearest one is. One pass, because the
--- ladder needs both numbers and the cache is walked per NPC per sweep.
local function scanThreats(x, y)
    local cache = BanditZombie and BanditZombie.CacheLightZ
    if not cache then return 0, math.huge end

    local n, nearestSq = 0, math.huge
    local r2 = FEAR_RADIUS * FEAR_RADIUS
    for _, entry in pairs(cache) do
        local dx, dy = entry.x - x, entry.y - y
        local d2 = dx * dx + dy * dy
        if d2 <= r2 then
            n = n + 1
            if d2 < nearestSq then nearestSq = d2 end
        end
    end
    return n, math.sqrt(nearestSq)
end

local function friendsNear(x, y, selfId)
    local cache = BanditZombie and BanditZombie.CacheLightB
    if not cache then return 0 end
    local n, r2 = 0, FRIEND_RANGE * FRIEND_RANGE
    for _, other in pairs(cache) do
        if other.id ~= selfId then
            local brain = other.brain
            if brain and not brain.hostile and not brain.hostileP then
                local dx, dy = other.x - x, other.y - y
                if dx * dx + dy * dy <= r2 then n = n + 1 end
            end
        end
    end
    return n
end

-- FEAR -------------------------------------------------------------------------------

--- How much fear this person can carry before survival takes over everything else.
---
--- brain.rnd[2] is ZombRand(10), fixed at spawn -- the same field ScenesRelationsThreat
--- reads for bravery, deliberately, so the two can never disagree about who is brave. A
--- coward breaks at 30; somebody steady holds until 93.
local function fearLimit(brain)
    local bravery = 0
    if type(brain.rnd) == "table" and brain.rnd[2] then bravery = brain.rnd[2] end
    return 30 + bravery * 7
end

--- Live health as a fraction of what this person spawned with.
---
--- brain.health is the SPAWN maximum (BanditServerSpawner.lua:332, a Lerp into 1..2.6) and
--- never changes; getHealth is the live value that bleeding drains and Bandage restores.
--- Reading brain.health as current health -- which the first version did -- makes the hurt
--- term a constant per person instead of a signal.
local function healthRatio(zombie, brain)
    local max = tonumber(brain.health) or 2
    if max <= 0 then return 1 end
    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return 1 end
    return now / max
end

local function updateFear(mood, threats, nearest, friends, hpRatio)
    local situational = 0

    if nearest <= FEAR_RADIUS then
        situational = situational + math.min(threats, 6) * FEAR_PER_ZOMBIE
    end
    if threats > friends + 1 then
        situational = situational + FEAR_OUTNUMBERED
    end
    if hpRatio < 0.5 then
        situational = situational + FEAR_HURT
    end

    local fear = (mood.fear or 0) * FEAR_KEEP + situational
    mood.fear = math.max(0, math.min(100, fear))
    return mood.fear
end

-- THE LADDER -------------------------------------------------------------------------

--- Which rung this person is on right now.
---
--- ctx carries what the sweep already measured: threats, nearest, friends, masterDist,
--- disengaging, masterFighting.
function Autonomy.RungOf(brain, mood, ctx)
    if (mood.fear or 0) >= fearLimit(brain) then return Autonomy.SURVIVE end

    local program = brain.program and brain.program.name
    local owned = (program == "Companion" or program == "CompanionGuard") and brain.master

    -- FIGHT, and the whole point is that it is now CONDITIONAL. Something within
    -- ENGAGE_RANGE is on top of them and there is nothing to decide. Beyond that, a
    -- companion fights because its master is fighting -- not because a zombie exists
    -- somewhere in the street, which is what made them ignore every order they were given.
    if ctx.nearest <= ENGAGE_RANGE then return Autonomy.FIGHT end

    if owned then
        -- Following outranks a distant zombie. This is the rule the player asked for in as
        -- many words: if I run, you run.
        if ctx.disengaging then return Autonomy.OBEY end
        if ctx.masterFighting and ctx.nearest <= ASSIST_RANGE then return Autonomy.FIGHT end
        return Autonomy.OBEY
    end

    -- Nobody's companion. They keep the wider engagement window, because for them there is
    -- no competing instruction and standing still next to a zombie reads as broken.
    if ctx.nearest <= ASSIST_RANGE then return Autonomy.FIGHT end

    if mood.wanting then return Autonomy.ERRAND end
    return Autonomy.IDLE
end

-- FOLLOWING --------------------------------------------------------------------------

--- Put the master back at the head of the queue, using the framework's own follow task.
---
--- BanditUtils.GetMoveTaskTarget tracks a character rather than a coordinate
--- (BanditUtils.lua:1000), which is exactly why "no saben donde estoy" stops being possible:
--- the task follows the player instead of walking to where the player used to be. Same call
--- ZPCompanion makes at the bottom of its Main; we are only making sure it is reached.
local function assertFollow(zombie, master, dist)
    local walkType = "Walk"
    local endurance = 0
    if master:isSprinting() or dist > 10 then
        walkType, endurance = "Run", -0.07
    elseif master:isSneaking() and dist < 12 then
        walkType, endurance = "SneakWalk", -0.01
    end

    local task = BanditUtils.GetMoveTaskTarget(endurance,
        master:getX(), master:getY(), master:getZ(),
        BanditUtils.GetCharacterID(master), true, walkType, dist)

    Bandit.ClearTasks(zombie)
    Bandit.AddTask(zombie, task)
    return walkType
end

-- STUCK AND CONTENDED ----------------------------------------------------------------

local function headTask(brain)
    return brain.tasks and brain.tasks[1] or nil
end

--- A cheap fingerprint of whatever is at the head of the queue. Action plus destination,
--- never the whole task: fields like `tick` change every frame and would make every sweep
--- look like progress.
local function headSignature(task)
    if not task then return nil end
    return string.format("%s@%s,%s", tostring(task.action), tostring(task.x), tostring(task.y))
end

--- Nobody else is already working this exact spot, or we are the one who claimed it.
--- Returns true if this NPC may proceed, plus the key and holder when it may not.
local function claimSpot(id, task)
    if not task or not EXCLUSIVE[task.action] then return true end
    if not task.x or not task.y then return true end

    local key = string.format("%s,%s,%s", tostring(task.x), tostring(task.y), tostring(task.z))
    local held = claims[key]

    if held and held.id ~= id and (sweepNumber - held.sweep) < CLAIM_SWEEPS then
        return false, key, held.id
    end

    claims[key] = { id = id, sweep = sweepNumber }
    return true, key
end

--- The direct fix for the reported bug, now with the two guards the first version lacked:
--- only tasks that CAN stall are watched, and the NPC must also have failed to move. A
--- survivor mid-swing has a constant fingerprint and is working perfectly; a survivor stuck
--- on a window latch has a constant fingerprint AND has not gone anywhere.
local function watchdog(zombie, brain, mood, name)
    local task = headTask(brain)
    local signature = headSignature(task)

    if not signature or not STALLABLE[task.action] then
        mood.taskSig, mood.taskTicks = nil, 0
        return false
    end

    local x, y = zombie:getX(), zombie:getY()
    local moved = true
    if mood.lastX and mood.lastY then
        local dx, dy = x - mood.lastX, y - mood.lastY
        moved = (dx * dx + dy * dy) > (MOVED_EPSILON * MOVED_EPSILON)
    end
    mood.lastX, mood.lastY = x, y

    if signature ~= mood.taskSig or moved then
        mood.taskSig, mood.taskTicks = signature, 1
        return false
    end

    mood.taskTicks = (mood.taskTicks or 0) + 1
    if mood.taskTicks < STUCK_SWEEPS then return false end

    Bandit.ClearTasks(zombie)
    mood.taskSig, mood.taskTicks = nil, 0
    SR.Log(string.format("AUTO %s | stuck on %s for %d sweeps without moving -- queue cleared",
        name, signature, STUCK_SWEEPS))
    return true
end

-- THE SWEEP --------------------------------------------------------------------------

local function sweep()
    local player = getSpecificPlayer(0)
    if not player then return end
    if not BanditZombie or not BanditZombie.GetAllB then return end

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    sweepNumber = sweepNumber + 1
    local census = (sweepNumber % CENSUS_EVERY) == 0

    local px, py = player:getX(), player:getY()
    local fighting = playerIsFighting(player)
    local sprinting = player:isSprinting() == true

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            local masterDist = math.sqrt(dx * dx + dy * dy)

            if masterDist <= NPC_RANGE then
                local brain = BanditBrain.Get(zombie)
                local mood = brain and SR.Mood(zombie)

                -- Somebody actively hostile is Bandits' business, not ours.
                if brain and mood and not brain.hostile and not brain.hostileP then
                    local name = tostring(brain.fullname)
                    local zx, zy = zombie:getX(), zombie:getY()

                    local threats, nearest = scanThreats(zx, zy)
                    local friends = friendsNear(zx, zy, id)
                    local hpRatio = healthRatio(zombie, brain)

                    updateFear(mood, threats, nearest, friends, hpRatio)

                    -- Is the player leaving? Growing distance is the honest test, because
                    -- it does not care WHY -- sprinting, driving, or just walking off while
                    -- the NPC dawdles all read the same to somebody being left behind.
                    local growing = mood.lastMasterDist
                        and (masterDist - mood.lastMasterDist) > 0.75
                    mood.lastMasterDist = masterDist

                    local ctx = {
                        threats = threats, nearest = nearest, friends = friends,
                        masterDist = masterDist,
                        masterFighting = fighting,
                        disengaging = sprinting or growing or masterDist > LEASH,
                    }

                    local before = mood.rung or Autonomy.IDLE
                    local now = Autonomy.RungOf(brain, mood, ctx)
                    mood.rung = now

                    -- Escalation clears the queue. Dropping back down does not: finishing
                    -- what you already started is correct, and clearing on every change
                    -- would mean an NPC that never completes anything at all.
                    if now < before then
                        Bandit.ClearTasks(zombie)
                        mood.taskSig, mood.taskTicks = nil, 0
                        SR.Log(string.format(
                            "AUTO %s | %s -> %s | fear=%d/%d z=%d@%.1f friends=%d hp=%.2f | queue cleared",
                            name, RUNG_NAME[before], RUNG_NAME[now],
                            mood.fear, fearLimit(brain), threats, nearest, friends, hpRatio))
                    end

                    -- OBEY is the one rung we do more than arbitrate on, because ZPCompanion
                    -- structurally cannot reach its own follow code while an enemy is within
                    -- 8 tiles of a companion within 20 of its master. Asserting the follow
                    -- task ourselves is what turns "if I run, you run" from a wish into
                    -- behaviour. Only when they are actually behind: re-pushing every sweep
                    -- would stop them ever finishing anything.
                    if now == Autonomy.OBEY and ctx.disengaging and masterDist > 2 then
                        local walkType = assertFollow(zombie, player, masterDist)
                        mood.taskSig, mood.taskTicks = nil, 0
                        if before ~= Autonomy.OBEY or census then
                            SR.Log(string.format(
                                "AUTO %s | following master at %.1f tiles (%s) -- %s",
                                name, masterDist, walkType,
                                sprinting and "master sprinting"
                                    or (growing and "falling behind" or "past leash")))
                        end
                    else
                        local task = headTask(brain)
                        local allowed, key, holder = claimSpot(id, task)
                        if not allowed then
                            -- Somebody is already on this window. Waiting is a real task,
                            -- so they visibly queue rather than crowding the same tile.
                            Bandit.ClearTasks(zombie)
                            Bandit.AddTask(zombie, { action = "Time", anim = "Shrug", time = 120 })
                            mood.taskSig, mood.taskTicks = nil, 0
                            SR.Log(string.format("AUTO %s | waits, %s is already working %s",
                                name, tostring(holder), tostring(key)))
                        elseif now >= before then
                            -- Only when nothing escalated, so the watchdog can never clear a
                            -- queue that was deliberately rebuilt one sweep ago.
                            watchdog(zombie, brain, mood, name)
                        end
                    end

                    if census then
                        SR.Log(string.format(
                            "AUTO census | %s | rung=%s fear=%d/%d hp=%.2f z=%d@%.1f friends=%d master=%.1f head=%s",
                            name, RUNG_NAME[mood.rung], mood.fear, fearLimit(brain),
                            hpRatio, threats, nearest, friends, masterDist,
                            tostring(headSignature(headTask(brain)) or "idle")))
                    end
                end
            end
        end
    end

    -- Claims from NPCs that died, wandered off, or finished. Cheap to rebuild, and leaving
    -- them would slowly lock every window on the map.
    if census then
        for key, held in pairs(claims) do
            if (sweepNumber - held.sweep) >= CLAIM_SWEEPS then claims[key] = nil end
        end
    end
end

Events.EveryOneMinute.Add(sweep)

Events.OnGameStart.Add(function()
    SR.Log("AUTO ready -- survive > fight > obey > errand > idle; the player's intent outranks a distant zombie")
end)
