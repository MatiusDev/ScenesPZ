-- ScenesPZ Doctor -- sampling loop and instrumentation targets.

require "ScenesDoctor"
local SD = ScenesDoctor

-- Instrument by prefix rather than a fixed list, so Bandits, Week One and our own
-- modules are all covered and new files need no edit here.
--   Bandit* -> Bandits NPC        BWO* -> Bandits Week One       Scenes* -> ours
local PREFIXES = { "Bandit", "BWO", "Scenes" }

local function boot()
    SD.log("BOOT", "ScenesPZ Doctor active")

    -- Snapshot the key list first: wrapping mutates the tables we are iterating.
    local names = {}
    for name, value in pairs(_G) do
        if type(value) == "table" and name ~= "ScenesDoctor" then
            for _, prefix in ipairs(PREFIXES) do
                if string.sub(name, 1, #prefix) == prefix then
                    table.insert(names, name)
                    break
                end
            end
        end
    end
    table.sort(names)

    local total = 0
    for _, name in ipairs(names) do
        total = total + SD.wrapTable(_G[name], name)
    end
    SD.log("BOOT", #names .. " modules, " .. total .. " functions instrumented")
    SD.sampleMemory()
end

-- OnGameStart fires after every mod's shared/ files have loaded, so the target
-- globals exist by now. Wrapping any earlier silently instruments nothing.
Events.OnGameStart.Add(boot)

Events.EveryOneMinute.Add(function()
    SD.sampleMemory()
    SD.report()
end)
