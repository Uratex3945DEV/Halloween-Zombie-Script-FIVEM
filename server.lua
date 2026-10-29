local activePlayers = {}
local previousBuckets = {}
local lastKillReward = {}
local sessionTickets = {} -- tickets gagnés pendant la session en cours
local ZOMBIE_BUCKET = (Config.Zone and Config.Zone.routingBucket) or 238

-- Instance du joueur : solo (propre à chaque joueur) ou partagée selon la config.
local function getZombieBucket(src)
    if Config.Zone.soloInstance then
        return (Config.Zone.soloBucketBase or 23800) + src
    end
    return ZOMBIE_BUCKET
end

local function getESX()
    for _, resource in ipairs({ 'SpinFramework', 'es_extended' }) do
        local ok, obj = pcall(function() return exports[resource]:getSharedObject() end)
        if ok and type(obj) == 'table' and obj.GetPlayerFromId then return obj end
    end
    return nil
end

local function addItem(src, item, amount)
    local spin = rawget(_G, 'Spin')
    if type(spin) == 'table' and type(spin.Items) == 'table' and type(spin.Items.Add) == 'function' then
        local ok, result = pcall(spin.Items.Add, src, item, amount)
        if ok and result ~= false then return true end
    end
    if GetResourceState('ox_inventory') == 'started' then
        local ok, result = pcall(function() return exports.ox_inventory:AddItem(src, item, amount) end)
        if ok and result ~= false then return true end
    end
    local ESX = getESX()
    local xPlayer = ESX and ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    local ok = pcall(function() xPlayer.addInventoryItem(item, amount) end)
    return ok
end

local function removeItem(src, item, amount)
    if not amount or amount <= 0 then return true end
    local spin = rawget(_G, 'Spin')
    if type(spin) == 'table' and type(spin.Items) == 'table' and type(spin.Items.Remove) == 'function' then
        local ok, result = pcall(spin.Items.Remove, src, item, amount)
        if ok and result ~= false then return true end
    end
    if GetResourceState('ox_inventory') == 'started' then
        local ok, result = pcall(function()
            local have = exports.ox_inventory:GetItemCount(src, item) or 0
            if have <= 0 then return true end
            return exports.ox_inventory:RemoveItem(src, item, math.min(amount, have))
        end)
        if ok and result ~= false then return true end
    end
    local ESX = getESX()
    local xPlayer = ESX and ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    local ok = pcall(function()
        local inv = xPlayer.getInventoryItem(item)
        local have = inv and inv.count or 0
        if have > 0 then xPlayer.removeInventoryItem(item, math.min(amount, have)) end
    end)
    return ok
end

local function addWeapon(src, weapon)
    local spin = rawget(_G, 'Spin')
    if type(spin) == 'table' and type(spin.Items) == 'table' and type(spin.Items.AddWeapon) == 'function' then
        local ok, result = pcall(spin.Items.AddWeapon, src, weapon, 60)
        if ok and result == true then return true end
    end
    if GetResourceState('ox_inventory') == 'started' then
        local ok, result = pcall(function() return exports.ox_inventory:AddItem(src, weapon, 1) end)
        if ok and result ~= false then return true end
    end
    local ESX = getESX()
    local xPlayer = ESX and ESX.GetPlayerFromId(src)
    if not xPlayer or not xPlayer.addWeapon then return false end
    local ok = pcall(function() xPlayer.addWeapon(weapon:upper(), 60) end)
    return ok
end

local function notify(src, message)
    TriggerClientEvent('esx:showNotification', src, message)
end

RegisterNetEvent('adam_zombie:requestJoin', function()
    local src = source
    if activePlayers[src] then
        TriggerClientEvent('adam_zombie:denied', src, 'Tu es déjà dans la zone zombie.')
        return
    end
    previousBuckets[src] = GetPlayerRoutingBucket(src)
    local bucket = getZombieBucket(src)
    SetPlayerRoutingBucket(src, bucket)
    -- Pas de PNJ/véhicules ambiants dans l'instance zombie
    SetRoutingBucketPopulationEnabled(bucket, false)
    activePlayers[src] = true
    sessionTickets[src] = 0
    TriggerClientEvent('adam_zombie:joined', src)
end)

-- Les zombies sont créés localement par le client ; le serveur valide ici la session
-- et limite les récompenses pour éviter le spam d'événements.
RegisterNetEvent('adam_zombie:zombieKilled', function()
    local src = source
    if not activePlayers[src] or GetPlayerRoutingBucket(src) ~= getZombieBucket(src) then return end
    local now = GetGameTimer()
    if lastKillReward[src] and now - lastKillReward[src] < 700 then return end
    lastKillReward[src] = now
    local playerPed = GetPlayerPed(src)
    if not playerPed or playerPed == 0 then return end
    local coords = GetEntityCoords(playerPed)
    if #(coords - Config.Zone.center) > Config.Zone.radius + 30.0 then return end

    local amount = math.random(Config.TicketMin, Config.TicketMax)
    if not addItem(src, Config.TicketItem, amount) then
        notify(src, ('Impossible de donner %s. Vérifie le nom de l’item et ton inventaire.'):format(Config.TicketItem))
        return
    end
    sessionTickets[src] = (sessionTickets[src] or 0) + amount

    local rare = false
    if math.random(1, 100) <= Config.RareWeaponChance then
        rare = addWeapon(src, Config.RareWeapon)
    end
    TriggerClientEvent('adam_zombie:reward', src, amount, rare)
end)

-- Mort dans la zone : le client revive le joueur, le serveur retire tous les tickets gagnés.
RegisterNetEvent('adam_zombie:playerDied', function()
    local src = source
    if not activePlayers[src] or GetPlayerRoutingBucket(src) ~= getZombieBucket(src) then return end
    local lost = sessionTickets[src] or 0
    sessionTickets[src] = 0
    if lost > 0 then
        removeItem(src, Config.TicketItem, lost)
        notify(src, ('~r~Tu es mort ! Tes %d ticket(s) gagnés ont été retirés.'):format(lost))
    else
        notify(src, '~r~Tu es mort ! Tu as été réanimé.')
    end
end)

RegisterNetEvent('adam_zombie:leave', function()
    local src = source
    activePlayers[src] = nil
    lastKillReward[src] = nil
    sessionTickets[src] = nil
    if previousBuckets[src] ~= nil then
        SetPlayerRoutingBucket(src, previousBuckets[src])
        previousBuckets[src] = nil
    else
        SetPlayerRoutingBucket(src, 0)
    end
end)

-- Sécurité supplémentaire : bloque les dégâts joueur contre joueur si l'un des deux est dans l'instance zombie.
AddEventHandler('weaponDamageEvent', function(sender, data)
    if not data or not data.hitGlobalId then return end
    local target = NetworkGetEntityFromNetworkId(data.hitGlobalId)
    if not target or target == 0 or not DoesEntityExist(target) or GetEntityType(target) ~= 1 or not IsPedAPlayer(target) then return end
    local targetPlayer = NetworkGetEntityOwner(target)
    if targetPlayer and targetPlayer > 0 then
        if activePlayers[sender] or activePlayers[targetPlayer] then
            CancelEvent()
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    activePlayers[src] = nil
    lastKillReward[src] = nil
    sessionTickets[src] = nil
    previousBuckets[src] = nil
end)

CreateThread(function()
    Wait(2000)
    print('^2[adam_zombie_halloween] Ressource chargée. Auteur : Adam.^0')
    print(('^3[adam_zombie_halloween] Récompenses : %d-%d %s | chance arme : %d%%^0'):format(
        Config.TicketMin, Config.TicketMax, Config.TicketItem, Config.RareWeaponChance
    ))
end)
