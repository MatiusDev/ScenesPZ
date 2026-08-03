-- The Last of Us -- one survivor at your side from the first minute.
--
-- WHY THIS EXISTS
-- Everything the relationship layer does needs a person in front of you, and waiting for
-- the spawn scheduler to roll one costs real minutes per test run. This places exactly one
-- companion beside the player on a NEW game, so a session starts with something to measure
-- instead of a walk.
--
-- WHY IT IS SERVER CODE
-- It creates a character in the world. World mutation belongs on the server side even in
-- singleplayer, where the host and the client are the same process -- that is the whole
-- reason `lua/server/` exists. Bandits' own spawner is server code for the same reason.
--
-- WHAT IT DELIBERATELY DOES NOT DO
-- It does not touch trust. The companion starts at zero like everyone else, and that is
-- the point: `loyal` is Bandits' mechanical flag -- it follows you and treats your enemies
-- as its own -- while trust is our number and has to be earned. Somebody who walks beside
-- you before deciding what they think of you is a better opening state than a friend, and
-- it makes the trust system testable from the first swing. It also keeps this mod free of
-- any dependency on ScenesRelations.

local CLAN_SURVIVORS = "a742fcf6-29eb-5107-8396-d6c760d54dc0"   -- TLOU_Survivors, clans.txt

-- OnNewGame fires before the cell is necessarily ready to take a spawn, so the request is
-- queued and retried on tick. The cap matters: without it a spawn that can never succeed
-- leaves a handler running on every frame for the rest of the session.
local MAX_ATTEMPTS = 200

local pending = false
local attempts = 0

local function log(msg)
    print("TLOU| " .. tostring(msg))
end

local function trySpawn()
    if not pending then return end

    attempts = attempts + 1
    if attempts > MAX_ATTEMPTS then
        pending = false
        Events.OnTick.Remove(trySpawn)
        log("companion spawn gave up after " .. MAX_ATTEMPTS .. " ticks")
        return
    end

    local player = getSpecificPlayer(0)
    if not player or not player:getCell() then return end

    -- Bandits loads its spawner as server code too. If it is missing, the mod order is
    -- wrong and saying so once beats a nil-index stack trace on every tick.
    if not BanditServer or not BanditServer.Spawner or not BanditServer.Spawner.Clan then
        pending = false
        Events.OnTick.Remove(trySpawn)
        log("BanditServer.Spawner unavailable -- is Bandits loaded before this mod?")
        return
    end

    pending = false
    Events.OnTick.Remove(trySpawn)

    -- Spawner.Clan, not Spawner.Individual. The latter reads an undefined global
    -- `spawnPoints` at BanditServerSpawner line 1145 and throws; Clan is the working one,
    -- and it is the path that lets us name the program and the loyalty outright instead of
    -- letting the clan flags decide.
    BanditServer.Spawner.Clan(player, {
        cid = CLAN_SURVIVORS,
        size = 1,
        program = "Companion",
        loyal = true,
        x = player:getX(),
        y = player:getY(),
        z = player:getZ(),
    })

    log(string.format("companion requested at %.0f,%.0f,%.0f after %d ticks",
        player:getX(), player:getY(), player:getZ(), attempts))
end

Events.OnNewGame.Add(function()
    -- Multiplayer is out of scope here: on a dedicated server there is no single player to
    -- start beside, and the client has no business spawning anyone.
    if isClient() then return end

    pending = true
    attempts = 0
    Events.OnTick.Add(trySpawn)
    log("new game -- one companion queued")
end)
