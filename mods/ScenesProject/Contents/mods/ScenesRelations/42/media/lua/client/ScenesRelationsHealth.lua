-- ScenesPZ -- somebody else's health, and doing something about it.
--
-- ASKED FOR IN THESE WORDS
--   "debe aparecer una opcion que diga salud, este debe de abrir el cuadro de salud
--    parecido al de jugador, pero con los stats del NPC, de manera que yo pueda vendarlo y
--    ayudarle. El echo de vendarlo hace que suba la confianza con mayor puntos."
--
-- WHY THIS IS NOT A COPY OF THE VANILLA HEALTH PANEL
-- The vanilla panel is a body diagram driven by BodyDamage: per-part scratches, bites,
-- bleeding, bandage life. A Bandits NPC does not run on that model. Its damage is a single
-- float on the entity -- getHealth, drained by the bleed-out loop at BanditUpdate.lua:500
-- and reset to 1.2 by their own Bandage action (ZABandage.lua:50) -- with brain.infection
-- tracked separately on the brain. getBodyDamage answers on an IsoZombie, but nothing in
-- the framework ever writes to it, so a body diagram would be a picture of zeroes.
--
-- Drawing the panel vanilla uses would therefore be a lie that looks like a feature. This
-- shows the model that is actually running: condition, infection, and whether they can
-- still fight. Fewer numbers, all of them true.
--
-- WHY THERE ARE NO NEEDS ON IT
-- Because the probe came back. Ten sweeps of CharacterStat -- PANIC, STRESS, THIRST,
-- HUNGER, ENDURANCE, PAIN, the lot -- never moved off their defaults for an NPC
-- (`PROBE stat VERDICT FROZEN`, 04-08 log). The engine does not tick them for a zombie.
-- A hunger bar here would be a bar that never moves.
--
-- WHY BANDAGING IS WORTH MORE THAN TALKING
-- Trust in this mod is meant to track what you RISK for somebody, not what you say to
-- them. Talking is 4 and rate-limited. Standing still next to a wounded person, spending a
-- bandage you might need yourself, is the largest single move available -- and unlike a
-- conversation it cannot be farmed, because it is only offered while they are actually
-- hurt.

require "ScenesRelations"
require "ScenesRelationsActions"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"

local SR = ScenesRelations

SR.Health = SR.Health or {}

local WIDTH, HEIGHT = 300, 250
local PAD = 12
local BAR_H = 18
local ROW = 46

-- What counts as a bandage, best first. All four verified in
-- pzserver/media/scripts/generated/items/normal.txt -- the alcohol variants first because
-- spending the better item on somebody else is the more generous act, and the player would
-- otherwise have no way to control which one goes.
local BANDAGES = {
    "Base.AlcoholBandage",
    "Base.Bandage",
    "Base.AlcoholRippedSheets",
    "Base.RippedSheets",
}

-- How much condition one bandage buys. Their own Bandage action snaps to a flat 1.2
-- regardless of the maximum, which for a tough survivor is a downgrade; this adds instead,
-- and never past what that person spawned able to take.
local BANDAGE_HEAL = 0.8

-- Where the visual bandage goes. Bandits rolls one of seventeen parts at random; a
-- player-applied one is deliberate, and the torso is the part that reads at a glance from
-- the outside. BodyPartType is vanilla and appears throughout ZABandage.lua.
local BANDAGE_PART = BodyPartType.Torso_Upper

--- Live condition, and what this person can hold at most.
---
--- brain.health is the SPAWN maximum -- BanditServerSpawner.lua:332 writes it once as a
--- Lerp into 1..2.6 and nothing touches it again. Reading it as current health is the
--- mistake the fear model made for a whole session; it is written down here so the next
--- reader does not have to rediscover it.
local function condition(zombie, brain)
    local max = tonumber(brain and brain.health) or 2
    if max <= 0 then max = 2 end
    local ok, now = pcall(function() return zombie:getHealth() end)
    if not ok or type(now) ~= "number" then return max, max end
    return now, max
end

--- The first usable bandage in the player's bags, or nil.
--- getFirstTypeRecurse searches containers inside containers, which is what "in my bag"
--- means to a player (ISInventoryBuildMenu.lua:106).
local function findBandage(player)
    local inventory = player:getInventory()
    if not inventory then return nil end
    for _, itemType in ipairs(BANDAGES) do
        local item = inventory:getFirstTypeRecurse(itemType)
        if item then return item, itemType end
    end
    return nil
end

-- THE WINDOW ---------------------------------------------------------------------------

ScenesRelationsHealthPanel = ISCollapsableWindow:derive("ScenesRelationsHealthPanel")

--- A labelled bar. No textures anywhere in this file on purpose: getTexture returned nil
--- for paths that appear in vanilla Lua and setTextureColor then threw 511 times in one
--- session (see the sidebar's history). drawRect always works.
function ScenesRelationsHealthPanel:bar(y, label, value, text, r, g, b)
    local w = self.width - PAD * 2
    self:drawText(label, PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
    self:drawTextRight(text, self.width - PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Small)

    local top = y + 18
    self:drawRect(PAD, top, w, BAR_H, 0.7, 0.08, 0.08, 0.10)
    local fill = math.max(0, math.min(1, value))
    if fill > 0 then
        self:drawRect(PAD, top, w * fill, BAR_H, 0.95, r, g, b)
    end
    self:drawRectBorder(PAD, top, w, BAR_H, 0.35, 1, 1, 1)
end

function ScenesRelationsHealthPanel:prerender()
    ISCollapsableWindow.prerender(self)

    local zombie = self.bandit
    if not zombie then return end

    local ok, brain = pcall(function() return BanditBrain.Get(zombie) end)
    if not ok or not brain then
        self:drawText("They are gone.", PAD, 40, 0.8, 0.5, 0.5, 1, UIFont.Small)
        return
    end

    local now, max = condition(zombie, brain)
    local ratio = now / max

    local y = 34

    -- CONDITION. Colour carries the reading so the number is confirmation, not homework:
    -- green holding, amber hurt, red about to be a corpse.
    local r, g, b = 0.30, 0.80, 0.35
    if ratio < 0.3 then r, g, b = 0.85, 0.25, 0.25
    elseif ratio < 0.6 then r, g, b = 0.90, 0.65, 0.25 end
    self:bar(y, "Condition", ratio, string.format("%.2f / %.2f", now, max), r, g, b)
    y = y + ROW

    -- INFECTION. Bandits' own model, counted to 100 and then a Zombify task
    -- (BanditUpdate.lua:509). Shown even at zero, because "not infected" is the single most
    -- useful thing to know about somebody you are deciding whether to travel with.
    local infection = tonumber(brain.infection) or 0
    self:bar(y, "Infection", infection / 100, string.format("%d%%", infection),
        0.75, 0.35, 0.75)
    y = y + ROW

    -- CAN THEY STILL FIGHT. Not a stat, a fact, and it decides whether walking them into
    -- trouble is a plan or a funeral.
    local outOfAmmo = true
    pcall(function() outOfAmmo = Bandit.IsOutOfAmmo(zombie) end)
    self:drawText("Weapon", PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
    if outOfAmmo then
        self:drawTextRight("out of ammo", self.width - PAD, y, 0.90, 0.65, 0.25, 1, UIFont.Small)
    else
        self:drawTextRight("loaded", self.width - PAD, y, 0.30, 0.80, 0.35, 1, UIFont.Small)
    end
    y = y + 24

    -- Why there is no hunger bar. Stated in the UI rather than only in a comment, because
    -- the absence is a finding and somebody will otherwise file it as missing.
    self:drawText("Needs are not simulated for NPCs yet.", PAD, y,
        0.5, 0.5, 0.5, 1, UIFont.Small)

    -- The button's label and availability are recomputed here rather than once at open:
    -- the player may spend their last bandage while this window is up.
    if self.bandageButton then
        local player = getSpecificPlayer(0)
        local item = player and findBandage(player)
        if ratio >= 0.999 then
            self.bandageButton:setEnable(false)
            self.bandageButton:setTitle("Not hurt")
        elseif not item then
            self.bandageButton:setEnable(false)
            self.bandageButton:setTitle("No bandage")
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
    if not item then
        SR.Log("HEALTH bandage refused -- nothing to bandage with")
        return
    end

    local now, max = condition(zombie, brain)
    if now >= max then
        SR.Log("HEALTH bandage refused -- not hurt")
        return
    end

    -- The engine change first. If setHealth or the visual throws, the player still has
    -- their bandage and the only cost is a log line -- the opposite order would spend the
    -- item on nothing, which is the failure the player would actually feel.
    local healed = math.min(max, now + BANDAGE_HEAL)
    local ok, err = pcall(function()
        zombie:setHealth(healed)
        zombie:addVisualBandage(BANDAGE_PART, true)
    end)
    if not ok then
        SR.Log("HEALTH bandage failed: " .. tostring(err))
        return
    end

    player:getInventory():Remove(item)
    player:playSound("FirstAidApplyBandage")

    local before, after = SR.Actions.RewardBandage(player, zombie)

    SR.Log(string.format("HEALTH %s bandaged with %s | condition %.2f -> %.2f / %.2f | %s -> %s",
        tostring(brain.fullname), tostring(itemType), now, healed, max,
        tostring(before), tostring(after)))
end

function ScenesRelationsHealthPanel:createChildren()
    ISCollapsableWindow.createChildren(self)

    local h = 24
    local w = self.width - PAD * 2
    self.bandageButton = ISButton:new(PAD, self.height - h - PAD, w, h,
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

--- Public: opened from the wheel's Health card.
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

    SR.Log(string.format("HEALTH opened on %s | condition %.2f / %.2f | infection %s",
        name, now, max, tostring(brain and brain.infection or 0)))
end

function SR.Health.Close()
    if panel then
        panel:removeFromUIManager()
        panel = nil
    end
end

Events.OnGameStart.Add(function()
    SR.Log("HEALTH ready -- Health on the wheel; bandaging costs an item and moves trust")
end)
