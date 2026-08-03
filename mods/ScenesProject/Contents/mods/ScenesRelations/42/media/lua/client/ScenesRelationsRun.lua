-- ScenesPZ Relations -- periodic upkeep.

require "ScenesRelations"
local SR = ScenesRelations

-- Records live on the NPC entities themselves, so there is no global table to walk.
-- We iterate only BANDITS, never plain zombies: touching a zombie would create a trust
-- record on it, and the store would grow without bound. GetAllB is documented in
-- BanditZombie.lua:183 as "returns all cached bandits", but it yields light cache
-- entries -- the real IsoZombie has to be fetched by id before getModData() works.
--
-- EveryOneMinute is a confirmed vanilla event. Decay runs here rather than per tick:
-- trust is a slow signal, and per-tick work across every NPC is precisely what makes
-- Bandits burn CPU (BanditUtils.AreEnemies measured at 460,361 calls per minute).
Events.EveryOneMinute.Add(function()
    if not BanditZombie or not BanditZombie.GetAllB then return end
    local ok, bandits = pcall(BanditZombie.GetAllB)
    if not ok or type(bandits) ~= "table" then return end

    local n = 0
    for id, _ in pairs(bandits) do
        local zombie = BanditZombie.GetInstanceById(id)
        if zombie then
            SR.Decay(zombie, 1)
            n = n + 1
        end
    end
    if SR.DEBUG then SR.Log("decayed " .. n .. " loaded bandits") end
end)

Events.OnGameStart.Add(function()
    SR.Log("ScenesPZ Relations active")
end)
