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

local SR = ScenesRelations

-- Vanilla's own icon strings, taken from files rather than invented. The stop sign reads
-- as "do not hit these people" and the speech icon as "who I know", which is as close to
-- self-explanatory as a 24-pixel square gets.
local ICON_GUARD = "media/ui/emotes/stop.png"
local ICON_PANEL = "media/ui/Traits/trait_talkative.png"

local SPACING = 5

local function iconOr(path)
    local ok, texture = pcall(getTexture, path)
    if ok and texture then return texture end
    return nil
end

--- Called by both buttons; ISButton hands us the button itself.
local function onClick(self, button)
    if button.internal == "SCENES_GUARD" then
        SR.Guard.Toggle()
    elseif button.internal == "SCENES_PANEL" then
        SR.Panel.Toggle()
    end
end

local function addButton(owner, y, internal, texture, tooltip)
    local size = owner.healthBtn and owner.healthBtn:getWidth() or 24

    local btn = ISButton:new(0, y, size, size, "", owner, onClick)
    btn:setImage(texture)
    btn.internal = internal
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)
    btn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
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

    self.scenesGuardBtn = addButton(self, y, "SCENES_GUARD",
        iconOr(ICON_GUARD), "Protect survivors from your own attacks")
    y = self.scenesGuardBtn:getBottom() + SPACING

    self.scenesPanelBtn = addButton(self, y, "SCENES_PANEL",
        iconOr(ICON_PANEL), "Relationships")

    self:shrinkWrap()
end

local originalPrerender = ISEquippedItem.prerender

--- Green while the guard is on, dull red while it is off, so the state is readable without
--- clicking anything. Same trick vanilla uses on its own safety toggle
--- (ISEquippedItem.lua:906-914, setTextureColor on safetyBtn).
function ISEquippedItem:prerender()
    originalPrerender(self)

    if self.scenesGuardBtn then
        local on = SR.Guard and SR.Guard.enabled
        pcall(function()
            self.scenesGuardBtn:setTextureColor(
                on and { r = 0.4, g = 0.9, b = 0.4, a = 1 }
                   or { r = 0.9, g = 0.3, b = 0.3, a = 1 })
        end)
    end
end

Events.OnGameStart.Add(function()
    SR.Log("SIDEBAR ready -- two buttons under the heart: protection, and relationships")
end)
