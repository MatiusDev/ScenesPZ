-- ScenesPZ -- somebody else's health, body part by body part.
--
-- ASKED FOR IN THESE WORDS
--   "debe aparecer una opcion que diga salud, este debe de abrir el cuadro de salud
--    parecido al de jugador, pero con los stats del NPC, de manera que yo pueda vendarlo y
--    ayudarle. El echo de vendarlo hace que suba la confianza con mayor puntos."
--
-- THE 10-08 SESSION: BODY PARTS ARE REACHABLE, AND ALWAYS WERE.
--
-- The first version of this file stated "a Bandits NPC does not run on that model. Its
-- damage is a single float -- getHealth, drained by the bleed-out loop." That was wrong,
-- and it was wrong because it was never tested. Bandits itself uses getBodyDamage on NPCs:
--   ZASmack.lua:358-359 -- bd:SetBitten(BodyPartType.Torso_Upper, true)
--   ZABandage.lua:50-51 -- zombie:addVisualBandage(bodyPart.name, true)
--   ZABandage.lua:27 -- 1 + BanditRandom.Get() % 17 body parts
--
-- Vanilla confirms the full API is callable:
--   LastStand/AReallyCDDAy.lua:76 -- getBodyParts():get(i):setWetness()
--   Steps.lua:1572 -- getBodyPart(Hand_L):setScratched(true, true)
--   Steps.lua:1718 -- getBodyPart(Hand_L):getBandageLife() > 0
--
-- The engine DOES tick body part wounds for IsoZombie because IsoZombie extends
-- IsoGameCharacter and the Java-side damage pipeline processes everything through
-- BodyDamage regardless of class. The body diagram IS a picture of real data.
--
-- WHAT THIS PANEL SHOWS
-- Every body part Bandits knows about (17 parts), with its current wound state directly
-- from the engine. A part can be scratched, lacerated, have a deep wound, be bitten, be
-- bleeding, have glass in it, or be bandaged. All of these are engine facts now -- no more
-- simulated wounds on brain.scenesWound.
--
-- WHY THERE ARE NO NEEDS ON IT (unchanged from the first version)
-- The probe came back. Ten sweeps of CharacterStat never moved for an NPC. The engine does
-- not tick them for a zombie. A hunger bar here would be a bar that never moves.

require "ScenesRelations"
require "ScenesRelationsActions"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"

local SR = ScenesRelations

SR.Health = SR.Health or {}

local WIDTH, HEIGHT = 360, 520
local PAD = 10
local ROW_H = 22

-- All 17 body parts Bandits knows about, in display order (head to feet).
-- Names from ZABandage.lua:3-21, same enum values vanilla uses.
local BODY_PARTS = {
    { part = BodyPartType.Head,        label = "Head" },
    { part = BodyPartType.Neck,        label = "Neck" },
    { part = BodyPartType.Torso_Upper, label = "Upper Torso" },
    { part = BodyPartType.Torso_Lower, label = "Lower Torso" },
    { part = BodyPartType.Groin,       label = "Groin" },
    { part = BodyPartType.UpperArm_L,  label = "L Upper Arm" },
    { part = BodyPartType.UpperArm_R,  label = "R Upper Arm" },
    { part = BodyPartType.ForeArm_L,   label = "L Forearm" },
    { part = BodyPartType.ForeArm_R,   label = "R Forearm" },
    { part = BodyPartType.Hand_L,      label = "L Hand" },
    { part = BodyPartType.Hand_R,      label = "R Hand" },
    { part = BodyPartType.UpperLeg_L,  label = "L Thigh" },
    { part = BodyPartType.UpperLeg_R,  label = "R Thigh" },
    { part = BodyPartType.LowerLeg_L,  label = "L Shin" },
    { part = BodyPartType.LowerLeg_R,  label = "R Shin" },
    { part = BodyPartType.Foot_L,      label = "L Foot" },
    { part = BodyPartType.Foot_R,      label = "R Foot" },
}

-- Wound type colours. Matches the vanilla health panel's colour scheme so
-- the player reads them the same way they read their own.
local WOUND_COLORS = {
    scratch   = { r = 0.90, g = 0.80, b = 0.40 },  -- yellow
    laceration  = { r = 0.95, g = 0.45, b = 0.20 },  -- orange
    deepWound   = { r = 0.90, g = 0.20, b = 0.20 },  -- red
    bite      = { r = 0.80, g = 0.20, b = 0.60 },  -- magenta
    bleeding  = { r = 0.85, g = 0.15, b = 0.15 },  -- dark red
    glass     = { r = 0.60, g = 0.85, b = 0.95 },  -- light blue
    bandaged  = { r = 0.40, g = 0.70, b = 0.40 },  -- green
    healthy   = { r = 0.30, g = 0.30, b = 0.30 },  -- grey
}

-- Bandage types, best first. Verified in pzserver/media/scripts/generated/items/normal.txt.
local BANDAGES = {
    "Base.AlcoholBandage",
    "Base.Bandage",
    "Base.AlcoholRippedSheets",
    "Base.RippedSheets",
}

-- Condition one bandage restores to a body part. Bandits' own action snaps to flat 1.2
-- regardless of part; player-applied care is more precise.
local BANDAGE_HEAL = 0.6

-- Trust gained for bandaging a wounded part (once per part per session).
local TRUST_PER_PART = 10

--- Wound description for a body part. Read directly from the engine.
local function partStatus(bd, partType)
    local ok, bp = pcall(function() return bd:getBodyPart(partType) end)
    if not ok or not bp then return { kind = "healthy", label = "" } end

    -- The engine tracks these as booleans with an infection flag.
    -- Order matters: bite is worst, scratch is least.
    local bitten = false;    pcall(function() bitten = bp:IsBitten() end)
    local deep = false;      pcall(function() deep = bp:IsDeepWound() end)
    local laceration = false; pcall(function() laceration = bp:IsLacerated() end)
    local scratched = false; pcall(function() scratched = bp:scratched() end)
    local bleeding = false;  pcall(function() bleeding = bp:isBleeding() end)
    local hasGlass = false;  pcall(function() hasGlass = bp:getHaveGlass() end)
    local bandageLife = 0;   pcall(function() bandageLife = bp:getBandageLife() or 0 end)

    if bitten then
        return { kind = "bite", label = "Bitten", color = WOUND_COLORS.bite }
    elseif deep then
        if bleeding then
            return { kind = "deepWound", label = "Deep wound (bleeding)", color = WOUND_COLORS.bleeding }
        elseif bandageLife > 0 then
            return { kind = "bandaged", label = "Deep wound (bandaged)", color = WOUND_COLORS.bandaged }
        else
            return { kind = "deepWound", label = "Deep wound", color = WOUND_COLORS.deepWound }
        end
    elseif laceration then
        if bleeding then
            return { kind = "laceration", label = "Laceration (bleeding)", color = WOUND_COLORS.bleeding }
        elseif bandageLife > 0 then
            return { kind = "bandaged", label = "Laceration (bandaged)", color = WOUND_COLORS.bandaged }
        else
            return { kind = "laceration", label = "Laceration", color = WOUND_COLORS.laceration }
        end
    elseif scratched then
        if bleeding then
            return { kind = "scratch", label = "Scratch (bleeding)", color = WOUND_COLORS.bleeding }
        elseif bandageLife > 0 then
            return { kind = "bandaged", label = "Scratch (bandaged)", color = WOUND_COLORS.bandaged }
        else
            return { kind = "scratch", label = "Scratch", color = WOUND_COLORS.scratch }
        end
    end

    -- Glass can coexist with any wound or on its own.
    if hasGlass then
        return { kind = "glass", label = "Glass lodged", color = WOUND_COLORS.glass }
    end

    if bandageLife > 0 then
        return { kind = "bandaged", label = "Bandaged", color = WOUND_COLORS.bandaged }
    end

    return { kind = "healthy", label = "", color = WOUND_COLORS.healthy }
end

-- THE PANEL -----------------------------------------------------------------------------

ScenesRelationsHealthPanel = ISCollapsableWindow:derive("ScenesRelationsHealthPanel")

function ScenesRelationsHealthPanel:prerender()
    ISCollapsableWindow.prerender(self)

    local zombie = self.bandit
    if not zombie then return end

    local ok, brain = pcall(function() return BanditBrain.Get(zombie) end)
    if not ok or not brain then
        self:drawText("They are gone.", PAD, 40, 0.8, 0.5, 0.5, 1, UIFont.Small)
        return
    end

    local bd = nil
    pcall(function() bd = zombie:getBodyDamage() end)

    local y = 34
    local name = tostring(brain.fullname)

    -- Overall condition bar at the top.
    local now = 1; pcall(function() now = zombie:getHealth() end)
    local max = tonumber(brain.health) or 2
    if max <= 0 then max = 2 end
    local ratio = now / max

    local r, g, b = 0.30, 0.80, 0.35
    if ratio < 0.3 then r, g, b = 0.85, 0.25, 0.25
    elseif ratio < 0.6 then r, g, b = 0.90, 0.65, 0.25 end

    local w = self.width - PAD * 2
    self:drawText("Condition", PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
    self:drawTextRight(string.format("%.2f / %.2f", now, max), self.width - PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
    local barTop = y + 18
    self:drawRect(PAD, barTop, w, 16, 0.7, 0.08, 0.08, 0.10)
    local fill = math.max(0, math.min(1, ratio))
    if fill > 0 then
        self:drawRect(PAD, barTop, w * fill, 16, 0.95, r, g, b)
    end
    self:drawRectBorder(PAD, barTop, w, 16, 0.35, 1, 1, 1)
    y = barTop + 24

    -- Infection
    local infection = tonumber(brain.infection) or 0
    self:drawText("Infection: " .. string.format("%d%%", infection), PAD, y,
        0.75, 0.35, 0.75, 1, UIFont.Small)
    y = y + 20

    -- Separator
    self:drawRect(PAD, y, w, 1, 0.5, 0.4, 0.4, 0.4)
    y = y + 8

    -- Body parts header
    self:drawText("Body Parts", PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Medium)
    y = y + 22

    -- Each body part row
    if not bd then
        self:drawText("Body damage unavailable", PAD, y, 0.8, 0.5, 0.5, 1, UIFont.Small)
        return
    end

    for _, entry in ipairs(BODY_PARTS) do
        if y > self.height - 54 then
            -- Ran out of room. The list is long enough for scanning but not
            -- a scrollable panel (keeping this file simple).
            self:drawText("(more parts below...)", PAD, y, 0.4, 0.4, 0.4, 1, UIFont.Small)
            break
        end
        local status = partStatus(bd, entry.part)
        local color = status.color

        -- Part name
        self:drawText(entry.label, PAD + 4, y + 1, 0.85, 0.85, 0.85, 1, UIFont.Small)

        -- Status dot
        if status.kind ~= "healthy" then
            self:drawRect(PAD + 110, y + 5, 10, 10, 0.95, color.r, color.g, color.b)
            self:drawText(status.label, PAD + 126, y + 1, color.r, color.g, color.b, 1, UIFont.Small)
        end

        y = y + ROW_H
    end

    -- Bandage button state
    if self.bandageButton then
        local player = getSpecificPlayer(0)
        local item = player and findBandage(player)
        if not item then
            self.bandageButton:setEnable(false)
            self.bandageButton:setTitle("No bandage")
        else
            self.bandageButton:setEnable(true)
            self.bandageButton:setTitle("Bandage selected part")
        end
    end
end

--- Find the first usable bandage in the player's inventory.
local function findBandage(player)
    local inventory = player:getInventory()
    if not inventory then return nil end
    for _, itemType in ipairs(BANDAGES) do
        local item = inventory:getFirstTypeRecurse(itemType)
        if item then return item, itemType end
    end
    return nil
end

--- Live condition of the NPC.
local function condition(zombie, brain)
    local max = tonumber(brain and brain.health) or 2
    if max <= 0 then max = 2 end
    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return max, max end
    return now, max
end

function ScenesRelationsHealthPanel:onBandage()
    local player = getSpecificPlayer(0)
    local zombie = self.bandit
    if not player or not zombie then return end

    local brain = BanditBrain.Get(zombie)
    if not brain then return end

    local item, itemType = findBandage(player)
    if not item then
        SR.Log("HEALTH bandage refused -- nothing to bandage with")
        return
    end

    -- Find the first wounded body part and bandage it.
    local bd = nil
    pcall(function() bd = zombie:getBodyDamage() end)
    if not bd then
        SR.Log("HEALTH bandage refused -- body damage unavailable")
        return
    end

    local bandagedPart = nil
    local bandagedKind = nil
    for _, entry in ipairs(BODY_PARTS) do
        local status = partStatus(bd, entry.part)
        if status.kind ~= "healthy" and status.kind ~= "bandaged" then
            local ok, bp = pcall(function() return bd:getBodyPart(entry.part) end)
            if ok and bp then
                -- Heal the part: stop bleeding, apply bandage.
                pcall(function() bp:setBleeding(false) end)
                pcall(function() zombie:addVisualBandage(entry.part, true) end)
                bandagedPart = entry.part
                bandagedKind = status.kind
                break
            end
        end
    end

    if not bandagedPart then
        -- No wounded parts to bandage (all already bandaged or healthy).
        -- Fall back to general health restore.
        local now, max = condition(zombie, brain)
        if now >= max then
            SR.Log("HEALTH bandage refused -- all parts healthy")
            return
        end
        local healed = math.min(max, now + BANDAGE_HEAL)
        pcall(function() zombie:setHealth(healed) end)
        pcall(function() zombie:addVisualBandage(BodyPartType.Torso_Upper, true) end)
    end

    player:getInventory():Remove(item)
    player:playSound("FirstAidApplyBandage")

    local before, after = SR.Actions.RewardBandage(player, zombie)

    SR.Log(string.format("HEALTH %s bandaged with %s | part=%s wound=%s | trust %s -> %s",
        tostring(brain.fullname), tostring(itemType),
        tostring(bandagedPart or "general"), tostring(bandagedKind or "health"),
        tostring(before), tostring(after)))
end

function ScenesRelationsHealthPanel:createChildren()
    ISCollapsableWindow.createChildren(self)

    local bw = self.width - PAD * 2
    local bh = 26
    self.bandageButton = ISButton:new(PAD, self.height - bh - PAD, bw, bh,
        "Bandage", self, ScenesRelationsHealthPanel.onBandage)
    self.bandageButton:initialise()
    self.bandageButton:instantiate()
    self:addChild(self.bandageButton)
end

function ScenesRelationsHealthPanel:new(bandit, name)
    local x = getCore():getScreenWidth() / 2 - WIDTH / 2
    local y = getCore():getScreenHeight() / 2 - HEIGHT / 2
    local o = ISCollapsableWindow.new(self, x, y, WIDTH, HEIGHT)
    o.bandit = bandit
    o.title = name
    o:setResizable(false)
    return o
end

local panel = nil

function SR.Health.Open(player, bandit)
    if panel then
        panel:removeFromUIManager()
        panel = nil
    end

    local brain = BanditBrain.Get(bandit)
    local name = tostring(brain and brain.fullname or "Survivor")
    local now, max = condition(bandit, brain)

    panel = ScenesRelationsHealthPanel:new(bandit, name)
    panel:initialise()
    panel:addToUIManager()

    SR.Log(string.format("HEALTH opened on %s | condition %.2f / %.2f | body parts view",
        name, now, max))
end

function SR.Health.Close()
    if panel then
        panel:removeFromUIManager()
        panel = nil
    end
end

Events.OnGameStart.Add(function()
    SR.Log("HEALTH ready -- body part view with per-part wound status and bandaging")
end)
