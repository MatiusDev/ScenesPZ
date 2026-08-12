-- ScenesPZ -- somebody else's health, read honestly instead of guessed at.
--
-- ASKED FOR IN THESE WORDS
--   "debe aparecer una opcion que diga salud, este debe de abrir el cuadro de salud
--    parecido al de jugador, pero con los stats del NPC, de manera que yo pueda vendarlo y
--    ayudarle."
--
-- THE 11-08 FINDING THAT REWROTE THIS FILE, VERIFIED THIS SESSION -- DO NOT RE-DERIVE
-- `zombie:getBodyDamage()` on an IsoZombie is callable and RETURNS NIL. There is no per-body-
-- part data for a Bandits NPC. The previous version of this file assumed otherwise (citing
-- ZASmack.lua:358 and ZABandage.lua:50, both vendor Bandits code and both actually operating on
-- the PLAYER or on a different method -- `addVisualBandage`, not `getBodyDamage`) and rendered
-- the literal string "Body data unavailable" for every NPC, every time (caps/npc-health-menu.png).
-- The in-game probe confirmed it directly: `PROBE needs | getBodyDamage ok=true value=-` --
-- `ok=true` only means the call did not throw; `value=-` is `tostring(nil)`. Grepping every
-- `getBodyDamage()` callsite across Bandits 42.20 turns up nothing on a bandit -- ZASmack.lua:358
-- is inside `Bite(attacker, victim)` and its only caller passes the PLAYER as victim
-- (ZASmack.lua:608); BanditUtils.lua:302, BanditPlayer.lua:137, PlayerDamageModel.lua and
-- BanditServerCommands.lua:277 are all the player too.
--
-- WHAT ACTUALLY EXISTS FOR AN NPC, AND NOTHING ELSE IS DRAWN
--   zombie:getHealth()            live overall health, one float
--   brain.health                  the SPAWN MAXIMUM (BanditServerSpawner.lua:332), not current
--   brain.infection                zombie virus percentage
--   brain.scenesWound              our own record: dressing, bleeding, bleedDay, bleedSweeps
--                                  (ScenesRelationsWounds.lua:150-156)
--   SR.Wounds.NeedsDressing(z,b)   whether they want a bandage right now
-- There is no per-part health for an NPC and this file does not fabricate one. Where that data
-- would go, it says so once, in one line, instead of seventeen rows of a number nobody can read.
--
-- LAYOUT -- follows the shape of the player's own Salud tab (caps/player-health-menu*.png)
--   Left:  a blocky humanoid silhouette (drawn with drawRect/drawRectBorder, no texture -- the
--          only body-shaped texture found this session belongs to the compiled NewHealthPanel
--          widget, built for an IsoPlayer and never confirmed to take an IsoZombie -- see the
--          note above drawSilhouette) plus a vertical white-to-black condition bar.
--   Right: overall condition, zombie virus, and the wound state we actually track. An active
--          bleed expands inline in red, the way the player's panel expands a wound in place.
--   Bottom: the bandage button.
--
-- HOW HEALING WORKS NOW -- REPLACES A FALSE CLAIM THIS HEADER USED TO MAKE
-- The old header said bandaging here "matches vanilla" and heals gradually the way the engine
-- heals a player's body part. That relied on the same getBodyDamage() pipeline just proven
-- unreachable, so it was never true for an NPC. What actually happens: clicking Bandage spends
-- one dressing from the PLAYER's inventory and restores a fraction of the NPC's own maximum
-- (brain.health) immediately -- see PANEL_RESTORE below for the fractions and why they are not
-- copy-pasted from ScenesRelationsWounds.lua's own tiers.
--
-- TODO: Spanish localization for the UI labels. Currently English only, matching every other
-- panel in this mod (ScenesRelationsPanel.lua, ScenesRelationsSidebar.lua).

require "ScenesRelations"
require "ScenesRelationsActions"
require "ScenesRelationsWounds"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"

local SR = ScenesRelations

SR.Health = SR.Health or {}

local WIDTH, HEIGHT = 460, 330
local PAD = 10

-- Left-column geometry: silhouette, then a gap, then the condition bar, then a gap before the
-- text column starts. Chosen to read as a small body diagram at this window size, nothing more
-- precise than that -- there is no reference sprite to match dimensions against.
local SIL_W, SIL_H = 70, 190
local BAR_W = 14
local COL_GAP = 14
local TEXT_GAP = 20

-- Colours used by the right-hand text. Trimmed to only what this file actually draws --
-- the old per-wound-kind palette (scratch/deepWound/bite/glass/burn/fracture/pain) described
-- data this file can no longer read, so it is gone rather than kept unused.
local C = {
    ok        = { r = 0.35, g = 0.85, b = 0.35 },
    hurt      = { r = 0.90, g = 0.65, b = 0.25 },
    critical  = { r = 0.90, g = 0.25, b = 0.25 },
    bleeding  = { r = 0.90, g = 0.25, b = 0.25 },
    bandaged  = { r = 0.35, g = 0.75, b = 0.40 },
    infection = { r = 0.65, g = 0.35, b = 0.80 },
    dim       = { r = 0.55, g = 0.55, b = 0.55 },
}

-- Bandage types this panel will look for in the PLAYER's inventory, best first. Matches the
-- list ScenesRelationsWounds.lua ranks by getBandagePower/isAlcoholic, kept as a fixed list here
-- because this panel only ever needs the single best item, not a full inventory ranking.
local BANDAGES = {
    "Base.AlcoholBandage", "Base.Bandage",
    "Base.AlcoholRippedSheets", "Base.RippedSheets",
}

--- What buying back health should give back, as a fraction of the NPC's own maximum
--- (brain.health). Re-declared here rather than imported, because ScenesRelationsWounds.lua's
--- RESTORE is file-local to that module and this file must not reach into another module's
--- private state.
---
--- THE VALUES NOW MATCH THAT TABLE EXACTLY (ScenesRelationsWounds.lua:118-124), and the first
--- version's did not. It shipped 0.85 / 0.65 against the AI's 0.95 / 0.80, with a comment
--- arguing the panel's floor was "already higher than the AI's own worst case" -- which is
--- backwards: 0.85 < 0.95. The consequence was absurd and would have been read as a bug in
--- the wrong place: bandaging a companion YOURSELF healed them LESS than walking away and
--- letting them do it with the same item. Two copies of one rule, divergent at birth, which
--- is exactly what R6 is about. If one of these tables changes, change both, and say so here.
---
--- The "clean" and lower tiers are deliberately ABSENT rather than carried over. Every item on
--- the BANDAGES list above classifies as sterile or bandage -- AlcoholBandage and
--- AlcoholRippedSheets are alcoholic, plain Bandage and RippedSheets both declare
--- BandagePower >= 2.0 (normal.txt:8028/8046/8061/10640) -- so a "clean" entry here could
--- never be reached. A constant with a careful comment that nothing can select is worse than
--- a missing feature, because the comment is the evidence a reviewer checks. `audit.py`'s
--- deadconst check cannot see this one: the lookup is dynamic (`PANEL_RESTORE[kind]`), so the
--- key reads as used. That is why it is written down instead.
local PANEL_RESTORE = {
    sterile = 1.00,
    bandage = 0.95,
}

--- Find the first usable bandage in the player's inventory.
--- getFirstTypeRecurse verified at client/ISUI/ISWorldObjectContextMenu.lua:557 and elsewhere
--- in that same file.
local function findBandage(player)
    local inv = player:getInventory()
    if not inv then return nil end
    for _, t in ipairs(BANDAGES) do
        local item = inv:getFirstTypeRecurse(t)
        if item then return item, t end
    end
    return nil
end

--- Which restore tier an item earns. Same two engine flags ScenesRelationsWounds.lua's own
--- bestDressing() ranks by (getBandagePower, isAlcoholic), verified at
--- client/XpSystem/ISUI/ISHealthPanel.lua:1154 (power > 0 means "is a bandage") and :1722
--- (power >= 2 is the line vanilla itself draws between a rag and a proper bandage);
--- isAlcoholic() is read the same way ISApplyBandage.lua:119 reads it for sterility.
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

--- Live condition of the NPC: brain.health is the spawn maximum, zombie:getHealth() is the
--- live value. Both verified in the capability table at the top of this file.
local function condition(zombie, brain)
    local max = tonumber(brain and brain.health) or 2
    if max <= 0 then max = 2 end
    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return max, max end
    return now, max
end

-- THE SILHOUETTE ------------------------------------------------------------------------

--- A blocky humanoid, drawn entirely with drawRect (ISUIElement.lua:1191) and drawRectBorder
--- (ISUIElement.lua:1219) -- no texture path. The one body-shaped texture this session found is
--- the compiled NewHealthPanel widget vanilla's own health tab instantiates
--- (client/XpSystem/ISUI/ISHealthPanel.lua:12-13: `NewHealthPanel.new(self.x, self.y,
--- self.character)`); it takes a character object and was never confirmed to accept an
--- IsoZombie, so it is not used here. Proportions below are fractions of the given box chosen
--- to read as a person at panel size -- there is no reference sprite to match against.
local function drawSilhouette(panel, x, y, w, h, r, g, b, a)
    local headW, headH = w * 0.34, h * 0.13
    local headX, headY = x + (w - headW) / 2, y

    local torsoW, torsoH = w * 0.56, h * 0.32
    local torsoX = x + (w - torsoW) / 2
    local torsoY = headY + headH + h * 0.02

    local armW, armH = w * 0.16, h * 0.30
    local armY = torsoY
    local armLX = torsoX - armW - w * 0.03
    local armRX = torsoX + torsoW + w * 0.03

    local legGap = w * 0.04
    local legW, legH = (torsoW - legGap) / 2, h * 0.32
    local legY = torsoY + torsoH + h * 0.02
    local legLX = torsoX
    local legRX = torsoX + legW + legGap

    -- Faint fill first so the shapes read as a body rather than a wireframe, then the outline.
    local shapes = {
        { headX, headY, headW, headH }, { torsoX, torsoY, torsoW, torsoH },
        { armLX, armY, armW, armH }, { armRX, armY, armW, armH },
        { legLX, legY, legW, legH }, { legRX, legY, legW, legH },
    }
    for _, s in ipairs(shapes) do
        panel:drawRect(s[1], s[2], s[3], s[4], a * 0.18, r, g, b)
    end
    for _, s in ipairs(shapes) do
        panel:drawRectBorder(s[1], s[2], s[3], s[4], a, r, g, b)
    end
end

-- Strips the vertical condition bar is built from. Fine enough that the steps do not read as
-- banding at BAR_W (14px) wide; there is no gradient texture verified for this panel (see the
-- note above drawSilhouette), so it is built from flat drawRect strips instead.
local BAR_STRIPS = 24

--- White at the top fading to black at the bottom, with a coloured marker at the current
--- condition ratio. drawRect verified at ISUIElement.lua:1191.
local function drawConditionBar(panel, x, y, w, h, ratio, mr, mg, mb)
    local stripH = h / BAR_STRIPS
    for i = 0, BAR_STRIPS - 1 do
        local shade = 1 - (i / (BAR_STRIPS - 1))
        panel:drawRect(x, y + i * stripH, w, stripH + 1, 1, shade, shade, shade)
    end
    panel:drawRectBorder(x, y, w, h, 0.6, 1, 1, 1)

    -- Full health (ratio 1) marks the white top; empty marks the black bottom.
    local markerY = y + (1 - ratio) * h
    panel:drawRect(x - 3, markerY - 1, w + 6, 3, 1, mr, mg, mb)
end

-- THE PANEL -----------------------------------------------------------------------------

ScenesRelationsHealthPanel = ISCollapsableWindow:derive("ScenesRelationsHealthPanel")

function ScenesRelationsHealthPanel:prerender()
    -- EXPLICIT, SELF-DRAWN BACKGROUND, AND THE CAUSE OF THE SEE-THROUGH PANEL.
    --
    -- The base class was never the problem, and neither was `background` or `isCollapsed`. It
    -- was the DEFAULT ALPHA: `ISPanel:new()` sets `backgroundColor = {r=0, g=0, b=0, a=0.5}`
    -- (pzserver/media/lua/client/ISUI/ISPanel.lua:105), and the version of this file that
    -- shipped never overrode it. Half alpha is exactly what `caps/npc-health-menu.png` shows --
    -- the game world legible straight through a panel that was working correctly and painting
    -- the colour it had been given.
    --
    -- Confirmed rather than reasoned: `git show HEAD:...ScenesRelationsHealth.lua | grep
    -- backgroundColor` returns nothing. There was no override, so the default stood.
    --
    -- Two things fix it and both are kept, because they fail independently. `new()` now sets an
    -- opaque colour (see there), and this paints it explicitly before the base class runs, so a
    -- future change to ISPanel's default or to when the base decides to paint cannot quietly
    -- make the panel transparent again.
    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a,
        self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)

    ISCollapsableWindow.prerender(self)

    local zombie = self.bandit
    if not zombie then return end

    local ok, brain = pcall(function() return BanditBrain.Get(zombie) end)
    if not ok or not brain then
        self:drawText("They are gone.", PAD, self:titleBarHeight() + PAD, 0.8, 0.5, 0.5, 1, UIFont.Small)
        return
    end

    local now, max = condition(zombie, brain)
    local ratio = max > 0 and (now / max) or 0

    -- Same three severity bands used for both the bar marker and the status word below, so the
    -- colour and the word can never disagree about how hurt somebody is.
    local band
    if ratio < 0.3 then band = "critical"
    elseif ratio < 0.6 then band = "hurt"
    else band = "ok" end
    local col = C[band]

    local top = self:titleBarHeight() + PAD

    -- === LEFT: silhouette + condition bar ===
    local silX, silY = PAD, top
    drawSilhouette(self, silX, silY, SIL_W, SIL_H, col.r, col.g, col.b, 0.9)

    local barX = silX + SIL_W + COL_GAP
    drawConditionBar(self, barX, silY, BAR_W, SIL_H, ratio, col.r, col.g, col.b)

    -- === RIGHT: what we can actually say about them ===
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

    local wound = brain.scenesWound
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

    -- === Shared footnote: what this panel deliberately does not show, and why ===
    local footY = math.max(silY + SIL_H, ry) + 12
    self:drawRect(PAD, footY, self.width - PAD * 2, 1, 0.4, 0.4, 0.4, 0.4)
    footY = footY + 8
    self:drawText("Per-part health is not exposed for NPCs by the engine.",
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

    -- The fallback is `bandage`, not a lower invented tier. `dressingKind` can only return
    -- something outside PANEL_RESTORE if getBandagePower or isAlcoholic throws, and every item
    -- on the BANDAGES list is a real dressing worth at least that much -- so guessing LOWER on
    -- a failed read would quietly punish the player for an engine hiccup.
    local restore = (PANEL_RESTORE[kind] or PANEL_RESTORE.bandage) * max
    -- Never a downgrade: somebody already above what this dressing would give stays where
    -- they are. Same shape as ScenesRelationsWounds.lua's own scenesBandageComplete
    -- (ScenesRelationsWounds.lua:394), re-derived rather than imported for the same reason
    -- PANEL_RESTORE is not imported.
    local healed = math.min(max, math.max(before, restore))

    local set = pcall(function() zombie:setHealth(healed) end)
    if not set then
        SR.Log("HEALTH could not bandage " .. tostring(brain.fullname) .. " -- setHealth threw")
        return
    end

    -- REMOVE IT FROM THE CONTAINER IT IS ACTUALLY IN, not from the main inventory.
    --
    -- This was a free-bandage bug and it was newly live: `findBandage` searches with
    -- `getFirstTypeRecurse`, which walks NESTED containers, but the removal was
    -- `player:getInventory():Remove(item)` -- the top level only. A bandage kept in a
    -- backpack, which is where everybody keeps them, healed the NPC, awarded the trust,
    -- played the sound, and STAYED IN THE BAG. Repeatable without limit, and silent.
    --
    -- It never fired before this rewrite only because the old onBandage returned early at
    -- `if not bd then return end`, and `getBodyDamage()` is nil for an NPC -- so every click
    -- died before reaching this line. Fixing the button exposed it.
    --
    -- Vanilla does not have this problem because it never removes across containers: the
    -- player's own health panel MOVES the item to the main inventory first
    -- (client/XpSystem/ISUI/ISHealthPanel.lua:1189 calls `toPlayerInventory`, whose test at
    -- :1125-1135 is exactly `item:getContainer() ~= doctor:getInventory()`), and only then
    -- does ISApplyBandage do its own top-level Remove (shared/TimedActions/ISApplyBandage.lua:120).
    -- We have no timed action to hang a transfer on, so we remove where it lives. That is the
    -- same branch vanilla takes after any *Recurse search --
    -- server/BuildingObjects/ISBuildUtil.lua:146-153:
    --     if item:getContainer() then item:getContainer():Remove(item)
    --     else playerInv:Remove(item) end
    -- A branch that would be pointless unless the top-level Remove failed for nested items.
    --
    -- playSound("FirstAidApplyBandage") verified at shared/TimedActions/ISApplyBandage.lua:70.
    local holder = item:getContainer() or player:getInventory()
    holder:Remove(item)
    player:playSound("FirstAidApplyBandage")

    -- The only place THIS side clears a bleed -- mirrors the rule ScenesRelationsWounds.lua
    -- states for its own scenesBandageComplete (ScenesRelationsWounds.lua:360-364): a
    -- completed dressing, and only a completed dressing, stops it.
    if wound.bleeding then
        wound.bleeding, wound.bleedDay, wound.bleedSweeps = nil, nil, nil
    end
    wound.dressing = kind
    wound.day = SR.Today()

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
    -- Explicit and near-opaque, rather than trusting the inherited default -- see the note at
    -- the top of prerender() for why this file no longer trusts that alone.
    o.background = true
    o.backgroundColor = { r = 0.04, g = 0.04, b = 0.05, a = 0.95 }
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
    SR.Log("HEALTH ready -- overall condition, zombie virus and our own wound record; "
        .. "no per-part display, the engine exposes none for an NPC")
end)
