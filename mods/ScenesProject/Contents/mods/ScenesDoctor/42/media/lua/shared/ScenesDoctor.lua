-- ScenesPZ Doctor -- diagnostic instrumentation. Changes no gameplay.
--
-- Everything it prints is prefixed with SDOC| so it can be pulled out of
-- console.txt with a single grep, and parsed by tools/logdoctor.py.

ScenesDoctor = ScenesDoctor or {}
local SD = ScenesDoctor

SD.PREFIX = "SDOC|"
SD.counts = {}        -- label -> number of calls since boot
SD.wrapped = {}       -- label -> true, so we never double-wrap
SD.lastMem = nil

function SD.log(kind, msg)
    print(SD.PREFIX .. kind .. "|" .. tostring(getTimestampMs()) .. "|" .. msg)
end

--- Count every call to fn without changing what it does.
-- Errors are re-raised after being counted, so behavior is identical.
function SD.wrap(tbl, key, label)
    if type(tbl) ~= "table" then return false end
    local fn = tbl[key]
    if type(fn) ~= "function" then return false end
    if SD.wrapped[label] then return false end

    SD.wrapped[label] = true
    SD.counts[label] = 0

    tbl[key] = function(...)
        SD.counts[label] = SD.counts[label] + 1
        local ok, err = pcall(fn, ...)
        if not ok then
            local errLabel = label .. "!ERR"
            SD.counts[errLabel] = (SD.counts[errLabel] or 0) + 1
            -- Log only the first few, then let the counter carry the volume.
            -- A runaway error must not become a runaway logger.
            if SD.counts[errLabel] <= 3 then
                SD.log("ERR", label .. " | " .. tostring(err))
            end
            error(err, 0)
        end
        return err
    end
    SD.log("WRAP", label)
    return true
end

--- Wrap every function on a table. Returns how many it instrumented.
function SD.wrapTable(tbl, name)
    if type(tbl) ~= "table" then
        SD.log("MISS", name .. " (not a table / not loaded)")
        return 0
    end
    local n = 0
    for key, value in pairs(tbl) do
        if type(value) == "function" and SD.wrap(tbl, key, name .. "." .. key) then
            n = n + 1
        end
    end
    SD.log("SCAN", name .. " -> " .. n .. " functions instrumented")
    return n
end

--- Lua heap sample. NOTE: collectgarbage counts Lua memory only -- a leak on the
--- Java side will not show up here, it shows up as repeated log lines instead.
function SD.sampleMemory()
    local kb = collectgarbage("count")
    local delta = SD.lastMem and (kb - SD.lastMem) or 0
    SD.lastMem = kb
    SD.log("MEM", string.format("%.0f|%+.0f", kb, delta))
end

--- Dump call counters, busiest first, then reset the window.
function SD.report()
    local rows = {}
    for label, count in pairs(SD.counts) do
        if count > 0 then table.insert(rows, { label = label, count = count }) end
    end
    table.sort(rows, function(a, b) return a.count > b.count end)

    for i = 1, math.min(#rows, 15) do
        SD.log("CALL", rows[i].count .. "|" .. rows[i].label)
    end
    for label, _ in pairs(SD.counts) do SD.counts[label] = 0 end
end
