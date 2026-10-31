local activePlayers = {}
local previousBuckets = {}
local lastKillReward = {}
local sessionTickets = {} -- tickets gagnés pendant la session en cours
local ZOMBIE_BUCKET = (Config.Zone and Config.Zone.routingBucket) or 238

-- Instance du joueur : solo (propre à chaque joueur) ou partagée selon la config.
local playerBuckets = {} -- instance choisie à l'entrée (solo ou crew)
local CrewApi = {}       -- rempli plus bas (système de crews)

-- Instances actives : [bucket] = { host, members = {[src]=true}, hostWave, total, best }
-- L'hôte (1er arrivé) fait tourner les vagues ; les autres membres voient les mêmes PNJ.
local instances = {}

local function cleanupBucketPeds(bucket)
    for _, ped in ipairs(GetAllPeds()) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and GetEntityRoutingBucket(ped) == bucket then
            DeleteEntity(ped)
        end
    end
end

-- Retire un joueur de son instance ; passe la main à un autre membre si c'était l'hôte
local function leaveInstance(src, bucket)
    local inst = bucket and instances[bucket]
    if not inst then return end
    inst.members[src] = nil
    local nextHost
    for m in pairs(inst.members) do nextHost = m break end
    if not nextHost then
        instances[bucket] = nil
        SetTimeout(500, function() cleanupBucketPeds(bucket) end)
        return
    end
    if inst.host == src then
        inst.host = nextHost
        TriggerClientEvent('adam_zombie:becomeHost', nextHost, inst.hostWave or 0, inst.total or 0)
    end
end

local function defaultBucket(src)
    if Config.Zone.soloInstance then
        return (Config.Zone.soloBucketBase or 23800) + src
    end
    return ZOMBIE_BUCKET
end

local function getZombieBucket(src)
    return playerBuckets[src] or defaultBucket(src)
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

-- Leaderboard (ressource adam_zombi_leaderboard) : ignoré si elle n'est pas démarrée
local function lbAdd(src, stat, amount)
    local L = Config.Leaderboard
    if not (L and L.enabled) then return end
    if GetResourceState(L.resource) ~= 'started' then return end
    pcall(function() exports[L.resource]:AddStat(src, stat, amount or 1) end)
end

local sessionWave = {}

local function notify(src, message)
    TriggerClientEvent('esx:showNotification', src, message)
end

-- Fait entrer un joueur dans l'instance (bucket) : crée la partie (il devient hôte) ou rejoint celle en cours.
-- Les PNJ sont toujours en réseau afin qu'un fondateur puisse rejoindre n'importe quelle partie.
local function enterInstance(src, bucket)
    playerBuckets[src] = bucket
    previousBuckets[src] = GetPlayerRoutingBucket(src)
    SetPlayerRoutingBucket(src, bucket)
    -- Pas de PNJ/véhicules ambiants dans l'instance zombie
    SetRoutingBucketPopulationEnabled(bucket, false)
    activePlayers[src] = true
    sessionTickets[src] = 0

    local inst = instances[bucket]
    local asHost = false
    if not inst then
        inst = { host = src, members = {}, hostWave = 0, total = 0, best = 0 }
        instances[bucket] = inst
        asHost = true
    end
    inst.members[src] = true
    sessionWave[src] = asHost and 0 or (inst.best or 0)
    local shared = true
    TriggerClientEvent('adam_zombie:joined', src, asHost, shared, inst.hostWave, inst.total)
end

RegisterNetEvent('adam_zombie:requestJoin', function(mode)
    local src = source
    if activePlayers[src] then
        TriggerClientEvent('adam_zombie:denied', src, 'Tu es déjà dans la zone zombie.')
        return
    end
    -- mode 'crew' : même instance que les membres du crew ; sinon instance solo
    local bucket
    if mode == 'crew' then
        local c = CrewApi.getApprovedCrew and CrewApi.getApprovedCrew(src)
        if not c then
            TriggerClientEvent('adam_zombie:denied', src, 'Tu n’as pas de crew validé.')
            return
        end
        bucket = (Config.Zone.crewBucketBase or 24800) + c.id
        playerBuckets[src] = bucket
        if CrewApi.notifyCrew then
            CrewApi.notifyCrew(c, ('~o~%s a rejoint la zone zombie avec le crew.'):format(GetPlayerName(src) or src))
        end
    else
        bucket = defaultBucket(src)
        playerBuckets[src] = bucket
    end
    enterInstance(src, bucket)
end)

-- Gagnants de l'arme rare (un seul gain par joueur)
local RARE_T = 'adam_zombie_rare_winners'
local rareWinners = {}

local function rareIdentity(src)
    local identifier = GetPlayerIdentifierByType(src, 'license')
    local sp = rawget(_G, 'Spin')
    if type(sp) == 'table' and type(sp.Player) == 'table' then
        pcall(function()
            local i = sp.Player.GetIdentifier(src)
            if type(i) == 'string' and i ~= '' then identifier = i end
        end)
    end
    return identifier
end

CreateThread(function()
    for _ = 1, 10 do
        local ok = pcall(function()
            MySQL.query.await(([[
                CREATE TABLE IF NOT EXISTS `%s` (
                    `identifier` VARCHAR(80) NOT NULL,
                    PRIMARY KEY (`identifier`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            ]]):format(RARE_T))
            for _, r in ipairs(MySQL.query.await(('SELECT `identifier` FROM `%s`'):format(RARE_T)) or {}) do
                rareWinners[r.identifier] = true
            end
        end)
        if ok then return end
        Wait(5000)
    end
    print('^1[adam_zombie] Impossible de charger les gagnants de l’arme rare.^0')
end)

-- Les zombies sont créés localement par le client ; le serveur valide ici la session
-- et limite les récompenses pour éviter le spam d'événements.
RegisterNetEvent('adam_zombie:zombieKilled', function(wasTerrifier, killerId)
    local src = source
    if not activePlayers[src] or GetPlayerRoutingBucket(src) ~= getZombieBucket(src) then return end
    -- Le client qui gère les zombies (l'hôte) signale le kill ; la récompense va au joueur qui a tué
    -- (s'il est dans la même instance), sinon à l'hôte.
    local receiver = src
    killerId = tonumber(killerId)
    local inst = instances[getZombieBucket(src)]
    if killerId and killerId ~= src and inst and inst.host == src and inst.members[killerId] and activePlayers[killerId] then
        receiver = killerId
    end
    local now = GetGameTimer()
    if lastKillReward[receiver] and now - lastKillReward[receiver] < 700 then return end
    lastKillReward[receiver] = now
    local playerPed = GetPlayerPed(receiver)
    if not playerPed or playerPed == 0 then return end
    local coords = GetEntityCoords(playerPed)
    if #(coords - Config.Zone.center) > Config.Zone.radius + 30.0 then return end

    local amount = math.random(Config.TicketMin, Config.TicketMax)
    if not addItem(receiver, Config.TicketItem, amount) then
        notify(receiver, ('Impossible de donner %s. Vérifie le nom de l’item et ton inventaire.'):format(Config.TicketItem))
        return
    end
    sessionTickets[receiver] = (sessionTickets[receiver] or 0) + amount
    if wasTerrifier == true and Config.Terrifier and Config.Terrifier.enabled then
        lbAdd(receiver, 'terrifier', 1)
    else
        lbAdd(receiver, 'zombies', 1)
    end
    lbAdd(receiver, 'tickets', amount)

    -- Arme rare : une seule fois par joueur (mémorisé en base, même s'il la perd ou la revend)
    local rare = false
    local rareIdent = rareIdentity(receiver)
    if rareIdent and not rareWinners[rareIdent] and math.random(1, 100) <= Config.RareWeaponChance then
        rare = addWeapon(receiver, Config.RareWeapon)
        if rare then
            rareWinners[rareIdent] = true
            pcall(function()
                MySQL.insert(('INSERT IGNORE INTO `%s` (`identifier`) VALUES (?)'):format(RARE_T), { rareIdent })
            end)
        end
    end
    TriggerClientEvent('adam_zombie:reward', receiver, amount, rare)
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
    leaveInstance(src, playerBuckets[src])
    activePlayers[src] = nil
    playerBuckets[src] = nil
    lastKillReward[src] = nil
    sessionTickets[src] = nil
    if previousBuckets[src] ~= nil then
        SetPlayerRoutingBucket(src, previousBuckets[src])
        previousBuckets[src] = nil
    else
        SetPlayerRoutingBucket(src, 0)
    end
end)

local function toU32(h) return (tonumber(h) or 0) & 0xFFFFFFFF end
local function isZombieWeapon(hash)
    hash = toU32(hash)
    if hash == toU32(joaat('WEAPON_UNARMED')) then return true end
    local tw = Config.Terrifier and Config.Terrifier.weapon
    return tw ~= nil and hash == toU32(joaat(tw))
end

-- Sécurité supplémentaire : bloque les dégâts joueur contre joueur si l'un des deux est dans l'instance zombie.
AddEventHandler('weaponDamageEvent', function(sender, data)
    if not data or not data.hitGlobalId then return end
    local target = NetworkGetEntityFromNetworkId(data.hitGlobalId)
    if not target or target == 0 or not DoesEntityExist(target) or GetEntityType(target) ~= 1 or not IsPedAPlayer(target) then return end
    local targetPlayer = NetworkGetEntityOwner(target)
    if targetPlayer and targetPlayer > 0 then
        if activePlayers[sender] or activePlayers[targetPlayer] then
            -- Les zombies en réseau appartiennent à un joueur de l'instance : leurs coups (mains nues /
            -- arme du Terrifier) sur un membre du crew doivent passer. Tout le reste = joueur contre joueur.
            if activePlayers[sender] and activePlayers[targetPlayer]
                and getZombieBucket(sender) == getZombieBucket(targetPlayer)
                and isZombieWeapon(data.weaponType) then
                return
            end
            CancelEvent()
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    leaveInstance(src, playerBuckets[src])
    activePlayers[src] = nil
    playerBuckets[src] = nil
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


-- =====================================================================
--  /configzombie : configuration en jeu (réservée au rôle fondateur)
-- =====================================================================
local fieldByPath = {}
for _, f in ipairs(Config.Editable) do fieldByPath[f.path] = f end

local function lowerStr(v)
    if v == nil then return nil end
    return tostring(v):lower()
end

local function collectRoles(src)
    local out = {}
    local function add(label, v)
        if type(v) == 'string' or type(v) == 'number' then out[#out + 1] = { label, tostring(v) } end
    end
    local spin = rawget(_G, 'Spin')
    local spinOk = false
    if type(spin) == 'table' and type(spin.Player) == 'table' then
        spinOk = true
        pcall(function() add('Spin.group', spin.Player.GetGroup(src)) end)
        pcall(function()
            local j = spin.Player.GetJob(src)
            if type(j) == 'table' then
                for _, key in ipairs({ 'name', 'label', 'grade_name', 'grade_label' }) do add('Spin.job.' .. key, j[key]) end
            end
        end)
        pcall(function() add('Spin.uniqueId', spin.Player.GetUniqueId(src)) end)
    end
    local ESX = getESX()
    local xPlayer = ESX and ESX.GetPlayerFromId(src)
    if not xPlayer then return out, spinOk end
    local function try(label, fn)
        local ok, v = pcall(fn)
        if ok then add(label, v) end
    end
    for _, key in ipairs({ 'group', 'rank', 'role', 'grade', 'permission_level', 'perm' }) do
        try(key, function() return xPlayer[key] end)
    end
    for _, fn in ipairs({ 'getGroup', 'getRank', 'getRole', 'getGrade', 'getPermissionLevel' }) do
        try(fn .. '()', function() return xPlayer[fn] and xPlayer[fn]() end)
    end
    local okJ, job = pcall(function() return xPlayer.getJob and xPlayer.getJob() or xPlayer.job end)
    if okJ and type(job) == 'table' then
        for _, key in ipairs({ 'name', 'label', 'grade_name', 'grade_label', 'grade' }) do add('job.' .. key, job[key]) end
    end
    return out, true
end

local function isFounder(src)
    if src == 0 then return true end -- console
    local wanted = {}
    for _, r in ipairs(Config.Admin.roles or {}) do wanted[lowerStr(r)] = true end
    for _, entry in ipairs((collectRoles(src))) do
        if entry[1] ~= 'Spin.uniqueId' and wanted[lowerStr(entry[2])] then return true end
    end
    return false
end

local function currentValues()
    local out = {}
    for _, f in ipairs(Config.Editable) do out[f.path] = ZConfigGet(f.path) end
    return out
end

local function persistSettings()
    local ok = pcall(function()
        SaveResourceFile(GetCurrentResourceName(), Config.Admin.saveFile or 'settings.json',
            json.encode(currentValues(), { indent = true }), -1)
    end)
    if not ok then print('^1[adam_zombie] Impossible de sauvegarder les réglages.^0') end
end

-- Nettoie/valide une valeur selon le champ. Retourne nil si invalide.
local function sanitize(f, v)
    if f.type == 'boolean' then
        if type(v) == 'boolean' then return v end
        return nil
    elseif f.type == 'number' then
        v = tonumber(v)
        if not v or v ~= v then return nil end
        if f.min and v < f.min then v = f.min end
        if f.max and v > f.max then v = f.max end
        return v
    elseif f.type == 'string' then
        if type(v) ~= 'string' then return nil end
        v = v:gsub('^%s+', ''):gsub('%s+$', '')
        if #v == 0 or #v > 64 or not v:match('^[%w_%-]+$') then return nil end
        return v
    end
    return nil
end

local function applyValues(values)
    local applied = 0
    for path, raw in pairs(values) do
        local f = fieldByPath[path]
        if f then
            local v = sanitize(f, raw)
            if v ~= nil then
                ZConfigSet(path, v)
                applied = applied + 1
            end
        end
    end
    -- Cohérence entre champs liés
    if Config.TicketMin > Config.TicketMax then Config.TicketMax = Config.TicketMin end
    if Config.Zone.spawnRadiusMin >= Config.Zone.spawnRadiusMax then
        Config.Zone.spawnRadiusMax = Config.Zone.spawnRadiusMin + 1.0
    end
    -- Entiers pour les champs "nombre d'entités / ms"
    for _, p in ipairs({ 'TicketMin', 'TicketMax', 'Zone.maxZombies', 'Waves.startDelay', 'Waves.betweenWaves',
        'Waves.spawnInterval', 'Waves.baseZombies', 'Waves.zombiesPerWave', 'Waves.maxZombiesPerWave',
        'Zombie.health', 'Terrifier.health', 'Terrifier.startWave', 'Terrifier.everyNWaves', 'Terrifier.count', 'Crew.price', 'Crew.maxMembers' }) do
        ZConfigSet(p, math.floor(ZConfigGet(p) + 0.5))
    end
    return applied
end

local function broadcastConfig()
    TriggerClientEvent('adam_zombie:syncConfig', -1, currentValues())
end

-- Chargement des réglages sauvegardés
CreateThread(function()
    local raw = LoadResourceFile(GetCurrentResourceName(), Config.Admin.saveFile or 'settings.json')
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            applyValues(data)
            print('^2[adam_zombie] Réglages sauvegardés chargés.^0')
        end
    end
end)

RegisterNetEvent('adam_zombie:requestConfig', function()
    TriggerClientEvent('adam_zombie:syncConfig', source, currentValues())
end)

local function openConfigFor(src)
    if not isFounder(src) then
        notify(src, '~r~Tu n’as pas la permission (rôle fondateur requis).')
        return
    end
    TriggerClientEvent('adam_zombie:openConfig', src, Config.Editable, currentValues())
end

RegisterCommand(Config.Admin.command or 'configzombie', function(src)
    if src == 0 then print('[adam_zombie] Cette commande s’utilise en jeu.') return end
    openConfigFor(src)
end, false)

RegisterNetEvent('adam_zombie:saveConfig', function(values)
    local src = source
    if not isFounder(src) then
        notify(src, '~r~Tu n’as pas la permission (rôle fondateur requis).')
        return
    end
    if type(values) ~= 'table' then return end
    local n = applyValues(values)
    persistSettings()
    broadcastConfig()
    notify(src, ('~g~Configuration zombie enregistrée (%d réglage(s)).'):format(n))
    print(('[adam_zombie] Config modifiée par %s (%d)'):format(GetPlayerName(src) or src, src))
    TriggerClientEvent('adam_zombie:openConfig', src, Config.Editable, currentValues(), true)
end)

RegisterNetEvent('adam_zombie:resetConfig', function()
    local src = source
    if not isFounder(src) then
        notify(src, '~r~Tu n’as pas la permission (rôle fondateur requis).')
        return
    end
    applyValues(Config.Defaults)
    persistSettings()
    broadcastConfig()
    notify(src, '~y~Configuration zombie réinitialisée.')
    TriggerClientEvent('adam_zombie:openConfig', src, Config.Editable, currentValues(), true)
end)

-- =====================================================================
--  /zombiekick [id|all] : forcer un joueur (ou tous) à sortir de la zone (fondateurs)
-- =====================================================================
local function forceLeave(target)
    if not activePlayers[target] then return false end
    -- Le client supprime les zombies, retire le HUD et téléporte au retour.
    TriggerClientEvent('adam_zombie:leaveClient', target)
    TriggerClientEvent('adam_zombie:forceStop', target)
    -- Nettoyage serveur direct (au cas où le client ne répondrait pas)
    leaveInstance(target, playerBuckets[target])
    activePlayers[target] = nil
    playerBuckets[target] = nil
    lastKillReward[target] = nil
    sessionTickets[target] = nil
    SetPlayerRoutingBucket(target, previousBuckets[target] or 0)
    previousBuckets[target] = nil
    notify(target, '~r~Tu as été expulsé de la zone zombie.')
    return true
end

RegisterCommand('zombiekick', function(src, args)
    if src ~= 0 and not isFounder(src) then
        notify(src, '~r~Tu n’as pas la permission (rôle fondateur requis).')
        return
    end
    local function reply(msg)
        if src == 0 then print('[adam_zombie] ' .. msg) else notify(src, msg) end
    end
    local arg = args[1] and args[1]:lower()
    if not arg then
        local ids = {}
        for id in pairs(activePlayers) do ids[#ids + 1] = tostring(id) end
        reply(#ids > 0 and ('Joueurs dans la zone : ' .. table.concat(ids, ', ') .. ' — /zombiekick <id|all>')
            or 'Personne dans la zone zombie.')
        return
    end
    if arg == 'all' then
        local n = 0
        for id in pairs(activePlayers) do
            if forceLeave(id) then n = n + 1 end
        end
        reply(('~g~%d joueur(s) expulsé(s) de la zone.'):format(n))
        return
    end
    local target = tonumber(arg)
    if target and forceLeave(target) then
        reply(('~g~Joueur %d expulsé de la zone.'):format(target))
    else
        reply('~r~Ce joueur n’est pas dans la zone zombie.')
    end
end, false)

-- /zombiewho : montre ce que le script voit pour TON compte (pour régler Config.Admin.roles)
RegisterCommand('zombiewho', function(src)
    if src == 0 then return end
    local list, found = collectRoles(src)
    local parts = {}
    for _, e in ipairs(list) do parts[#parts + 1] = e[1] .. '=' .. e[2] end
    local msg = found and (#parts > 0 and table.concat(parts, ' | ') or 'aucune info de rôle trouvée')
        or 'joueur introuvable via ESX/Spin (getESX a échoué)'
    print(('[adam_zombie] /zombiewho %d -> %s'):format(src, msg))
    notify(src, 'Zombie rôles : ' .. msg)
    notify(src, isFounder(src) and '~g~Fondateur : OUI' or '~r~Fondateur : NON')
end, false)


-- Meilleure vague atteinte : signalée par l'hôte, créditée à tous les membres de l'instance
RegisterNetEvent('adam_zombie:waveReached', function(wave)
    local src = source
    if not activePlayers[src] or type(wave) ~= 'number' then return end
    wave = math.floor(wave)
    local inst = instances[getZombieBucket(src)]
    if not inst or inst.host ~= src then return end
    if wave <= inst.best or wave > inst.best + 2 then return end
    inst.best = wave
    for m in pairs(inst.members) do
        if activePlayers[m] and wave > (sessionWave[m] or 0) then
            sessionWave[m] = wave
            lbAdd(m, 'wave', wave)
        end
    end
end)

-- État des vagues envoyé par l'hôte (HUD des autres membres + reprise si l'hôte part)
RegisterNetEvent('adam_zombie:hostState', function(wave, total, pause, nextIn)
    local src = source
    local inst = instances[getZombieBucket(src)]
    if not inst or inst.host ~= src then return end
    wave, total, nextIn = tonumber(wave) or 0, tonumber(total) or 0, tonumber(nextIn) or 0
    inst.hostWave, inst.total = wave, total
    for m in pairs(inst.members) do
        if m ~= src then TriggerClientEvent('adam_zombie:syncState', m, wave, total, pause == true, nextIn) end
    end
end)

-- Suppression des zombies morts demandée par l'hôte (le serveur peut supprimer même si le contrôle a migré)
RegisterNetEvent('adam_zombie:removeZombie', function(netId)
    local src = source
    local inst = instances[getZombieBucket(src)]
    if not inst or inst.host ~= src then return end
    netId = tonumber(netId)
    if not netId then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 1 and not IsPedAPlayer(ent)
        and GetEntityRoutingBucket(ent) == getZombieBucket(src) then
        DeleteEntity(ent)
    end
end)

-- Annonces de vague / vague terminée, relayées aux autres membres
RegisterNetEvent('adam_zombie:hostBroadcast', function(kind, a, b, c)
    local src = source
    local inst = instances[getZombieBucket(src)]
    if not inst or inst.host ~= src then return end
    if kind ~= 'announce' and kind ~= 'cleared' then return end
    a, b = tonumber(a) or 0, tonumber(b) or 0
    for m in pairs(inst.members) do
        if m ~= src then TriggerClientEvent('adam_zombie:crewBroadcast', m, kind, a, b, c == true) end
    end
end)

AddEventHandler('playerDropped', function() sessionWave[source] = nil end)


-- Classements affichés dans le menu de la zone (lus depuis adam_zombi_leaderboard)
RegisterNetEvent('adam_zombie:requestLeaderboard', function()
    local src = source
    local L = Config.Leaderboard
    if not (L and L.enabled) or GetResourceState(L.resource) ~= 'started' then
        TriggerClientEvent('adam_zombie:leaderboardData', src, nil)
        return
    end
    local ok, boards, champion = pcall(function() return exports[L.resource]:GetBoards() end)
    TriggerClientEvent('adam_zombie:leaderboardData', src, ok and boards or nil, ok and champion or nil)
end)


-- =====================================================================
--  CREWS : création payante (menu) -> validation fondateur (/configzombie) -> invitations par ID unique
-- =====================================================================
local CREW_T, MEM_T, REF_T = 'adam_zombie_crews', 'adam_zombie_crew_members', 'adam_zombie_crew_refunds'
local Crews = {}          -- [id] = { id, name, status, owner_identifier, members = { {identifier, uid, name} } }
local crewInvites = {}    -- [targetSrc] = { [crewId] = { fromName, expires } }
local crewReady = false
local crewCooldown = {}

local function spinTable()
    local sp = rawget(_G, 'Spin')
    if type(sp) == 'table' and type(sp.Player) == 'table' then return sp end
    return nil
end

-- identifiant, nom RP, ID unique
local function crewIdentity(src)
    local identifier = GetPlayerIdentifierByType(src, 'license')
    local name, uid = GetPlayerName(src), ''
    local sp = spinTable()
    if sp then
        pcall(function() local i = sp.Player.GetIdentifier(src) if type(i) == 'string' and i ~= '' then identifier = i end end)
        pcall(function() local n = sp.Player.GetName(src) if type(n) == 'string' and n ~= '' then name = n end end)
        pcall(function() local u = sp.Player.GetUniqueId(src) if u ~= nil then uid = tostring(u) end end)
    else
        local ESX = getESX()
        local xPlayer = ESX and ESX.GetPlayerFromId(src)
        if xPlayer then
            identifier = xPlayer.identifier or identifier
            if xPlayer.idunique ~= nil then uid = tostring(xPlayer.idunique) end
            if xPlayer.getName then
                local ok, n = pcall(xPlayer.getName)
                if ok and type(n) == 'string' and n ~= '' then name = n end
            end
        end
    end
    return identifier, name, uid
end

local function sourceByUid(uid)
    local sp = spinTable()
    if not sp then return nil end
    for _, v in ipairs({ tonumber(uid), tostring(uid) }) do
        local ok, src = pcall(function() return sp.Player.GetSourceByUniqueId(v) end)
        if ok and src and tonumber(src) and tonumber(src) > 0 and GetPlayerName(tonumber(src)) then return tonumber(src) end
    end
    return nil
end

local function removeMoney(src, amount, reason)
    if amount <= 0 then return true end
    local account = Config.Crew.account or 'bank'
    local sp = rawget(_G, 'Spin')
    if type(sp) == 'table' and type(sp.Money) == 'table' and type(sp.Money.Remove) == 'function' then
        local ok, res = pcall(sp.Money.Remove, src, account, amount, reason)
        return ok and res == true
    end
    local ESX = getESX()
    local xPlayer = ESX and ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    local ok, res = pcall(function()
        local acc = xPlayer.getAccount(account)
        if not acc or acc.money < amount then return false end
        xPlayer.removeAccountMoney(account, amount)
        return true
    end)
    return ok and res == true
end

local function addMoney(src, amount, reason)
    if amount <= 0 then return true end
    local account = Config.Crew.account or 'bank'
    local sp = rawget(_G, 'Spin')
    if type(sp) == 'table' and type(sp.Money) == 'table' and type(sp.Money.Add) == 'function' then
        local ok, res = pcall(sp.Money.Add, src, account, amount, reason)
        return ok and res == true
    end
    local ESX = getESX()
    local xPlayer = ESX and ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    return pcall(function() xPlayer.addAccountMoney(account, amount) end)
end

local function crewOf(identifier)
    for _, c in pairs(Crews) do
        for _, m in ipairs(c.members) do
            if m.identifier == identifier then return c, m end
        end
    end
    return nil
end

local function crewNameTaken(name, exceptId)
    local l = name:lower()
    for id, c in pairs(Crews) do
        if id ~= exceptId and c.name:lower() == l then return true end
    end
    return false
end

-- Nom valide ? retourne le nom nettoyé ou nil, raison
local function cleanCrewName(raw)
    if type(raw) ~= 'string' then return nil, 'Nom invalide.' end
    local name = raw:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    local len = utf8.len(name)
    if not len then return nil, 'Nom invalide.' end
    if len < (Config.Crew.nameMin or 3) or len > (Config.Crew.nameMax or 20) then
        return nil, ('Le nom doit faire entre %d et %d caractères.'):format(Config.Crew.nameMin or 3, Config.Crew.nameMax or 20)
    end
    if name:find('[<>"\'&\\%c]') then return nil, 'Le nom contient des caractères interdits.' end
    return name
end

local function crewMemberView(c)
    local list = {}
    for _, m in ipairs(c.members) do
        list[#list + 1] = { name = m.name, uid = m.uid, owner = (m.identifier == c.owner_identifier) }
    end
    table.sort(list, function(a, b) if a.owner ~= b.owner then return a.owner end return a.name < b.name end)
    return list
end

local function ownerOf(c)
    for _, m in ipairs(c.members) do
        if m.identifier == c.owner_identifier then return m end
    end
    return { name = 'Inconnu', uid = '' }
end

local function sendCrewView(src)
    local identifier = crewIdentity(src)
    local c = crewOf(identifier)
    local view = { price = Config.Crew.price, maxMembers = Config.Crew.maxMembers, invites = {} }
    if c then
        local o = ownerOf(c)
        view.crew = {
            id = c.id, name = c.name, status = c.status,
            isOwner = (c.owner_identifier == identifier),
            ownerName = o.name, ownerUid = o.uid,
            members = crewMemberView(c)
        }
    else
        local now = os.time()
        for crewId, inv in pairs(crewInvites[src] or {}) do
            local cr = Crews[crewId]
            if inv.expires < now or not cr or cr.status ~= 'approved' then
                crewInvites[src][crewId] = nil
            else
                view.invites[#view.invites + 1] = { crewId = crewId, name = cr.name, fromName = inv.fromName }
            end
        end
    end
    TriggerClientEvent('adam_zombie:crewView', src, view)
end

local function refreshCrewMembers(c)
    for _, m in ipairs(c.members) do
        for _, pid in ipairs(GetPlayers()) do
            pid = tonumber(pid)
            local ident = crewIdentity(pid)
            if ident == m.identifier then sendCrewView(pid) end
        end
    end
end

local function notifyCrew(c, msg)
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local ident = crewIdentity(pid)
        for _, m in ipairs(c.members) do
            if m.identifier == ident then notify(pid, msg) end
        end
    end
end

function CrewApi.getApprovedCrew(src)
    local c = crewOf((crewIdentity(src)))
    if c and c.status == 'approved' then return c end
    return nil
end
CrewApi.notifyCrew = notifyCrew

local function playerBySrcIdentifier(identifier)
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if (crewIdentity(pid)) == identifier then return pid end
    end
    return nil
end

local function payPendingRefunds(src)
    if not crewReady then return end
    local identifier = crewIdentity(src)
    local rows = MySQL.query.await(('SELECT `amount` FROM `%s` WHERE `identifier` = ?'):format(REF_T), { identifier }) or {}
    if #rows == 0 then return end
    local total = 0
    for _, r in ipairs(rows) do total = total + (tonumber(r.amount) or 0) end
    if total > 0 and addMoney(src, total, 'Remboursement crew') then
        MySQL.update.await(('DELETE FROM `%s` WHERE `identifier` = ?'):format(REF_T), { identifier })
        notify(src, ('~g~Remboursement de ~s~%s $ ~g~pour ta demande de crew.'):format(total))
    end
end

local function rateLimited(src)
    local now = GetGameTimer()
    if crewCooldown[src] and now - crewCooldown[src] < 400 then return true end
    crewCooldown[src] = now
    return false
end

-- ---------- Base de données ----------
local crewDbError = 'initialisation...'
local function initCrewDb()
    local ok, err = pcall(function()
        MySQL.query.await(([[
            CREATE TABLE IF NOT EXISTS `%s` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `name` VARCHAR(64) NOT NULL,
                `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
                `owner_identifier` VARCHAR(80) NOT NULL,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]):format(CREW_T))
        MySQL.query.await(([[
            CREATE TABLE IF NOT EXISTS `%s` (
                `crew_id` INT NOT NULL,
                `identifier` VARCHAR(80) NOT NULL,
                `uid` VARCHAR(32) NOT NULL DEFAULT '',
                `name` VARCHAR(64) NOT NULL DEFAULT '',
                PRIMARY KEY (`identifier`),
                KEY `idx_crew` (`crew_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]):format(MEM_T))
        MySQL.query.await(([[
            CREATE TABLE IF NOT EXISTS `%s` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `identifier` VARCHAR(80) NOT NULL,
                `amount` INT NOT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_ident` (`identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]):format(REF_T))
        for _, r in ipairs(MySQL.query.await(('SELECT * FROM `%s`'):format(CREW_T)) or {}) do
            Crews[r.id] = { id = r.id, name = r.name, status = r.status, owner_identifier = r.owner_identifier, members = {} }
        end
        for _, m in ipairs(MySQL.query.await(('SELECT * FROM `%s`'):format(MEM_T)) or {}) do
            local c = Crews[m.crew_id]
            if c then c.members[#c.members + 1] = { identifier = m.identifier, uid = m.uid, name = m.name } end
        end
    end)
    if ok then
        crewReady = true
        crewDbError = nil
        local n = 0 for _ in pairs(Crews) do n = n + 1 end
        print(('^2[adam_zombie]^0 Crews chargés : %d'):format(n))
    else
        crewDbError = tostring(err)
        print('^1[adam_zombie] Erreur base de données (crews) : ' .. crewDbError .. '^0')
    end
    return ok
end

CreateThread(function()
    for attempt = 1, 10 do
        if initCrewDb() then return end
        Wait(5000)
    end
end)

-- ---------- Joueur ----------
RegisterNetEvent('adam_zombie:crewRequest', function()
    local src = source
    if not crewReady then
        print('^1[adam_zombie] Crews indisponibles : ' .. tostring(crewDbError) .. '^0')
        TriggerClientEvent('adam_zombie:crewView', src, { error = 'Base de données indisponible : ' .. tostring(crewDbError) })
        return
    end
    payPendingRefunds(src)
    sendCrewView(src)
end)

RegisterNetEvent('adam_zombie:crewCreate', function(rawName)
    local src = source
    if not crewReady or rateLimited(src) then return end
    local identifier, pname, uid = crewIdentity(src)
    if not identifier then return end
    if crewOf(identifier) then notify(src, '~r~Tu es déjà dans un crew (ou une demande est en attente).') return end
    local name, why = cleanCrewName(rawName)
    if not name then notify(src, '~r~' .. why) return end
    if crewNameTaken(name) then notify(src, '~r~Ce nom de crew est déjà pris.') return end
    local price = math.floor(Config.Crew.price or 0)
    if not removeMoney(src, price, 'Création de crew') then
        notify(src, ('~r~Il te faut %s $ sur ton compte pour créer un crew.'):format(price))
        return
    end
    local id = MySQL.insert.await(('INSERT INTO `%s` (`name`, `status`, `owner_identifier`) VALUES (?, \'pending\', ?)'):format(CREW_T), { name, identifier })
    if not id then
        addMoney(src, price, 'Remboursement crew')
        notify(src, '~r~Erreur lors de la création, tu as été remboursé.')
        return
    end
    MySQL.insert.await(('INSERT INTO `%s` (`crew_id`, `identifier`, `uid`, `name`) VALUES (?, ?, ?, ?)'):format(MEM_T), { id, identifier, uid, pname })
    Crews[id] = { id = id, name = name, status = 'pending', owner_identifier = identifier,
        members = { { identifier = identifier, uid = uid, name = pname } } }
    notify(src, ('~g~Demande envoyée pour le crew ~s~%s~g~ (%s $ payés). Un fondateur doit la valider.'):format(name, price))
    sendCrewView(src)
end)

RegisterNetEvent('adam_zombie:crewInvite', function(targetUid)
    local src = source
    if not crewReady or rateLimited(src) then return end
    local identifier, pname = crewIdentity(src)
    local c = crewOf(identifier)
    if not c or c.status ~= 'approved' or c.owner_identifier ~= identifier then
        notify(src, '~r~Seul le owner d’un crew validé peut inviter.')
        return
    end
    targetUid = tostring(targetUid or ''):gsub('%s', '')
    if not targetUid:match('^%d+$') or #targetUid > 12 then notify(src, '~r~ID unique invalide.') return end
    if #c.members >= (Config.Crew.maxMembers or 10) then notify(src, '~r~Ton crew est complet.') return end
    local target = sourceByUid(targetUid)
    if not target then notify(src, '~r~Aucun joueur connecté avec cet ID unique.') return end
    if target == src then notify(src, '~r~Tu ne peux pas t’inviter toi-même.') return end
    local tIdent = crewIdentity(target)
    if crewOf(tIdent) then notify(src, '~r~Ce joueur est déjà dans un crew.') return end
    crewInvites[target] = crewInvites[target] or {}
    if crewInvites[target][c.id] and crewInvites[target][c.id].expires > os.time() then
        notify(src, '~y~Ce joueur a déjà une invitation en attente pour ton crew.')
        return
    end
    crewInvites[target][c.id] = { fromName = pname, expires = os.time() + (Config.Crew.inviteTtl or 300) }
    notify(src, '~g~Invitation envoyée.')
    notify(target, ('~y~%s t’invite à rejoindre le crew ~s~%s~y~. Ouvre le menu zombie (/crew) pour répondre.'):format(pname, c.name))
    sendCrewView(target)
end)

RegisterNetEvent('adam_zombie:crewRespond', function(crewId, accept)
    local src = source
    if not crewReady or rateLimited(src) then return end
    crewId = tonumber(crewId)
    local inv = crewId and crewInvites[src] and crewInvites[src][crewId]
    if not inv then return end
    crewInvites[src][crewId] = nil
    if accept ~= true then sendCrewView(src) return end
    local c = Crews[crewId]
    local identifier, pname, uid = crewIdentity(src)
    if inv.expires < os.time() or not c or c.status ~= 'approved' then notify(src, '~r~Cette invitation n’est plus valable.') sendCrewView(src) return end
    if crewOf(identifier) then notify(src, '~r~Tu es déjà dans un crew.') return end
    if #c.members >= (Config.Crew.maxMembers or 10) then notify(src, '~r~Ce crew est complet.') sendCrewView(src) return end
    MySQL.insert.await(('INSERT INTO `%s` (`crew_id`, `identifier`, `uid`, `name`) VALUES (?, ?, ?, ?)'):format(MEM_T), { c.id, identifier, uid, pname })
    c.members[#c.members + 1] = { identifier = identifier, uid = uid, name = pname }
    crewInvites[src] = nil
    notifyCrew(c, ('~g~%s a rejoint le crew ~s~%s~g~.'):format(pname, c.name))
    refreshCrewMembers(c)
end)

local function removeMember(c, identifier)
    for i, m in ipairs(c.members) do
        if m.identifier == identifier then table.remove(c.members, i) break end
    end
    MySQL.update.await(('DELETE FROM `%s` WHERE `identifier` = ?'):format(MEM_T), { identifier })
end

RegisterNetEvent('adam_zombie:crewKick', function(targetUid)
    local src = source
    if not crewReady or rateLimited(src) then return end
    local identifier = crewIdentity(src)
    local c = crewOf(identifier)
    if not c or c.owner_identifier ~= identifier then return end
    targetUid = tostring(targetUid or '')
    for _, m in ipairs(c.members) do
        if m.uid == targetUid and m.identifier ~= identifier then
            local tSrc = playerBySrcIdentifier(m.identifier)
            local kickedName = m.name
            removeMember(c, m.identifier)
            if tSrc then notify(tSrc, ('~r~Tu as été retiré du crew ~s~%s~r~.'):format(c.name)) sendCrewView(tSrc) end
            notifyCrew(c, ('~y~%s a été retiré du crew.'):format(kickedName))
            refreshCrewMembers(c)
            return
        end
    end
end)

RegisterNetEvent('adam_zombie:crewLeave', function()
    local src = source
    if not crewReady or rateLimited(src) then return end
    local identifier, pname = crewIdentity(src)
    local c = crewOf(identifier)
    if not c then return end
    if c.owner_identifier == identifier then
        notify(src, '~r~Le owner ne peut pas quitter son crew. Contacte un fondateur.')
        return
    end
    removeMember(c, identifier)
    notify(src, ('~y~Tu as quitté le crew ~s~%s~y~.'):format(c.name))
    notifyCrew(c, ('~y~%s a quitté le crew.'):format(pname))
    sendCrewView(src)
    refreshCrewMembers(c)
end)

-- ---------- Admin (/configzombie, fondateurs uniquement) ----------
local function sendCrewAdminList(src)
    local list = {}
    for _, c in pairs(Crews) do
        local o = ownerOf(c)
        list[#list + 1] = { id = c.id, name = c.name, status = c.status, ownerName = o.name, ownerUid = o.uid, members = crewMemberView(c) }
    end
    table.sort(list, function(a, b)
        if a.status ~= b.status then return a.status == 'pending' end
        return a.name:lower() < b.name:lower()
    end)
    TriggerClientEvent('adam_zombie:crewAdminData', src, list, Config.Crew.price)
end

RegisterNetEvent('adam_zombie:crewAdminList', function()
    local src = source
    if not isFounder(src) then return end
    sendCrewAdminList(src)
end)

RegisterNetEvent('adam_zombie:crewAdmin', function(action, crewId, value)
    local src = source
    if not isFounder(src) then notify(src, '~r~Rôle fondateur requis.') return end
    if not crewReady or rateLimited(src) then return end
    crewId = tonumber(crewId)
    local c = crewId and Crews[crewId]
    if not c then notify(src, '~r~Crew introuvable.') return end

    if action == 'approve' then
        if c.status == 'approved' then return end
        c.status = 'approved'
        MySQL.update.await(('UPDATE `%s` SET `status` = \'approved\' WHERE `id` = ?'):format(CREW_T), { c.id })
        notifyCrew(c, ('~g~Ton crew ~s~%s~g~ a été accepté !'):format(c.name))
        refreshCrewMembers(c)
        notify(src, ('~g~Crew %s confirmé.'):format(c.name))

    elseif action == 'rename' then
        local name, why = cleanCrewName(value)
        if not name then notify(src, '~r~' .. why) return end
        if crewNameTaken(name, c.id) then notify(src, '~r~Ce nom est déjà pris.') return end
        c.name = name
        MySQL.update.await(('UPDATE `%s` SET `name` = ? WHERE `id` = ?'):format(CREW_T), { name, c.id })
        refreshCrewMembers(c)
        notify(src, '~g~Crew renommé.')

    elseif action == 'owner' then
        local uid = tostring(value or ''):gsub('%s', '')
        if not uid:match('^%d+$') then notify(src, '~r~ID unique invalide.') return end
        local target
        for _, m in ipairs(c.members) do if m.uid == uid then target = m break end end
        if not target then
            -- pas encore membre : il doit être connecté et sans crew, on l'ajoute
            local tSrc = sourceByUid(uid)
            if not tSrc then notify(src, '~r~Joueur introuvable (il doit être membre du crew ou connecté).') return end
            local ident, pname, puid = crewIdentity(tSrc)
            if crewOf(ident) then notify(src, '~r~Ce joueur est déjà dans un autre crew.') return end
            if #c.members >= (Config.Crew.maxMembers or 10) then notify(src, '~r~Crew complet.') return end
            MySQL.insert.await(('INSERT INTO `%s` (`crew_id`, `identifier`, `uid`, `name`) VALUES (?, ?, ?, ?)'):format(MEM_T), { c.id, ident, puid, pname })
            target = { identifier = ident, uid = puid, name = pname }
            c.members[#c.members + 1] = target
        end
        c.owner_identifier = target.identifier
        MySQL.update.await(('UPDATE `%s` SET `owner_identifier` = ? WHERE `id` = ?'):format(CREW_T), { target.identifier, c.id })
        notifyCrew(c, ('~y~%s est maintenant owner du crew ~s~%s~y~.'):format(target.name, c.name))
        refreshCrewMembers(c)
        notify(src, '~g~Owner modifié.')

    elseif action == 'delete' then
        local price = math.floor(Config.Crew.price or 0)
        local ownerIdent = c.owner_identifier
        local wasPending = c.status == 'pending'
        notifyCrew(c, ('~r~Le crew ~s~%s~r~ a été supprimé par un fondateur.'):format(c.name))
        local members = c.members
        Crews[c.id] = nil
        MySQL.update.await(('DELETE FROM `%s` WHERE `crew_id` = ?'):format(MEM_T), { c.id })
        MySQL.update.await(('DELETE FROM `%s` WHERE `id` = ?'):format(CREW_T), { c.id })
        for _, ti in pairs(crewInvites) do ti[c.id] = nil end
        if wasPending and Config.Crew.refundOnReject and price > 0 then
            local oSrc = playerBySrcIdentifier(ownerIdent)
            if oSrc and addMoney(oSrc, price, 'Remboursement crew') then
                notify(oSrc, ('~g~Remboursement de ~s~%s $ ~g~pour ta demande de crew.'):format(price))
            else
                MySQL.insert.await(('INSERT INTO `%s` (`identifier`, `amount`) VALUES (?, ?)'):format(REF_T), { ownerIdent, price })
            end
        end
        for _, m in ipairs(members) do
            local pSrc = playerBySrcIdentifier(m.identifier)
            if pSrc then sendCrewView(pSrc) end
        end
        notify(src, '~y~Crew supprimé.')
    end
    sendCrewAdminList(src)
end)

AddEventHandler('playerDropped', function()
    crewInvites[source] = nil
    crewCooldown[source] = nil
end)


-- ---------- Top des crews (envoyé au leaderboard) ----------
-- Score d'un crew = somme des kills (Config.Leaderboard.crewStats) de ses membres actuels
local lastCrewBoard = ''

local function pushCrewBoard()
    local L = Config.Leaderboard
    if not (L and L.enabled and L.crewBoard) or not crewReady then return end
    if GetResourceState(L.resource) ~= 'started' then return end

    local stats = L.crewStats or { 'zombies' }
    local marks = {}
    for _ = 1, #stats do marks[#marks + 1] = '?' end
    local ok, rows = pcall(function()
        return MySQL.query.await(
            ('SELECT `license`, `uid`, `value` FROM `%s` WHERE `stat` IN (%s)'):format(L.table, table.concat(marks, ',')),
            stats
        )
    end)
    if not ok or type(rows) ~= 'table' then return end

    local byUid, byIdent = {}, {}
    for _, c in pairs(Crews) do
        if c.status == 'approved' then
            for _, m in ipairs(c.members) do
                if m.uid and m.uid ~= '' then byUid[m.uid] = c end
                byIdent[m.identifier] = c
            end
        end
    end

    local totals = {}
    for _, r in ipairs(rows) do
        local c = (r.uid and r.uid ~= '' and byUid[r.uid]) or byIdent[r.license]
        if c then totals[c.id] = (totals[c.id] or 0) + (tonumber(r.value) or 0) end
    end

    local list = {}
    for id, total in pairs(totals) do
        if total > 0 then list[#list + 1] = { name = Crews[id].name, value = total } end
    end
    table.sort(list, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.name < b.name end)

    local encoded = json.encode(list)
    if encoded == lastCrewBoard then return end
    lastCrewBoard = encoded
    pcall(function() exports[L.resource]:SetBoardRows(L.crewBoard, list) end)
end

CreateThread(function()
    Wait(8000)
    while true do
        pushCrewBoard()
        Wait(15000)
    end
end)

-- Si le leaderboard redémarre, on renvoie le classement
AddEventHandler('onResourceStart', function(resource)
    local L = Config.Leaderboard
    if L and resource == L.resource then
        lastCrewBoard = ''
        SetTimeout(5000, pushCrewBoard)
    end
end)


-- /configzombie : nombre de joueurs actuellement en mode zombie (fondateurs uniquement)
RegisterNetEvent('adam_zombie:zoneCountRequest', function()
    local src = source
    if not isFounder(src) then return end
    local count = 0
    for _ in pairs(activePlayers) do count = count + 1 end
    local list = {}
    local crewBase = Config.Zone.crewBucketBase or 24800
    local soloBase = Config.Zone.soloBucketBase or 23800
    for bucket, inst in pairs(instances) do
        local names = {}
        for m in pairs(inst.members) do
            local _, pname = crewIdentity(m)
            names[#names + 1] = pname or GetPlayerName(m) or tostring(m)
        end
        table.sort(names)
        local label, kind = 'Zone partagée', 'shared'
        if Config.Zone.soloInstance then
            if bucket >= crewBase and Crews[bucket - crewBase] then
                label, kind = 'Crew ' .. Crews[bucket - crewBase].name, 'crew'
            else
                label, kind = 'Solo – ' .. (names[1] or '?'), 'solo'
            end
        end
        list[#list + 1] = {
            bucket = bucket, label = label, kind = kind, players = names,
            wave = inst.hostWave or 0,
            joined = activePlayers[src] and getZombieBucket(src) == bucket or false
        }
    end
    table.sort(list, function(x, y) return x.label:lower() < y.label:lower() end)
    TriggerClientEvent('adam_zombie:zoneCount', src, count, list)
end)

-- Un fondateur rejoint une partie en cours (uniquement depuis /configzombie)
RegisterNetEvent('adam_zombie:adminJoin', function(bucket)
    local src = source
    if not isFounder(src) then notify(src, '~r~Rôle fondateur requis.') return end
    bucket = tonumber(bucket)
    if not bucket or not instances[bucket] then
        TriggerClientEvent('adam_zombie:denied', src, 'Cette partie est terminée.')
        return
    end
    if activePlayers[src] then
        TriggerClientEvent('adam_zombie:denied', src, 'Tu es déjà dans la zone zombie.')
        return
    end
    enterInstance(src, bucket)
    notify(src, '~g~Tu as rejoint la partie en cours.')
end)


-- =====================================================================
--  CONCOURS : chrono + gagnant (plus de zombies tués), figé à l'heure de fin
-- =====================================================================
local CONTEST_T = 'adam_zombie_contest'
local contestWinner = nil -- figé une fois la date de fin passée

local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = (y >= 0 and y or y - 399) // 400
    local yoe = y - era * 400
    local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
    local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468
end

local function contestEndTs()
    local C = Config.Contest
    if not (C and C.enabled) then return nil end
    local y, mo, d, h, mi = tostring(C.endsAt or ''):match('^(%d+)-(%d+)-(%d+)%s+(%d+):(%d+)')
    if not y then
        print('^1[adam_zombie] Config.Contest.endsAt invalide (format AAAA-MM-JJ HH:MM).^0')
        return nil
    end
    y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
    return daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 - math.floor((C.utcOffset or 0) * 3600)
end

local CONTEST_END = contestEndTs()

local function topKillers(limit)
    local L = Config.Leaderboard
    local ok, rows = pcall(function()
        return MySQL.query.await(
            ('SELECT `license`, `name`, `uid`, `value` FROM `%s` WHERE `stat` = ? AND `value` > 0 ORDER BY `value` DESC, `name` ASC LIMIT ?'):format(L.table),
            { Config.Contest.stat or 'zombies', limit }
        )
    end)
    return (ok and type(rows) == 'table') and rows or {}
end

local function winnerFrom(rows)
    local top = rows[1]
    if not top then return { none = true } end
    local tie = {}
    for i = 2, #rows do
        if tonumber(rows[i].value) == tonumber(top.value) then tie[#tie + 1] = rows[i].name end
    end
    return {
        name = (top.name and top.name ~= '') and top.name or 'Inconnu',
        uid = top.uid or '',
        kills = tonumber(top.value) or 0,
        identifier = top.license,
        tie = tie
    }
end

CreateThread(function()
    if not CONTEST_END then return end
    for _ = 1, 10 do
        local ok = pcall(function()
            MySQL.query.await(([[
                CREATE TABLE IF NOT EXISTS `%s` (
                    `ends_ts` BIGINT NOT NULL,
                    `license` VARCHAR(80) NOT NULL DEFAULT '',
                    `name` VARCHAR(64) NOT NULL DEFAULT '',
                    `uid` VARCHAR(32) NOT NULL DEFAULT '',
                    `kills` INT NOT NULL DEFAULT 0,
                    `tie` VARCHAR(255) NOT NULL DEFAULT '',
                    PRIMARY KEY (`ends_ts`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            ]]):format(CONTEST_T))
            local r = MySQL.query.await(('SELECT * FROM `%s` WHERE `ends_ts` = ?'):format(CONTEST_T), { CONTEST_END })
            if r and r[1] then
                if r[1].name == '' then
                    contestWinner = { none = true }
                else
                    local tie = {}
                    for n in tostring(r[1].tie or ''):gmatch('[^|]+') do tie[#tie + 1] = n end
                    contestWinner = { name = r[1].name, uid = r[1].uid, kills = r[1].kills, identifier = r[1].license, tie = tie }
                end
            end
        end)
        if ok then break end
        Wait(5000)
    end
    while true do
        if not contestWinner and os.time() >= CONTEST_END then
            local w = winnerFrom(topKillers(5))
            contestWinner = w
            pcall(function()
                MySQL.insert(('INSERT IGNORE INTO `%s` (`ends_ts`, `license`, `name`, `uid`, `kills`, `tie`) VALUES (?, ?, ?, ?, ?, ?)'):format(CONTEST_T),
                    { CONTEST_END, w.identifier or '', w.none and '' or w.name, w.uid or '', w.kills or 0, table.concat(w.tie or {}, '|'):sub(1, 255) })
            end)
            if w.none then
                print('^3[adam_zombie] Concours terminé : aucun kill enregistré.^0')
            else
                print(('^2[adam_zombie] Concours terminé ! Gagnant : %s (ID unique %s) avec %d zombies tués.^0'):format(w.name, tostring(w.uid), w.kills))
            end
        end
        Wait(5000)
    end
end)

local liveLeader, liveLeaderAt = nil, 0

RegisterNetEvent('adam_zombie:contestRequest', function()
    local src = source
    if not CONTEST_END then
        TriggerClientEvent('adam_zombie:contestData', src, { enabled = false })
        return
    end
    local left = CONTEST_END - os.time()
    local info = { enabled = true, ended = left <= 0, secondsLeft = math.max(0, left) }
    -- Gagnant / leader : réservé aux fondateurs (affiché dans /configzombie)
    if isFounder(src) then
        if contestWinner then
            info.winner, info.final = contestWinner, true
        else
            local now = GetGameTimer()
            if not liveLeader or now - liveLeaderAt > 5000 then
                liveLeader, liveLeaderAt = winnerFrom(topKillers(5)), now
            end
            info.winner, info.final = liveLeader, false
        end
    end
    TriggerClientEvent('adam_zombie:contestData', src, info)
end)
