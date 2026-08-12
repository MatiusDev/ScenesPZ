-- ScenesPZ -- somebody else's health, with body part detail.
--
-- THE 11-08 FINDING THAT SHAPES THIS FILE, DO NOT RE-DERIVE
-- `zombie:getBodyDamage()` on an IsoZombie is callable and RETURNS NIL. There is no per-body-
-- part data for a Bandits NPC. Every wound displayed here lives on brain.scenesWound.bodyParts,
-- which is our own tracking and the sole source of truth for the per-part display.
--
-- WHAT ACTUALLY EXISTS FOR AN NPC
--   zombie:getHealth()            live overall health, one float
--   brain.health                  the SPAWN MAXIMUM (BanditServerSpawner.lua:332), not current
--   brain.infection                zombie virus percentage
--   brain.scenesWound              our own record: dressing, bleeding, bodyParts, etc.
--   SR.Wounds.NeedsDressing(z,b)   whether they want a bandage right now
--
-- LAYOUT
--   Left:  a 17-part humanoid silhouette drawn with drawRect, each body part coloured by its
--          worst wound state. Clicking a part selects it for detail on the right. A vertical
--          condition bar runs alongside.
--   Right: overall condition, zombie virus, and the wound state we track. When a body part is
--          selected, its name and wound list expands inline below the global stats.
--   Bottom: the bandage button and the engine-limitation footnote.
--
-- HOW HEALING WORKS
-- Clicking Bandage spends one dressing from the PLAYER's inventory and restores a fraction of
-- the NPC's own maximum (brain.health) immediately. Per-part bleeding is cleared and wounded
-- parts are marked as bandaged.

require "ScenesRelations"
require "ScenesRelationsActions"
require "ScenesRelationsWounds"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"

local SR = ScenesRelations

SR.Health = SR.Health or {}

local WIDTH, HEIGHT = 680, 420
local PAD = 10

-- Left-column geometry
local SIL_W, SIL_H = 160, 280
local BAR_W = 14
local COL_GAP = 10
local TEXT_GAP = 20

-- Colours
local C = {
    ok        = { r = 0.35, g = 0.85, b = 0.35 },
    hurt      = { r = 0.90, g = 0.65, b = 0.25 },
    critical  = { r = 0.90, g = 0.25, b = 0.25 },
    bleeding  = { r = 0.90, g = 0.25, b = 0.25 },
    bandaged  = { r = 0.35, g = 0.75, b = 0.40 },
    infection = { r = 0.65, g = 0.35, b = 0.80 },
    dim       = { r = 0.55, g = 0.55, b = 0.55 },
    -- Body part fill colours
    part_healthy  = { r = 0.35, g = 0.38, b = 0.42 },
    part_scratch  = { r = 0.92, g = 0.50, b = 0.42 },
    part_cut      = { r = 0.92, g = 0.30, b = 0.28 },
    part_deep     = { r = 0.88, g = 0.16, b = 0.16 },
    part_fracture = { r = 0.85, g = 0.40, b = 0.15 },
    part_bandaged = { r = 0.28, g = 0.65, b = 0.38 },
}

-- Body part region definitions relative to the silhouette origin (silX, silY). Each entry is
-- { x, y, w, h } in pixels within the 160x280 silhouette box.
local PART_REGIONS = {
    [BodyPartType.Head]         = { x = 45,  y = 0,   w = 70,  h = 42 },
    [BodyPartType.Neck]         = { x = 65,  y = 42,  w = 30,  h = 14 },
    [BodyPartType.UpperArm_L]   = { x = 0,   y = 56,  w = 28,  h = 50 },
    [BodyPartType.Torso_Upper]  = { x = 28,  y = 56,  w = 104, h = 50 },
    [BodyPartType.UpperArm_R]   = { x = 132, y = 56,  w = 28,  h = 50 },
    [BodyPartType.ForeArm_L]    = { x = 0,   y = 106, w = 28,  h = 50 },
    [BodyPartType.Torso_Lower]  = { x = 28,  y = 106, w = 104, h = 50 },
    [BodyPartType.ForeArm_R]    = { x = 132, y = 106, w = 28,  h = 50 },
    [BodyPartType.Hand_L]       = { x = 0,   y = 156, w = 28,  h = 20 },
    [BodyPartType.Groin]        = { x = 40,  y = 156, w = 80,  h = 20 },
    [BodyPartType.Hand_R]       = { x = 132, y = 156, w = 28,  h = 20 },
    [BodyPartType.UpperLeg_L]   = { x = 28,  y = 176, w = 48,  h = 52 },
    [BodyPartType.UpperLeg_R]   = { x = 84,  y = 176, w = 48,  h = 52 },
    [BodyPartType.LowerLeg_L]   = { x = 28,  y = 228, w = 48,  h = 36 },
    [BodyPartType.LowerLeg_R]   = { x = 84,  y = 228, w = 48,  h = 36 },
    [BodyPartType.Foot_L]       = { x = 24,  y = 264, w = 52,  h = 16 },
    [BodyPartType.Foot_R]       = { x = 84,  y = 264, w = 52,  h = 16 },
}

-- All 17 parts in draw order -- back to front so overlapping regions layer correctly.
local ALL_PARTS = {
    BodyPartType.Head, BodyPartType.Neck,
    BodyPartType.UpperArm_L, BodyPartType.Torso_Upper, BodyPartType.UpperArm_R,
    BodyPartType.ForeArm_L, BodyPartType.Torso_Lower, BodyPartType.ForeArm_R,
    BodyPartType.Hand_L, BodyPartType.Groin, BodyPartType.Hand_R,
    BodyPartType.UpperLeg_L, BodyPartType.UpperLeg_R,
    BodyPartType.LowerLeg_L, BodyPartType.LowerLeg_R,
    BodyPartType.Foot_L, BodyPartType.Foot_R,
}

-- Bandage types this panel will look for in the PLAYER's inventory, best first.
local BANDAGES = {
    "Base.AlcoholBandage", "Base.Bandage",
    "Base.AlcoholRippedSheets", "Base.RippedSheets",
}

local PANEL_RESTORE = {
    sterile = 1.00,
    bandage = 0.95,
}

-- The selected body part, if any. A file-local transient -- meaningless after a reload, and
-- that is correct: a selection made before the panel was closed should not survive.
local selectedPart = nil

-- THE silhouette is drawn per-part rather than as one monolithic shape. Each body part is a
-- coloured fill box with a border, and the box is drawn only if the engine exposes the
-- BodyPartType constant -- which it always does, but a nil index under a missing part stays
-- silent rather than throwing.

--- Which colour a body part earns, based on the worst wound in its tracking entry.
local function partColor(partState)
    if not partState then return C.part_healthy end
    if partState.deepWounds > 0 or partState.bites > 0 or partState.bleeding then
        return C.part_deep
    end
    if partState.cuts > 0 then return C.part_cut end
    if partState.scratches > 0 then return C.part_scratch end
    if partState.fractures > 0 then return C.part_fracture end
    if partState.bandaged then return C.part_bandaged end
    return C.part_healthy
end

--- The body part at (mx, my), or nil. Coordinates are relative to the panel, the region
--- table is relative to the silhouette origin (silX, silY).
local function hitPart(silX, silY, mx, my)
    local rx, ry = mx - silX, my - silY
    for _, pt in ipairs(ALL_PARTS) do
        local r = PART_REGIONS[pt]
        if r then
            if rx >= r.x and rx < r.x + r.w and ry >= r.y and ry < r.y + r.h then
                return pt
            end
        end
    end
    return nil
end

-- STRIP CONDITION BAR -------------------------------------------------------------------

local BAR_STRIPS = 24

local function drawConditionBar(panel, x, y, w, h, ratio, mr, mg, mb)
    local stripH = h / BAR_STRIPS
    for i = 0, BAR_STRIPS - 1 do
        local shade = 1 - (i / (BAR_STRIPS - 1))
        panel:drawRect(x, y + i * stripH, w, stripH + 1, 1, shade, shade, shade)
    end
    panel:drawRectBorder(x, y, w, h, 0.6, 1, 1, 1)
    local markerY = y + (1 - ratio) * h
    panel:drawRect(x - 3, markerY - 1, w + 6, 3, 1, mr, mg, mb)
end

-- BANDAGE HELPERS -----------------------------------------------------------------------

local function findBandage(player)
    local inv = player:getInventory()
    if not inv then return nil end
    for _, t in ipairs(BANDAGES) do
        local item = inv:getFirstTypeRecurse(t)
        if item then return item, t end
    end
    return nil
end

local function dressingKind(item)
    local sterile, power = false, 0
    local okAlc = pcall(function() sterile = item:isAlcoholic() == true end)
    local okPow = pcall(function() power = item:getBandagePower() or 0 end)
    if not okAlc or not okPow then
        SR.Log("HEALTH dressingKind could not read item flags -- treating as clean")
    end
    if sterile then return "sterile" end
    if power >= 2 then return "bandage" end
    return "clean"
end

local function condition(zombie, brain)
    local max = tonumber(brain and brain.health) or 2
    if max <= 0 then max = 2 end
    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return max, max end
    return now, max
end

-- THE PANEL -----------------------------------------------------------------------------

ScenesRelationsHealthPanel = ISCollapsableWindow:derive("ScenesRelationsHealthPanel")

function ScenesRelationsHealthPanel:onMouseDown(x, y)
    local silX = PAD
    local silY = (self.titleBarHeight and self:titleBarHeight() or 18) + PAD
    local pt = hitPart(silX, silY, x, y)
    if pt then
        selectedPart = (selectedPart == pt) and nil or pt
        return true
    end
    selectedPart = nil
    return ISCollapsableWindow.onMouseDown(self, x, y)
end

function ScenesRelationsHealthPanel:prerender()
    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a,
        self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)

    ISCollapsableWindow.prerender(self)

    local zombie = self.bandit
    if not zombie then return end

    local ok, brain = pcall(function() return BanditBrain.Get(zombie) end)
    if not ok or not brain then
        self:drawText("They are gone.", PAD, self:titleBarHeight() + PAD,
            0.8, 0.5, 0.5, 1, UIFont.Small)
        return
    end

    local now, max = condition(zombie, brain)
    local ratio = max > 0 and (now / max) or 0

    local band
    if ratio < 0.3 then band = "critical"
    elseif ratio < 0.6 then band = "hurt"
    else band = "ok" end
    local col = C[band]

    local top = self:titleBarHeight() + PAD

    -- === LEFT: body part silhouette + condition bar ===
    local silX, silY = PAD, top
    local wound = brain.scenesWound
    local parts = wound and wound.bodyParts

    -- Draw body part regions
    for _, pt in ipairs(ALL_PARTS) do
        local r = PART_REGIONS[pt]
        local state = parts and parts[pt]
        local pc = partColor(state)
        local isSel = selectedPart == pt

        local fillA = isSel and 0.35 or 0.18
        self:drawRect(silX + r.x, silY + r.y, r.w, r.h, fillA, pc.r, pc.g, pc.b)

        local ba = isSel and 0.95 or 0.45
        self:drawRectBorder(silX + r.x, silY + r.y, r.w, r.h, ba, pc.r, pc.g, pc.b)
    end

    local barX = silX + SIL_W + COL_GAP
    drawConditionBar(self, barX, silY, BAR_W, SIL_H, ratio, col.r, col.g, col.b)

    -- === RIGHT: global status + selected part detail ===
    local rx = barX + BAR_W + TEXT_GAP
    local ry = top

    self:drawText("Overall Body Status", rx, ry, 0.85, 0.85, 0.85, 1, UIFont.Medium)
    ry = ry + 20

    local statusWord = (band == "ok" and (ratio >= 1 and "OK" or "Minor injuries"))
        or (band == "hurt" and "Hurt") or "Critical"
    self:drawText(string.format("%s (%.0f%%)", statusWord, ratio * 100),
        rx, ry, col.r, col.g, col.b, 1, UIFont.Small)
    ry = ry + 20

    local infection = tonumber(brain.infection) or 0
    self:drawText(string.format("Zombie virus: %d%%", infection),
        rx, ry, C.infection.r, C.infection.g, C.infection.b, 1, UIFont.Small)
    ry = ry + 20

    local bleeding = wound and wound.bleeding
    if bleeding then
        self:drawText("Bleeding", rx, ry, C.bleeding.r, C.bleeding.g, C.bleeding.b, 1, UIFont.Small)
        ry = ry + 16
        local sweeps = tonumber(wound.bleedSweeps) or 0
        self:drawText(string.format("  - for %d sweep%s", sweeps, sweeps == 1 and "" or "s"),
            rx, ry, C.bleeding.r, C.bleeding.g, C.bleeding.b, 1, UIFont.Small)
        ry = ry + 20
    else
        self:drawText("Not bleeding", rx, ry, C.dim.r, C.dim.g, C.dim.b, 1, UIFont.Small)
        ry = ry + 20
    end

    if wound and wound.dressing then
        self:drawText("Dressing: " .. tostring(wound.dressing),
            rx, ry, C.bandaged.r, C.bandaged.g, C.bandaged.b, 1, UIFont.Small)
    else
        self:drawText("No dressing", rx, ry, C.dim.r, C.dim.g, C.dim.b, 1, UIFont.Small)
    end
    ry = ry + 20

    local needsOk, needs = pcall(SR.Wounds.NeedsDressing, zombie, brain)
    if needsOk and needs then
        self:drawText("Wants a bandage", rx, ry, C.hurt.r, C.hurt.g, C.hurt.b, 1, UIFont.Small)
        ry = ry + 20
    end

    -- === Selected body part detail ===
    if selectedPart and parts then
        ry = ry + 4
        self:drawRect(rx, ry, 180, 1, 0.5, 0.5, 0.5, 0.5)
        ry = ry + 6

        local nameOk, partName = pcall(BodyPartType.getDisplayName, selectedPart)
        local displayName = nameOk and partName or "Unknown part"
        self:drawText(displayName, rx, ry, 0.9, 0.9, 0.9, 1, UIFont.Small)
        ry = ry + 18

        local state = parts[selectedPart]
        if state then
            local hasWound = false
            if state.scratches > 0 then
                self:drawText("- " .. getText("IGUI_health_Scratched"),
                    rx, ry, C.part_scratch.r, C.part_scratch.g, C.part_scratch.b, 1, UIFont.Small)
                ry = ry + 16; hasWound = true
            end
            if state.cuts > 0 then
                self:drawText("- " .. getText("IGUI_health_Cut"),
                    rx, ry, C.part_cut.r, C.part_cut.g, C.part_cut.b, 1, UIFont.Small)
                ry = ry + 16; hasWound = true
            end
            if state.deepWounds > 0 then
                self:drawText("- " .. getText("IGUI_health_DeepWound"),
                    rx, ry, C.part_deep.r, C.part_deep.g, C.part_deep.b, 1, UIFont.Small)
                ry = ry + 16; hasWound = true
            end
            if state.bites > 0 then
                self:drawText("- " .. getText("IGUI_health_Bitten"),
                    rx, ry, C.part_deep.r, C.part_deep.g, C.part_deep.b, 1, UIFont.Small)
                ry = ry + 16; hasWound = true
            end
            if state.bleeding then
                self:drawText("- " .. getText("IGUI_health_Bleeding"),
                    rx, ry, C.bleeding.r, C.bleeding.g, C.bleeding.b, 1, UIFont.Small)
                ry = ry + 16; hasWound = true
            end
            if state.fractures > 0 then
                self:drawText("- " .. getText("IGUI_health_Fracture"),
                    rx, ry, C.part_fracture.r, C.part_fracture.g, C.part_fracture.b, 1, UIFont.Small)
                ry = ry + 16; hasWound = true
            end
            if state.bandaged then
                self:drawText("- " .. getText("IGUI_health_Bandaged"),
                    rx, ry, C.part_bandaged.r, C.part_bandaged.g, C.part_bandaged.b, 1, UIFont.Small)
                ry = ry + 16; hasWound = true
            end
            if not hasWound then
                self:drawText("Healthy", rx, ry, 0.5, 0.8, 0.5, 1, UIFont.Small)
            end
        else
            self:drawText("Healthy", rx, ry, 0.5, 0.8, 0.5, 1, UIFont.Small)
        end
    end

    -- === Shared footnote ===
    local footY = math.max(silY + SIL_H, ry) + 12
    self:drawRect(PAD, footY, self.width - PAD * 2, 1, 0.4, 0.4, 0.4, 0.4)
    footY = footY + 8
    self:drawText("Per-part health is not exposed for NPCs by the engine. "
        .. "Shown data is our own tracking.",
        PAD, footY, C.dim.r, C.dim.g, C.dim.b, 1, UIFont.Small)

    -- === Bandage button state ===
    if self.bandageButton then
        local player = getSpecificPlayer(0)
        local item = player and findBandage(player)
        if not (needsOk and needs) then
            self.bandageButton:setEnable(false)
            self.bandageButton:setTitle("Not injured")
        elseif not item then
            self.bandageButton:setEnable(false)
            self.bandageButton:setTitle("No bandage in inventory")
        else
            self.bandageButton:setEnable(true)
            self.bandageButton:setTitle("Bandage")
        end
    end
end

function ScenesRelationsHealthPanel:onBandage()
    local player = getSpecificPlayer(0)
    local zombie = self.bandit
    if not player or not zombie then return end

    local brain = BanditBrain.Get(zombie)
    if not brain then return end

    local item, itemType = findBandage(player)
    if not item then return end

    local wound = SR.Wounds.Of(brain)
    local kind = dressingKind(item)

    local max = tonumber(brain.health) or 2
    local before = max
    local gotHealth = pcall(function() before = zombie:getHealth() end)
    if not gotHealth then
        SR.Log("HEALTH could not read current health for " .. tostring(brain.fullname)
            .. " -- assuming their maximum")
    end

    local restore = (PANEL_RESTORE[kind] or PANEL_RESTORE.bandage) * max
    local healed = math.min(max, math.max(before, restore))

    local set = pcall(function() zombie:setHealth(healed) end)
    if not set then
        SR.Log("HEALTH could not bandage " .. tostring(brain.fullname) .. " -- setHealth threw")
        return
    end

    local holder = item:getContainer() or player:getInventory()
    holder:Remove(item)
    player:playSound("FirstAidApplyBandage")

    if wound.bleeding then
        wound.bleeding, wound.bleedDay, wound.bleedSweeps = nil, nil, nil
        SR.Wounds.ClearBodyBleeding(brain)
    end
    wound.dressing = kind
    wound.day = SR.Today()
    SR.Wounds.MarkBodyBandaged(brain, kind)

    local rewardBefore, rewardAfter = SR.Actions.RewardBandage(player, zombie)

    SR.Log(string.format(
        "HEALTH %s bandaged with %s (%s) | %.2f -> %.2f / %.2f | trust %s -> %s",
        tostring(brain.fullname), tostring(itemType), kind, before, healed, max,
        tostring(rewardBefore), tostring(rewardAfter)))
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
    o.background = true
    o.backgroundColor = { r = 0.04, g = 0.04, b = 0.05, a = 0.95 }
    o:setResizable(false)
    return o
end

local panel = nil

function SR.Health.Open(player, bandit)
    if panel then panel:removeFromUIManager(); panel = nil end
    selectedPart = nil
    local brain = BanditBrain.Get(bandit)
    local name = tostring(brain and brain.fullname or "Survivor")
    panel = ScenesRelationsHealthPanel:new(bandit, name)
    panel:initialise()
    panel:addToUIManager()
end

function SR.Health.Close()
    if panel then panel:removeFromUIManager(); panel = nil end
    selectedPart = nil
end

Events.OnGameStart.Add(function()
    SR.Log("HEALTH ready -- 17-part body display, condition bar, bandage action; "
        .. "no per-part engine data for NPCs, our own tracking is drawn")
end)
