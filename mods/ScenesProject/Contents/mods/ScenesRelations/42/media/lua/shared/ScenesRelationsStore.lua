-- ScenesPZ Relations -- the durable store.
--
-- WHY THIS EXISTS
-- The trust record used to live on the NPC entity, in `bandit:getModData().scenesRel`.
-- That is fine while the NPC is loaded and worthless the moment it is not: the entity is
-- destroyed when its cell unloads, and every memory of the player goes with it. The scene
-- that breaks is the whole premise of the mod -- you fight beside someone for half an
-- hour, walk eight blocks away, come back, and they have never met you.
--
-- HOW BANDITS SOLVES IT, AND WHY WE COPY THE SHAPE
-- `BanditGMD.lua:47-54` creates 32 global ModData tables, `BanditC0`..`BanditC31`, and
-- stores each NPC brain in the one at `id % 32`. `BanditUpdate.lua:1983-1991` is the proof
-- that it works: on every zombie update, a zombie NOT flagged Bandit whose id IS present
-- in the cluster gets re-banditized from the stored brain, and one that is flagged but
-- absent gets turned back into an ordinary zombie. That single branch is how an NPC
-- survives a cell reload at all -- which means the entire framework already depends on
-- `BanditUtils.GetZombieID` returning the same number for the same NPC across the cycle.
-- We key off exactly that id, so if it ever stops being stable, Bandits breaks first and
-- far more loudly than we do.
--
-- WHY 32 TABLES AND NOT ONE
-- ModData is serialised as a unit. One table holding every survivor you have ever met is
-- rewritten in full on every save; 32 shards keep each write small. The number is Bandits'
-- and there is no reason to differ.
--
-- We copy the pattern, never their tables. Our prefix is `ScenesRelC0`..`ScenesRelC31`.

ScenesRelations = ScenesRelations or {}
local SR = ScenesRelations

SR.Store = SR.Store or {}
local Store = SR.Store

Store.CLUSTER_COUNT = 32
Store.clusters = {}
Store.ready = false

local function clusterName(c)
    return "ScenesRelC" .. tostring(c)
end

local function clusterOf(id)
    return math.floor(math.abs(id) % Store.CLUSTER_COUNT)
end

--- Whole-store size. Only for probes and logs -- it walks every shard.
function Store.Count()
    local total = 0
    for i = 0, Store.CLUSTER_COUNT - 1 do
        local cluster = Store.clusters[i]
        if cluster then
            for _ in pairs(cluster) do total = total + 1 end
        end
    end
    return total
end

function Store.Get(id)
    if not id then return nil end
    local cluster = Store.clusters[clusterOf(id)]
    if not cluster then return nil end
    return cluster[id]
end

--- Writes the record and, in multiplayer only, pushes the shard.
---
--- `ModData.transmit` is a network call. In singleplayer there is nobody to tell, and
--- trust moves once per melee swing, so the guard is not a micro-optimisation -- it is the
--- difference between a quiet save and a packet per hit. Both `isClient` and `isServer`
--- are false in singleplayer, which is what makes this the right test.
local warnedNotReady = false

function Store.Put(id, record)
    if not id then return end
    local c = clusterOf(id)
    local cluster = Store.clusters[c]
    if not cluster then
        -- A write before OnInitGlobalModData would otherwise vanish without a sound, and
        -- the symptom -- trust that resets every time you look away -- is indistinguishable
        -- from a dozen other bugs. Say it once, loudly, rather than never.
        if not warnedNotReady then
            warnedNotReady = true
            SR.Log("STORE WARNING: write before global ModData was ready; that record is lost")
        end
        return
    end
    cluster[id] = record
    if isClient() or isServer() then
        ModData.transmit(clusterName(c))
    end
end

--- Records are keyed by the NPC, so an NPC that is gone for good leaves one behind.
--- Nothing calls this yet: forgetting the dead is a design decision (see
--- docs/DESIGN-MEMORY.md -- a grudge outliving its target is arguably correct), not a
--- cleanup chore. The entry point exists so that decision has somewhere to land.
function Store.Remove(id)
    if not id then return end
    local c = clusterOf(id)
    local cluster = Store.clusters[c]
    if not cluster then return end
    cluster[id] = nil
    if isClient() or isServer() then
        ModData.transmit(clusterName(c))
    end
end

-- ModData tables must be claimed inside OnInitGlobalModData; asking for one earlier
-- returns something the engine will not save. On a multiplayer client the local table is
-- empty until the server answers `request`, which arrives on OnReceiveGlobalModData below.
local function initModData()
    for i = 0, Store.CLUSTER_COUNT - 1 do
        local name = clusterName(i)
        Store.clusters[i] = ModData.getOrCreate(name)
        if isClient() then
            ModData.request(name)
        end
    end
    Store.ready = true
    SR.Log("STORE ready | " .. Store.CLUSTER_COUNT .. " shards | "
        .. Store.Count() .. " records recovered from this save")
end

local function receiveModData(key, data)
    if not isClient() then return end
    if not key or not data then return end
    for i = 0, Store.CLUSTER_COUNT - 1 do
        if key == clusterName(i) then
            Store.clusters[i] = data
            return
        end
    end
end

Events.OnInitGlobalModData.Add(initModData)
Events.OnReceiveGlobalModData.Add(receiveModData)
