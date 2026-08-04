-- ScenesPZ -- two buttons in the left-hand column, beside health and the rest.
--
-- WHY NOT KEYBINDINGS
-- The first version bound K, G and M. Vanilla already claims every letter of the alphabet
-- except K (shared/keyBinding.lua), so two of those three were fighting the game outright,
-- and the third was spending a scarce key on something you touch twice a session.
--
-- The correct home was named directly: the column that already holds the heart, the
-- crafting icon and the move-objects cursor. Social state and the friendly-fire toggle
-- belong there because that is where a player already looks for "things about me".
-- The interaction wheel keeps its key -- that one is used constantly and is worth it.
--
-- EXTEND, NEVER REPLACE
-- ISEquippedItem.createChildren is wrapped, not overwritten: the original runs first and
-- untouched, then two buttons are appended below whatever it built, then shrinkWrap()
-- recomputes the panel bounds the same way vanilla does at the end of its own method.
-- Any other mod that wraps the same function keeps working, in either order.

require "ScenesRelations"
require "ScenesRelationsPanel"
require "ScenesRelationsGuard"
require "ISUI/ISEquippedItem"
require "ISUI/ISButton"

local SR = ScenesRelations

-- NO TEXTURES. The first version used the icon paths that appear in vanilla's own Lua --
-- media/ui/emotes/stop.png and friends -- on the reasonable assumption that a string
-- present in a shipped file resolves to a shipped image. It does not: getTexture returned
-- nil, the buttons drew as nothing, and setTextureColor on a texture-less ISButton threw
-- 511 times in a single session (ISButton.lua:184), once per frame, filling a 3 MB log.
--
-- So these are text buttons with a background. Short labels, real tooltips, and the guard
-- state shown by the label itself rather than by tinting an image that may not exist.
-- Everything below is plain Lua table assignment and cannot throw.
local SPACING = 5

--- Called by both buttons; ISButton hands us the button itself.
local function onClick(self, button)
    if button.internal == "SCENES_GUARD" then
        SR.Guard.Toggle()
    elseif button.internal == "SCENES_PANEL" then
        SR.Panel.Toggle()
    end
end

local function addButton(owner, y, internal, title, tooltip)
    local size = owner.healthBtn and owner.healthBtn:getWidth() or 24

    local btn = ISButton:new(0, y, size, size, title, owner, onClick)
    btn.internal = internal
    btn:initialise()
    btn:instantiate()
    -- Background ON, unlike vanilla's icon buttons: without an image there would be
    -- nothing to see or click.
    btn:setDisplayBackground(true)
    btn.backgroundColor = { r = 0.15, g = 0.15, b = 0.17, a = 0.8 }
    btn.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
    btn:ignoreWidthChange()
    btn:ignoreHeightChange()
    owner:addChild(btn)

    if owner.addMouseOverToolTipItem then
        pcall(function() owner:addMouseOverToolTipItem(btn, tooltip) end)
    end

    return btn
end

local originalCreateChildren = ISEquippedItem.createChildren

function ISEquippedItem:createChildren()
    originalCreateChildren(self)

    -- Where vanilla left off. It calls shrinkWrap() at the end of its own createChildren,
    -- so the height here is the bottom of the last real button rather than a guess.
    local y = self:getHeight() + SPACING

    self.scenesGuardBtn = addButton(self, y, "SCENES_GUARD", "SAFE",
        "Survivors are protected from your own attacks. Click to allow hitting them.")
    y = self.scenesGuardBtn:getBottom() + SPACING

    self.scenesPanelBtn = addButton(self, y, "SCENES_PANEL", "WHO",
        "Relationships - who you know and how they feel about you")

    self:shrinkWrap()
end

local originalPrerender = ISEquippedItem.prerender

--- SAFE in green while the guard is on, HIT in red while it is off, so the state is
--- readable without clicking anything.
---
--- This writes Lua tables and calls setTitle -- no setTextureColor, which is what threw
--- once per frame in the previous build. A prerender hook runs on every frame of the
--- game: anything in here that can fail, fails thousands of times.
function ISEquippedItem:prerender()
    originalPrerender(self)

    local btn = self.scenesGuardBtn
    if not btn then return end

    local on = SR.Guard and SR.Guard.enabled
    btn:setTitle(on and "SAFE" or "HIT")
    btn.backgroundColor = on
        and { r = 0.13, g = 0.28, b = 0.15, a = 0.85 }
        or  { r = 0.32, g = 0.12, b = 0.12, a = 0.85 }
end

Events.OnGameStart.Add(function()
    SR.Log("SIDEBAR ready -- two buttons under the heart: protection, and relationships")
end)
