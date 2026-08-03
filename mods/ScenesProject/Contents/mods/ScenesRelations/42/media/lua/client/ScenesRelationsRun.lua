-- ScenesPZ Relations -- periodic upkeep.

require "ScenesRelations"
local SR = ScenesRelations

-- EveryOneMinute is a confirmed vanilla event (used in pzserver/media/lua). Decay runs
-- here rather than per tick: trust is a slow signal and per-tick work on every NPC is
-- what makes Bandits burn CPU (BanditUtils.AreEnemies measured at 460k calls/minute).
Events.EveryOneMinute.Add(function()
    local data = ModData.getOrCreate("ScenesRelations")
    if not data.actors then return end
    local n = 0
    for _ in pairs(data.actors) do n = n + 1 end
    if SR.DEBUG then SR.Log("tracking " .. n .. " actors") end
end)

Events.OnGameStart.Add(function()
    SR.Log("ScenesPZ Relations active")
end)
