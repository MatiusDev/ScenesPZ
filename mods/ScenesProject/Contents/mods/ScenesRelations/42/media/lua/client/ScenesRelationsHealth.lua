-- ScenesPZ -- somebody else's health, body part by body part.
--
-- ASKED FOR IN THESE WORDS
--   "debe aparecer una opcion que diga salud, este debe de abrir el cuadro de salud
--    parecido al de jugador, pero con los stats del NPC, de manera que yo pueda vendarlo y
--    ayudarle."
--
-- THE 10-08 SESSION: BODY PARTS ARE REACHABLE. Bandits uses getBodyDamage on NPCs
-- (ZASmack.lua:358-359, ZABandage.lua:50-51). The engine's body part pipeline processes
-- IsoZombie fully. getBodyDamage, BodyPartType.*, setBleeding, setHaveGlass, addVisualBandage
-- are all verified callable.
--
-- LAYOUT
--   Left (60%): body part list — each part with name + wound status icon + bandage indicator
--   Right (40%): details panel — wound type, severity, actions for the selected part
--
-- TODO: Spanish localization for the UI labels. Currently English only.
--
-- HOW HEALING WORKS (matches vanilla player model)
-- Bandaging a body part stops the bleeding and applies a visual bandage. The engine then
-- handles gradual recovery over time — exactly as it does for players. Health is not
-- instantly restored; a bandaged part heals slowly. When fully healed, the bandage falls off
-- (the engine removes it automatically when the part reaches full health).
--
-- This is different from the old model where one "Bandage" button restored a flat 0.8 health.
-- Now bandaging is per-part, stops bleeding, and lets the engine's recovery tick run.

require "ScenesRelations"
require "ScenesRelationsActions"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"

local SR = ScenesRelations

SR.Health = SR.Health or {}

local WIDTH, HEIGHT = 480, 460
local PAD = 10
local LEFT_W = 260   -- body part list width
local ROW_H = 24

-- All 17 body parts Bandits knows about, in display order (head to feet).
-- Names from ZABandage.lua:3-21.
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

-- Wound colours matching vanilla's scheme so the player reads them the same way.
local C = {
    healthy   = { r = 0.30, g = 0.30, b = 0.30 },
    scratch   = { r = 0.90, g = 0.80, b = 0.40 },
    deepWound = { r = 0.90, g = 0.20, b = 0.20 },
    bite      = { r = 0.80, g = 0.20, b = 0.60 },
    bleeding  = { r = 0.85, g = 0.15, b = 0.15 },
    glass     = { r = 0.55, g = 0.80, b = 0.95 },
    bandaged  = { r = 0.35, g = 0.65, b = 0.35 },
}

-- Bandage types, best first.
local BANDAGES = {
    "Base.AlcoholBandage", "Base.Bandage",
    "Base.AlcoholRippedSheets", "Base.RippedSheets",
}

--- Wound status for a body part, read directly from the engine.
--- Returns { kind, label, color, bleeding, bandaged, hasGlass, isDeep }
local function readPart(bd, partType)
    local ok, bp = pcall(function() return bd:getBodyPart(partType) end)
    if not ok or not bp then return nil end

    local bitten, deep, scratched, bleeding, hasGlass, bandageLife = false, false, false, false, false, 0
    pcall(function() bitten = bp:bitten() end)
    pcall(function() deep = bp:isDeepWounded() or bp:deepWounded() end)
    pcall(function() scratched = bp:scratched() end)
    pcall(function() bleeding = bp:bleeding() end)
    pcall(function() hasGlass = bp:haveGlass() end)
    pcall(function() bandageLife = bp:getBandageLife() or 0 end)

    local bandaged = bandageLife > 0

    if bitten then
        return { kind = "bite", label = "Bitten", color = C.bite, bleeding = bleeding,
            bandaged = bandaged, hasGlass = hasGlass, isDeep = false, bp = bp }
    elseif deep then
        return { kind = "deepWound", label = "Deep wound", color = C.deepWound,
            bleeding = bleeding, bandaged = bandaged, hasGlass = hasGlass, isDeep = true, bp = bp }
    elseif scratched then
        return { kind = "scratch", label = "Scratch", color = C.scratch,
            bleeding = bleeding, bandaged = bandaged, hasGlass = hasGlass, isDeep = false, bp = bp }
    end

    if hasGlass then
        return { kind = "glass", label = "Glass lodged", color = C.glass, bleeding = false,
            bandaged = false, hasGlass = true, isDeep = false, bp = bp }
    end

    if bandaged then
        return { kind = "bandaged", label = "Bandaged", color = C.bandaged, bleeding = false,
            bandaged = true, hasGlass = false, isDeep = false, bp = bp }
    end

    return { kind = "healthy", label = "Healthy", color = C.healthy, bleeding = false,
        bandaged = false, hasGlass = false, isDeep = false, bp = bp }
end

--- Find the first usable bandage.
local function findBandage(player)
    local inv = player:getInventory()
    if not inv then return nil end
    for _, t in ipairs(BANDAGES) do
        local item = inv:getFirstTypeRecurse(t)
        if item then return item, t end
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

    local now, max = condition(zombie, brain)
    local ratio = max > 0 and (now / max) or 0

    -- === LEFT PANEL: body part list ===
    local lx = PAD
    local ly = 34
    local lw = LEFT_W

    -- Overall condition
    local cr, cg, cb = 0.30, 0.80, 0.35
    if ratio < 0.3 then cr, cg, cb = 0.85, 0.25, 0.25
    elseif ratio < 0.6 then cr, cg, cb = 0.90, 0.65, 0.25 end
    self:drawText(string.format("Condition: %.0f%%", ratio * 100), lx, ly, cr, cg, cb, 1, UIFont.Medium)
    ly = ly + 22
    self:drawRect(lx, ly, lw, 8, 0.7, 0.08, 0.08, 0.10)
    if ratio > 0 then self:drawRect(lx, ly, lw * ratio, 8, 0.95, cr, cg, cb) end
    self:drawRectBorder(lx, ly, lw, 8, 0.35, 1, 1, 1)
    ly = ly + 14

    -- Infection
    local inf = tonumber(brain.infection) or 0
    self:drawText(string.format("Infection: %d%%", inf), lx, ly, 0.75, 0.35, 0.75, 1, UIFont.Small)
    ly = ly + 18

    -- Separator
    self:drawRect(lx, ly, lw, 1, 0.4, 0.4, 0.4, 0.4)
    ly = ly + 8

    -- Body parts
    if not bd then
        self:drawText("Body data unavailable", lx, ly, 0.6, 0.3, 0.3, 1, UIFont.Small)
    else
        for i, entry in ipairs(BODY_PARTS) do
            if ly + ROW_H > self.height - 50 then break end

            local st = readPart(bd, entry.part)
            if st then
                local isSel = (self.selectedPart == i)
                local bgR, bgG, bgB = 0.12, 0.12, 0.12
                if isSel then bgR, bgG, bgB = 0.18, 0.18, 0.22 end

                self:drawRect(lx, ly, lw, ROW_H - 1, 0.9, bgR, bgG, bgB)

                -- Status dot
                local c = st.color
                self:drawRect(lx + 4, ly + 7, 8, 8, 0.95, c.r, c.g, c.b)

                -- Part name
                self:drawText(entry.label, lx + 18, ly + 2, 0.85, 0.85, 0.85, 1, UIFont.Small)

                -- Wound label
                if st.kind ~= "healthy" then
                    self:drawText(st.label, lx + lw - 100, ly + 2, c.r, c.g, c.b, 1, UIFont.Small)
                end

                ly = ly + ROW_H
            end
        end
    end

    -- === RIGHT PANEL: wound details ===
    local rx = lx + lw + 8
    local rw = self.width - rx - PAD
    local ry = 34

    self:drawText("Wound Details", rx, ry, 0.85, 0.85, 0.85, 1, UIFont.Medium)
    ry = ry + 24

    if not bd then
        self:drawText("Select a body part", rx, ry, 0.5, 0.5, 0.5, 1, UIFont.Small)
    elseif not self.selectedPart then
        self:drawText("Click a body part", rx, ry, 0.5, 0.5, 0.5, 1, UIFont.Small)
        self:drawText("to see details", rx, ry + 16, 0.5, 0.5, 0.5, 1, UIFont.Small)
    else
        local entry = BODY_PARTS[self.selectedPart]
        local st = readPart(bd, entry.part)
        if not st then
            self:drawText("Cannot read part", rx, ry, 0.8, 0.3, 0.3, 1, UIFont.Small)
        else
            self:drawText(entry.label, rx, ry, 0.9, 0.9, 0.9, 1, UIFont.Medium)
            ry = ry + 24

            self:drawText("Status: " .. st.label, rx, ry, st.color.r, st.color.g, st.color.b, 1, UIFont.Small)
            ry = ry + 20

            if st.bleeding then
                self:drawText("[!] Bleeding", rx, ry, C.bleeding.r, C.bleeding.g, C.bleeding.b, 1, UIFont.Small)
                ry = ry + 18
            end
            if st.hasGlass then
                self:drawText("[!] Glass lodged", rx, ry, C.glass.r, C.glass.g, C.glass.b, 1, UIFont.Small)
                ry = ry + 18
            end
            if st.isDeep then
                self:drawText("[!] Deep wound - needs suture", rx, ry, C.deepWound.r, C.deepWound.g, C.deepWound.b, 1, UIFont.Small)
                ry = ry + 18
            end
            if st.bandaged then
                self:drawText("Bandage applied", rx, ry, C.bandaged.r, C.bandaged.g, C.bandaged.b, 1, UIFont.Small)
                ry = ry + 18
            end
            if st.kind == "healthy" then
                self:drawText("No injuries", rx, ry, 0.4, 0.7, 0.4, 1, UIFont.Small)
            end
        end
    end

    -- Bandage button
    if self.bandageButton then
        local player = getSpecificPlayer(0)
        local item = player and findBandage(player)
        if not item then
            self.bandageButton:setEnable(false)
            self.bandageButton:setTitle("No bandage in inventory")
        elseif not self.selectedPart then
            self.bandageButton:setEnable(false)
            self.bandageButton:setTitle("Select a body part first")
        else
            local entry = BODY_PARTS[self.selectedPart]
            local st = bd and readPart(bd, entry.part)
            if st and st.kind == "healthy" then
                self.bandageButton:setEnable(false)
                self.bandageButton:setTitle("Part is healthy")
            else
                self.bandageButton:setEnable(true)
                self.bandageButton:setTitle("Bandage " .. entry.label)
            end
        end
    end
end

function ScenesRelationsHealthPanel:onMouseDown(x, y)
    -- Check if click is on a body part row in the left panel
    local ly = 34 + 22 + 8 + 14 + 18 + 8  -- offset to first body part row
    for i, _ in ipairs(BODY_PARTS) do
        if ly + ROW_H > self.height - 50 then break end
        if x > PAD and x < PAD + LEFT_W and y > ly and y < ly + ROW_H then
            self.selectedPart = i
            return true
        end
        ly = ly + ROW_H
    end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end

function ScenesRelationsHealthPanel:onBandage()
    local player = getSpecificPlayer(0)
    local zombie = self.bandit
    if not player or not zombie then return end
    if not self.selectedPart then return end

    local brain = BanditBrain.Get(zombie)
    if not brain then return end

    local item, itemType = findBandage(player)
    if not item then return end

    local bd = nil
    pcall(function() bd = zombie:getBodyDamage() end)
    if not bd then return end

    local entry = BODY_PARTS[self.selectedPart]
    local ok, bp = pcall(function() return bd:getBodyPart(entry.part) end)
    if not ok or not bp then return end

    -- Stop bleeding on this part, apply visual bandage.
    -- vanilla uses setBleedingTime(0) to stop bleeding (ISHealthPanel:198).
    pcall(function() bp:setBleedingTime(0) end)
    pcall(function() zombie:addVisualBandage(entry.part, true) end)

    player:getInventory():Remove(item)
    player:playSound("FirstAidApplyBandage")

    local before, after = SR.Actions.RewardBandage(player, zombie)

    SR.Log(string.format("HEALTH %s bandaged %s with %s | trust %s -> %s",
        tostring(brain.fullname), entry.label, tostring(itemType),
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
    o.selectedPart = nil
    o:setResizable(false)
    return o
end

local panel = nil

function SR.Health.Open(player, bandit)
    if panel then panel:removeFromUIManager(); panel = nil end
    local brain = BanditBrain.Get(bandit)
    local name = tostring(brain and brain.fullname or "Survivor")
    panel = ScenesRelationsHealthPanel:new(bandit, name)
    panel:initialise()
    panel:addToUIManager()
end

function SR.Health.Close()
    if panel then panel:removeFromUIManager(); panel = nil end
end

Events.OnGameStart.Add(function()
    SR.Log("HEALTH ready -- body part panel with per-part wound details and bandaging")
end)
