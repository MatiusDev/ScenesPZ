-- ScenesPZ -- the interaction wheel. Hold a key near somebody, choose, release.
--
-- WHY THIS REPLACES THE RIGHT-CLICK MENU
-- Play testing settled it: recruiting through a context menu means clicking a moving
-- target, then finding our entry below Bandits' and vanilla's. It works and it is
-- unusable, which is worse than broken -- it made every other test harder to run.
--
-- The wheel fixes the actual problem. You do not aim at anybody: hold the key and the
-- nearest survivor you can see is the one you are talking to. Vanilla ships the pattern
-- (ISEmoteRadialMenu.lua:199-268) and four files use it.
--
-- OUR OWN MENU INSTANCE, NOT THE SHARED ONE
-- Vanilla's emote wheel calls getPlayerRadialMenu(n), which returns a single menu shared
-- by everything that wants a wheel. Using it would mean fighting the emote menu for the
-- same object. ISRadialMenu:new gives us our own, and the collision disappears.
--
-- RELEASE-TO-SELECT, WHICH VANILLA DOES NOT DO ON KEYBOARD
-- ISRadialMenu only acts on a mouse click (line 18) or a joypad button release (line 106).
-- On keyboard, releasing the emote key just hides the wheel. Asking the slice under the
-- cursor ourselves on release costs three lines and is what makes hold-and-release work
-- the way a wheel should. Clicking still works too -- that path is untouched.

require "ScenesRelations"
require "ScenesRelationsActions"
require "ISUI/ISRadialMenu"

local SR = ScenesRelations

-- Held rather than tapped, so a stray press does nothing. Vanilla uses 450ms before its
-- emote wheel appears; 250 feels immediate without firing on a tap.
local HOLD_MS = 250

-- Tiles. Deliberately the same 8 as the zombie engagement range: it is roughly "near
-- enough to matter", and one number the player can learn beats two they cannot.
local RANGE = 8

-- Registered so the player can rebind it in Options. V is free in vanilla 42.20; if
-- another mod claims it, rebinding is a menu away rather than a code change.
table.insert(keyBinding, { value = "[ScenesPZ]" })
table.insert(keyBinding, { value = "Talk to survivor", key = Keyboard.KEY_V })

local wheel = nil
local pressedMs = nil

local function isOurKey(key)
    return getCore():isKey("Talk to survivor", key)
end

--- Nearest bandit within RANGE that the player can actually see.
---
--- Line of sight is not decoration. Without it you would be talking through a wall to
--- somebody in the next room, which reads as a bug the first time it happens and as magic
--- the second. BanditZombie keeps the proximity cache already, so this is a walk over a
--- list that exists rather than a scan of the cell.
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

--- Draws the name and trust under the wheel. ISRadialMenu has no centre label, and without
--- this the player has no idea which of two survivors standing together they picked.
local function renderWithHeader(self)
    ISRadialMenu.render(self)
    if not self.srHeader then return end
    self:drawTextCentre(self.srHeader, self.width / 2, self.height + 4,
        1, 1, 1, 1, UIFont.Small)
end

local function close()
    if wheel then
        wheel:removeFromUIManager()
        wheel = nil
    end
end

--- Fires the slice the cursor is over. Returns true if something ran.
local function fireHovered()
    if not wheel or not wheel.javaObject then return false end

    local index = wheel.javaObject:getSliceIndexFromMouse(wheel:getMouseX(), wheel:getMouseY())
    if not index or index < 0 then return false end

    local command = wheel:getSliceCommand(index + 1)
    if not command or not command[1] then return false end

    command[1](command[2], command[3])
    return true
end

local function open(player)
    local bandit = nearestSurvivor(player)
    if not bandit then
        -- Silence here would be indistinguishable from a broken keybinding, and on a
        -- machine with no hot reload that costs a session to tell apart.
        if HaloTextHelper then
            HaloTextHelper.addText(player, "Nobody close enough")
        end
        return
    end

    local list, brain, trust, tier = SR.Actions.List(player, bandit)
    if not list then
        if HaloTextHelper then
            HaloTextHelper.addBadText(player, "They are not listening")
        end
        return
    end

    local x = getPlayerScreenLeft(0) + getPlayerScreenWidth(0) / 2
    local y = getPlayerScreenTop(0) + getPlayerScreenHeight(0) / 2

    wheel = ISRadialMenu:new(x - 100, y - 100, 40, 100, 0)
    wheel:initialise()
    wheel:instantiate()
    wheel.srHeader = SR.Actions.Header(brain, trust, tier)
    wheel.render = renderWithHeader

    for _, action in ipairs(list) do
        if action.available then
            wheel:addSlice(action.label, nil, action.run, player, bandit)
        else
            -- Refused actions stay on the wheel, labelled with what is missing. Hiding
            -- them would make the relationship invisible: the player would never learn
            -- that Follow me is four conversations away rather than impossible.
            wheel:addSlice(action.label .. " (" .. tostring(action.reason) .. ")", nil,
                function() end)
        end
    end

    wheel:addToUIManager()

    SR.Log(string.format("WHEEL opened on %s | %d options", wheel.srHeader, #list))
end

-- KEY HANDLING ----------------------------------------------------------------------
-- Three events, same shape as ISEmoteRadialMenu.lua:266-268. Start records the moment,
-- Keep opens once the hold threshold passes, and the release both selects and closes.

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

    local ok, fired = pcall(fireHovered)
    if not ok then
        SR.Log("WHEEL selection failed: " .. tostring(fired))
    elseif not fired then
        SR.Log("WHEEL closed without a selection")
    end

    close()
end

Events.OnKeyStartPressed.Add(onKeyStart)
Events.OnKeyKeepPressed.Add(onKeyKeep)
Events.OnKeyPressed.Add(onKeyRelease)

Events.OnGameStart.Add(function()
    SR.Log("WHEEL ready -- hold the 'Talk to survivor' key (default V) near somebody")
end)
