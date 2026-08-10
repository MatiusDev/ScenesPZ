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

--- One companion per CHARACTER, not per save.
---
--- ASKED FOR: "si reaparezco por que mori tambien deberia de aparecer un NPC conmigo al
--- spawnear." Right, and OnNewGame could never do it -- it fires once, for the save. Dying
--- and coming back left you alone in a mod whose whole premise is that you are not.
---
--- OnCreatePlayer fires for a new game AND for a respawn, which is exactly the set wanted.
--- It also fires every time an existing character loads, which is exactly the case we must
--- NOT act on -- so the flag lives in `player:getModData()`, which belongs to the IsoPlayer
--- and is therefore fresh for a new character and preserved across reloads of an old one.
--- The same property the relationship store uses to scope itself to a life.
Events.OnCreatePlayer.Add(function(_, player)
    -- Multiplayer is out of scope here: on a dedicated server there is no single player to
    -- start beside, and the client has no business spawning anyone.
    if isClient() then return end
    if not player then return end

    local modData = player:getModData()
    if not modData then return end

    if modData.tlouCompanionGiven then
        log("this character already has their companion -- not spawning another")
        return
    end
    modData.tlouCompanionGiven = true

    -- A TEST KIT, AND IT IS ONLY THAT.
    --
    -- ASKED FOR: "dame tambien un arma de fuego" -- hearing whether an NPC switches to melee
    -- indoors, and watching two survivors decide differently with a gun in the picture, cannot
    -- be tested without one. Every id is verified in pzserver/media/scripts/generated/ --
    -- Pistol at weapon.txt:10996, Bullets9mmBox at normal.txt:13669, 9mmClip at normal.txt:13772.
    --
    -- DELETE THIS BLOCK once those tests pass. Starting equipment is a scenario decision and
    -- belongs in the Scenes mod, not in a spawner, and a permanent free pistol would quietly
    -- change what every later balance observation means.
    --
    -- THE SIX BAGS ARE GONE, ON REQUEST: "la prueba de los bolsos, ya la podemos quitar, para no
    -- spawnear con todos esos bolsos, deja que el jugador solo spawnee con la pistola, los
    -- cargadores y las balas."
    --
    -- They measured what they were for and the answer was not the one the experiment assumed.
    -- The spread of capacities was supposed to make the `carrying X / Y` line diverge per NPC
    -- via `SR.Loot.CarryBudget`. It cannot: a worn bag on an NPC is `brain.bag = { name = ... }`
    -- -- a field plus a sprite, with the real item REMOVED from the inventory
    -- (ScenesRelationsLoot.lua:927-937). There is no second container behind it, so every bag in
    -- that list produced exactly the same ceiling and the six of them were measuring one number
    -- six times. Handing them out from now on would only keep six bags out of the loot economy.
    --
    -- THE PISTOL NEEDS A MAGAZINE, and that is why it was once unusable: "la pistola que me das
    -- al inicio, no tiene cargador, entonces nunca he podido usarla con los NPC." Base.Pistol
    -- declares `MagazineType = Base.9mmClip` and `ClipSize = 15` (weapon.txt), so a box of loose
    -- rounds was never enough -- the rounds go in the clip and the clip goes in the gun. Two
    -- clips so a reload can actually be observed rather than inferred.
    local testKit = {
        "Base.Pistol", "Base.9mmClip", "Base.9mmClip", "Base.Bullets9mmBox",
    }

    local given = 0
    for _, itemType in ipairs(testKit) do
        local ok, err = pcall(function() player:getInventory():AddItem(itemType) end)
        if ok then
            given = given + 1
        else
            log("could not give " .. itemType .. ": " .. tostring(err))
        end
    end
    log(string.format("test kit given -- %d of %d items, pistol with two clips and a box, "
        .. "no bags (TEMPORARY, see comment)", given, #testKit))

    pending = true
    attempts = 0
    Events.OnTick.Add(trySpawn)
    log("new character -- one companion queued")
end)
