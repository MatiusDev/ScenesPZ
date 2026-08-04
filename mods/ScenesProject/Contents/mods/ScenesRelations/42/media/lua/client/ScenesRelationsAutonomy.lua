-- ScenesPZ -- stage 03. What matters right now, and fear is what decides it.
--
-- WHY THIS EXISTS, IN THE WORDS THAT PRODUCED IT
--   "no ordenan bien su cola de actividades y no las priorizan, algunos hasta se buguean
--    abriendo una ventana y se quedan abriendola, y terminan siendo mordidos por la espalda"
--
-- That reframed the whole problem, and checking the framework proved it exactly right.
-- Bandits is not missing behaviours. ZPCompanion ALREADY mirrors the player -- it switches
-- to Run when you sprint, SneakWalk when you crouch, WalkAim when you aim and Limp when
-- hurt, all at ZPCompanion.lua:38-56. Survivors already loot, climb, shelter and fight.
--
-- The catch is one line of framework design: a Bandits program only runs when the task
-- queue is EMPTY. An NPC three tasks deep into opening a window never reaches the code
-- that would have noticed you sprinting, or noticed the zombie behind it. It is not
-- ignoring the situation. It never gets asked.
--
-- So this file adds no verbs. It decides which of the existing ones matters, and -- this is
-- the whole mechanism -- it CLEARS THE QUEUE when something more important turns up.
-- Bandit.ClearTasks already exists and Bandits uses it itself when an NPC turns; it
-- preserves anything marked lock, so a Zombify in progress is never interrupted.
--
-- THE LADDER
-- Lower number wins. Moving UP a rung clears the queue so the program re-decides from
-- scratch; drifting back down does not, because finishing what you started is correct.
--
--   1 SURVIVE  cornered, badly hurt, or more afraid than this person can bear
--   2 FIGHT    a threat is close and they are not too afraid of it
--   3 OBEY     they accepted an order and have a master
--   4 ERRAND   they want something specific and are on their way to it
--   5 IDLE     nothing else
--
-- FEAR IS AN INPUT, NOT DECORATION
-- Two survivors in the same corridor should do different things, and the difference is
-- disposition. brain.rnd[2] is fixed at spawn and is already what ScenesRelationsThreat
-- uses for bravery, so the same field decides how much fear a person can carry before
-- rung 1 takes over. Fear itself lives on SR.Mood: transient, on the entity, decaying --
-- exactly what the PRD's emotion-versus-memory split requires.

require "ScenesRelations"

local SR = ScenesRelations

SR.Autonomy = SR.Autonomy or {}
local Autonomy = SR.Autonomy

Autonomy.SURVIVE, Autonomy.FIGHT, Autonomy.OBEY, Autonomy.ERRAND, Autonomy.IDLE = 1, 2, 3, 4, 5

local RUNG_NAME = { "survive", "fight", "obey", "errand", "idle" }

-- Tiles. Only NPCs near the player are worth thinking about.
local NPC_RANGE = 40

-- Tiles. What counts as "a threat is close".
local THREAT_RANGE = 10

-- Tiles. Who counts as backup when working out whether they are outnumbered.
local FRIEND_RANGE = 12

-- Fear moves in steps per sweep, clamped 0..100. These are tuning numbers and belong in
-- docs/NPC-BEHAVIOR-PLAN.md the moment they change.
local FEAR_PER_ZOMBIE = 6
local FEAR_OUTNUMBERED = 15
local FEAR_HURT = 20
local FEAR_DECAY = 12

-- Sweeps a task may sit unchanged at the head of the queue before it counts as stuck. An
-- in-game minute is about six real seconds, so three is roughly twenty. The longest
-- legitimate task we queue anywhere is OpenWindow at time=60, comfortably inside that.
local STUCK_SWEEPS = 3

local function countNear(cache, x, y, range)
    if not cache then return 0 end
    local n, r2 = 0, range * range
    for _, entry in pairs(cache) do
        local dx, dy = entry.x - x, entry.y - y
        if dx * dx + dy * dy <= r2 then n = n + 1 end
    end
    return n
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

--- Fear for this sweep. Rises from the situation, falls when the situation passes.
local function updateFear(brain, mood, threats, friends)
    local fear = mood.fear or 0
    local rising = false

    if threats > 0 then
        fear = fear + math.min(threats, 6) * FEAR_PER_ZOMBIE
        rising = true
    end
    if threats > friends + 1 then
        fear = fear + FEAR_OUTNUMBERED
        rising = true
    end
    -- brain.health is Bandits' own scale (Bandit.lua:423), not the player's.
    if (tonumber(brain.health) or 2) < 1.2 then
        fear = fear + FEAR_HURT
        rising = true
    end

    if not rising then fear = fear - FEAR_DECAY end

    mood.fear = math.max(0, math.min(100, fear))
    return mood.fear
end

--- Which rung this person is on right now.
function Autonomy.RungOf(brain, mood, threats)
    local fear = mood.fear or 0

    if fear >= fearLimit(brain) then return Autonomy.SURVIVE end
    if threats > 0 then return Autonomy.FIGHT end

    local program = brain.program and brain.program.name
    if (program == "Companion" or program == "CompanionGuard") and brain.master then
        return Autonomy.OBEY
    end

    if mood.wanting then return Autonomy.ERRAND end
    return Autonomy.IDLE
end

--- A cheap fingerprint of whatever is at the head of the queue.
---
--- Not the whole task: fields like `tick` change every frame and would make every sweep
--- look like progress. Action plus destination is enough to tell "still doing the same
--- thing in the same place" from "moved on".
local function headSignature(brain)
    local task = brain.tasks and brain.tasks[1]
    if not task then return nil end
    return string.format("%s@%s,%s", tostring(task.action), tostring(task.x), tostring(task.y))
end

--- The direct fix for the reported bug: an NPC that has been on the same task longer than
--- that task could plausibly take gets its queue emptied so the program can think again.
--- Worth having no matter how good the ladder gets, because it catches every future
--- variant of "stuck" without needing to know what caused it.
local function watchdog(zombie, brain, mood, name)
    local signature = headSignature(brain)

    if not signature then
        mood.taskSig, mood.taskTicks = nil, 0
        return false
    end

    if signature ~= mood.taskSig then
        mood.taskSig, mood.taskTicks = signature, 1
        return false
    end

    mood.taskTicks = (mood.taskTicks or 0) + 1
    if mood.taskTicks < STUCK_SWEEPS then return false end

    Bandit.ClearTasks(zombie)
    mood.taskSig, mood.taskTicks = nil, 0
    SR.Log(string.format("AUTO %s | stuck on %s for %d sweeps -- queue cleared",
        name, signature, STUCK_SWEEPS))
    return true
end

local function sweep()
    local player = getSpecificPlayer(0)
    if not player then return end
    if not BanditZombie or not BanditZombie.GetAllB then return end

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    local px, py = player:getX(), player:getY()
    local zcache = BanditZombie.CacheLightZ

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            if dx * dx + dy * dy <= NPC_RANGE * NPC_RANGE then
                local brain = BanditBrain.Get(zombie)
                local mood = brain and SR.Mood(zombie)

                -- Somebody actively hostile is Bandits' business, not ours.
                if brain and mood and not brain.hostile and not brain.hostileP then
                    local name = tostring(brain.fullname)
                    local zx, zy = zombie:getX(), zombie:getY()

                    local threats = countNear(zcache, zx, zy, THREAT_RANGE)
                    local friends = friendsNear(zx, zy, id)

                    updateFear(brain, mood, threats, friends)

                    local before = mood.rung or Autonomy.IDLE
                    local now = Autonomy.RungOf(brain, mood, threats)
                    mood.rung = now

                    -- Escalation clears the queue. Dropping back down does not: finishing
                    -- what you already started is correct, and clearing on every change
                    -- would mean an NPC that never completes anything at all.
                    if now < before then
                        Bandit.ClearTasks(zombie)
                        mood.taskSig, mood.taskTicks = nil, 0
                        SR.Log(string.format(
                            "AUTO %s | %s -> %s | fear=%d/%d zombies=%d friends=%d | queue cleared",
                            name, RUNG_NAME[before], RUNG_NAME[now],
                            mood.fear, fearLimit(brain), threats, friends))
                    else
                        -- Only when nothing escalated, so the watchdog can never clear a
                        -- queue that was deliberately rebuilt one sweep ago.
                        watchdog(zombie, brain, mood, name)
                    end
                end
            end
        end
    end
end

Events.EveryOneMinute.Add(sweep)

Events.OnGameStart.Add(function()
    SR.Log("AUTO ready -- survive > fight > obey > errand > idle, and fear picks the rung")
end)
