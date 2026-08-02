-- ScenesPZ Doctor -- sampling loop and instrumentation targets.

require "ScenesDoctor"
local SD = ScenesDoctor

-- Global tables to instrument if present. Absent ones are reported as MISS,
-- which is itself useful: it tells us the mod did not load.
local TARGETS = { "Bandit", "BanditUtils", "BanditPrograms", "BanditPlayer", "BanditScheduler" }

local function boot()
    SD.log("BOOT", "ScenesPZ Doctor active")
    for _, name in ipairs(TARGETS) do
        SD.wrapTable(_G[name], name)
    end
    SD.sampleMemory()
end

-- OnGameStart fires after every mod's shared/ files have loaded, so the Bandit
-- globals exist by now. Wrapping any earlier silently instruments nothing.
Events.OnGameStart.Add(boot)

Events.EveryOneMinute.Add(function()
    SD.sampleMemory()
    SD.report()
end)
