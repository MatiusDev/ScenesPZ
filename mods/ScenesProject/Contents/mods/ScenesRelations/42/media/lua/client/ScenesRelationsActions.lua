-- ScenesPZ -- what you can ask an NPC to do, and whether it will agree.
--
-- WHY THIS EXISTS SEPARATELY FROM ANY MENU
-- The first version of this lived inside the right-click handler, which meant the answer
-- to "what can I do with this person right now" was tangled with "how do I draw a context
-- menu". Testing showed the right-click menu is the wrong interface -- you are clicking a
-- moving target through a list of unrelated entries -- and replacing it should not mean
-- rewriting the rules about who agrees to what.
--
-- So the rules live here and return a plain list. The wheel renders it. The old context
-- menu renders the same list. Persuasion, when it arrives, renders the same list as
-- floating text. One place decides, several places draw.
--
-- WE DECIDE, THEY EXECUTE
-- The program switch is BanditMenu.SwitchProgram (BanditMenu.lua:145). It sets
-- brain.master, replaces brain.program, calls BanditBrain.Update and syncs with
-- Bandit.ForceSyncPart. Reimplementing that would mean owning their multiplayer sync
-- forever, and ZPCompanion does nothing at all without brain.master (ZPCompanion.lua:26).
-- We only choose whether the call happens.

require "ScenesRelations"
require "BanditMenu"

ScenesRelations = ScenesRelations or {}
local SR = ScenesRelations

SR.Actions = SR.Actions or {}
local Actions = SR.Actions

-- Two different things, deliberately.
--
-- FOLLOW is the "friendly" boundary from SR.TIERS: they will walk with you. An
-- arrangement, not a commitment, and it costs them little to accept.
--
-- JOIN is the "ally" boundary, and it sets brain.loyal. That flag is not decoration:
-- BanditUtils.AreEnemies (BanditUtils.lua:774) makes a loyal NPC treat anyone hostile to
-- the player as its own enemy. Joining means taking your side in fights that are not
-- theirs, so it costs more than agreeing to walk behind you.
Actions.FOLLOW_MIN_TRUST = 25
Actions.JOIN_MIN_TRUST = 60

-- Talking is the slow path and it is meant to be. Fighting beside somebody is worth more
-- per event and always will be -- what you risk for a person outranks what you say to
-- them. Conversation exists so that a stranger has any way in at all, and so that the
-- relationship is not purely a function of how many zombies happened to show up.
--
-- The cooldown is in IN-GAME hours. At the measured compression an in-game hour is about
-- six real minutes, so half an hour is roughly three. Both numbers are tuning, and both
-- belong in docs/NPC-BEHAVIOR-PLAN.md the moment they change.
Actions.TALK_REWARD = 4
Actions.TALK_COOLDOWN_HOURS = 0.5

local function hoursNow()
    local gt = getGameTime()
    if not gt then return 0 end
    local ok, hours = pcall(function() return gt:getWorldAgeHours() end)
    if not ok or type(hours) ~= "number" then return 0 end
    return hours
end

local function nameOf(brain)
    return tostring(brain and brain.fullname or "Survivor")
end

--- Every action logs. Choosing one is the single moment the player states an intention,
--- and without a line here a failure is indistinguishable from a misclick -- which on a
--- machine with no hot reload costs a whole session to tell apart.
local function logAction(bandit, action)
    local brain = BanditBrain.Get(bandit)
    local record = SR.Peek(bandit)
    SR.Log(string.format("ACT %s | %s | trust=%d loyal=%s master=%s",
        nameOf(brain), action,
        record and record.trust or 0,
        tostring(brain and brain.loyal),
        tostring(brain and brain.master)))
end

--- Sets or clears the loyalty flag that separates a follower from a group member.
--- SwitchProgram does not touch brain.loyal, so we write it ourselves and sync it the same
--- way they sync everything else, rather than leaving host and client disagreeing about
--- who is on whose side.
local function setLoyal(bandit, loyal)
    local brain = BanditBrain.Get(bandit)
    if not brain then return end
    brain.loyal = loyal
    BanditBrain.Update(bandit, brain)
    Bandit.ForceSyncPart(bandit, { id = brain.id, loyal = loyal })
end

--- Feedback goes on the PLAYER, not the NPC. Every vanilla HaloTextHelper callsite passes
--- a player (forageClient.lua:73, ISInventoryPage.lua:1927, and the rest) and whether the
--- Java side accepts an IsoZombie is still unproven. When that probe comes back positive
--- this is the one line that moves.
local function say(player, text, good)
    if not HaloTextHelper or not player then return end
    if good == true then
        HaloTextHelper.addGoodText(player, text)
    elseif good == false then
        HaloTextHelper.addBadText(player, text)
    else
        HaloTextHelper.addText(player, text)
    end
end

-- ACTIONS ---------------------------------------------------------------------------

local function runTalk(player, bandit)
    local brain = BanditBrain.Get(bandit)
    local mood = SR.Mood(bandit)
    if mood then mood.lastTalk = hoursNow() end

    local before, after = SR.Adjust(bandit, Actions.TALK_REWARD, "talked")
    logAction(bandit, "talk")

    if before ~= after then
        say(player, nameOf(brain) .. " now sees you as " .. tostring(after), true)
    else
        say(player, "You talk with " .. nameOf(brain), true)
    end
end

local function runFollow(player, bandit)
    BanditMenu.SwitchProgram(player, bandit, "Companion")
    setLoyal(bandit, false)
    logAction(bandit, "follow")
    say(player, nameOf(BanditBrain.Get(bandit)) .. " will walk with you", true)
end

local function runJoin(player, bandit)
    BanditMenu.SwitchProgram(player, bandit, "Companion")
    setLoyal(bandit, true)
    logAction(bandit, "join")
    say(player, nameOf(BanditBrain.Get(bandit)) .. " has taken your side", true)
end

local function runLeave(player, bandit)
    BanditMenu.SwitchProgram(player, bandit, "Looter")
    setLoyal(bandit, false)
    logAction(bandit, "leave")
    say(player, nameOf(BanditBrain.Get(bandit)) .. " goes their own way")
end

-- THE LIST --------------------------------------------------------------------------

--- Returns every action for this NPC right now, in a fixed order, each marked available or
--- not with the reason.
---
--- Refused actions are RETURNED, not omitted. A missing option reads as a bug; a refused
--- one reads as a person, and it tells the player exactly what the relationship still
--- needs. That was the one thing the right-click version got right and it survives here.
---
--- Returns nil when there is nothing to talk to at all -- not a bandit, no brain, or
--- actively trying to kill you. Somebody mid-attack does not take requests; same gate
--- Bandits puts on its own menu at BanditMenu.lua:210.
function Actions.List(player, bandit)
    if not player or not bandit then return nil end
    if not bandit:getVariableBoolean("Bandit") then return nil end

    local brain = BanditBrain.Get(bandit)
    if not brain then return nil end
    if brain.hostile or brain.hostileP then return nil end

    local record = SR.Peek(bandit)
    local trust = record and record.trust or 0
    local tier = SR.Tier(bandit)

    local list = {}

    -- TALK. Available to a stranger on purpose -- it is the only way in, and the PRD is
    -- explicit that nobody trusts you on sight. Refused at the hostile tier, because
    -- somebody who has decided you are dangerous is past conversation.
    local mood = SR.Mood(bandit)
    local since = mood and mood.lastTalk and (hoursNow() - mood.lastTalk) or nil

    if tier == "hostile" then
        list[#list + 1] = { label = "Talk", available = false,
                            reason = "past talking to you" }
    elseif since and since < Actions.TALK_COOLDOWN_HOURS then
        list[#list + 1] = { label = "Talk", available = false,
                            reason = "nothing more to say yet" }
    else
        list[#list + 1] = { label = "Talk", available = true, run = runTalk }
    end

    local program = brain.program and brain.program.name
    local following = program == "Companion" or program == "CompanionGuard"

    if following then
        if not brain.loyal then
            if trust >= Actions.JOIN_MIN_TRUST then
                list[#list + 1] = { label = "Join me", available = true, run = runJoin }
            else
                list[#list + 1] = { label = "Join me", available = false,
                                    reason = string.format("needs %d trust", Actions.JOIN_MIN_TRUST) }
            end
        end

        -- Dismissal is never gated. Trust decides who will follow you, not who is allowed
        -- to stop. A companion you cannot release is a prisoner, not an ally.
        list[#list + 1] = { label = "Leave me", available = true, run = runLeave }
    else
        if trust >= Actions.FOLLOW_MIN_TRUST then
            list[#list + 1] = { label = "Follow me", available = true, run = runFollow }
        else
            list[#list + 1] = { label = "Follow me", available = false,
                                reason = string.format("needs %d trust", Actions.FOLLOW_MIN_TRUST) }
        end
    end

    return list, brain, trust, tier
end

--- The one-line identity shown wherever the list is drawn.
function Actions.Header(brain, trust, tier)
    return string.format("%s   %s %d", nameOf(brain), tostring(tier), trust)
end
