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
-- WHAT THE 10-08 SESSION CHANGED, AND WHY
-- Three complaints, and the log could not confirm or refute any of them -- which is itself
-- the fourth complaint ("mira de que manera puedes agregar mas logs").
--
-- 1. "ME ALEJE MUCHO Y NO FUE CAPAZ DE REGRESAR A MI LADO." NPC_RANGE (40) bounded BOTH the
--    slow sweep and the fast lane, so a companion 41 tiles behind got no rung, no follow and
--    no watchdog -- it was not lagging, it was dropped. The census proves it: free NPCs sat
--    at `master=37-39 rung=idle head=Time@nil,nil/-` and nothing was ever going to move them.
--    LOST_RANGE now carries OWNED companions out to 150 tiles on a deliberately cheap path.
--
-- 2. "SE QUEDA PEGANDOLE A LOS ZOMBIES" WHILE THE PLAYER RUNS. Two separate causes, both
--    real, and the previous rounds only ever addressed one of them:
--    (a) We only ever read `isSprinting()`. A player who JOGS is invisible to this file, and
--        jogging is what people actually do. `obey -> fight` is the single most common rung
--        transition in the 10-08 log -- 36 times, several off ONE zombie at 5 tiles.
--    (b) Even once we assert a follow, ManageCombat can call Bandit.ClearTasks and append a
--        Smack (BanditUpdate.lua:1181/1196/1205/1212). Bandit.ClearTasks KEEPS tasks whose
--        `lock == true` (Bandit.lua:369-382), so a locked follow survives, stays at the head,
--        and the Smack queues BEHIND it. Upstream sets `task.lock = false` itself
--        (BanditUpdate.lua:1383), so writing that field is an accepted pattern here.
--
--        TWO CORRECTIONS THIS COMMENT USED TO GET WRONG, BOTH FOUND BY MEASURING.
--
--        It said "UNCONDITIONALLY". It is not: all four sites are guarded by
--        BanditBrain.HasTaskType / HasTaskTypes / HasActionTask. That guard is load-bearing --
--        it is why a Smack already in the queue is not re-cleared every frame, and therefore
--        why a locked follow holds the head most of the time instead of fighting for it.
--
--        And it treated (b) as the main thief. The census now measures exactly that, and in a
--        full session `combat took the follow before it ran` fired ONCE, while our own ladder
--        printed `obey -> fight` 35 times. The lock is worth keeping and it fixes a real case,
--        but the thing taking your companion off you is RungOf, not Bandits -- see the FIGHT
--        branches there, which is where the remaining work is.
--
-- 3. "SI CAMINA PUEDE DESCANSAR MAS SU ENDURANCE." brain.endurance was a one-way ratchet:
--    Bandit.UpdateEndurance (Bandit.lua:423-432) accepts a positive delta, but nothing in
--    Bandits ever passes one except our own Sleep task. Hitting 0 costs about sixteen
--    seconds of helplessness -- ManageEndurance (BanditUpdate.lua:427-445) queues FIVE
--    {action="Time", anim="Exhausted", time=200, lock=true} tasks, and it runs BEFORE
--    ManageCombat, so an exhausted companion cannot even swing. That is the other half of
--    complaint 2, and it never appeared in a log line because endurance was never printed.
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
-- actually fresh (F3): mood.rung is never cleared on the way out of range, so reading the
-- SAME bound rather than a second number of Threat's own is what stops an NPC that wandered
-- off keeping a stale SURVIVE forever, unwatched by the module that could correct it.
--
-- THIS COMMENT USED TO SAY "mood.rung is only ever written inside the masterDist <=
-- NPC_RANGE guard below", and as of the lost-companion branch that is no longer true: an
-- owned companion between NPC_RANGE and LOST_RANGE has its rung FORCED to OBEY. The
-- conclusion above survives the correction, and it survives it in the safe direction --
-- Threat still only reads NPCs within NPC_RANGE, and the one rung written outside that
-- bound is OBEY, which is the rung that asks Threat to do nothing.
Autonomy.NPC_RANGE = NPC_RANGE

-- Tiles. The far leash, and it applies to OWNED companions ONLY.
--
-- NPC_RANGE is a COST bound, not a caring bound: everything expensive in this file --
-- scanSurroundings over the zombie cache, friendsNear over the bandit cache -- is per NPC per
-- sweep, and running it on everybody within 150 tiles would be the most expensive thing in
-- the mod. So the full ladder stays bounded at 40.
--
-- But "we cannot afford to think about you" was silently doing the work of "you are on your
-- own", and that produced the report: "me aleje mucho y no fue capaz de regresar a mi lado...
-- temporalmente deshabilitamos su autonomia si me alejo demasiado, su objetivo debe ser
-- llegar hasta donde estoy yo". Somebody who agreed to follow you does not stop being your
-- companion at 41 tiles.
--
-- 150 rather than something tidier: a companion further than that is almost certainly on the
-- far side of a cell boundary or was never going to path to you anyway, and a Move task
-- across that distance is a pathfinder request we should not be making every six seconds.
-- The path taken at this range is deliberately CHEAP -- no scan, no fear, no watchdog, no
-- claims -- so widening it costs one distance test and one task push per companion.
local LOST_RANGE = 150

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

-- ENDURANCE ---------------------------------------------------------------------------
--
-- brain.endurance is 0..1, spawns at 1.00 and -- until this round -- ONLY EVER DECREASED.
-- Bandit.UpdateEndurance (Bandit.lua:423-432) adds a delta and clamps to [0,1], and it does
-- accept a positive one; nothing in Bandits ever passes one. The only source of recovery in
-- the whole framework is our own sitting task (ScenesRelationsCompanion.lua:195-196, a Sleep
-- carrying endurance = REST_RECOVERY).
--
-- WHY A ONE-WAY RATCHET IS NOT MERELY UNTIDY. When it reaches 0, ManageEndurance
-- (BanditUpdate.lua:427-445) resets it to 1 and queues FIVE
-- {action="Time", anim="Exhausted", time=200, lock=true} tasks. task.time burns at roughly
-- 60 units per second (BanditUpdate.lua:1802-1803: decrement = 1 / ((fps + 0.5) * 0.01666667),
-- which is about 1 per frame), so 5 x 200 is about SIXTEEN SECONDS of a helpless NPC -- and
-- ManageEndurance runs BEFORE ManageCombat, so those tasks sit above every swing. That is the
-- "se cansa en medio camino y se le acercan muchos zombies" half of the running-fight report,
-- and because they are locked, our own Bandit.ClearTasks cannot lift them either.
--
-- THE ARITHMETIC, so the ratio is a decision and not a guess.
--   Sitting  REST_RECOVERY 0.5 per Sleep task of REST_TIME 450 units
--            450 / 60 = 7.5 s  ->  0.5 / 7.5   = 0.067 endurance per second
--   Walking  WALK_RECOVERY 0.02 per slow sweep; EveryOneMinute is ~6 real seconds
--                                  0.02 / 6    = 0.0033 endurance per second
-- That is a 20:1 ratio in favour of sitting down, which is the shape asked for: "si camina
-- puede descansar mas su endurance, es decir, aumenta su endurance pero mucho menos que
-- sentarse". Walking from empty to full takes about 50 sweeps (five real minutes); two sits
-- do it in fifteen seconds. Walking keeps you off the floor; it does not replace resting.
local WALK_RECOVERY = 0.02

-- Actions that earn NO walking recovery, because none of them is walking. Names taken from
-- vendor/Bandits/mods/Bandits/42.20/media/lua/shared/ZombieActions/ (ZASmack, ZAPush, ZAShoot,
-- ZAAim, ZARack, ZALoad, ZAUnload, ZADestroy, ZASmashWindow, ZAClimbFence), never invented.
--
-- Sleep is on the list for a different reason: it already pays REST_RECOVERY through the
-- framework's own completion hook (BanditUpdate.lua:1820-1822), so granting a walk bonus on
-- top would silently make sitting worth 0.52 instead of 0.5 and put the tuned 20:1 ratio out
-- by an amount nobody would ever find.
local NO_WALK_RECOVERY = {
    Smack = true, Push = true, Shoot = true, Aim = true, Rack = true,
    Load = true, Unload = true,
    Destroy = true, SmashWindow = true, ClimbFence = true,
    Sleep = true,
}

-- Below this fraction of endurance, a companion is winded and running is a bad trade.
-- 0.35 leaves real headroom above 0: at -0.07 per completed Run task that is still five Run
-- legs of margin before ManageEndurance's sixteen seconds of Exhausted, which is enough to
-- cross a street at a walk. Lower and the downgrade would fire too late to prevent anything;
-- higher and companions would walk in situations where sprinting is genuinely the answer.
local WINDED = 0.35

-- The band above WINDED that has to be cleared before the "rested" line prints again.
--
-- Without it the two crossing lines chatter forever. A companion hovering at 0.35 gains
-- WALK_RECOVERY (+0.02) on a walking sweep and prints "rested", then pays a Run leg (-0.07)
-- and prints "winded" -- two lines per companion per two sweeps, in a file whose whole
-- logging argument is that one census line is already expensive. 0.05 is wider than a single
-- walking sweep's gain (0.02) and narrower than a single Run leg's cost (0.07), so recovery
-- has to be real -- three walking sweeps at least -- before it is announced.
--
-- LOGGING ONLY. The behaviour threshold in assertFollow stays exactly WINDED; a companion
-- between 0.35 and 0.40 still runs. Widening the behaviour would be a tuning change and this
-- is not one.
local WINDED_HYSTERESIS = 0.05

-- Tiles. How far a WINDED companion is still willing to walk rather than run.
--
-- The tradeoff, stated plainly because it is a judgement and not a measurement: a companion
-- that walks and arrives beats one that sprints, collapses and gets eaten. Under this
-- distance walking closes the gap in a bearable time (15 tiles at a walk is roughly seventeen
-- seconds), so the endurance is worth more than the seconds. Past it, walking loses the
-- player entirely and running is the only option that ends with them beside you -- so beyond
-- 15 tiles we pay the 0.07 and run anyway. 15 is deliberately just past LEASH (12): inside
-- the leash they are still with you, and that is exactly where saving legs is affordable.
local WINDED_WALK_MAX = 15

-- Tiles. How much masterDist has to change, sweep to sweep, to count as a real shift
-- rather than pathing jitter. One name for what used to be two separate bare 0.75
-- literals (the falling-behind check and the old moving-toward check), so both agree on
-- what "changed" means.
local MASTER_DIST_EPSILON = 0.75

-- THE JOG TERM'S TWO GUARDS. Both exist because the first version of that term had neither,
-- and a term with no guard re-broke a bug this file had already fixed once.
--
-- The failure: `growing` only means the gap opened by MASTER_DIST_EPSILON (0.75 tiles) across
-- one six-second sweep, and `running` is sampled at the instant the sweep lands. A player who
-- jogs from the kitchen counter to the bedroom trips both. `disengaging` goes true, RungOf
-- returns OBEY, and assertFollow's Bandit.ClearTasks destroys whatever the companion was
-- doing -- once every six seconds. That is precisely what the comment beside the `growing and
-- masterDist > 6` term already warns about: "a player shuffling around a room they are
-- looting together kept tripping it". The claim that "jogging is by definition not shuffling"
-- was wrong; jogging between rooms is shuffling with a faster animation.
--
-- IT ALSO SILENTLY DESTROYED CHANGE 3. REST_RECOVERY (0.5) rides a Sleep of REST_TIME 450
-- (~7.5 s) and task.endurance is paid ONLY in the COMPLETED branch (BanditUpdate.lua:1819-1821),
-- so a rest cancelled at 7.4 seconds pays NOTHING. Every spurious trip of this term threw away
-- 0.5 endurance -- twenty-five sweeps of WALK_RECOVERY -- while claiming to add endurance.
--
-- RUNNING_LEAVE_RANGE (4) is deliberately LOWER than the 6 of the drift term beside it, and
-- that is not a preference: at 6 the jog term would be exactly subsumed by its neighbour and
-- would be dead code that reads like a rule -- the same defect this file records for
-- BREACH_PANIC and GRABBED_RANGE. A jog is stronger evidence than drift, so it earns a
-- tighter floor; 4 is inside FREE_RADIUS (7, ScenesRelationsCompanion.lua:60) on purpose,
-- because the streak below is what protects free activity, not the distance.
--
-- A SECOND GUARD -- two consecutive growing sweeps -- WAS DESIGNED AND IS NOT BUILT, and the
-- reason is that FLEE_HOLD_MS replaced the need for it. It would have added twelve seconds of
-- latency to a term whose whole job is to notice somebody leaving, and it would have been
-- protecting against a case that declared flight now answers directly and in under a second.
-- It is recorded here rather than left as a constant: `RUNNING_LEAVE_SWEEPS = 2` sat in this
-- file unreferenced for one commit, which is precisely the defect BREACH_PANIC and
-- GRABBED_RANGE were deleted for -- a number that reads like a rule nobody enforces.
local RUNNING_LEAVE_RANGE = 4

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

-- Sweeps before the same obstacle square is re-attempted. Without it, an NPC stuck at a
-- fence that cannot be climbed or a door that cannot be opened would try the same action
-- every sweep forever -- the same loop the user described as "se quedo atascado en la vaya
-- ... se quedaba corriendo contra la puerta cerrada y eso hacia que bajar mucho su
-- endurance, entonces descansaba y volvía a correr."
local OBSTACLE_RETRY = 8

-- One-time probes. If an engine method throws on IsoZombie, log it once and stop.
local engineProbeDone = false

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

-- IS THE MASTER RUNNING? --------------------------------------------------------------
--
-- IsoPlayer:isRunning() is the JOG, and it is a DIFFERENT method from isSprinting(). Vanilla
-- treats them as two states and tests both: pzserver/media/lua/client/Foraging/ISBaseIcon.lua
-- :700 reads `self.character:isRunning() or self.character:isSprinting()`, and
-- pzserver/media/lua/client/Tutorial/Steps.lua:1994 does the same. Until this round we only
-- ever read isSprinting(), which is why a jogging player was invisible to the whole file.
--
-- WHY THE RESULT IS REMEMBERED RATHER THAN PROBED EVERY TIME. This is called from the 800 ms
-- lane. If the method were ever absent, an unwrapped call would throw several times a second
-- forever, and a pcall taken fresh each time would still pay for a failed dispatch at that
-- cadence. So the first call decides, once, and the answer is kept for the session; a missing
-- method degrades to sprint-only behaviour, which is exactly what shipped before this change.
-- The log line fires ONCE, because a per-call line at 800 ms would bury console.txt.
local runningIsCallable

local function masterIsRunning(player)
    if runningIsCallable == false then return false end

    local ok, running = pcall(function() return player:isRunning() end)
    if not ok then
        if runningIsCallable == nil then
            SR.Log("AUTO isRunning() is not callable on this IsoPlayer -- "
                .. "falling back to isSprinting() only for the rest of the session")
        end
        runningIsCallable = false
        return false
    end

    runningIsCallable = true
    return running == true
end

-- FLIGHT, DECLARED BY THE PLAYER ------------------------------------------------------
--
-- ASKED FOR IN THESE WORDS, after a round where following was better but still not right:
--
--   "siento que no es necesario que hayan tantos tiles para que el sepa que estoy huyendo,
--    el hecho de correr o mantener shift presionado por mas de 5 segundos deberia
--    referenciar que estoy huyendo... De esta manera es mas facil para ellos seguirme."
--
-- That is a better signal than everything above it, and the reason is worth stating because it
-- reframes the whole problem. Every previous attempt asked a GEOMETRIC question -- is the gap
-- growing, is he past the leash, did masterDist change by more than 0.75 in six seconds -- and
-- every one of them shares the same defect: it cannot answer until the player has ALREADY got
-- away. By the time the geometry is convincing, the companion is the distance behind that the
-- geometry required as evidence. That is the "tantos tiles" in the sentence, exactly.
--
-- Holding run is not evidence of flight. It IS flight, and it is authored by the person who
-- knows. Nobody sprints for five seconds by accident, and nobody who is doing it wants their
-- companion to stay and trade blows. So this measures ONE thing: how long the player has been
-- under power without a break, in milliseconds, on the player and not per NPC.
--
-- FIVE SECONDS is the user's number and it is a good one. Shorter and crossing a room at a jog
-- would count; longer and a short sprint away from a bad room would not register until it was
-- over. It is deliberately NOT tunable per NPC: this is a fact about the player, and every
-- companion should read the same fact.
--
-- WHY A GRACE PERIOD. `isRunning()` is sampled, and the sample can be false for a frame at a
-- doorway, on a stair, or in the frame a collision resolves -- which would reset the clock and
-- mean a player who is plainly fleeing never accumulates five seconds. So a gap shorter than
-- FLEE_GRACE_MS does not break the run; anything longer does. This is the same reason
-- MOVED_EPSILON exists for the watchdog: a sampled world needs a tolerance or the measurement
-- is of the sampling, not of the thing.
--
-- AND IT MUST BE LARGER THAN THE SAMPLE PERIOD, which is the whole reason FAST_MS is declared
-- HERE rather than beside the fast lane that uses it. The first version of this shipped with a
-- flat 700 ms against an 800 ms tick, and an independent review found that it made the entire
-- feature dead code: every consecutive sample is at least FAST_MS apart, 800 > 700 was true on
-- EVERY tick, so `runStartedMs` was reset every tick and `now - runStartedMs` was always 0. The
-- five-second threshold could never be reached, six call sites read a value that was
-- permanently false, and the only evidence on the gaming PC would have been `flee=false` on
-- every census line -- indistinguishable from "he never ran".
--
-- A tolerance smaller than the resolution of the thing it tolerates is not a small mistake, it
-- is the measurement inverted. So the relationship is now STRUCTURAL rather than a coincidence
-- of two numbers that happen to be ordered correctly: two ticks of slack means one dropped
-- sample never breaks a run, and no future change to FAST_MS can silently kill this again.
-- THREE TICKS, NOT TWO, AND THE REASON IS THAT THE THROTTLE DRIFTS. The gate is
-- `if now - lastFastMs < FAST_MS then return end` followed by `lastFastMs = now` -- `now`, not
-- `lastFastMs + FAST_MS`. So each execution fires on the first OnTick at or past 800 ms and
-- then re-bases the clock to that later timestamp, never absorbing the overshoot. Two
-- consecutive executions are 1600 + 2 frames apart, which at 60fps is ~1633 ms.
--
-- At `FAST_MS * 2` (1600) that gap EXCEEDS the grace on every single dropped sample, so the
-- tolerance could never once be exercised: the only gap it exists to forgive is the gap that
-- breaks it. A review caught it; the shipped behaviour would have been "one missed frame at a
-- doorway costs you the whole five seconds", which is the complaint this feature answers.
--
-- Three ticks (2400) clears 1633 with room for a frame spike, and still cannot swallow a real
-- stop: two genuine crossings of the run/walk boundary are seconds apart, not milliseconds.
local FAST_MS = 800
local FLEE_HOLD_MS = 5000
local FLEE_GRACE_MS = FAST_MS * 3

local runStartedMs = nil     -- when the current unbroken run began
local runLastSeenMs = nil    -- the last tick the player was actually under power

-- The verdict, held for whoever asks between ticks. A plain value rather than a mood field on
-- purpose: it is a fact about the player, so storing a copy per NPC would let two companions
-- disagree about whether you are running away, which is not a thing that can be true.
local playerFleeing = false

--- Forget the run entirely. Called when the player is gone rather than merely walking.
---
--- ITS OWN FUNCTION BECAUSE THE CALLER THAT NEEDS IT IS THE ONE THAT RETURNS EARLY. fastFollow
--- is the only writer of `playerFleeing`, and it bails above the write when the player is dead
--- (`player:isDead()`). `sweep` has no such test and keeps running on EveryOneMinute, so it
--- would keep reading a stale `true`: every companion pinned on OBEY -- no fighting, no
--- looting, no resting -- for the whole death screen, because RungOf returns OBEY outright for
--- an owned companion whenever `disengaging` holds.
local function forgetFlight()
    runStartedMs, runLastSeenMs, playerFleeing = nil, nil, false
end

--- Update the flight clock, and answer whether the player is fleeing RIGHT NOW.
---
--- Called once per fast tick from fastFollow -- once per 800 ms for the whole world, not once
--- per NPC -- and the answer is cached on a file-local so the slow sweep reads the SAME verdict
--- rather than sampling the player a second time on its own cadence. Two modules measuring the
--- same player on two clocks is the R6 mistake this file's header already warns about.
local function updateFlight(player, now)
    local underPower = player:isSprinting() == true or masterIsRunning(player)

    if underPower then
        if not runStartedMs or (runLastSeenMs and (now - runLastSeenMs) > FLEE_GRACE_MS) then
            runStartedMs = now
        end
        runLastSeenMs = now
    elseif runLastSeenMs and (now - runLastSeenMs) > FLEE_GRACE_MS then
        runStartedMs, runLastSeenMs = nil, nil
    end

    return runStartedMs ~= nil and (now - runStartedMs) >= FLEE_HOLD_MS
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
--- "Inside" is `square:isOutside() == false`, the same question BanditUpdate.lua:912 asks
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

--- Release every lock WE placed, so our own clearing works again.
---
--- THIS IS THE SAFETY VALVE FOR THE WHOLE LOCKING SCHEME, and it is the single most important
--- function added this round. Bandit.ClearTasks (Bandit.lua:369-382) rebuilds brain.tasks
--- keeping only tasks whose `lock == true` -- it does not care WHO locked them. So a locked
--- task is invisible to every clear in the mod, including the watchdog's, which is the one
--- thing standing between a jammed NPC and a permanently frozen one.
---
--- ONLY OURS, AND ONLY FOLLOW. Bandits locks tasks of its own, and this is the complete list
--- in 42.20 (grepped for `lock = true` across the whole vendored tree):
---   Die       BanditUpdate.lua:282, BanditUpdate.lua:1721
---   Exhausted BanditUpdate.lua:439 (the five ManageEndurance queues)
---   Zombify   BanditUpdate.lua:476
---   GetUp     BanditUpdate.lua:2191, ZPCamper.lua:86, ZPRoadblock.lua:34
--- Every one of those is load-bearing for a state machine we do not own -- an NPC that never
--- finishes dying, or gets up halfway through standing. Clearing one would break it silently,
--- so the srGoal test is not a nicety: it is the boundary between "undo our own doing" and
--- "reach into somebody else's".
---
--- AND THE ACTION TEST, WHICH SRGOAL ALONE TURNED OUT NOT TO COVER. `srGoal == FOLLOW` was the
--- only condition at first, and it was too wide the moment the watchdog started queueing its
--- own locked work: the ClimbFence it inserts to get an NPC over a fence is tagged FOLLOW too
--- (it exists to resume the follow), so the next assertFollow unlocked it and the ClearTasks on
--- the very next line deleted it. The climb never happened and the NPC walked back into the
--- same fence -- the exact loop the watchdog was extended to break.
---
--- Movement is the only thing we ever lock for the reason this function exists to undo: a
--- follow must survive somebody else's clear, and then WE must be able to replace it. An action
--- task we locked is locked because it has to run to completion, which is the opposite.
---
--- Returns how many were released, so callers can log a number rather than a guess.
local function unlockOurs(brain)
    if not brain or type(brain.tasks) ~= "table" then return 0 end

    local released = 0
    for _, task in pairs(brain.tasks) do
        if task.lock == true and task.srGoal == SR.GOAL.FOLLOW
           and (task.action == "Move" or task.action == "GoTo") then
            task.lock = false
            released = released + 1
        end
    end
    return released
end

--- Hand the pathfinder back before throwing a movement task away.
---
--- THIS IS THE FIX FOR "EL NPC COMENZO A CORRER DEMASIADO RAPIDO... Y DIO TODA LA VUELTA".
--- Reported from play on 2026-08-10, and it is our bug, not Bandits'.
---
--- Bandits runs a task through NEW -> WORKING -> COMPLETED, and ONLY the COMPLETED branch
--- calls `ZombieActions[task.action].onComplete` (BanditUpdate.lua:1824). For a Move that
--- handler is the entire cleanup: `finder:cancel()`, `finder:reset()`, `setPath2(nil)`
--- (ZAMove.lua:45-51). Neither `Bandit.ClearTasks` (Bandit.lua:369-382) nor
--- `Bandit.RemoveTask` (Bandit.lua:361-367) calls it -- both are a bare `table.remove` /
--- table rebuild. A Move discarded mid-flight therefore leaves the pathfinder RUNNING, still
--- holding the route it was computing.
---
--- Two things follow, and the player reported both in the same sentence:
---
---   TOO FAST. `ZAMove.onStart` calls `pathToLocation` and then `getPathFindBehavior2():update()`
---   (ZAMove.lua:9-10), and `onWorking` calls `update()` again (:34) on the same frame the new
---   task starts working. On a finder that was never reset, that is two advancement steps in one
---   frame. Bandits never notices because its own programs replace a task perhaps once every few
---   seconds; our fast lane re-asserts up to five times in four seconds, so we pay it constantly.
---
---   THE LONG WAY ROUND. The stale route was computed for where the player USED to be. Cancelled
---   properly it is discarded; left alive it keeps steering, which is a companion walking a
---   corner it no longer has any reason to walk.
---
--- Calling `onComplete` ourselves is using their action's own contract, not replacing it
--- (principle 4) -- it is idempotent, it is exactly what "cancel this move" means, and it is
--- what the COMPLETED branch would have called one moment later. Deliberately NOT applying
--- `task.endurance`: the COMPLETED branch pays that (BanditUpdate.lua:1820) and this task is
--- being cancelled, not finished. Charging for a journey we are throwing away is how endurance
--- became a one-way ratchet in the first place.
---
--- Only Move and GoTo, and only while WORKING. A task still in NEW never started a path, and
--- every other action's onComplete has side effects we have no business triggering early.
local function releaseMove(zombie, brain)
    local head = brain and type(brain.tasks) == "table" and brain.tasks[1]
    if not head then return false end
    if head.action ~= "Move" and head.action ~= "GoTo" then return false end
    if head.state ~= "WORKING" then return false end

    local handler = ZombieActions and ZombieActions[head.action]
    if not handler or not handler.onComplete then return false end

    -- WRAPPED for the same reason the watchdog's probe is: this runs immediately before the
    -- ClearTasks that unsticks an NPC, and a throw here would propagate out of the per-NPC
    -- loop and out of a function registered bare on an event. Cleanup that can disable the
    -- clearing it precedes would be worse than no cleanup.
    local ok, err = pcall(handler.onComplete, zombie, head)
    if not ok then
        SR.Log(string.format("AUTO could not release the pathfinder on a %s -- %s",
            tostring(head.action), tostring(err)))
    end
    return ok
end

--- Put the master back at the head of the queue, using the framework's own follow task.
---
--- Same call ZPCompanion makes at the bottom of its Main; we are only making sure it is
--- reached. `free` means charge no endurance for this one. `lock` means this follow must
--- survive somebody else's Bandit.ClearTasks -- see below.
---
--- WHAT THIS COMMENT USED TO CLAIM, AND WHY IT WAS WRONG. It said GetMoveTaskTarget "tracks a
--- character rather than a coordinate", so the task would follow the player instead of walking
--- to where the player used to be. That is not true in 42.20. GetMoveTaskTarget
--- (BanditUtils.lua:1017-1036) does store `tid` and `isPlayer` on the task, but a grep of
--- vendor/Bandits/mods/Bandits/42.20/media/lua for either identifier returns those three lines
--- and NOTHING ELSE -- no consumer reads them back, and ZAMove.lua paths to task.x/task.y
--- once in onStart. The follow is a stale coordinate. What makes it track the player is that
--- the task is SHORT (Move carries time = 20 in singleplayer, about a third of a second at
--- 60 fps by BanditUpdate.lua:1802-1803) and is therefore re-asserted constantly -- by this
--- sweep every six seconds and by the fast lane every 800 ms. The behaviour is right; the
--- stated reason was not, and the difference matters the moment somebody tries to make the
--- task longer to "help it stick".
---
--- CHARGING. brain.endurance only ever decreased in this framework until WALK_RECOVERY above,
--- and a Run task costs 0.07 EVERY TIME ONE COMPLETES. The slow sweep pushes one per six
--- seconds, the same cadence their own program would; the fast tick can push one per second,
--- so charging both the same would drain a chasing companion to zero inside a minute -- which
--- is exactly the reported "despues de un rato los veo cansado de nuevo". A re-assertion is a
--- correction to a journey already being paid for, not a new journey.
---
--- LOCKING. ManageCombat calls Bandit.ClearTasks unconditionally before appending its Smack
--- (BanditUpdate.lua:1181/1196/1205/1212, task appended at 1911-1915 and never inserted
--- first), so an unlocked follow queued by us is wiped in the same frame and replaced by a
--- swing. With lock = true the follow survives that clear, stays at the head, and the Smack
--- queues behind it -- the NPC walks its leg, then swings, instead of only ever swinging.
--- That is "no quedarse peleando contra los zombies", implemented where the collision
--- actually happens.
---
--- A LOCKED MOVE CANNOT FREEZE AN NPC FOREVER, and that is a property of the framework rather
--- than of our care: ProcessTask decrements task.time unconditionally and forces COMPLETED at
--- <= 0 (BanditUpdate.lua:1799-1808), and Bandit.RemoveTask ignores the lock flag entirely
--- (Bandit.lua:361-367). So the worst case is one wasted third of a second. unlockOurs still
--- exists and is still called, because the guarantee we rely on there is OURS to keep, not
--- theirs to keep for us.
local function assertFollow(zombie, master, dist, free, lock, disengage)
    local brain = BanditBrain.Get(zombie)
    local endurance = tonumber(brain and brain.endurance) or 1

    -- THE JOG BELONGS HERE TOO, and leaving it out made the whole jog fix end in a WALK order.
    --
    -- The reported scenario, traced: the player jogs past, the companion is three tiles away
    -- swinging, the fast lane's closeChase fires correctly and calls this with dist = 3.0.
    -- With only isSprinting() to read, `false or 3.0 > 10` is false, so walkType was "Walk" --
    -- the companion was ordered to WALK after a jogging player, and stayed on Walk until the
    -- gap passed ten tiles. Every other part of change 1 worked and delivered a companion
    -- twelve tiles behind.
    --
    -- masterIsRunning rather than a second player:isRunning() call, so the pcall-once caching
    -- (see its own comment above) is not duplicated at a site that runs per NPC per tick.
    --
    -- WIDENING WHO PAYS -0.07 IS SAFE, and that was checked rather than assumed: of the three
    -- call sites, fastFollow and the LOST branch both pass free = true, so the only caller
    -- charged for a Run is the slow sweep's disengaging branch -- one leg per six seconds,
    -- exactly as before this change.
    local walkType = "Walk"
    local cost = 0
    if master:isSprinting() or masterIsRunning(master) or dist > 10 then
        walkType, cost = "Run", -0.07
    elseif master:isSneaking() and dist < 12 then
        walkType, cost = "SneakWalk", -0.01
    end

    -- WINDED: walk instead, and charge nothing. See WINDED / WINDED_WALK_MAX above for the
    -- tradeoff. Deliberately AFTER the choice above rather than folded into it, so the log
    -- still reads "Walk" and the downgrade is visible in the census rather than inferred.
    local downgraded = false
    if walkType == "Run" and endurance < WINDED and dist <= WINDED_WALK_MAX then
        walkType, cost, downgraded = "Walk", 0, true
    end

    if free then cost = 0 end

    local task = BanditUtils.GetMoveTaskTarget(cost,
        master:getX(), master:getY(), master:getZ(),
        BanditUtils.GetCharacterID(master), true, walkType, dist)

    -- BEFORE the clear, never after: a lock we placed on the last assertion would otherwise
    -- survive this one, and re-asserting a follow every 800 ms would stack locked follows
    -- until Bandit.AddTask's overflow guard flushed the queue (Bandit.lua:290-293).
    unlockOurs(brain)
    releaseMove(zombie, brain)
    Bandit.ClearTasks(zombie)

    -- PUSH THE NEAREST ZOMBIE BEFORE FOLLOWING when the master is leaving. A follow queued
    -- into the empty space after a clear still loses to ManageCombat's Smack on the very next
    -- tick because Combat runs inside GenerateTask before the program can re-assert. A Push is
    -- one fast frame that shoves whatever is in front, clears the melee range, and lets the
    -- follow start without an immediate combat override.
    if disengage and BanditZombie and BanditZombie.CacheLightZ
       and BanditUtils.GetClosestZombieLocation then
        local z = BanditUtils.GetClosestZombieLocation(zombie, { levelDiff = 0 })
        if z and z.dist and z.dist < 2 and z.id then
            Bandit.AddTask(zombie, SR.Own(SR.GOAL.FIGHT, {
                action = "Push", anim = "Shove", sound = "AttackShove",
                time = 60, endurance = -0.05,
                eid = z.id, x = z.x, y = z.y, z = z.z,
            }))
        end
    end

    -- PREEMPTIVE ROUTING. Before walking directly to the master, check whether the
    -- straight line is blocked by an actionable obstacle. If it is, route through the
    -- best opening first -- walk there, then start the follow from that square. Bandits'
    -- own bump handler does the crossing.
    --
    -- The watchdog (below, in the sweep) still fires reactively on a stall; this catches
    -- the case before the NPC walks into the wall at all. Same function, two moments:
    -- before the walk (here) and after a confirmed stall (the watchdog).
    if SR.Pathfinding and SR.Pathfinding.ChooseRoute then
        local opening = SR.Pathfinding.ChooseRoute(zombie,
            master:getX(), master:getY(), master:getZ())
        if opening then
            local legDist = BanditUtils.DistTo(zombie:getX(), zombie:getY(),
                opening.x + 0.5, opening.y + 0.5)
            local legTime = math.max(120, math.floor(legDist * 60) + 60)

            -- Match the watchdog's own routing: a locked ROUTE Move that walks to the
            -- standing square next to the opening. The ROUTE is queued before the follow,
            -- so it runs first. Locked so ManageCombat cannot steal it mid-route; the
            -- follow behind it is locked by the caller's own `lock` parameter as before.
            -- Uses Walk regardless of the follow's walkType -- a positioning leg is not
            -- a chase (see the watchdog at Autonomy.lua:1423-1427 for the same choice).
            Bandit.AddTask(zombie, SR.Own(SR.GOAL.ROUTE, {
                action = "Move", walkType = "Walk", lock = true,
                x = opening.x, y = opening.y, z = opening.z,
                time = legTime,
            }))
        end
    end

    local ours = SR.Own(SR.GOAL.FOLLOW, task)
    if lock then ours.lock = true end
    Bandit.AddTask(zombie, ours)

    -- The task table itself is returned so the caller can hold on to it. That reference is
    -- the ONLY way to answer "did this follow get to run" one sweep later -- see the
    -- did-combat-take-it check in the sweep.
    return walkType, downgraded, ours
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
    local isCombat = task and (task.action == "Smack" or task.action == "Push")

    if not signature or (not STALLABLE[task.action] and not isCombat) then
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

        -- AND THE LIST OF OPENINGS WE ALREADY TRIED DIES HERE, which is the clear that keeps
        -- `mood.triedOpenings` from being a latch. Reaching this line means the NPC is either
        -- working on something new or has physically moved, and both answer the only question
        -- the list exists to answer: the route is no longer stuck, so nothing is owed to the
        -- memory of which door failed. A door that was locked a minute ago may be open now, and
        -- refusing it forever is a worse lie than trying it twice.
        --
        -- Reachability, stated because this project has shipped four latches whose clear could
        -- not be reached: this branch is not gated on anything the list influences. `moved` is
        -- physics and `signature` is whatever Bandits put at the head -- neither can be
        -- suppressed by refusing an opening, and the routing leg itself sets `moved` true the
        -- moment the NPC takes a step. It cannot starve itself.
        mood.triedOpenings = nil
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
    local bx, by  -- blocker square, needed when a combat task (Smack/Push) is stuck at a window
    if SR.Move and SR.Move.WhatBlocks and task.x and task.y then
        local okWhy, kind, blx, bly = pcall(SR.Move.WhatBlocks, zombie,
            task.x, task.y, task.z or zombie:getZ())
        blocking = okWhy and tostring(kind or "clear") or "probe threw"
        bx, by = blx, bly
    end

    -- THE WATCHDOG IS THE SAFETY NET, AND A LOCK MAKES IT A NO-OP.
    --
    -- Bandit.ClearTasks keeps every task whose lock == true (Bandit.lua:369-382). We started
    -- locking follow tasks this round so ManageCombat cannot steal them -- which means that
    -- without this line, a locked follow whose Move walked into a wall would be preserved by
    -- the exact call that exists to remove it, the log would print "queue cleared" while
    -- nothing was cleared, and the watchdog would quietly stop being a safety net for the one
    -- task type most likely to need it.
    --
    -- Only ours: a Bandits lock (Die, Zombify, Exhausted, GetUp) is theirs and their state
    -- machines depend on it surviving.
    unlockOurs(brain)

    -- RELEASED HERE, NOT BESIDE THE CLEAR AT THE BOTTOM, and the difference is the whole fix.
    --
    -- It sat next to that clear first, and a review found it silently no-oped in the one branch
    -- the comment there claims it matters most for. The obstacle block below calls
    -- Bandit.AddTaskFirst, which inserts at index 1 (Bandit.lua:300-307) and pushes the stuck
    -- Move to index 2 -- so by the time the bottom of this function ran, releaseMove read
    -- ClimbFence as the head, saw a non-movement action, and returned without cancelling
    -- anything. The pathfinder kept the exact route that had just failed.
    --
    -- Up here the head is still the stuck task itself, which is what we mean to release: a
    -- stuck NPC is BY DEFINITION one whose route did not work, so carrying that route past the
    -- clear is carrying the thing that broke.
    releaseMove(zombie, brain)

    -- WHAT THE 10-08 SESSION ADDED, AND WHY CLEARING THE QUEUE WAS NOT ENOUGH.
    --
    -- The watchdog has been clearing the queue on a stuck NPC for weeks. It unsticks them for
    -- one sweep, and the next sweep re-queues the same follow/loot task to the same blocked
    -- destination -- so they walk back into the same wall and the watchdog fires again.
    --
    -- "se quedo atascado en la vaya... se quedaba corriendo contra la puerta cerrada y eso
    -- hacia que bajar mucho su endurance, entonces descansaba y volvia a correr" is exactly
    -- that loop described by the user: stuck → clear → re-queue → stuck → endurance zero →
    -- exhausted → rest → re-queue → stuck again. Clearing alone is a safety net with no exit.
    --
    -- Now, for obstacles a Bandits action can overcome, the watchdog queues that action FIRST
    -- and then clears the old one. After the action completes and the task queue drains, the
    -- sweep re-evaluates and queues a fresh follow/loot -- which now paths through the cleared
    -- obstacle rather than into it.
    --
    -- Obstacles that cannot be acted on (solid walls, locked doors with no key) are still just
    -- cleared, because the only fix is a different route and that belongs to block B.
    --
    -- RETRY COOLDOWN, because a fence ClimbFence cannot clear or a door that stays locked
    -- would otherwise loop forever. The cooldown key includes the square so a different
    -- obstacle on a different tile gets its own fresh attempt.
    local obstacleKey = string.format("%d.%d.%d.%s",
        task.x or 0, task.y or 0, task.z or zombie:getZ(), blocking)
    local lastAttempt = mood.obstacleAttempts and mood.obstacleAttempts[obstacleKey]
    if not lastAttempt or (sweepNumber - lastAttempt) >= OBSTACLE_RETRY then
        local overcame = false

        -- COMBAT AT A WINDOW: the NPC is swinging/pushing at a zombie behind glass.
        -- The watchdog never fires on Smack/Push under the normal STALLABLE gate,
        -- but the NPC is stuck nonetheless — the weapon can't reach through a window.
        if isCombat and blocking == "window" then
            local smashTask = { action = "SmashWindow", anim = "WindowSmash",
                lock = true, x = bx or task.x, y = by or task.y, z = task.z or zombie:getZ(),
                srGoal = SR.GOAL.FOLLOW }
            Bandit.AddTaskFirst(zombie, smashTask)
            overcame = true
            SR.Log(string.format(
                "AUTO %s | stuck on %s for %d sweeps -- fighting through window -- queued SmashWindow at %d,%d",
                name, signature, STUCK_SWEEPS, bx or task.x, by or task.y))

        elseif blocking == "hop" or blocking == "tall" then
            -- FENCE/WALL CLIMB — hybrid: engine state for animation, teleport for movement.
            --
            -- Research (12-08): climbOverFence/Wall DON'T WORK on IsoZombie. Bandits'
            -- changeState(ClimbOverFenceState) plays the animation but the engine never
            -- completes the tile transition because ClimbOverFenceState.execute() runs in
            -- Java and does not move IsoZombie objects. The original ZAClimbFence.lua
            -- (commented out in Bandits) worked around this by nudging the NPC 0.005
            -- units/frame via setX/setY — same concept, but incremental nudges are janky.
            --
            -- This approach keeps the engine state for the VISUAL animation and handles
            -- the MOVEMENT ourselves with a single teleport after the animation duration.
            -- ZASleep.lua confirms setX/setY/setZ work on IsoZombie for full repositioning.
            local square = zombie:getCell():getGridSquare(task.x, task.y, task.z or zombie:getZ())
            if square then
                local dir
                if square:has(IsoFlagType.HoppableN) then
                    dir = (zombie:getY() < square:getY()) and IsoDirections.S or IsoDirections.N
                else
                    dir = (zombie:getX() < square:getX()) and IsoDirections.E or IsoDirections.W
                end

                zombie:faceDirection(dir)

                -- Start the engine state + bump animation (visual only).
                if blocking == "tall" then
                    zombie:setBumpType("ClimbFenceTall")
                    zombie:setCollidable(false)
                else
                    zombie:changeState(ClimbOverFenceState.instance())
                    zombie:setBumpType("ClimbFenceEnd")
                end

                -- Landing tile: centre of the fence square + one full tile in the
                -- facing direction. Anchored to the SQUARE, not the NPC: if the NPC
                -- is behind the square centre, adding 1.0 from the NPC position lands
                -- them on the same fence tile. The square centre + 1.0 reliably produces
                -- the adjacent tile, matching vanilla climbOverFence(dir)'s behaviour.
                local fd = zombie:getForwardDirection()
                local landingX = square:getX() + 0.5 + fd:getX() * 1.0
                local landingY = square:getY() + 0.5 + fd:getY() * 1.0
                local landingZ = zombie:getZ()

                -- Stored on mood so the sweep (below) teleports after ~12s.
                -- Preserve the pre-climb collidable state for restoration.
                mood.climbTarget = { x = landingX, y = landingY, z = landingZ, ticks = 0,
                                     wasCollidable = zombie:isCollidable() }
                overcame = true

                SR.Log(string.format(
                    "AUTO %s | stuck on %s for %d sweeps -- blocked by %s -- climb hybrid %s | landing %.1f,%.1f",
                    name, signature, STUCK_SWEEPS, blocking,
                    blocking == "tall" and "ClimbFenceTall+teleport" or "ClimbOverFence+ClimbFenceEnd+teleport",
                    landingX, landingY))
            end  -- if square then

        elseif blocking == "window" then
            -- TWO KINDS OF WINDOW, AND THE NPC FINDS OUT WHICH BY TRYING.
            -- Sliding windows open (ToggleWindow), fixed windows must be smashed. The NPC
            -- cannot know which is which without touching it, so it tries the least
            -- destructive option first: OpenWindow on the first attempt, SmashWindow on
            -- the retry if the open did not work.
            --
            -- The obstacleAttempts mechanism already records the first attempt and prevents
            -- re-queuing for OBSTACLE_RETRY sweeps. If the NPC reaches this branch again
            -- AFTER the cooldown, the open action completed but the NPC is STILL stuck at
            -- the same window -- which means it is a fixed window that cannot be opened.
            -- Second attempt: smash it.
            local isRetry = lastAttempt and (sweepNumber - lastAttempt) >= OBSTACLE_RETRY
            if isRetry then
                local smashTask = { action = "SmashWindow", anim = "WindowSmash",
                    lock = true, x = task.x, y = task.y, z = task.z or zombie:getZ(),
                    srGoal = SR.GOAL.FOLLOW }
                Bandit.AddTaskFirst(zombie, smashTask)
                overcame = true
                SR.Log(string.format(
                    "AUTO %s | stuck on %s for %d sweeps -- blocked by window, open failed -- queued SmashWindow",
                    name, signature, STUCK_SWEEPS))
            else
                -- First attempt: try to open it.
                local openTask = { action = "OpenWindow", anim = "WindowOpen",
                    lock = true, x = task.x, y = task.y, z = task.z or zombie:getZ(),
                    srGoal = SR.GOAL.FOLLOW, time = 60 }
                Bandit.AddTaskFirst(zombie, openTask)
                overcame = true
                SR.Log(string.format(
                    "AUTO %s | stuck on %s for %d sweeps -- blocked by window -- queued OpenWindow",
                    name, signature, STUCK_SWEEPS))
            end

        elseif blocking == "door" then
            -- Try to open the door. getIsoDoor is Bandits API on IsoGridSquare
            -- (vendor/Bandits/42.20/BanditUtils.lua:490); vanilla uses getIsoDoor() on
            -- IsoCell at one callsite but the square variant is Bandits-only.
            -- door:ToggleDoor(character) is vanilla (Tests/TimedActionsTests.lua:422)
            -- but only ever called with an IsoPlayer -- IsoZombie extends IsoGameCharacter
            -- so the Java binding may accept it. pcall protects us either way.
            local square = zombie:getCell():getGridSquare(task.x, task.y, task.z or zombie:getZ())
            if square then
                local door = square:getIsoDoor()
                if door and not door:IsOpen() then
                    local okDoor = pcall(function() door:ToggleDoor(zombie) end)
                    overcame = okDoor
                    if overcame then
                        SR.Log(string.format(
                            "AUTO %s | stuck on %s for %d sweeps -- blocked by door -- toggled it",
                            name, signature, STUCK_SWEEPS))
                elseif not engineProbeDone then
                    engineProbeDone = true
                    SR.Log(string.format(
                        "AUTO %s | ToggleDoor(zombie) threw -- door open via Lua may not work on IsoZombie",
                        name))
                    end
                end
            end
        end

        -- THE SIXTEEN OF TWENTY THE TWO BRANCHES ABOVE CANNOT TOUCH.
        --
        -- Measured across two play sessions, `blocked by` came out 10 `solid`, 6 `clear`,
        -- 2 `locked`, 2 `hop`, 0 `door`. ClimbFence and ToggleDoor between them address four of
        -- those twenty, and in a full session afterwards they fired once and never. The other
        -- sixteen are a wall, or a jam with the straight line clear -- meaning the obstacle was
        -- never on the line at all, which WhatBlocks is blind to by construction.
        --
        -- Those sixteen are one symptom with one cause, and the player named all three faces of
        -- it in one sentence: "se atasca demasiado para salir de una casa", "rodean todo los
        -- edificios", "sigue sin poder saltar muros y vallas". An NPC inside a building whose
        -- target is outside asks the engine pathfinder for a route, and the engine answers with
        -- the way around, because going around IS a valid path and nothing tells it to prefer an
        -- opening. It is not failing to use the window. It is never asked to.
        --
        -- SO WE ROUTE, AND BANDITS CROSSES. Move.FindOpening is a pure query that returns the
        -- square to STAND ON next to the best door or window, in the ordering the user asked
        -- for. We walk them there and stop. Their own bump handler does the rest:
        -- canClimbThrough -> ClimbThroughWindowState (BanditUpdate.lua:683-686), or a closed
        -- window -> its own OpenWindow task (:677-680). We add no crossing verb, which is
        -- principle 4 -- the machinery already works, it was just never reached.
        --
        -- HERE, NOT IN THE SWEEP, and that is the routing agent's own constraint: this scans
        -- about 314 squares of getObjects(), which is fine occasionally and badly wrong several
        -- times a second. Being stuck is exactly "occasionally", and it is also the only moment
        -- we KNOW the ordinary route failed. The obstacleAttempts cooldown below covers it for
        -- free, so a building whose openings are all unusable is not re-scanned every sweep.
        --
        -- NO LATCH, DELIBERATELY. Nothing remembers that an opening was chosen. The next stall
        -- asks again from scratch, because the door may have been opened, locked or smashed by
        -- anyone in the meantime -- an objective is RECALCULATED, never REMEMBERED, and the
        -- one-shot flag is precisely how ScenesRelationsIdle.goGet died on 2026-08-08.
        if not overcame and SR.Move and SR.Move.FindOpening then
            -- THE OPENING WE ALREADY TRIED IS EXCLUDED, which is how the user's second tier --
            -- "la siguiente puerta exterior" -- actually happens. FindOpening deliberately
            -- keeps no memory (an objective is recalculated, never remembered), so "we tried
            -- that one and it did not work" is the caller's to hold, and the caller is here.
            --
            -- Without this the branch re-picks the same door on every stall forever: the
            -- obstacleAttempts cooldown is keyed on the TARGET square, which moves with the
            -- player, so it never stands in for this. A documented capability wired to nothing
            -- is the same defect as a constant nobody reads.
            --
            -- Scoped per building visit rather than forever: cleared as soon as a route
            -- succeeds or the NPC stops being stuck, because a door that was locked five
            -- minutes ago may be open now and refusing it permanently is a worse lie than
            -- trying it twice.
            mood.triedOpenings = mood.triedOpenings or {}
            local okOpen, opening = pcall(SR.Move.FindOpening, zombie,
                task.x, task.y, task.z or zombie:getZ(),
                { exclude = mood.triedOpenings })

            -- BREAK is a REPORT, not a plan, and we decline it here. Smashing a window is loud,
            -- permanent and never what a companion trying to follow you should do on its own;
            -- it is logged so the census can show how often it was the only way through.
            if okOpen and opening and opening.kind ~= SR.Move.OPEN_BREAK then
                -- LOCKED, AND TAGGED ROUTE RATHER THAN FOLLOW. Both halves are load-bearing and
                -- the first version had neither, which made this whole branch a no-op that
                -- logged success -- the most expensive kind of bug, because the log is the only
                -- instrument on the other machine.
                --
                --   lock: `Bandit.ClearTasks` fires twenty lines below and keeps ONLY locked
                --   tasks (Bandit.lua:369-382). Unlocked, the route was deleted in the same
                --   sweep it was queued. The ClimbFence branch above already states this rule;
                --   this branch was written without it, which is exactly the R6 shape.
                --
                --   ROUTE, not FOLLOW: `unlockOurs` releases every locked FOLLOW Move so a
                --   re-asserted follow can replace the old one, and the fast lane calls it
                --   about once a second. Tagged FOLLOW, the route would have survived the clear
                --   here only to be unlocked and deleted ~800 ms later. Adding the lock alone
                --   fixes nothing; it took both.
                --
                -- TIME DERIVED FROM THE ACTUAL DISTANCE, not a flat 200. task.time burns about
                -- one unit per frame normalised to 60fps (BanditUpdate.lua:1802), so 200 is
                -- ~3.3 real seconds -- and openings are selected out to OPENING_RADIUS (10)
                -- plus the standing square. A walk that times out mid-route completes exactly
                -- like a walk that arrived (ZAMove.lua:33-38 only reports done on Succeeded or
                -- Failed), so the difference would have been invisible. 60 units per tile at a
                -- walk is generous; the watchdog re-fires if it was not enough.
                -- THE CEILING THIS BUYS, STATED SO NOBODY HAS TO DERIVE IT. A locked task at the
                -- head is one nothing else can replace, so for legTime the NPC will not
                -- re-assert a follow and will not be pulled off by the fast lane. At the widest
                -- opening (11 tiles) that is about twelve seconds of committed walking.
                --
                -- That is deliberate and it is the point: the whole failure being fixed is an
                -- NPC that keeps being redirected at the player and therefore keeps taking the
                -- route around the building. It is also SAFE, because nothing can hold it past
                -- the timer -- ProcessTask forces COMPLETED at time <= 0 and Bandit.RemoveTask
                -- ignores lock entirely (Bandit.lua:361-367), so a route that cannot finish
                -- expires rather than freezing anybody.
                local legDist = BanditUtils.DistTo(zombie:getX(), zombie:getY(),
                    opening.x + 0.5, opening.y + 0.5)
                local legTime = math.max(120, math.floor(legDist * 60) + 60)

                Bandit.AddTaskFirst(zombie, SR.Own(SR.GOAL.ROUTE, {
                    action = "Move", walkType = "Walk", lock = true,
                    x = opening.x, y = opening.y, z = opening.z,
                    time = legTime,
                }))
                -- Recorded BEFORE we know whether it worked, on purpose. If it works we clear
                -- the list on the next unstuck sweep; if it does not, the next stall must pick
                -- a different one, and that is only possible if this attempt is already here.
                table.insert(mood.triedOpenings,
                    { x = opening.ox or opening.x, y = opening.oy or opening.y,
                      z = opening.oz or opening.z })
                overcame = true
                SR.Log(string.format(
                    "AUTO %s | stuck on %s -- blocked by %s -- routing to the %s at %d,%d (%s) | %.1f tiles, %d units",
                    name, signature, blocking, tostring(opening.kind),
                    opening.ox or opening.x, opening.oy or opening.y, tostring(opening.why),
                    legDist, legTime))
            elseif okOpen and opening then
                SR.Log(string.format(
                    "AUTO %s | stuck on %s -- blocked by %s -- the only way through is %s (%s), declined",
                    name, signature, blocking, tostring(opening.kind), tostring(opening.why)))
            elseif not okOpen then
                SR.Log(string.format("AUTO %s | FindOpening threw -- %s",
                    name, tostring(opening)))
            end
        end

        if overcame then
            if not mood.obstacleAttempts then mood.obstacleAttempts = {} end
            mood.obstacleAttempts[obstacleKey] = sweepNumber
        end
    end

    -- releaseMove already ran, ABOVE the obstacle block -- see the note there for why it
    -- cannot run here: AddTaskFirst has moved the stuck task off the head by this point.
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

    -- THE JOG, WHICH USED TO BE INVISIBLE. See masterIsRunning above for why this is a
    -- different method from isSprinting() and where vanilla tests both.
    --
    -- CALIBRATION, AND IT IS THE WHOLE OF THIS CHANGE. `running` is deliberately NOT OR'd
    -- into `disengaging` on its own. In play the player jogs almost all of the time, so an
    -- unqualified term would make disengaging permanently true -- and disengaging is the FIRST
    -- test in RungOf, returning OBEY above everything. Every companion would follow forever:
    -- no looting, no fighting, no free activity, ever. That is a worse bug than the one being
    -- fixed, and it would look like the mod had simply stopped working.
    --
    -- So running only counts WITH `growing`, i.e. the gap is actually opening. A sprint stays
    -- unqualified because a sprint is unambiguous and player-authored; a jog is only evidence
    -- of leaving when you are in fact being left.
    local running = masterIsRunning(player)

    -- READ, NOT MEASURED. The flight clock is advanced once per fast tick (800 ms) in
    -- fastFollow; this six-second sweep only reads the verdict. Sampling the player again on
    -- this cadence would give the two lanes different answers about the same person, and a
    -- five-second threshold measured on a six-second clock cannot distinguish four seconds of
    -- running from eleven.
    local fleeing = playerFleeing

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

                    local program = brain.program and brain.program.name
                    local owned = (program == "Companion" or program == "CompanionGuard")
                        and brain.master

                    -- BACK IN RANGE. The other half of the lost-companion state below; logged
                    -- so the console shows a recovery rather than a companion that simply
                    -- stopped being mentioned.
                    if mood.lost then
                        mood.lost = nil
                        SR.Log(string.format(
                            "AUTO %s | found again at %.1f tiles -- back inside %d, autonomy restored",
                            name, masterDist, NPC_RANGE))
                    end

                    -- THE HEAD AS WE FOUND IT, sampled before anything in this sweep touches
                    -- the queue. Everything below that reasons about "what were they doing for
                    -- the last six seconds" has to read THIS, not a head we just rewrote.
                    local entryHead = headTask(brain)
                    local entryAction = entryHead and entryHead.action or nil

                    -- DID MANAGECOMBAT TAKE OUR FOLLOW BEFORE IT RAN? This is the direct
                    -- measurement of "se queda pegandole a los zombies", and nothing in the
                    -- log could see it happen: a Smack at the head looks identical whether it
                    -- replaced a follow or was queued into an empty queue by their own program.
                    --
                    -- COMPARING HEADS ACROSS SWEEPS CANNOT ANSWER IT, and the first version of
                    -- this check tried to. A follow Move carries time = 20 in singleplayer
                    -- (BanditUtils.lua:1033), which is about a third of a second
                    -- (BanditUpdate.lua:1802-1803), so by the next sweep six seconds later it
                    -- is gone EITHER WAY -- finished normally, or cleared mid-flight. A test
                    -- built on "the head used to be a follow and is now a Smack" would report
                    -- theft on every single follow leg, including the ones that worked, which
                    -- is worse than no line at all.
                    --
                    -- The reference to the task table we queued does answer it. ProcessTask
                    -- writes task.state, and only sets "COMPLETED" on the path that then calls
                    -- Bandit.RemoveTask (BanditUpdate.lua:1806-1830). So a follow that is no
                    -- longer in the queue and never reached "COMPLETED" was removed by somebody
                    -- else's Bandit.ClearTasks -- which, when the head is now one of the two
                    -- tasks ManageCombat queues (Push at BanditUpdate.lua:1187, Smack at
                    -- 1199/1222), names the culprit.
                    --
                    -- Once per EPISODE, not per sweep. The episode ends when the head stops
                    -- being a combat task.
                    --
                    -- THE REFERENCE LIVES ON SR.Mood, which is entity modData and therefore
                    -- saved. That is one small table of primitives per companion -- a task is
                    -- action/time/endurance/x/y/z/walkType/state and nothing else -- and it is
                    -- overwritten on every assertion, so it cannot accumulate. After a load the
                    -- reference is a different table from anything in brain.tasks, so the check
                    -- fires at most one spurious line per NPC per load and then clears itself;
                    -- that was judged cheaper than a file-local keyed by NPC id, which would
                    -- have needed its own eviction for NPCs that died out of sight.
                    local combatHead = entryAction == "Smack" or entryAction == "Push"

                    local pending = mood.followTask
                    if pending then
                        local queued = false
                        if type(brain.tasks) == "table" then
                            for _, t in pairs(brain.tasks) do
                                if t == pending then
                                    queued = true
                                    break
                                end
                            end
                        end

                        if not queued then
                            mood.followTask = nil
                            if pending.state ~= "COMPLETED" and combatHead then
                                if not mood.stolenEpisode then
                                    SR.Log(string.format(
                                        "AUTO %s | combat took the follow before it ran | "
                                        .. "state=%s locked=%s head=%s master=%.1f",
                                        name, tostring(pending.state),
                                        tostring(pending.lock == true),
                                        tostring(entryAction), masterDist))
                                end
                                mood.stolenEpisode = true
                            end
                        end
                    end

                    if not combatHead then mood.stolenEpisode = nil end

                    -- ENDURANCE COMES BACK WHILE WALKING. See WALK_RECOVERY above for the
                    -- arithmetic and for why a one-way ratchet costs sixteen seconds of
                    -- Exhausted the moment it reaches zero.
                    --
                    -- Judged on entryHead, because that is what they actually spent the sweep
                    -- doing. Running is excluded by walkType rather than by action: a follow
                    -- and a sprint for a window are both Move tasks and only the walkType
                    -- (BanditUtils.lua:1033) tells them apart. Bandit.UpdateEndurance clamps
                    -- to [0,1] for us (Bandit.lua:427-429), so no bound is needed here.
                    local exerting = entryAction and NO_WALK_RECOVERY[entryAction] or false
                    local runningLeg = (entryAction == "Move" or entryAction == "GoTo")
                        and entryHead.walkType == "Run"
                    if not exerting and not runningLeg then
                        Bandit.UpdateEndurance(zombie, WALK_RECOVERY)
                    end

                    -- Read AFTER the recovery above, so the census and the crossing below
                    -- report the value this sweep actually leaves the NPC with.
                    local endurance = tonumber(brain.endurance) or 1

                    -- ONE LINE PER CROSSING. Endurance moves every sweep; the only interesting
                    -- moments are the two where it changes what the NPC will do -- below WINDED
                    -- a follow downgrades from Run to Walk (assertFollow), above it does not.
                    --
                    -- THE BAND IS NOW ACTUALLY APPLIED, and the play log is what proved it had
                    -- to be. WINDED_HYSTERESIS was declared, documented, and then never
                    -- referenced -- so this shipped as a bare threshold and printed 36 lines in
                    -- one session, Carter Wood alone crossing five times each way. A single
                    -- threshold cannot help flapping here: the two forces either side of it are
                    -- tiny and opposite -- +WALK_RECOVERY (0.02) pushes up through 0.35 on a
                    -- walking sweep, one completed Run leg (-0.07) pushes straight back down.
                    if endurance < WINDED and not mood.winded then
                        mood.winded = true
                        SR.Log(string.format(
                            "AUTO %s | winded -- endurance %.2f below %.2f, follow walks under %d tiles",
                            name, endurance, WINDED, WINDED_WALK_MAX))
                    elseif endurance >= (WINDED + WINDED_HYSTERESIS) and mood.winded then
                        mood.winded = nil
                        SR.Log(string.format("AUTO %s | rested -- endurance %.2f back above %.2f",
                            name, endurance, WINDED + WINDED_HYSTERESIS))
                    end

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
                        --
                        -- `fleeing` IS THE ANSWER AND IT COMES FIRST, with no distance term of
                        -- any kind. See updateFlight: five seconds of unbroken running is the
                        -- player SAYING they are leaving, and a companion should not need to
                        -- watch a gap open to be told something it has already been told.
                        -- Everything below it is now the fallback for a player who is leaving
                        -- without running -- walking out of a house, driving off.
                        --
                        -- `running and growing` is the jog, and it is QUALIFIED with a distance
                        -- floor of its own. It did not have one, and that was a defect an
                        -- independent review caught before it reached the gaming PC: `growing`
                        -- only needs 0.75 tiles across a six-second sweep, so a player jogging
                        -- from the kitchen counter to the bedroom -- four tiles -- tripped it,
                        -- and every trip clears the queue. The comment that used to sit here
                        -- argued "a player who is jogging is by definition not shuffling",
                        -- which is false: jogging between rooms is shuffling with a faster
                        -- animation. RUNNING_LEAVE_RANGE is the floor, and it is lower than
                        -- the 6 of the drift term below because running is a stronger signal
                        -- than drifting, not because four tiles means anything on its own.
                        disengaging = fleeing
                            or sprinting or masterDist > LEASH
                            or (running and growing and masterDist > RUNNING_LEAVE_RANGE)
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

                        -- RELEASE BEFORE CLEARING, both the lock and the pathfinder.
                        --
                        -- The lock: without this, ClearTasks PRESERVES our locked follow
                        -- (Bandit.lua:369-382) and the line below prints "queue cleared" while
                        -- one task quietly survived -- the log would be lying about the single
                        -- most load-bearing action in this file. Escalation is allowed to win:
                        -- a rung can only rise to FIGHT or SURVIVE when `disengaging` is false,
                        -- because RungOf returns OBEY outright whenever an owned companion is
                        -- disengaging, so this can never cancel a follow the player is owed.
                        --
                        -- The pathfinder: see releaseMove. Escalating to FIGHT while a route
                        -- keeps steering is a companion swinging at one thing and drifting
                        -- toward another.
                        unlockOurs(brain)
                        releaseMove(zombie, brain)
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
                        -- LOCKED, because reaching this branch IS the disengaging case. The
                        -- master is leaving and ManageCombat would otherwise wipe this follow
                        -- in the same frame and replace it with a swing -- see assertFollow.
                        local walkType, downgraded, followTask =
                            assertFollow(zombie, player, masterDist, false, true, true)
                        mood.followTask = followTask
                        mood.taskSig, mood.taskTicks = nil, 0
                        if before ~= Autonomy.OBEY or census then
                            SR.Log(string.format(
                                "AUTO %s | following master at %.1f tiles (%s%s, locked) -- %s",
                                name, masterDist, walkType,
                                downgraded and ", winded" or "",
                                sprinting and "master sprinting"
                                    or (running and growing and "master running")
                                    or (growing and "falling behind" or "past leash")))
                        end
                    else
                        -- A LOCK IS A LOAN. They have caught up, or the master stopped: the
                        -- reason the follow needed to outlive somebody else's ClearTasks is
                        -- gone, and a companion still carrying one would make the ladder's own
                        -- escalation clear (above) and the watchdog (below) into no-ops.
                        --
                        -- Owned only, because only an owned companion is ever handed a locked
                        -- follow in the first place.
                        if owned and not ctx.disengaging then
                            local released = unlockOurs(brain)
                            if released > 0 then
                                SR.Log(string.format(
                                    "AUTO %s | caught up at %.1f tiles -- released %d follow lock(s)",
                                    name, masterDist, released))
                            end
                        end

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

                    -- CLIMB TELEPORT TICKER. The watchdog queues a climb state + animation
                    -- (above) and stores the landing tile on mood.climbTarget. This counter
                    -- fires once per sweep (~6s) until the animation has had time to play,
                    -- then teleports the NPC to the landing tile in a single setX/setY/setZ
                    -- jump. ZASleep.lua (Bandits) confirms setX/setY/setZ work on IsoZombie.
                    --
                    -- 2 sweeps at ~6s each = ~12s. That is generous for a fence crossing,
                    -- fence crossing animation, but the sweep is the cheapest clock we have.
                    -- A faster cadence (OnTick) would be 360x more expensive for one delayed
                    -- action. If the animation completes sooner, the engine handles it;
                    -- the teleport is the SAFETY NET for the case where it does not.
                    if mood.climbTarget then
                        mood.climbTarget.ticks = mood.climbTarget.ticks + 1
                        if mood.climbTarget.ticks >= 2 then  -- ~12s, animation should be done
                            local tx, ty, tz = mood.climbTarget.x, mood.climbTarget.y, mood.climbTarget.z
                            zombie:setX(tx)
                            zombie:setY(ty)
                            zombie:setZ(tz)
                            -- Restore the collidable state the NPC had before the climb,
                            -- not unconditionally true: they may have been non-collidable.
                            zombie:setCollidable(mood.climbTarget.wasCollidable ~= false)
                            SR.Log(string.format(
                                "AUTO %s | climb teleport to %.1f,%.1f,%d after %d sweeps",
                                name, tx, ty, tz, mood.climbTarget.ticks))
                            mood.climbTarget = nil
                        end
                    end

                    -- THE HEAD AS WE LEAVE IT, for the census. Read once rather than twice so
                    -- `head=` and `lock=` describe the same task and can never disagree.
                    local tail = headTask(brain)
                    local headLocked = tail ~= nil and tail.lock == true

                    if census then
                        -- THREE FIELDS ADDED THIS ROUND, all because the 10-08 report could
                        -- not be confirmed or refuted from the log:
                        --   end=   brain.endurance. Both "se cansa en medio camino" and "si
                        --          camina puede descansar" are endurance claims, and endurance
                        --          had never once been printed.
                        --   run=   whether the master was running or sprinting this sweep --
                        --          the state that is supposed to pull them off a fight.
                        --   lock=  whether the head task is locked. Without it there is no way
                        --          to see that a follow survived ManageCombat's ClearTasks.
                        -- Still ONE line: a second census line per NPC halves how much history
                        -- fits in console.txt, and console.txt is the only debugger we have.
                        SR.Log(string.format(
                            -- `dis=` AND `flee=` ARE THE TWO THAT WERE MISSING, and their
                            -- absence is why the last round could not be diagnosed from the
                            -- log alone. 35 `obey -> fight` transitions were recorded with no
                            -- way to tell whether the disengage test had FAILED or had never
                            -- been consulted -- and those are opposite bugs with opposite
                            -- fixes. `disengaging` is the first test in RungOf and decides
                            -- everything below it; a value that decides everything and prints
                            -- nowhere is the most expensive kind of invisible.
                            "AUTO census | %s | rung=%s fear=%d/%d hp=%.2f end=%.2f z=%d@%.1f in=%d out=%d %s friends=%d master=%.1f run=%s flee=%s dis=%s bag=%s head=%s lock=%s",
                            name, RUNG_NAME[mood.rung], mood.fear, fearLimit(brain),
                            hpRatio, endurance, threats, nearest, insiders, outsiders,
                            mood.indoors and "indoors" or "outdoors",
                            friends, masterDist,
                            tostring(sprinting and "sprint" or (running and "run" or "no")),
                            tostring(fleeing),
                            tostring(ctx.disengaging == true),
                            -- `SR.Loot and HasBag(...) or "?"` printed "?" for everybody,
                            -- because `false or "?"` is "?" -- the whole run logged bag=?
                            -- and told us nothing. Lua's and/or is not a ternary when the
                            -- middle value can be false.
                            SR.Loot and tostring(SR.Loot.HasBag(brain)) or "?",
                            headDescription(tail),
                            tostring(headLocked)))
                    end

                    -- Per-NPC: expire obstacle retry records that are four times past the
                    -- cooldown window. Cheap -- the table is almost always empty or tiny --
                    -- and leaving them forever is a leak.
                    if mood.obstacleAttempts then
                        for key, at in pairs(mood.obstacleAttempts) do
                            if (sweepNumber - at) > OBSTACLE_RETRY * 4 then
                                mood.obstacleAttempts[key] = nil
                            end
                        end
                    end
                end

            elseif masterDist <= LOST_RANGE then
                -- A LOST COMPANION IS NEVER ABANDONED.
                --
                -- "me aleje mucho y no fue capaz de regresar a mi lado... temporalmente
                -- deshabilitamos su autonomia si me alejo demasiado, su objetivo debe ser
                -- llegar hasta donde estoy yo, para que logremos quitar cualquier traba que
                -- pueda ocurrirle." That is exactly what this branch does: no rung arithmetic,
                -- no fear, no free activity -- one objective, get here.
                --
                -- DELIBERATELY CHEAP, and the list of what is absent is the point.
                -- scanSurroundings walks the whole zombie cache per NPC and friendsNear walks
                -- the bandit cache per NPC; those two are the entire reason NPC_RANGE is 40,
                -- and running them out to 150 tiles would make this the most expensive thing
                -- in the mod. Also absent: the watchdog (its fingerprint would be a fresh
                -- follow every sweep, so it could never arm) and claimSpot (nobody 40+ tiles
                -- away is contending for a window with anybody here).
                --
                -- OWNED ONLY. A free survivor at 60 tiles has no obligation to us and no
                -- fresh rung; leaving them entirely alone is correct and costs nothing.
                local brain = BanditBrain.Get(zombie)
                local mood = brain and SR.Mood(zombie)

                if brain and mood and not brain.hostile and not brain.hostileP
                   and (not SR.IsStillOurs or SR.IsStillOurs(zombie)) then
                    local program = brain.program and brain.program.name
                    local owned = (program == "Companion" or program == "CompanionGuard")
                        and brain.master

                    if owned then
                        local name = tostring(brain.fullname)

                        if not mood.lost then
                            mood.lost = true
                            SR.Log(string.format(
                                "AUTO %s | LOST at %.1f tiles -- past %d, autonomy suspended, "
                                .. "one objective: reach the master",
                                name, masterDist, NPC_RANGE))
                        end

                        -- Forced, not decided. RungOf is never called on this path, and the
                        -- rung is what ScenesRelationsThreat and the companion wrapper read --
                        -- so writing OBEY here is what stops them acting on a rung that has
                        -- been stale since the NPC crossed 40 tiles.
                        mood.rung = Autonomy.OBEY

                        -- Locked, for the same reason as the disengaging branch above: a
                        -- companion this far behind that stops to swing at something will
                        -- never arrive.
                        --
                        -- FREE (no endurance charge), and that is not generosity. A Run leg
                        -- costs 0.07 and this pushes one every six seconds for as long as the
                        -- gap lasts, so a two-minute walk back would spend 1.4 -- more than a
                        -- full bar -- and hand the NPC ManageEndurance's sixteen seconds of
                        -- Exhausted halfway home. Being lost is already the punishment.
                        local walkType, _, followTask =
                            assertFollow(zombie, player, masterDist, true, true)
                        mood.followTask = followTask
                        mood.taskSig, mood.taskTicks = nil, 0

                        if census then
                            SR.Log(string.format(
                                "AUTO lost | %s | master=%.1f (%s, locked) end=%.2f run=%s",
                                name, masterDist, walkType,
                                tonumber(brain.endurance) or 1,
                                tostring(sprinting and "sprint" or (running and "run" or "no"))))
                        end
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
-- FAST_MS lives up with the flight clock, not here, because FLEE_GRACE_MS is derived from it
-- and a tolerance smaller than its own sample period silently kills the feature it guards --
-- which is exactly what shipped once. Declaring it beside its only other consumer would have
-- put the two numbers a thousand lines apart and made that relationship invisible again.
local CHASE_NOW = 5          -- tiles; past this while the master is moving off, go now

-- Tiles. The SAME question at a much shorter range, and only while the master is actually
-- running or sprinting AND the gap is verifiably opening.
--
-- This is the case the 10-08 log misses entirely, and it is the reported one: the player
-- jogs past, the companion is three tiles away swinging at a zombie, and nothing ever fires
-- because three is under CHASE_NOW. Six seconds later the slow sweep finds them at fifteen
-- tiles and calls it "falling behind" -- by which point the complaint has already happened.
--
-- 2.5 rather than 0: under about two tiles the companion is effectively on top of the
-- player, pathing noise alone moves the number, and re-asserting a follow at that range
-- would cancel a swing at a zombie the player is also fighting. 2.5 is the smallest
-- distance at which "you are being left behind" is a true statement rather than jitter.
local CHASE_RUNNING = 2.5

-- Tiles. The floor while the player has DECLARED flight (five unbroken seconds under power).
-- Lower than CHASE_RUNNING because a declaration needs no corroborating distance, and not zero
-- because zero means "re-issue the order to somebody already at your shoulder", which clears
-- their queue every 800 ms and is how a rest that only pays on completion never completes.
-- 1.5 tiles is close enough to be moving with you already.
local CHASE_FLEEING = 1.5

-- Consecutive fast ticks with no pull before a chase counts as over, for LOGGING only --
-- nothing about behaviour reads it. 4 x FAST_MS is about 3.2 seconds, which is longer than
-- any flicker of `widening` and shorter than any real journey, so the pair of lines brackets
-- a chase instead of stuttering through one.
local CHASE_END_TICKS = 4

local lastFastMs = 0

local function fastFollow()
    local now = getTimestampMs()
    if now - lastFastMs < FAST_MS then return end
    lastFastMs = now

    local player = getSpecificPlayer(0)
    -- FORGET THE RUN BEFORE BAILING. This function is the ONLY writer of playerFleeing, and
    -- `sweep` has no isDead test of its own -- so returning here with the flag still true would
    -- leave every companion pinned on OBEY for the whole death screen. See forgetFlight.
    if not player or player:isDead() then
        forgetFlight()
        return
    end
    if not BanditZombie or not BanditZombie.GetAllB then return end

    -- Only worth doing while the player is actually going somewhere. Standing still is what
    -- the six-second sweep is for.
    local sprinting = player:isSprinting() == true
    local running = masterIsRunning(player)
    local px, py = player:getX(), player:getY()

    -- THE FLIGHT CLOCK IS ADVANCED HERE AND NOWHERE ELSE, on this 800 ms tick, once for the
    -- whole world. It has to live in the fast lane: five seconds cannot be measured to any
    -- useful precision by a clock that only ticks every six. The slow sweep reads the result.
    local fleeing = updateFlight(player, now)
    if fleeing ~= playerFleeing then
        SR.Log(string.format("AUTO the player %s -- %s",
            fleeing and "is fleeing" or "stopped fleeing",
            fleeing and string.format("under power for %.1fs without a break",
                (now - (runStartedMs or now)) / 1000)
                or "no longer running"))
    end
    playerFleeing = fleeing

    -- The floor for this tick. Lowered ONLY while the master is moving under their own
    -- power; with the player standing still it stays at CHASE_NOW, so nothing about a
    -- stationary scene changes.
    --
    -- DECLARED FLIGHT LOWERS THE FLOOR TO CHASE_FLEEING, NOT TO ZERO. Zero was the first
    -- version and a review caught what it costs: `dist > 0` is true for every companion at
    -- every distance, so assertFollow -- and with it ClearTasks -- ran every 800 ms for
    -- everybody, including a companion sitting down. The rest task is a Sleep of ~7.5 s that
    -- pays its 0.5 endurance ONLY on completion (BanditUpdate.lua:1820), so it could never
    -- finish and a tired companion recovered NOTHING for the whole flight. That is the same
    -- defect the previous round found on the shelter route, re-opened through a new term.
    --
    -- CHASE_FLEEING (1.5) is "already at your shoulder". Somebody inside it is coming with you
    -- whatever they are doing, so re-issuing the order buys nothing and costs a cleared queue.
    -- It is still far below CHASE_RUNNING (2.5) and CHASE_NOW (5), which is the request --
    -- "no es necesario que hayan tantos tiles" -- honoured without the side effect.
    local chaseFloor = fleeing and CHASE_FLEEING
        or ((sprinting or running) and CHASE_RUNNING or CHASE_NOW)

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            local dist = math.sqrt(dx * dx + dy * dy)

            -- LOST_RANGE, not NPC_RANGE. The bound here was never about cost -- this lane
            -- does no cache scan -- it was copied from the sweep, and copying it is what made
            -- a companion 41 tiles back invisible to the one piece of code whose entire job
            -- is closing that gap. Only owned companions get the wider bound; see below.
            --
            -- THE DISTANCE FLOOR MOVED INSIDE, and that is not cosmetic. It used to gate this
            -- whole block, which meant a companion that ARRIVED simply stopped being visited
            -- -- fine when nothing was remembered between ticks, wrong now that a chase is an
            -- episode with a closing line. Arriving is the commonest way a chase ends and it
            -- has to be the commonest line in the log, not the one case that never prints.
            if dist <= LOST_RANGE then
                local brain = BanditBrain.Get(zombie)
                local mood = brain and SR.Mood(zombie)

                if brain and mood and not brain.hostile and not brain.hostileP
                   and (not SR.IsStillOurs or SR.IsStillOurs(zombie)) then
                    local program = brain.program and brain.program.name
                    local owned = (program == "Companion" or program == "CompanionGuard")
                        and brain.master

                    -- Everything below only ever acts on an owned companion, and mood.fastDist
                    -- is read nowhere else in the mod (grepped), so skipping the rest for a
                    -- free survivor changes no behaviour and keeps the widened bound free.
                    if owned then
                        -- Widening, not merely wide. A companion holding station eight tiles
                        -- away while you stand still is fine; one at eight tiles and growing is
                        -- being left behind.
                        local widening = mood.fastDist and (dist - mood.fastDist) > 0.35
                        mood.fastDist = dist

                        -- Normally the ladder's verdict is respected: somebody surviving or
                        -- with a zombie in their face is not being asked to jog after you.
                        --
                        -- Sprinting is the exception, and it has to be. The rung is up to six
                        -- seconds old, and a player who has just started running has already
                        -- changed the plan -- waiting a sweep to notice is the whole complaint
                        -- ("pasan muchos tiles, y no me sigue"). A sprint is unambiguous and
                        -- player-authored, so it does not wait for the ladder to catch up.
                        --
                        -- RUNNING JOINS IT, BUT ONLY WITH `widening`, and that pairing is
                        -- load-bearing rather than cautious. Without it the new CHASE_RUNNING
                        -- floor would be inert for the exact case it was added for: a
                        -- companion swinging at a zombie is on rung FIGHT (2), which is BELOW
                        -- OBEY (3), so `free` would be false and the lowered floor would never
                        -- be reached. A jog plus a gap that is measurably opening is the same
                        -- statement a sprint makes, just with evidence attached -- and it is
                        -- the literal sentence from the report: "cuando estamos corriendo se
                        -- queda pegandole a los zombies".
                        --
                        -- SURVIVE IS DELIBERATELY PROTECTED, and that exception was found by an
                        -- independent review rather than by reasoning. `(running and widening)`
                        -- as first written bypassed BOTH rungs below OBEY. Bypassing FIGHT is
                        -- the intent. Bypassing SURVIVE is not, and it is self-inflicted: a
                        -- companion that is fleeing is itself moving, and its own motion makes
                        -- `widening` true with the player standing perfectly still. So a
                        -- frightened companion's shelter route was cleared every 800 ms while
                        -- the six-second sweep re-queued it -- a 0.8 s clear against a 6 s
                        -- rebuild, which means the route never completes and the companion dies
                        -- in the open. Fleeing is the one thing this file does not own; it
                        -- belongs to ScenesRelationsThreat and to their own program.
                        --
                        -- Declared flight is the ONE case that outranks even that, because it is
                        -- not a guess: if the player has been running for five seconds, coming
                        -- with them IS the survival plan, and it is a better one than a door.
                        local free = sprinting or fleeing
                            or (running and widening and (mood.rung or Autonomy.IDLE) >= Autonomy.FIGHT)
                            or (mood.rung and mood.rung >= Autonomy.OBEY)

                        -- Two ways to be pulled. The ordinary one is unchanged and still
                        -- starts at CHASE_NOW; the close one exists only while the master is
                        -- under power and the gap is opening, and it is the only reason
                        -- `chaseFloor` can be lower than CHASE_NOW at all.
                        --
                        -- `widening` is dropped while fleeing, and dropping it is the point.
                        -- It is the evidence clause -- "the gap is measurably opening" -- and a
                        -- companion that is keeping up perfectly produces no such evidence. A
                        -- five-second run is the statement itself, so requiring corroboration
                        -- would mean the only companions that come with you are the ones
                        -- already losing you. That is the "tantos tiles" complaint restated.
                        local closeChase = dist > chaseFloor
                            and (fleeing or ((sprinting or running) and widening))
                        local ordinaryChase = dist > CHASE_NOW
                            and (sprinting or widening or dist > LEASH)

                        -- LOCKED when the master is genuinely leaving, which is the case
                        -- ManageCombat would otherwise overwrite in the same frame. A pure
                        -- `widening` with the player standing still is a catch-up, not a
                        -- disengagement, and takes no lock -- see assertFollow.
                        local leaving = sprinting or running or dist > LEASH

                        if free and (closeChase or ordinaryChase) then
                            mood.chaseIdle = 0

                            -- Only re-assert when they are not already chasing. Re-pushing
                            -- every tick would restart the walk each time -- ZAMove.onStart
                            -- calls pathToLocation afresh (ZAMove.lua:9) -- and they would
                            -- never arrive.
                            local head = brain.tasks and brain.tasks[1]
                            local chasing = head and (head.action == "Move" or head.action == "GoTo")
                                and head.isPlayer

                            if not chasing then
                                local walkType, downgraded, followTask =
                                    assertFollow(zombie, player, dist, true, leaving,
                                        sprinting or fleeing)
                                -- Overwrites whatever the slow sweep left. Correct: the check
                                -- that reads it only ever asks about the MOST RECENT follow,
                                -- and an older one it never got to judge is not evidence of
                                -- anything six seconds later.
                                mood.followTask = followTask
                                mood.taskSig, mood.taskTicks = nil, 0

                                -- ONE LINE PER CHASE, not one per 800 ms. The old line fired
                                -- on every re-assertion, which at this cadence was already
                                -- several a second across a party; lowering the floor to
                                -- CHASE_RUNNING would have made it the loudest thing in
                                -- console.txt and buried the census the file exists to read.
                                if not mood.chaseEpisode then
                                    mood.chaseEpisode = dist
                                    SR.Log(string.format(
                                        "AUTO %s | fast follow at %.1f tiles (%s%s%s) -- %s",
                                        tostring(brain.fullname), dist, walkType,
                                        downgraded and ", winded" or "",
                                        leaving and ", locked" or "",
                                        sprinting and "master sprinting"
                                            or (running and "master running" or "gap opening")))
                                end
                            end
                        elseif mood.chaseEpisode then
                            -- The closing half of the pair. Where a chase ENDED is the fact
                            -- that answers "no fue capaz de regresar a mi lado" -- a chase
                            -- that started at 30 and ended at 28 did not work, and until now
                            -- the log could not tell that from one that ended at 2.
                            --
                            -- NOT ON THE FIRST QUIET TICK, and this is the difference between
                            -- a useful pair of lines and chatter. `widening` is a per-tick
                            -- comparison, so a companion keeping pace at seven tiles behind a
                            -- jogging player flips it true/false constantly -- closing on the
                            -- first false would print an open and a close every couple of
                            -- seconds, per companion, which is exactly the kind of volume the
                            -- census exists to avoid. CHASE_END_TICKS of quiet is the test.
                            mood.chaseIdle = (mood.chaseIdle or 0) + 1
                            if mood.chaseIdle >= CHASE_END_TICKS then
                                SR.Log(string.format(
                                    "AUTO %s | chase over -- started %.1f, ended %.1f tiles",
                                    tostring(brain.fullname), mood.chaseEpisode, dist))
                                mood.chaseEpisode, mood.chaseIdle = nil, nil
                            end
                        end
                    end
                end
            end
        end
    end
end

Events.OnTick.Add(fastFollow)

Events.OnGameStart.Add(function()
    SR.Log(string.format(
        "AUTO ready -- survive > fight > obey > errand > idle | ladder <= %d tiles, "
        .. "owned companions followed out to %d | chase floor %.1f running / %d walking | "
        .. "follows lock so combat cannot steal them | walk recovery %.2f per sweep, winded below %.2f",
        NPC_RANGE, LOST_RANGE, CHASE_RUNNING, CHASE_NOW, WALK_RECOVERY, WINDED))
end)
