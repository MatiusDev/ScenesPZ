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

-- Exposed so ScenesRelationsThreat can bound its own sweep to NPCs whose mood.rung is
-- actually fresh (F3): mood.rung is only ever written inside the masterDist <= NPC_RANGE
-- guard below and never cleared on the way out, so reading the SAME bound rather than a
-- second number of Threat's own is what stops an NPC that wandered off keeping a stale
-- SURVIVE forever, unwatched by the module that could correct it.
Autonomy.NPC_RANGE = NPC_RANGE

-- GRABBED_RANGE (1.6 tiles) lived here -- "this close has them, running is not on the table".
-- Deleted rather than kept: the reasoning is in RungOf where the branch used to be. Once
-- leaving wins outright for a companion, 1.6 is simply a subset of ENGAGE_RANGE and the test
-- could never fire. A dead constant that reads like a rule is how the next person tunes a
-- number and wonders why nothing changed. git has it if the branch ever comes back.

-- Tiles. Close enough to be worth swinging at when nothing else is being asked of them.
-- Was 10, which meant any zombie in the street outranked every order the player had given.
local ENGAGE_RANGE = 4

-- Tiles. How far somebody's business extends, BY STANDING. Asked for in these words:
--
--   "si a los NPC que no tienen grupo le aumentamos su tile, y cuando nos esta siguiendo lo
--    dejamos como esta actual, y cuando ya estan adentro del clan (join me) que el tile sea
--    defender un tile menor a los NPC que no tienen grupo, para que sea defender."
--
-- The shape of that is a gradient of commitment, and it reads correctly in play:
--
--   FREE    nobody's companion. Widest, because they answer to nothing else -- a zombie ten
--           tiles away is genuinely the most interesting thing in their life.
--   FOLLOW  walking with you. Unchanged, because it was already tuned against real runs.
--   CLAN    joined. TIGHTEST, and that is what makes it read as defending rather than
--           hunting: somebody who took your side holds the ground around you instead of
--           chasing whatever they can see.
local FREE_ENGAGE = 10
local FOLLOW_ENGAGE = 8
local CLAN_ENGAGE = 6

--- How far this person's business extends right now.
local function assistRange(brain, owned)
    if not owned then return FREE_ENGAGE end
    if brain.loyal then return CLAN_ENGAGE end
    return FOLLOW_ENGAGE
end

-- Tiles. Past this a companion has lost its master and catching up is the only task that
-- matters. ZPCompanion switches to Run at 10, so 12 leaves it room to do its own job first.
local LEASH = 12

-- Tiles. How close the master has to have gotten, while moving, for a companion who broke
-- for SURVIVE to count as found rather than merely somewhere in the area. Same number as
-- FOLLOW_ENGAGE -- that already means "close enough to be walking with you."
local REJOIN_RANGE = FOLLOW_ENGAGE

-- Sweeps a rejoin may hold before it expires no matter what. About half a real minute at this
-- cadence -- long enough to actually close a gap and get behind the player, short enough that a
-- companion pinned by a fear that will not fall goes back to deciding on the merits instead of
-- standing there refusing to fight. The bound exists because the CLEAR condition below cannot be
-- guaranteed to arrive: fear is fed by the zombies the companion would be helping to kill.
local REJOIN_SWEEPS = 5

-- Tiles. How much masterDist has to change, sweep to sweep, to count as a real shift
-- rather than pathing jitter. One name for what used to be two separate bare 0.75
-- literals (the falling-behind check and the old moving-toward check), so both agree on
-- what "changed" means.
local MASTER_DIST_EPSILON = 0.75

-- Tiles. Below this, the player's own displacement this sweep is noise, not movement --
-- gates `approaching` (F4) so a stationary player can never register as closing the gap,
-- however much masterDist happens to shift purely because the companion itself is
-- running for a window.
local PLAYER_MOVE_EPSILON = 0.3

-- Tiles. What an NPC is frightened by. Wider than ENGAGE_RANGE -- you should be able to be
-- afraid of something you are not yet obliged to fight.
local FEAR_RADIUS = 9

-- Tiles. The radius the surroundings scan actually covers. One pass answers every question
-- below, so it is set to the widest of them rather than scanning the cache three times.
local SCAN_RADIUS = 10

-- BREACH_PANIC (4) lived here -- "one inside is a problem, four is a reason to leave", asked
-- for in those words: "a no ser de que esten entrando demasiados zombies y sea necesario para
-- escapar del lugar." It was referenced NOWHERE. The rule it names is enforced, but by the
-- FEAR_PER_BREACH term, which crosses the limit at three rather than four -- so the documented
-- rule and the shipped behaviour disagreed silently, with this constant as the only evidence
-- anybody had intended four. Recalibrating that term is a tuning decision and it is tracked
-- with the rest of the fear model in docs/PLAN-OBJETIVOS.md.

-- Zombies outside the walls but close enough to be working on them. Below this, searching
-- the house is reasonable; at or above it, the job is to clear the area first --
-- "si estan golpeando varios zombies, la actividad principal es matarlos para despejar
-- la zona y poder lotear con tranquilidad."
local BANGING = 2

-- Extra fear per zombie that is inside the building with them. Being cornered indoors is
-- worse than the same count in the open, and the model should say so.
local FEAR_PER_BREACH = 10

-- Tiles. Who counts as backup.
local FRIEND_RANGE = 12

-- Fear is a decaying average, not an accumulator. Each sweep keeps this fraction of what
-- was there and adds what the situation justifies, so it settles at a level the moment
-- deserves and falls as soon as the moment passes. The old version only ever subtracted
-- when nothing at all was near, which in a populated street meant never.
local FEAR_KEEP = 0.6
local FEAR_PER_ZOMBIE = 6
local FEAR_HURT = 20

-- Fear per unit the threat-to-people ratio sits above 1:1. People is this NPC plus its
-- friends (friendsNear, which now includes the player), so a lone NPC facing five
-- zombies (5:1) is measured the same way as two people facing five (5:2) -- the ratio,
-- not a flat headcount. Calibrated against three concrete points the user gave:
--   3 zombies vs 2 people -- ratio 1.5, +0.5 over 1:1 -- fine, keep fighting
--   4 zombies vs 2 people -- ratio 2.0, +1.0 over 1:1 -- the ceiling, still fighting
--   5 zombies vs 2 people -- ratio 2.5, +1.5 over 1:1 -- a problem, fear should climb
-- 10 per point over 1:1 reproduces that ladder (5, 10, 15). The settled fear those
-- produce -- 51, 72.5, 94 -- and the single fixed FEAR_LIMIT (83) chosen to sit between
-- the ceiling and the problem are worked in full in fearLimit's own comment below.
local FEAR_OUTNUMBERED_PER_RATIO = 10

-- Caps the outnumbered term so a single NPC swarmed by a whole horde (ratio 10:1, 20:1...)
-- does not produce an unbounded number. The user's own example -- "if ~5 zombies are
-- focused on ONE NPC specifically, that alone is reason to escape" -- is ratio 5:1, over
-- = 4, which already reaches this cap.
local FEAR_OUTNUMBERED_MAX = 30

-- Being in a group means more confidence: somebody who joined chose to stand with this
-- person, and that should make fleeing rarer, not just survivable. Halves the outnumbered
-- term for anyone who joined the clan.
--
-- brain.loyal, not a "joinMe" field -- there is no such field on the brain record. The
-- PROBE line's `joinMe=%s` (ScenesRelationsRun.lua:80) prints a LOCAL variable computed
-- by wouldOfferJoinMe(brain), which only asks whether brain.program.name == "Looter" --
-- i.e. whether the right-click menu option would currently appear, not whether anyone
-- joined. The verified "has joined the clan" flag is brain.loyal: set by the JOIN action
-- (ScenesRelationsActions.lua:94, "JOIN is the ally boundary, and it sets brain.loyal" --
-- ScenesRelationsActions.lua:35) and already read in this file for engage range
-- (assistRange above, "if brain.loyal then return CLAN_ENGAGE end").
local GROUP_CONFIDENCE = 0.5

-- Sweeps a task may sit unchanged, WITH THE NPC NOT MOVING, before it counts as stuck.
--
-- Was 3, which is about eighteen seconds of standing at a fence looking at it -- long
-- enough to be photographed twice (caps/npc-window.png, caps/npc-fence.png). Nothing on the
-- STALLABLE list can legitimately spend twelve seconds getting nowhere, so 2 costs nothing
-- and halves how long a jam is visible.
local STUCK_SWEEPS = 2

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

-- The exact fingerprint pushed onto a denied NPC's queue below. Named and exposed so
-- ScenesRelationsThreat can tell "waiting for a turn at a claimed spot" from "actually
-- displaced" (F2) without duplicating the literal and risking the two copies drifting
-- apart.
Autonomy.WAIT_ACTION = "Time"
Autonomy.WAIT_ANIM = "Shrug"

-- Sweeps between census lines. Transitions alone told us nothing about the NPCs that never
-- transitioned -- the whole 04-08 log has AUTO lines for exactly one survivor, because the
-- other three sat quietly on a rung and were therefore invisible.
local CENSUS_EVERY = 5

local claims = {}      -- "x,y,z" -> { id = <npc id>, sweep = <sweep number> }
local sweepNumber = 0
local lastSwingMs = 0
local lastPlayerX, lastPlayerY -- the player's position last sweep; see playerMovedDist below

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

--- Everything the ladder and the companion program need to know about what is around this
--- NPC, in ONE pass over the cache.
---
--- Deliberately one function. The companion program needs the indoor/outdoor split to
--- decide whether searching a house is reasonable, and the ladder needs it to decide
--- whether to clear the area first. Two modules measuring the same street on their own
--- radii is exactly what R6 exists to stop, and it is what the threat module already did
--- once. So this measures, stores it on SR.Mood, and both read the same numbers.
---
--- Returns: threats (within FEAR_RADIUS), nearest, insiders, outsiders.
---
--- "Inside" is `square:isOutside() == false`, the same question BanditUpdate.lua:941 asks
--- of the NPC itself. A zombie whose square cannot be read counts as outside: being unsure
--- should not sound the breach alarm.
local function scanSurroundings(cell, x, y, z)
    local cache = BanditZombie and BanditZombie.CacheLightZ
    if not cache then return 0, math.huge, 0, 0 end

    local n, nearestSq, insiders, outsiders = 0, math.huge, 0, 0
    local fearR2 = FEAR_RADIUS * FEAR_RADIUS
    local scanR2 = SCAN_RADIUS * SCAN_RADIUS

    for _, entry in pairs(cache) do
        local dx, dy = entry.x - x, entry.y - y
        local d2 = dx * dx + dy * dy

        if d2 <= scanR2 then
            if d2 <= fearR2 then
                n = n + 1
                if d2 < nearestSq then nearestSq = d2 end
            end

            local inside = false
            if cell then
                local sq = cell:getGridSquare(math.floor(entry.x), math.floor(entry.y), z)
                if sq then inside = not sq:isOutside() end
            end
            if inside then insiders = insiders + 1 else outsiders = outsiders + 1 end
        end
    end

    return n, math.sqrt(nearestSq), insiders, outsiders
end

--- `player` is optional so callers that only care about NPC backup (none today, but the
--- signature should not lie) still work.
---
--- The player counts as a friend. CacheLightB (BanditZombie.lua:16) holds only NPCs --
--- BanditZombie.lua:80-85 files a bandit into CacheLightB and everyone else into
--- CacheLightZ, and the player is neither -- so a census that only reads this cache always
--- finds the player alone. Confirmed in play: census lines read `master=0.5 ... friends=0`
--- with the player standing half a tile away. Dead or absent, the player counts as zero;
--- "the same plane/range as the NPC test" means the same FRIEND_RANGE, 2D, no z filter --
--- exactly what the loop below already does for NPCs, so the player is measured no
--- differently.
local function friendsNear(x, y, selfId, player)
    local cache = BanditZombie and BanditZombie.CacheLightB
    if not cache then return 0 end
    local n, r2 = 0, FRIEND_RANGE * FRIEND_RANGE

    if player and player:isAlive() then
        local pdx, pdy = player:getX() - x, player:getY() - y
        if pdx * pdx + pdy * pdy <= r2 then n = n + 1 end
    end

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
--- WAS a per-NPC dice roll (brain.rnd[2], fixed at spawn -- BanditServerSpawner.lua:375),
--- 30 to 93 depending on the roll. Removed on explicit direction: "No quiero que haya una
--- probabilidad del 50/50 de que un NPC solo corra por que si... el hecho de que un NPC
--- entre en pánico debería provocar que un NPC huya. No una probabilidad, si no un hecho
--- o un evento." No coin flip decides who breaks. One threshold, shared by everybody,
--- until fear is driven by an actual state (a panic flag set by a real cause) instead of
--- a number rolled once at spawn -- that model is future work and is deliberately NOT
--- built here.
---
--- THE ARITHMETIC BEHIND THE NUMBER. updateFear is a decaying average: each sweep keeps
--- FEAR_KEEP (0.6) of what was there and adds this sweep's situational term, so under a
--- CONSTANT situation it settles at situational / (1 - FEAR_KEEP) = situational / 0.4.
--- Working the settle point for a loyal NPC (GROUP_CONFIDENCE halves the outnumbered
--- term) with the player counted as one friend (friendsNear), so "vs 2 people" means this
--- NPC plus one friend:
---
---   3 zombies vs 2 -- ratio 1.5: term1 = 3*FEAR_PER_ZOMBIE = 18
---                                term2 = min(30,(1.5-1)*10)*0.5 = 2.5
---                                situational = 20.5 -> settles at 20.5/0.4 = 51.25
---   4 zombies vs 2 -- ratio 2.0: term1 = 4*6 = 24
---                                term2 = min(30,(2.0-1)*10)*0.5 = 5.0
---                                situational = 29.0 -> settles at 29.0/0.4 = 72.5
---   5 zombies vs 2 -- ratio 2.5: term1 = 5*6 = 30
---                                term2 = min(30,(2.5-1)*10)*0.5 = 7.5
---                                situational = 37.5 -> settles at 37.5/0.4 = 93.75
---
--- The user's own calibration is "3 is fine, 4 is the ceiling, 5 is a problem" -- the
--- threshold has to clear 72.5 (4 must still fight) and stay under 93.75 (5 must break).
--- 83 is roughly the midpoint, leaving about ten points of headroom on both sides so a
--- brief spike near the ceiling does not accidentally trip survival, and 5-on-2 still
--- reliably trips it once it settles.
local FEAR_LIMIT = 83

--- `brain` is unused now -- kept as a parameter so every call site (RungOf, the two log
--- lines in sweep()) stays untouched rather than needing its own edit for a value that is
--- no longer per-person.
local function fearLimit(brain)
    return FEAR_LIMIT
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

local function updateFear(mood, threats, nearest, friends, hpRatio, insiders, loyal)
    local situational = 0

    if nearest <= FEAR_RADIUS then
        situational = situational + math.min(threats, 6) * FEAR_PER_ZOMBIE
    end

    -- Ratio of threats to people, not a flat headcount -- see FEAR_OUTNUMBERED_PER_RATIO
    -- above for the calibration. `threats` is scanSurroundings' own count within
    -- FEAR_RADIUS, already measured per NPC; nothing here asks a zombie who it is chasing
    -- (zombie:getTarget() does not exist in 42.20 -- Threat.lua:11).
    local people = 1 + friends
    local ratio = threats / people
    if ratio > 1 then
        local outnumbered = math.min(FEAR_OUTNUMBERED_MAX, (ratio - 1) * FEAR_OUTNUMBERED_PER_RATIO)
        if loyal then outnumbered = outnumbered * GROUP_CONFIDENCE end
        situational = situational + outnumbered
    end

    if hpRatio < 0.5 then
        situational = situational + FEAR_HURT
    end
    -- Being cornered indoors is worse than the same count in the open, and this is what
    -- turns "too many are getting in" into leaving rather than dying in a kitchen. It is a
    -- fear term rather than a rule so that a brave person still holds the room longer than
    -- a frightened one -- the same body of water, different waterline.
    if mood.indoors and insiders > 0 then
        situational = situational + math.min(insiders, 6) * FEAR_PER_BREACH
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
    local program = brain.program and brain.program.name
    local owned = (program == "Companion" or program == "CompanionGuard") and brain.master

    -- IF I RUN, YOU RUN. Above everything -- above fear, above being grabbed, above a whole
    -- street of them.
    --
    -- This sat two rungs lower and it did not work. Reported twice, the second time with the
    -- reason attached: "no se si es que hubiera varios zombies cerca, no lo hizo correr" and
    -- "se quedo pegandoles". Exactly so. With a horde on you something is always inside
    -- GRABBED_RANGE, so FIGHT won every sweep and the companion stood there swinging while
    -- the player left. Fear did not rescue it either: rung 1 is "get behind a door", which is
    -- not the same as "come with me" and in a running fight is worse.
    --
    -- The honest reading is that a companion whose master is sprinting away has already been
    -- told what the plan is. Holding a horde alone is not bravery, it is not having been
    -- asked. Being grabbed by one zombie while your friend runs is survivable; being left
    -- behind by choice is not.
    if owned and ctx.disengaging then return Autonomy.OBEY end

    if (mood.fear or 0) >= fearLimit(brain) then return Autonomy.SURVIVE end

    -- GRABBED. Something is close enough that leaving is not a choice anybody has.
    -- Deliberately tighter than ENGAGE_RANGE, because of what the 04-08 log showed:
    -- `following master at 25.9 tiles` -- a companion with a zombie four tiles away would
    -- not break off no matter how hard the player ran, so the player had to get 25 tiles
    -- clear before being followed. With a horde that is a death sentence, and it was
    -- reported in exactly those words: "yo tendria que irme muy lejos para que el me
    -- persiga, eso seria suicidio."
    -- One test, not two. GRABBED_RANGE used to be checked separately here because it
    -- outranked disengaging; now that leaving wins outright for a companion, 1.6 tiles is
    -- simply a subset of 4 and the extra branch could never fire. A dead branch that reads
    -- like a rule is worse than no branch -- the next person to tune this would move
    -- GRABBED_RANGE and wonder why nothing changed.
    if ctx.nearest <= ENGAGE_RANGE then return Autonomy.FIGHT end

    local reach = assistRange(brain, owned)

    if owned then
        -- Disengaging is NOT re-checked here. It is the first test in the function now, so a
        -- copy at this depth is dead code pretending to be the rule.
        if ctx.masterFighting and ctx.nearest <= reach then return Autonomy.FIGHT end

        -- CLEARING THE HOUSE. Standing in a building with something already inside, or with
        -- several working on the walls, is the one case where nobody has to be swinging yet
        -- and fighting is still the right answer -- because the alternative is searching
        -- drawers with your back to a doorway.
        --
        -- Note this is BELOW the breach case: once too many are in, fear has already
        -- carried them to rung 1 above and leaving wins. Clearing a room is a plan; holding
        -- a room against four is not.
        if ctx.indoors and (ctx.insiders > 0 or ctx.outsiders >= BANGING) then
            return Autonomy.FIGHT
        end

        return Autonomy.OBEY
    end

    -- Nobody's companion, so the widest window: there is no competing instruction, and
    -- standing still next to a zombie reads as broken.
    if ctx.nearest <= reach then return Autonomy.FIGHT end

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
--- `free` means charge no endurance for this one.
---
--- Not cosmetic. brain.endurance only ever decreases in this framework, and a Run task costs
--- 0.07 EVERY TIME ONE COMPLETES. The slow sweep pushes one per six seconds, the same
--- cadence their own program would; the fast tick can push one per second, so charging both
--- the same would drain a chasing companion to zero inside a minute -- which is exactly the
--- reported "despues de un rato los veo cansado de nuevo".
---
--- A re-assertion is a correction to a journey already being paid for, not a new journey.
local function assertFollow(zombie, master, dist, free)
    local walkType = "Walk"
    local endurance = 0
    if master:isSprinting() or dist > 10 then
        walkType, endurance = "Run", -0.07
    elseif master:isSneaking() and dist < 12 then
        walkType, endurance = "SneakWalk", -0.01
    end
    if free then endurance = 0 end

    -- AIM AT WHERE THEY WENT, NOT AT WHERE THEY ARE, when the straight line is shut.
    --
    -- Reported: "yo trepé un muro alto para pasar al otro lado, el NPC de una tomó la opción de
    -- rodearlo" -- and going the long way round is not merely slower, it drags a companion
    -- through streets it did not need to be in, which is how a quiet approach turns into a horde.
    --
    -- The trail is only consulted when the direct line is BLOCKED. With a clear line the old
    -- behaviour is exactly right and cheaper, and a heuristic that fires when it is not needed is
    -- a heuristic that will eventually be wrong for no reason.
    --
    -- This is NOT a claim that the trail is shorter. Proving that needs a real pathfind, and a
    -- pathfind commits the character. It is a claim that the trail is PASSABLE, which is a fact
    -- rather than an estimate: somebody walked it.
    local tx, ty, tz = master:getX(), master:getY(), master:getZ()
    local viaTrail = false

    if SR.Move and SR.Move.TrailTarget and SR.Move.WhatBlocks then
        local okLine, blocked = pcall(SR.Move.WhatBlocks, zombie, tx, ty, tz)
        if okLine and blocked ~= nil then
            local okTrail, cx, cy, cz = pcall(SR.Move.TrailTarget, zombie)
            if okTrail and cx then
                tx, ty, tz, viaTrail = cx, cy, cz, true
            end
        end
    end

    -- `tid`/`isPlayer` are still passed because that is the shape of the framework's own helper,
    -- but nothing in Bandits 42.20 reads either field -- ZAMove paths to the fixed coordinate
    -- captured at onStart (ZAMove.lua:9). The task walks to a POINT, which is precisely why
    -- aiming that point at a crumb works at all.
    local task = BanditUtils.GetMoveTaskTarget(endurance,
        tx, ty, tz,
        BanditUtils.GetCharacterID(master), true, walkType, dist)

    -- ON THE TRANSITION ONLY. `assertFollow` runs from the 800 ms tick, and a line that stays
    -- blocked stays blocked -- logging per call would put seventy-five lines a minute per
    -- companion into the one file this project reads by hand on another machine. That is the
    -- exact failure the interruption pass was discarded for, and it would have been the same
    -- mistake twice in one week.
    --
    -- Also: the first version called BanditBrain.Get TWICE inside the string.format, on that
    -- same hot path.
    local mood = SR.Mood(zombie)
    if mood and mood.viaTrail ~= viaTrail then
        mood.viaTrail = viaTrail
        if viaTrail then
            local brain = BanditBrain.Get(zombie)
            SR.Log(string.format("AUTO %s follows the trail to %.0f,%.0f -- direct line shut",
                tostring(brain and brain.fullname), tx, ty))
        end
    end

    Bandit.ClearTasks(zombie)
    Bandit.AddTask(zombie, SR.Own(SR.GOAL.FOLLOW, task))
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

--- The head of the queue, described for a human reading console.txt on another machine.
---
--- The OWNER is the part worth having and the part that did not exist before. A census line
--- saying `head=Move@10701,10272` never told anybody WHY the NPC was walking there -- catching
--- up, going to a window, or heading for a drawer all print identically. `head=Move/follow`
--- answers it, and it is the only way to see from the log that an objective actually owns what
--- it thinks it owns. Bandits' own tasks have no owner, and print as `-` rather than as a
--- guess.
local function headDescription(task)
    if not task then return "idle" end
    return string.format("%s@%s,%s/%s", tostring(task.action), tostring(task.x),
        tostring(task.y), tostring(task.srGoal or "-"))
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

    -- NAME THE OBSTACLE, not just the symptom. Clearing the queue unsticks an NPC and teaches
    -- nobody anything: "stuck on Move@10701,10272" has been in the log for weeks and never once
    -- said whether the thing in the way was a door somebody could have opened, a fence somebody
    -- could have climbed, or a wall that was never passable.
    --
    -- That distinction is the whole of block 6, and this is the cheapest place in the mod to
    -- collect it -- the watchdog already knows an NPC has stopped moving, and `Move.WhatBlocks`
    -- is a pure query. Bandits' own handler cannot do this: it scans for objects, and a map wall
    -- is not an object, so its silence is indistinguishable from success.
    -- WRAPPED, because CLEARING THE QUEUE IS THE SAFETY NET AND MUST SURVIVE THE DIAGNOSTICS.
    -- Unwrapped, a throw anywhere inside WhatBlocks -- getCell, getGridSquare, getObjects -- would
    -- propagate out of watchdog, out of the per-NPC loop, and out of `sweep` itself, which is
    -- registered bare on Events.EveryOneMinute. Three things would follow: the stuck NPC never
    -- gets unstuck, every remaining NPC is skipped for that sweep, and it repeats every six
    -- seconds forever, because the NPC is still stuck next time. Diagnostics that can disable the
    -- fix they are diagnosing are worse than no diagnostics.
    local blocking = "unknown"
    if SR.Move and SR.Move.WhatBlocks and task.x and task.y then
        local okWhy, kind = pcall(SR.Move.WhatBlocks, zombie,
            task.x, task.y, task.z or zombie:getZ())
        blocking = okWhy and tostring(kind or "clear") or "probe threw"
    end

    Bandit.ClearTasks(zombie)
    mood.taskSig, mood.taskTicks = nil, 0
    SR.Log(string.format(
        "AUTO %s | stuck on %s for %d sweeps without moving -- blocked by %s -- queue cleared",
        name, signature, STUCK_SWEEPS, blocking))
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

    -- The player's own movement, measured once per sweep rather than once per NPC -- there
    -- is only one player, and this is what makes `approaching` below (F4) immune to a
    -- companion's own flight changing masterDist just as much as the player moving does.
    local playerMovedDist = 0
    if lastPlayerX then
        local pdx, pdy = px - lastPlayerX, py - lastPlayerY
        playerMovedDist = math.sqrt(pdx * pdx + pdy * pdy)
    end
    lastPlayerX, lastPlayerY = px, py

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            local masterDist = math.sqrt(dx * dx + dy * dy)

            if masterDist <= NPC_RANGE then
                local brain = BanditBrain.Get(zombie)
                local mood = brain and SR.Mood(zombie)

                -- Somebody actively hostile is Bandits' business, not ours. And somebody who
                -- has already turned is nobody's -- the caches lag a frame or two behind
                -- BanditRemove, which is how the log filled with orders for a survivor that
                -- was a zombie by then.
                if brain and mood and not brain.hostile and not brain.hostileP
                   and (not SR.IsStillOurs or SR.IsStillOurs(zombie)) then
                    local name = tostring(brain.fullname)
                    local zx, zy = zombie:getX(), zombie:getY()

                    -- Where they are standing decides how the same street reads. Written to
                    -- SR.Mood so the companion program reads the same answer rather than
                    -- asking the world a second time on its own radius.
                    local square = zombie:getSquare()
                    local cell = square and square:getCell()
                    mood.indoors = square and not square:isOutside() or false

                    local threats, nearest, insiders, outsiders =
                        scanSurroundings(cell, zx, zy, zombie:getZ())
                    mood.insiders, mood.outsiders = insiders, outsiders

                    -- Standing in a broken window frame costs blood. Done here rather than
                    -- on its own tick because this loop already holds the square, and a
                    -- second sweep over the same NPCs to ask one more question about the
                    -- same tile would be waste.
                    if SR.Wounds then
                        SR.Wounds.CheckGlass(zombie, brain, mood, square)
                    end

                    local friends = friendsNear(zx, zy, id, player)
                    -- Shared with ScenesRelationsThreat so both modules report the same
                    -- headcount (F6) instead of Threat re-deriving a different one on its
                    -- own radius, which is exactly the R6 mistake this file's header warns
                    -- about. Threat's copy fed no decision, only its log line.
                    mood.friends = friends
                    local hpRatio = healthRatio(zombie, brain)

                    updateFear(mood, threats, nearest, friends, hpRatio, insiders, brain.loyal)

                    -- Is the player leaving? Growing distance is the honest test, because
                    -- it does not care WHY -- sprinting, driving, or just walking off while
                    -- the NPC dawdles all read the same to somebody being left behind.
                    local growing = mood.lastMasterDist
                        and (masterDist - mood.lastMasterDist) > MASTER_DIST_EPSILON

                    -- Is the MASTER approaching, isolated from the companion's own motion?
                    -- masterDist is the separation between two people, and a companion
                    -- sprinting for a window shifts it several tiles a sweep with the
                    -- player standing perfectly still (F4) -- so masterDist shrinking is
                    -- not by itself evidence the player did anything. Gating on
                    -- playerMovedDist (computed once above, from the player's own position
                    -- only) FIRST means a stationary player can never read as "approaching,"
                    -- whatever the companion does.
                    local approaching = playerMovedDist > PLAYER_MOVE_EPSILON
                        and mood.lastMasterDist
                        and (masterDist - mood.lastMasterDist) < -MASTER_DIST_EPSILON

                    mood.lastMasterDist = masterDist

                    -- Read before RungOf overwrites mood.rung with this sweep's verdict --
                    -- this is genuinely "were they fleeing a second ago."
                    local wasSurviving = mood.rung == Autonomy.SURVIVE

                    -- THE REJOIN LATCH (F4). The old version re-derived "found again" from
                    -- wasSurviving every single sweep, and firing it is what overwrites
                    -- mood.rung to OBEY -- so the very next sweep wasSurviving read false,
                    -- the clause vanished, fear (still high, decaying slowly under
                    -- FEAR_KEEP) sent them straight back to SURVIVE, and the cycle repeated:
                    -- a guaranteed two-sweep flicker, confirmed by reading the code, not
                    -- merely reported.
                    --
                    -- A latch fixes it because it does not live inside the value it forces.
                    -- CLEAR is gated on fear itself, not on mood.rung -- checking "rung is
                    -- no longer SURVIVE" would be exactly as self-cancelling as before,
                    -- since forcing OBEY below is what changes the rung. Fear actually
                    -- dropping under this person's limit is a real, independent signal that
                    -- the danger which sent them to SURVIVE has passed.
                    -- AND IT IS ALSO BOUNDED BY TIME, WHICH IS THE PART THAT WAS MISSING.
                    -- Fear alone is not a signal that can be trusted to arrive. The fear that
                    -- sent them to SURVIVE is fed by the very zombies the companion would
                    -- otherwise be helping to kill, so "wait for fear to drop" can mean
                    -- "wait for the player to clear the horde alone". And because
                    -- `disengaging` is the FIRST test in RungOf -- above fear, above every
                    -- FIGHT branch -- a latch that cannot clear is a companion standing next
                    -- to you that will not swing at a zombie one tile away.
                    --
                    -- That is strictly worse than the two-sweep flicker it replaced: a flicker
                    -- wastes six seconds, this loses the fight.
                    --
                    -- REJOIN_SWEEPS is the budget. Rejoining is a manoeuvre -- close the gap,
                    -- get behind the player -- and a manoeuvre that has not worked in half a
                    -- minute is not going to. When it expires the rung is decided on the
                    -- merits again, which may well be SURVIVE; that is a correct answer, and
                    -- unlike the latch it is one that gets re-asked every sweep.
                    if mood.rejoining then
                        mood.rejoinSweeps = (mood.rejoinSweeps or 0) + 1
                        if (mood.fear or 0) < fearLimit(brain)
                           or mood.rejoinSweeps >= REJOIN_SWEEPS then
                            mood.rejoining = nil
                            mood.rejoinSweeps = nil
                        end
                    end

                    -- SET only once, on the sweep the master verifiably closes the gap
                    -- (`approaching`, above) while within REJOIN_RANGE. Scoped to
                    -- `wasSurviving` for the same reason as before: widen it to fire from
                    -- any rung and a companion mid-FIGHT would be yanked off a zombie every
                    -- time the player merely walks near them while repositioning. The
                    -- intent is escaping together, not resuming the fight that was being
                    -- fled ("la idea es escapar no de regresar a darle a los zombies de los
                    -- que estabamos huyendo").
                    --
                    -- `brain.master` is required, and that is not redundant. RungOf only reads
                    -- `disengaging` on the owned path, so a free survivor latching this is
                    -- inert TODAY -- but it would be born already disengaging the moment
                    -- somebody recruits it, and a flag that is harmless until it silently is
                    -- not is exactly the kind of thing this project keeps paying for.
                    if not mood.rejoining and brain.master and wasSurviving and approaching
                       and masterDist <= REJOIN_RANGE then
                        mood.rejoining = true
                        mood.rejoinSweeps = 0
                    end

                    local ctx = {
                        threats = threats, nearest = nearest, friends = friends,
                        insiders = insiders, outsiders = outsiders,
                        indoors = mood.indoors,
                        masterDist = masterDist,
                        masterFighting = fighting,
                        -- `growing` is qualified by distance on purpose. Unqualified, a
                        -- player shuffling around a room they are looting together kept
                        -- tripping it, and every trip clears the queue -- which would yank
                        -- a companion off a drawer once every six seconds. Somebody four
                        -- tiles away is not leaving you.
                        --
                        -- The last clause is the rejoin latch above: found again, and it
                        -- stays true across sweeps until fear says the danger has actually
                        -- passed -- disengaging is checked before any FIGHT branch in
                        -- RungOf, so this can never resolve to FIGHT while it holds.
                        disengaging = sprinting or masterDist > LEASH
                            or (growing and masterDist > 6)
                            or mood.rejoining,
                    }

                    local before = mood.rung or Autonomy.IDLE
                    local now = Autonomy.RungOf(brain, mood, ctx)
                    mood.rung = now

                    -- Escalation clears the queue. Dropping back down does not: finishing
                    -- what you already started is correct, and clearing on every change
                    -- would mean an NPC that never completes anything at all.
                    if now < before then
                        -- UNFINISHED BUSINESS. Clearing the queue is what makes the ladder
                        -- work, and it is also what throws away whatever somebody was in
                        -- the middle of. The tasks are gone either way -- but the INTENT
                        -- does not have to be, and remembering it is the difference between
                        -- "a survivor interrupted while looting kills the zombie and returns
                        -- to the container" and a survivor who forgets the container ever
                        -- existed. That sentence is the stage's own done-criterion.
                        --
                        -- The ladder never invents an intent. The companion program records
                        -- what it started; this only moves it somewhere it survives.
                        if mood.doing then
                            mood.unfinished = mood.doing
                            mood.unfinishedAt = sweepNumber
                            mood.doing = nil
                            SR.Log(string.format("AUTO %s | sets aside %s at %s,%s",
                                name, tostring(mood.unfinished.kind),
                                tostring(mood.unfinished.x), tostring(mood.unfinished.y)))
                        end

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
                            -- The wait INHERITS the goal of the task it replaces. It is not a
                            -- plan of its own -- it is the same objective, queueing for a spot
                            -- somebody else holds -- so attributing it anywhere else would make
                            -- the queue lie about who is trying to do what.
                            -- Falls back to ARBITRATE rather than to nil. Six of the seven
                            -- EXCLUSIVE actions only ever come from a Bandits program, so the
                            -- blocked task usually has no owner -- and a nil here would mark a
                            -- task WE created as the framework's, which is the one thing the
                            -- tag exists to keep apart.
                            Bandit.AddTask(zombie,
                                SR.Own(task and task.srGoal or SR.GOAL.ARBITRATE,
                                { action = Autonomy.WAIT_ACTION, anim = Autonomy.WAIT_ANIM, time = 120 }))
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
                            "AUTO census | %s | rung=%s fear=%d/%d hp=%.2f z=%d@%.1f in=%d out=%d %s friends=%d master=%.1f bag=%s head=%s",
                            name, RUNG_NAME[mood.rung], mood.fear, fearLimit(brain),
                            hpRatio, threats, nearest, insiders, outsiders,
                            mood.indoors and "indoors" or "outdoors",
                            friends, masterDist,
                            -- `SR.Loot and HasBag(...) or "?"` printed "?" for everybody,
                            -- because `false or "?"` is "?" -- the whole run logged bag=?
                            -- and told us nothing. Lua's and/or is not a ternary when the
                            -- middle value can be false.
                            SR.Loot and tostring(SR.Loot.HasBag(brain)) or "?",
                            headDescription(headTask(brain))))
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

-- Sweeps an interrupted intention survives before it stops being worth going back for.
-- About two minutes: long enough to outlast a fight, short enough that a survivor does not
-- walk back across a street to a drawer it forgot about half an hour ago.
local UNFINISHED_SWEEPS = 20

--- Drop stale unfinished business. Expiry lives here rather than in the companion program
--- because the sweep counter is here; the alternative was exporting it, and one module
--- owning both the clock and the timeout is the smaller surface.
function Autonomy.ForgetIfStale(mood)
    if not mood.unfinished then return end
    if (sweepNumber - (mood.unfinishedAt or 0)) < UNFINISHED_SWEEPS then return end
    mood.unfinished, mood.unfinishedAt = nil, nil
end

Events.EveryOneMinute.Add(sweep)

-- THE FAST LANE ----------------------------------------------------------------------
--
-- Everything above runs on EveryOneMinute -- about six real seconds. For deciding what
-- somebody's priorities are, that is right: priorities do not change several times a
-- second, and a full cache scan per NPC at frame rate would be the most expensive thing in
-- this mod by an order of magnitude.
--
-- It is completely wrong for ONE question. A sprinting player covers roughly fifteen tiles
-- in six seconds, so "should I be running after them" answered on that cadence is answered
-- a street too late -- which is exactly the `following master at 25.9 tiles` in the log.
--
-- So that one question gets its own lane: no cache scan, no fear, no rungs. Is this person
-- mine, is their master pulling away, and are they already on their way. Throttled to a bit
-- over once a second, which is fast enough that the gap never opens and slow enough to cost
-- nothing.
local FAST_MS = 800
local CHASE_NOW = 5          -- tiles; past this while the master is moving off, go now
local lastFastMs = 0

local function fastFollow()
    local now = getTimestampMs()
    if now - lastFastMs < FAST_MS then return end
    lastFastMs = now

    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end
    if not BanditZombie or not BanditZombie.GetAllB then return end

    -- Only worth doing while the player is actually going somewhere. Standing still is what
    -- the six-second sweep is for.
    local sprinting = player:isSprinting() == true
    local px, py = player:getX(), player:getY()

    -- Remember where the player has BEEN. One distance test per pass, an append every couple of
    -- tiles. This tick already runs and already holds the player, so the trail costs nothing to
    -- collect -- and it is the only route to the player that is known to be walkable, because a
    -- body already walked it.
    if SR.Move and SR.Move.DropCrumb then
        pcall(SR.Move.DropCrumb, player)
    end

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist > CHASE_NOW and dist <= NPC_RANGE then
                local brain = BanditBrain.Get(zombie)
                local mood = brain and SR.Mood(zombie)

                if brain and mood and not brain.hostile and not brain.hostileP
                   and (not SR.IsStillOurs or SR.IsStillOurs(zombie)) then
                    local program = brain.program and brain.program.name
                    local owned = (program == "Companion" or program == "CompanionGuard")
                        and brain.master

                    -- Normally the ladder's verdict is respected: somebody surviving or with
                    -- a zombie in their face is not being asked to jog after you.
                    --
                    -- Sprinting is the exception, and it has to be. The rung is up to six
                    -- seconds old, and a player who has just started running has already
                    -- changed the plan -- waiting a sweep to notice is the whole complaint
                    -- ("pasan muchos tiles, y no me sigue"). A sprint is unambiguous and
                    -- player-authored, so it does not wait for the ladder to catch up.
                    local free = sprinting
                        or (mood.rung and mood.rung >= Autonomy.OBEY)

                    -- Widening, not merely wide. A companion holding station eight tiles
                    -- away while you stand still is fine; one at eight tiles and growing is
                    -- being left behind.
                    local widening = mood.fastDist and (dist - mood.fastDist) > 0.35
                    mood.fastDist = dist

                    if owned and free and (sprinting or widening or dist > LEASH) then
                        -- Only re-assert when they are not already chasing. The move task
                        -- tracks the player as a target, so re-pushing it every second
                        -- would restart the walk each time and they would never arrive.
                        local head = brain.tasks and brain.tasks[1]
                        local chasing = head and (head.action == "Move" or head.action == "GoTo")
                            and head.isPlayer

                        if not chasing then
                            local walkType = assertFollow(zombie, player, dist, true)
                            mood.taskSig, mood.taskTicks = nil, 0
                            SR.Log(string.format(
                                "AUTO %s | fast follow at %.1f tiles (%s) -- %s",
                                tostring(brain.fullname), dist, walkType,
                                sprinting and "master sprinting" or "gap opening"))
                        end
                    end
                end
            end
        end
    end
end

Events.OnTick.Add(fastFollow)

Events.OnGameStart.Add(function()
    SR.Log("AUTO ready -- survive > fight > obey > errand > idle; following is checked every second, not every sweep")
end)
