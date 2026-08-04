-- ScenesPZ -- the two controls that are not the wheel: friendly-fire protection, and the
-- relationship panel.
--
-- WHY THIS IS NOT IN VANILLA'S LEFT COLUMN ANY MORE
-- It was, and it overlapped the construction icons. That is not a positioning bug worth
-- chasing: `ISEquippedItem` builds its column with a running y offset and calls
-- shrinkWrap at the end, so anything appended afterwards competes for space with buttons
-- that appear and disappear depending on what the player is holding, whether debug is on,
-- and whether the game is multiplayer. Winning that argument once does not mean winning
-- it in the next patch.
--
-- So this is our own small panel. It cannot collide with anything, and the player can drag
-- it wherever they like.
--
-- WHY NOT KEYBINDINGS
-- Vanilla claims every letter of the alphabet except K (shared/keyBinding.lua), and K is
-- spent on the memory test. Two controls you touch a few times a session do not deserve
-- to fight the controls you use to stay alive.
--
-- NO TEXTURES, DELIBERATELY
-- An earlier version used the icon paths that appear in vanilla's own Lua, on the
-- reasonable assumption that a string in a shipped file resolves to a shipped image. It
-- does not: getTexture returned nil, the buttons drew as nothing, and setTextureColor on
-- a texture-less ISButton threw 511 times in one session -- once per frame. Everything
-- here is text and Lua table assignment, which cannot fail that way.

require "ScenesRelations"
require "ScenesRelationsPanel"
require "ScenesRelationsGuard"
require "ISUI/ISPanel"
require "ISUI/ISButton"

local SR = ScenesRelations

local BTN_W, BTN_H = 54, 22
local PAD = 4

SRSidebar = ISPanel:derive("SRSidebar")

local function onGuard() SR.Guard.Toggle() end
local function onPanel() SR.Panel.Toggle() end

function SRSidebar:createChildren()
    self.guardBtn = ISButton:new(PAD, PAD, BTN_W, BTN_H, "SAFE", self, onGuard)
    self.guardBtn:initialise()
    self.guardBtn:instantiate()
    self.guardBtn:setDisplayBackground(true)
    self.guardBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
    self.guardBtn:setTooltip("Survivors are protected from your own attacks. Click to allow hitting them.")
    self:addChild(self.guardBtn)

    self.panelBtn = ISButton:new(PAD * 2 + BTN_W, PAD, BTN_W, BTN_H, "WHO", self, onPanel)
    self.panelBtn:initialise()
    self.panelBtn:instantiate()
    self.panelBtn:setDisplayBackground(true)
    self.panelBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
    self.panelBtn:setTooltip("Relationships - who you know and how they feel about you")
    self:addChild(self.panelBtn)
end

--- SAFE in green while the guard is on, HIT in red while it is off, so the state reads
--- without clicking anything.
---
--- Only setTitle and Lua table assignment. This runs on every frame of the game: anything
--- in here that can fail, fails thousands of times, which is exactly how the previous
--- version buried a session's log.
function SRSidebar:prerender()
    ISPanel.prerender(self)

    local on = SR.Guard and SR.Guard.enabled
    self.guardBtn:setTitle(on and "SAFE" or "HIT")
    self.guardBtn.backgroundColor = on
        and { r = 0.13, g = 0.30, b = 0.16, a = 0.9 }
        or  { r = 0.34, g = 0.12, b = 0.12, a = 0.9 }
end

function SRSidebar:new()
    -- Left edge, below where vanilla's column ends on any reasonable resolution, and
    -- draggable from there. Deliberately not anchored to another panel -- the whole reason
    -- this file was rewritten is that sharing space with vanilla is a losing game.
    -- Bottom-left, side by side. At 55% of the screen height the previous version landed
    -- in the middle of vanilla's icon column -- see caps/side-bar.png. That column grows
    -- downward from the top and how far it reaches depends on what the player is holding,
    -- so any fraction of the height is a guess. The bottom edge is not: nothing vanilla
    -- puts an icon there, and two buttons in a row need half the height of two stacked.
    local x = 6
    local y = getCore():getScreenHeight() - (BTN_H + PAD * 2) - 8
    local o = ISPanel.new(self, x, y, BTN_W * 2 + PAD * 3, BTN_H + PAD * 2)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.moveWithMouse = true
    return o
end

local sidebar = nil

Events.OnGameStart.Add(function()
    if sidebar then return end
    sidebar = SRSidebar:new()
    sidebar:initialise()
    sidebar:addToUIManager()
    SR.Log("SIDEBAR ready -- SAFE and WHO, own panel on the left. Drag it anywhere.")
end)
