-- ScenesPZ -- the relationship panel. Who you know, and where you stand with them.
--
-- WHY THIS EXISTS
-- The trust number used to live in the wheel and in a right-click label, which meant the
-- only way to see a relationship was to walk up to the person and open something. That is
-- backwards: the wheel is for choosing an action in the moment, and a number you have to
-- decode mid-swing is not information, it is noise.
--
-- Asked for directly, with a good reference: the Sims relationship bars. One row per
-- person, a bar you read at a glance, no arithmetic.
--
-- WHY IT CAN LIST PEOPLE WHO ARE NOT THERE
-- It reads the durable store, not the world. Every survivor you have ever met is in it,
-- including the ones eight blocks away with their cell unloaded -- which is the entire
-- point of having moved the record off the entity. That also makes this panel the first
-- honest view of whether that move worked: if somebody vanishes from the list when you
-- walk away, the store is not doing its job.

require "ScenesRelations"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"

local SR = ScenesRelations

local WIDTH, HEIGHT = 340, 420
local ROW_HEIGHT = 42
local PAD = 10

-- Same five bands as SR.TIERS, in the same order, so the colour and the word can never
-- disagree. Red through green, with neutral deliberately colourless -- an unformed
-- relationship should not look like an opinion.
local TIER_COLOR = {
    ally     = { 0.30, 0.85, 0.35 },
    friendly = { 0.55, 0.80, 0.40 },
    neutral  = { 0.65, 0.65, 0.65 },
    wary     = { 0.90, 0.65, 0.25 },
    hostile  = { 0.85, 0.25, 0.25 },
}

ScenesRelationsPanel = ISCollapsableWindow:derive("ScenesRelationsPanel")

--- Everyone in the store, best relationship first.
---
--- Sorted by trust rather than by name because the question this panel answers is "who is
--- with me", not "find this person". The people at the top are the ones who would fight
--- for you; the people at the bottom are the ones to avoid.
local function collectRecords()
    local rows = {}
    if not SR.Store or not SR.Store.clusters then return rows end

    -- Which of them are actually in the world right now. Cheap -- the cache exists -- and
    -- it is the difference between "you know twelve people" and "two of them are here".
    local present = {}
    if BanditZombie and BanditZombie.GetAllB then
        local ok, bandits = pcall(BanditZombie.GetAllB)
        if ok and type(bandits) == "table" then
            for id, _ in pairs(bandits) do present[id] = true end
        end
    end

    for i = 0, (SR.Store.CLUSTER_COUNT or 32) - 1 do
        local cluster = SR.Store.clusters[i]
        if cluster then
            for id, record in pairs(cluster) do
                -- Only this character's relationships. The store is global ModData keyed by
                -- NPC id, so before this it happily listed people a PREVIOUS character had
                -- known -- reported as "si el jugador muere y vuelvo a aparecer, quedan las
                -- relaciones anteriores".
                if type(record) == "table" and type(record.trust) == "number"
                   and SR.RecordIsOurs(record) then
                    rows[#rows + 1] = {
                        id = id,
                        -- Records written before names were stored fall back to the id.
                        -- Ugly, honest, and it disappears the next time they are met.
                        name = record.name or ("#" .. tostring(id)),
                        trust = record.trust,
                        met = record.met,
                        dead = record.dead,
                        -- Being in the cache is not the same as being alive: a dead NPC's
                        -- entity lingers, so death wins the label.
                        here = present[id] == true and not record.dead,
                    }
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.trust ~= b.trust then return a.trust > b.trust end
        return tostring(a.name) < tostring(b.name)
    end)

    return rows
end

function ScenesRelationsPanel:createChildren()
    ISCollapsableWindow.createChildren(self)

    self.list = ISScrollingListBox:new(0, self:titleBarHeight(),
        self.width, self.height - self:titleBarHeight())
    self.list:initialise()
    self.list:instantiate()
    self.list:setAnchorRight(true)
    self.list:setAnchorBottom(true)
    self.list.itemheight = ROW_HEIGHT
    self.list.drawBorder = false
    self.list.doDrawItem = ScenesRelationsPanel.drawRow
    self:addChild(self.list)
end

--- One survivor, one bar.
---
--- The bar runs the full -100..100 so the centre line is zero and the eye reads which side
--- of "nobody trusts you on sight" the relationship has landed on. A bar that only grew
--- rightwards from empty would make being distrusted look the same as being unknown, and
--- those are very different situations.
function ScenesRelationsPanel:drawRow(y, item, alt)
    local row = item.item
    local tier = SR.TierOf(row.trust)
    local color = TIER_COLOR[tier] or TIER_COLOR.neutral

    if alt then
        self:drawRect(0, y, self:getWidth(), ROW_HEIGHT - 1, 0.08, 1, 1, 1)
    end

    -- Name, and where they stand: dead, present, or somewhere out there.
    --
    -- A dead survivor keeps their row and their bar -- the relationship happened and does
    -- not un-happen -- but the whole row dims and the label says so. Reported as "cuando el
    -- NPC muere, la relacion queda y no pasa nada con la barra, deberia aparecer muerto":
    -- from the menu a dead ally and a living one were identical, which is worst exactly
    -- when you are deciding who to go back for.
    local shade = row.dead and 0.45 or 1
    self:drawText(tostring(row.name), PAD, y + 4, shade, shade, shade, 1, UIFont.Small)

    if row.dead then
        self:drawText("dead", self:getWidth() - PAD - 30, y + 4,
            0.85, 0.30, 0.30, 1, UIFont.Small)
    elseif row.here then
        self:drawText("here", self:getWidth() - PAD - 30, y + 4,
            0.5, 0.9, 0.5, 1, UIFont.Small)
    end

    local barX = PAD
    local barY = y + 22
    local barW = self:getWidth() - PAD * 2
    local barH = 10

    -- Track.
    self:drawRect(barX, barY, barW, barH, 0.35, 0.1, 0.1, 0.1)

    -- Fill, measured from the centre outwards.
    local half = barW / 2
    local ratio = math.max(-1, math.min(1, row.trust / 100))
    local fillW = math.abs(ratio) * half
    local fillX = ratio >= 0 and (barX + half) or (barX + half - fillW)
    local alpha = row.dead and 0.4 or 0.95
    self:drawRect(fillX, barY, fillW, barH, alpha, color[1], color[2], color[3])

    -- Zero line, drawn last so the fill never hides it.
    self:drawRect(barX + half, barY - 1, 1, barH + 2, 0.8, 1, 1, 1)

    self:drawText(tier .. "  " .. tostring(row.trust),
        barX, barY + barH + 1, color[1], color[2], color[3], 1, UIFont.Small)

    return y + ROW_HEIGHT
end

function ScenesRelationsPanel:refresh()
    self.list:clear()
    local rows = collectRecords()
    for _, row in ipairs(rows) do
        self.list:addItem(row.name, row)
    end
    self:setTitle("Relationships  (" .. #rows .. ")")
end

function ScenesRelationsPanel:new()
    local x = getCore():getScreenWidth() / 2 - WIDTH / 2
    local y = getCore():getScreenHeight() / 2 - HEIGHT / 2
    local o = ISCollapsableWindow.new(self, x, y, WIDTH, HEIGHT)
    o:setResizable(true)
    o.title = "Relationships"
    return o
end

local panel = nil

SR.Panel = SR.Panel or {}

--- Public: opened from the left-hand button column, beside health and the rest.
function SR.Panel.Toggle()
    if panel then
        panel:removeFromUIManager()
        panel = nil
        return
    end

    panel = ScenesRelationsPanel:new()
    panel:initialise()
    panel:addToUIManager()
    -- Rebuilt on open rather than kept live. Trust moves on events, not per frame, and a
    -- panel that rescanned 32 shards every tick to show a number that changes twice an
    -- hour would be the most expensive thing in this mod.
    panel:refresh()

    SR.Log("PANEL opened")
end

function SR.Panel.IsOpen()
    return panel ~= nil
end

Events.OnGameStart.Add(function()
    SR.Log("PANEL ready -- open it from the left-hand button column")
end)
