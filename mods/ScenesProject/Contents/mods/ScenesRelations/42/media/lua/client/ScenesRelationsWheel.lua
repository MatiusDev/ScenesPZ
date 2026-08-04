-- ScenesPZ -- our own interaction wheel. Hold a key near somebody, choose, release.
--
-- WHY WE STOPPED USING ISRadialMenu
-- Two rounds of play testing said the same thing: you cannot tell what the wheel offers
-- without hovering every wedge in turn. That is not a styling problem, it is what
-- ISRadialMenu is: the Java side owns the drawing and only paints a slice's text once the
-- cursor is already on it. Icons were tried as a workaround and made it worse -- the
-- texture paths that appear in vanilla's Lua do not resolve to loadable textures here, so
-- the buttons came back empty and setTextureColor threw 511 times in one session.
--
-- So this draws itself. Every option is a labelled card placed on a circle, which is
-- fully expressible with drawRect and drawTextCentre, needs no art, and makes hit-testing
-- a rectangle check instead of an angle guess. The old version had to compute where slice
-- zero began because Java would not say; here we place the cards, so we know.
--
-- TWO LEVELS
-- Hovering an option that has questions behind it opens a second ring in place of the
-- first. Talk is the one that does today: who are you, what are you doing, how are you
-- holding up. Moving the cursor back to the middle returns to the top level.
--
-- HONEST ABOUT WHAT DOES NOT EXIST YET
-- Trade is on the wheel and does nothing, on purpose. So is asking what somebody is like,
-- which needs the traits stage. Both say so out loud rather than being hidden: an option
-- that is missing reads as a bug, an option that answers "I cannot do that yet" reads as
-- a roadmap. Every unbuilt path goes through SR.Wheel.NotYet so there is exactly one
-- place to delete when it stops being true.

require "ScenesRelations"
require "ScenesRelationsActions"
require "ISUI/ISPanel"

local SR = ScenesRelations

SR.Wheel = SR.Wheel or {}

-- Held rather than tapped, so a stray press does nothing.
local HOLD_MS = 250

-- Tiles. The wheel should only open when you are close enough to talk naturally.
-- 3 tiles is conversational distance; 8 was the zombie engagement range and felt wrong here.
local RANGE = 3

local RADIUS = 110          -- distance from centre to the middle of each card
local CARD_W, CARD_H = 130, 36
local CENTRE_R = 46         -- inside this, nothing is selected and a submenu closes

table.insert(keyBinding, { value = "[ScenesPZ]" })
table.insert(keyBinding, { value = "Talk to survivor", key = Keyboard.KEY_V })

local wheel = nil
local pressedMs = nil

local function isOurKey(key)
    return getCore():isKey("Talk to survivor", key)
end

--- The single place that says "not built yet". One function so that when a feature lands
--- there is one call site to delete rather than a search.
function SR.Wheel.NotYet(what)
    local player = getSpecificPlayer(0)
    if HaloTextHelper and player then
        HaloTextHelper.addBadText(player, "I can't do that yet - " .. tostring(what))
    end
    SR.Log("WHEEL not-yet: " .. tostring(what))
end

-- WHAT AN NPC CAN ACTUALLY ANSWER TODAY -----------------------------------------------
-- Only from brain fields that exist. Nothing here invents a fact about a person: if we
-- cannot answer something, the answer is that we cannot answer it.

local PROGRAM_WORDS = {
    Companion = "I'm with you.",
    CompanionGuard = "I'm watching your back.",
    Defend = "I'm holding this place.",
    Looter = "Looking for anything useful.",
    Camper = "Just camped up here.",
    Thief = "Keeping to myself.",
    Roadblock = "Watching this road.",
    Bandit = "None of your business.",
}

local function answerWhoAreYou(brain)
    local name = tostring(brain and brain.fullname or "nobody")
    if brain and brain.clan then
        return name .. ", and I run with my own people."
    end
    return name .. ". That's all you need."
end

local function answerWhatAreYouDoing(brain)
    local program = brain and brain.program and brain.program.name
    return PROGRAM_WORDS[program] or "Surviving. Same as you."
end

local function answerHowAreYou(brain)
    if not brain then return "I'm fine." end
    -- brain.health is Bandits' own scale (Bandit.lua:423), not the player's, so this
    -- reports bands rather than a number we would be pretending to understand.
    local health = tonumber(brain.health) or 2
    if health < 1.2 then return "I'm hurt. Badly." end
    if health < 2.0 then return "I've been better." end
    return "I'm holding up."
end

--- The Talk ring. Each entry answers from the brain, or admits it cannot.
local function talkOptions(player, bandit, brain)
    local function say(text)
        if HaloTextHelper and player then HaloTextHelper.addText(player, text) end
        SR.Log("WHEEL answer: " .. tostring(text))
        -- Any real exchange counts as talking, so it moves trust on the same terms and the
        -- same cooldown. Asking four questions in a row is one conversation, not four.
        SR.Actions.RewardTalk(player, bandit)
    end

    return {
        { label = "Who are you?", available = true,
          run = function() say(answerWhoAreYou(brain)) end },
        { label = "What are you doing?", available = true,
          run = function() say(answerWhatAreYouDoing(brain)) end },
        { label = "How are you holding up?", available = true,
          run = function() say(answerHowAreYou(brain)) end },
        -- Needs the traits stage: whether somebody is fearful, or a carpenter, is not
        -- modelled yet. Saying so is more useful than inventing an answer.
        { label = "What are you like?", available = false,
          reason = "traits not built",
          run = function() SR.Wheel.NotYet("asking what someone is like") end },
    }
end

-- THE WIDGET ---------------------------------------------------------------------------

SRWheelPanel = ISPanel:derive("SRWheelPanel")

--- Card centre for option i of n, starting at the top and going clockwise. We place them,
--- so unlike the old version there is nothing to guess about where they are.
local function cardCentre(self, i, n)
    local angle = -math.pi / 2 + (i - 1) * (2 * math.pi / n)
    return self.width / 2 + math.cos(angle) * RADIUS,
           self.height / 2 + math.sin(angle) * RADIUS
end

--- Which card the cursor is over, or nil. Returns nil inside the centre circle too, which
--- is what closes a submenu.
function SRWheelPanel:hovered()
    local mx, my = self:getMouseX(), self:getMouseY()
    local dx, dy = mx - self.width / 2, my - self.height / 2
    if dx * dx + dy * dy < CENTRE_R * CENTRE_R then return nil end

    for i = 1, #self.options do
        local cx, cy = cardCentre(self, i, #self.options)
        if math.abs(mx - cx) <= CARD_W / 2 and math.abs(my - cy) <= CARD_H / 2 then
            return i
        end
    end
    return nil
end

function SRWheelPanel:render()
    local hover = self:hovered()

    -- Opening a submenu on hover. Done here because render is the only place the cursor
    -- position is guaranteed fresh: ISPanel gives no mouse-move event we can rely on
    -- while a key is held down.
    if hover and self.options[hover] and self.options[hover].submenu and not self.inSubmenu then
        self:enterSubmenu(self.options[hover].submenu)
    -- Closing the submenu by returning to the middle -- but not instantly. A quick sweep
    -- across the centre should not kick you out; you must dwell there briefly. At 60 fps
    -- 8 frames is ~130 ms, long enough to be intentional, short enough to feel responsive.
    elseif self.inSubmenu and not hover then
        local dx = self:getMouseX() - self.width / 2
        local dy = self:getMouseY() - self.height / 2
        if dx * dx + dy * dy < CENTRE_R * CENTRE_R then
            self.centreFrames = (self.centreFrames or 0) + 1
            if self.centreFrames >= 8 then
                self:leaveSubmenu()
                self.centreFrames = 0
            end
        else
            self.centreFrames = 0
        end
    elseif self.inSubmenu then
        self.centreFrames = 0
    end

    hover = self:hovered()

    -- Centre: who you are talking to. No trust number -- that lives in the relationship
    -- panel, where it can be a bar you read rather than a figure you decode mid-swing.
    self:drawTextCentre(self.subject, self.width / 2, self.height / 2 - 8,
        1, 1, 1, 1, UIFont.Medium)
    if self.inSubmenu then
        self:drawTextCentre("< back", self.width / 2, self.height / 2 + 10,
            0.6, 0.6, 0.6, 1, UIFont.Small)
    end

    for i, option in ipairs(self.options) do
        local cx, cy = cardCentre(self, i, #self.options)
        local x, y = cx - CARD_W / 2, cy - CARD_H / 2
        local on = (i == hover)

        local r, g, b = 0.16, 0.16, 0.18
        if not option.available then
            r, g, b = 0.18, 0.14, 0.14
        elseif on then
            r, g, b = 0.22, 0.34, 0.24
        end

        self:drawRect(x, y, CARD_W, CARD_H, 0.92, r, g, b)
        self:drawRectBorder(x, y, CARD_W, CARD_H, on and 0.9 or 0.35, 1, 1, 1)

        -- Refused options stay, dimmed, with the reason under them. Hiding an option makes
        -- the relationship invisible; showing why it is closed makes it a goal.
        local shade = option.available and 1 or 0.5
        local textY = option.reason and (cy - 12) or (cy - 6)
        self:drawTextCentre(tostring(option.label), cx, textY,
            shade, shade, shade, 1, UIFont.Small)
        if option.reason then
            self:drawTextCentre("(" .. tostring(option.reason) .. ")", cx, cy + 2,
                0.5, 0.5, 0.5, 1, UIFont.Small)
        end
    end
end

function SRWheelPanel:enterSubmenu(builder)
    local ok, built = pcall(builder)
    if not ok or type(built) ~= "table" then
        SR.Log("WHEEL submenu failed to build: " .. tostring(built))
        return
    end
    self.rootOptions = self.options
    self.options = built
    self.inSubmenu = true
end

function SRWheelPanel:leaveSubmenu()
    if not self.rootOptions then return end
    self.options = self.rootOptions
    self.inSubmenu = false
end

--- Runs whatever the cursor is on. Returns true if something happened.
function SRWheelPanel:choose()
    local index = self:hovered()
    if not index then return false end

    local option = self.options[index]
    if not option then return false end

    -- A submenu parent is a doorway, not a choice. Releasing on it does nothing rather
    -- than firing something the player did not pick.
    if option.submenu then return false end

    if option.run then
        option.run()
        return true
    end
    return false
end

function SRWheelPanel:new(subject, options)
    local size = (RADIUS + CARD_H) * 2 + 40
    local x = getPlayerScreenLeft(0) + getPlayerScreenWidth(0) / 2 - size / 2
    local y = getPlayerScreenTop(0) + getPlayerScreenHeight(0) / 2 - size / 2

    local o = ISPanel.new(self, x, y, size, size)
    o.subject = subject
    o.options = options
    o.rootOptions = nil
    o.inSubmenu = false
    o.centreFrames = 0
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.35 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false
    return o
end

-- OPENING AND CLOSING ------------------------------------------------------------------

--- Nearest bandit within RANGE that the player can actually see. Line of sight matters:
--- without it you would be talking through a wall to somebody in the next room.
local function nearestSurvivor(player)
    if not BanditZombie or not BanditZombie.GetAllB then return nil end

    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return nil end

    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local best, bestDistSq = nil, RANGE * RANGE

    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie and math.abs(zombie:getZ() - pz) < 1 then
            local dx, dy = zombie:getX() - px, zombie:getY() - py
            local distSq = dx * dx + dy * dy
            if distSq < bestDistSq and zombie:CanSee(player) then
                best, bestDistSq = zombie, distSq
            end
        end
    end
    return best
end

local function close()
    if wheel then
        wheel:removeFromUIManager()
        wheel = nil
    end
end

local function open(player)
    local bandit = nearestSurvivor(player)
    if not bandit then
        -- Silent: the user is just pressing the key. A message every time they hit V in
        -- an empty room would train them to ignore all wheel feedback.
        return
    end

    local list, brain = SR.Actions.List(player, bandit)
    if not list then
        if HaloTextHelper then HaloTextHelper.addBadText(player, "They are not listening") end
        return
    end

    -- The root ring: Talk opens the questions, Trade is a placeholder that says so out
    -- loud, and the rest are the real actions from SR.Actions.List.
    local options = {
        { label = "Talk", available = true,
          submenu = function() return talkOptions(player, bandit, brain) end },
        { label = "Trade", available = false, reason = "not built",
          run = function() SR.Wheel.NotYet("trading") end },
    }
    for _, action in ipairs(list) do
        if action.label ~= "Talk" then
            options[#options + 1] = {
                label = action.label,
                available = action.available,
                reason = action.reason,
                run = action.run and function()
                    SR.Log("WHEEL action | " .. tostring(action.label) .. " on "
                        .. tostring(SR.Actions.Name(brain)))
                    action.run(player, bandit)
                end,
            }
        end
    end

    -- Memory test removed from the wheel: it needs the same survivor the wheel already
    -- picked, but running it from the wheel closes the UI and the user cannot see the
    -- result. A dedicated key is cleaner. See ScenesRelationsMemoryTest.lua.

    wheel = SRWheelPanel:new(SR.Actions.Name(brain), options)
    wheel:initialise()
    wheel:instantiate()
    wheel:addToUIManager()

    SR.Log(string.format("WHEEL opened on %s | %d options",
        tostring(SR.Actions.Name(brain)), #options))
end

local function onKeyStart(key)
    if not isOurKey(key) then return end
    pressedMs = getTimestampMs()
end

local function onKeyKeep(key)
    if not isOurKey(key) then return end
    if not pressedMs or wheel then return end
    if getTimestampMs() - pressedMs < HOLD_MS then return end

    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end
    open(player)
end

local function onKeyRelease(key)
    if not isOurKey(key) then return end
    pressedMs = nil
    if not wheel then return end

    local ok, chose = pcall(function() return wheel:choose() end)
    if not ok then
        SR.Log("WHEEL selection failed: " .. tostring(chose))
    elseif not chose then
        SR.Log("WHEEL closed without a selection")
    end

    close()
end

Events.OnKeyStartPressed.Add(onKeyStart)
Events.OnKeyKeepPressed.Add(onKeyKeep)
Events.OnKeyPressed.Add(onKeyRelease)

Events.OnGameStart.Add(function()
    SR.Log("WHEEL ready -- hold V near somebody (3 tiles) to open the interaction wheel")
end)
