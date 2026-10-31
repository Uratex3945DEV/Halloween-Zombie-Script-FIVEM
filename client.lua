local eventActive = false
local missionPeds = {}
local pedEntity = nil
local menuOpen = false
local configOpen = false
local closeLeaveDialog -- défini plus bas
local rewardedLocal = {}
local terrifierPeds = {}
local sessionId = 0
local currentWave = 0
local waveRemaining = 0 -- ennemis de la vague pas encore apparus
local nextWaveAt = 0
local isHost = true          -- true = ce client gère les vagues / PNJ de l'instance
local sharedInstance = false -- true = instance partagée (crew) : PNJ en réseau, vagues communes

local function notify(msg)
    TriggerEvent('esx:showNotification', msg)
end

local function helpText(msg)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function showHud()
    SendNUIMessage({ action = 'loadNEWApplication', data = { applicationName = 'zombiehud', color = '#ff6a2b' } })
end

local function hideHud()
    SendNUIMessage({ action = 'unloadNEWApplication', data = { applicationName = 'zombiehud' } })
end

local function addEnemyBlip(entity, isTerrifier)
    if not (Config.Blips and Config.Blips.enabled) then return end
    local cfg = isTerrifier and Config.Blips.terrifier or Config.Blips.zombie
    local blip = AddBlipForEntity(entity)
    SetBlipSprite(blip, cfg.sprite)
    SetBlipColour(blip, cfg.color)
    SetBlipScale(blip, cfg.scale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cfg.label)
    EndTextCommandSetBlipName(blip)
end

local function removeEnemyBlip(entity)
    local blip = GetBlipFromEntity(entity)
    if blip and blip ~= 0 and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
end

local function clearAllBlips()
    for _, z in ipairs(missionPeds) do removeEnemyBlip(z) end
end

local function announceWave(wave, count, terrifier)
    local A = Config.WaveAnnounce
    if not (A and A.enabled) then return end
    SendNUIMessage({
        action = 'emitNEWSUI',
        data = {
            applicationName = 'zombiehud',
            event = 'announce',
            wave = wave,
            count = count,
            terrifier = terrifier or false,
            subtitle = terrifier and A.terrifierSubtitle or A.subtitle,
            duration = A.duration or 4500,
            sound = A.customSound,
            volume = A.volume or 0.6
        }
    })
    if not A.customSound then
        local snd = (terrifier and A.terrifierSound) or A.sound
        if snd then PlaySoundFrontend(-1, snd.name, snd.set, true) end
    end
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(50) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function spawnContactPed()
    if DoesEntityExist(pedEntity) then return end
    local hash = loadModel(Config.Ped.model)
    if not hash then
        print('[adam_zombie_halloween] Impossible de charger le modèle du PNJ.')
        return
    end
    local c = Config.Ped.coords
    pedEntity = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityAsMissionEntity(pedEntity, true, true)
    SetBlockingOfNonTemporaryEvents(pedEntity, true)
    SetEntityInvincible(pedEntity, true)
    FreezeEntityPosition(pedEntity, true)
    SetPedCanRagdoll(pedEntity, false)
    if Config.Ped.scenario and Config.Ped.scenario ~= '' then
        TaskStartScenarioInPlace(pedEntity, Config.Ped.scenario, 0, true)
    end
    SetModelAsNoLongerNeeded(hash)
end

local function openMenu(tab)
    if eventActive then
        notify('~r~Tu es déjà dans la zone zombie.')
        return
    end
    menuOpen = true
    SendNUIMessage({
        action = 'loadNEWApplication',
        data = {
            applicationName = 'zombiezone',
            title = 'Zone Zombie',
            subtitle = 'Événement Halloween',
            description = 'Élimine les zombies pour gagner des tickets Halloween et tente d’obtenir un butin rare.',
            rewardMin = Config.TicketMin,
            rewardMax = Config.TicketMax,
            rareLabel = Config.RareWeaponLabel,
            tab = tab or 'zone',
            color = '#ff6a2b'
        }
    })
    SetNuiFocus(true, true)
    TriggerServerEvent('adam_zombie:requestLeaderboard')
    TriggerServerEvent('adam_zombie:crewRequest')
end

-- Callback unique UI -> Lua (liste blanche : aucun évènement arbitraire n'est relayé)
-- Évènements crew autorisés depuis l'UI (liste blanche ; le serveur revalide tout)
local CREW_EVENTS = {
    ['adam_zombie:crewCreate'] = true,
    ['adam_zombie:crewInvite'] = true,
    ['adam_zombie:crewRespond'] = true,
    ['adam_zombie:crewKick'] = true,
    ['adam_zombie:crewLeave'] = true,
    ['adam_zombie:crewRequest'] = true,
    ['adam_zombie:crewAdminList'] = true,
    ['adam_zombie:crewAdmin'] = true
}

RegisterNUICallback('eventNEWUI', function(data, cb)
    local name = data and data.event and data.event.name
    if name == 'ui:new:focus' then
        SetNuiFocus(true, true)
    elseif name == 'ui:new:unfocus' then
        menuOpen = false
        SetNuiFocus(false, false)
    elseif name == 'ui:onUnloadApplication' then
        menuOpen = false
    elseif name == 'adam_zombie:leaveConfirm' then
        closeLeaveDialog()
        if eventActive then TriggerEvent('adam_zombie:leaveClient') end
    elseif name == 'adam_zombie:leaveCancel' then
        closeLeaveDialog()
    elseif name == 'ui:config:close' then
        configOpen = false
        SetNuiFocus(false, false)
    elseif name == 'adam_zombie:saveConfig' then
        TriggerServerEvent('adam_zombie:saveConfig', data.args and data.args[1])
    elseif name == 'adam_zombie:resetConfig' then
        TriggerServerEvent('adam_zombie:resetConfig')
    elseif CREW_EVENTS[name] then
        local a = data.args or {}
        TriggerServerEvent(name, a[1], a[2], a[3])
    elseif name == 'adam_zombie:adminJoin' then
        -- rejoindre une partie en cours depuis /configzombie (le serveur vérifie le rôle fondateur)
        configOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'unloadNEWApplication', data = { applicationName = 'zombieconfig' } })
        if not eventActive then TriggerServerEvent('adam_zombie:adminJoin', data.args and data.args[1]) end
    elseif name == 'adam_zombie:join' then
        menuOpen = false
        SetNuiFocus(false, false)
        if not eventActive then TriggerServerEvent('adam_zombie:requestJoin', data.args and data.args[1]) end
    end
    cb({})
end)

local function randomSpawn()
    local angle = math.random() * math.pi * 2.0
    local distance = Config.Zone.spawnRadiusMin + math.random() * (Config.Zone.spawnRadiusMax - Config.Zone.spawnRadiusMin)
    local x = Config.Zone.center.x + math.cos(angle) * distance
    local y = Config.Zone.center.y + math.sin(angle) * distance

    -- Charge la collision autour du point avant de créer le ped.
    RequestCollisionAtCoord(x, y, Config.Zone.center.z)
    local found, z = false, Config.Zone.center.z
    local timeout = GetGameTimer() + 2500
    repeat
        found, z = GetGroundZFor_3dCoord(x, y, Config.Zone.center.z + 100.0, false)
        if not found then Wait(50) end
    until found or GetGameTimer() > timeout

    if not found then
        -- Dernier recours : garde le niveau de la zone, mais le point reste proche du joueur.
        z = Config.Zone.center.z
    end
    return vector3(x, y, z + 0.15)
end

local function countLivingZombies()
    local n = 0
    for i = #missionPeds, 1, -1 do
        local p = missionPeds[i]
        if not DoesEntityExist(p) then
            table.remove(missionPeds, i)
        elseif not IsEntityDead(p) then
            n = n + 1
        end
    end
    return n
end

-- Joueur vivant le plus proche (dans l'instance, donc les membres du crew) : cible des zombies
local function nearestPlayerPed(from)
    local fc = GetEntityCoords(from)
    local best, bestDist
    for _, pl in ipairs(GetActivePlayers()) do
        local p = GetPlayerPed(pl)
        if p ~= 0 and DoesEntityExist(p) and not IsEntityDead(p) then
            local d = #(GetEntityCoords(p) - fc)
            if not bestDist or d < bestDist then best, bestDist = p, d end
        end
    end
    return best or PlayerPedId()
end

-- ID serveur du joueur qui a tué le PNJ (nil si inconnu)
local function killerServerId(ped)
    local killer = GetPedSourceOfDeath(ped)
    if killer and killer ~= 0 and DoesEntityExist(killer) and IsEntityAPed(killer) and IsPedAPlayer(killer) then
        local idx = NetworkGetPlayerIndexFromPed(killer)
        if idx and idx ~= -1 then return GetPlayerServerId(idx) end
    end
    return nil
end

-- Un nouvel hôte récupère les zombies déjà présents dans l'instance
local function adoptExistingZombies()
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) then
            local st = Entity(ped).state.adamZombie
            if st and not IsEntityDead(ped) then
                NetworkRequestControlOfEntity(ped)
                SetEntityAsMissionEntity(ped, true, true)
                missionPeds[#missionPeds + 1] = ped
                if st == 2 then terrifierPeds[ped] = true end
            end
        end
    end
end

local function spawnEnemy(model, opts)
    opts = opts or {}
    if not eventActive then return false end
    local hash = loadModel(model)
    if not hash then
        print(('[adam_zombie_halloween] Modèle impossible à charger : %s'):format(tostring(model)))
        return false
    end
    local c = randomSpawn()
    -- Solo : création locale. Crew : PNJ en réseau (visibles et ciblables par tous les membres).
    local zombie = CreatePed(4, hash, c.x, c.y, c.z, math.random(0, 359) + 0.0, sharedInstance, true)
    if not DoesEntityExist(zombie) then
        SetModelAsNoLongerNeeded(hash)
        return false
    end
    if sharedInstance then
        local netId = NetworkGetNetworkIdFromEntity(zombie)
        SetNetworkIdExistsOnAllMachines(netId, true)
        SetNetworkIdCanMigrate(netId, false) -- l'hôte garde le contrôle de l'IA
        -- Repère pour les autres clients (blips) et pour un futur hôte (reprise)
        Entity(zombie).state:set('adamZombie', opts.terrifier and 2 or 1, true)
    end
    local health = opts.health or (Config.Zombie and Config.Zombie.health) or 250
    SetEntityAsMissionEntity(zombie, true, true)
    SetEntityVisible(zombie, true, false)
    ResetEntityAlpha(zombie)
    SetEntityAlpha(zombie, 255, false)
    SetEntityCollision(zombie, true, true)
    SetBlockingOfNonTemporaryEvents(zombie, false)
    SetPedAsEnemy(zombie, true)
    SetPedRelationshipGroupHash(zombie, joaat('HATES_PLAYER'))
    SetPedCombatAttributes(zombie, 46, true)
    SetPedCombatAttributes(zombie, 5, true)
    SetPedFleeAttributes(zombie, 0, false)
    SetPedCanRagdoll(zombie, true)
    SetPedCombatAbility(zombie, 2)
    SetPedCombatRange(zombie, 2)
    SetPedCombatMovement(zombie, 3)
    SetPedAlertness(zombie, 3)
    SetPedSeeingRange(zombie, 100.0)
    SetPedHearingRange(zombie, 100.0)
    SetPedMoveRateOverride(zombie, opts.moveRate or (Config.Zombie and Config.Zombie.moveRate) or 1.20)
    SetEntityMaxHealth(zombie, health)
    SetEntityHealth(zombie, health)
    SetPedArmour(zombie, 0)
    SetPedDropsWeaponsWhenDead(zombie, false)
    if opts.weapon then
        local weaponHash = joaat(opts.weapon)
        GiveWeaponToPed(zombie, weaponHash, 1, false, true)
        SetCurrentPedWeapon(zombie, weaponHash, true)
    end
    missionPeds[#missionPeds + 1] = zombie
    if opts.terrifier then terrifierPeds[zombie] = true end
    if not sharedInstance then addEnemyBlip(zombie, opts.terrifier) end -- en crew : géré par le scanner de blips
    TaskCombatPed(zombie, nearestPlayerPed(zombie), 0, 16)
    SetPedKeepTask(zombie, true)
    SetModelAsNoLongerNeeded(hash)
    return true
end

-- Construit la file d'apparition d'une vague : zombies d'abord, Terrifier(s) à la fin.
local function buildWaveQueue(wave)
    local W, T = Config.Waves, Config.Terrifier
    local total = math.min(W.baseZombies + (wave - 1) * W.zombiesPerWave, W.maxZombiesPerWave)
    local queue = {}
    for _ = 1, total do
        queue[#queue + 1] = { model = Config.ZombieModels[math.random(1, #Config.ZombieModels)] }
    end
    if T and T.enabled and wave >= T.startWave and (wave - T.startWave) % T.everyNWaves == 0 then
        for _ = 1, T.count do
            queue[#queue + 1] = { model = T.model, weapon = T.weapon, health = T.health, moveRate = T.moveRate, terrifier = true }
        end
    end
    return queue
end

local function handlePlayerDeath()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    -- Le serveur retire tous les tickets gagnés pendant la session.
    TriggerServerEvent('adam_zombie:playerDied')
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    if Config.Death.reviveEvent then TriggerEvent(Config.Death.reviveEvent) end
    SetPlayerInvincible(PlayerId(), true)
    Wait(Config.Death.invincibleMs)
    SetPlayerInvincible(PlayerId(), false)
end

-- Supprime un zombie mort. En crew, le contrôle de l'entité a pu changer de main :
-- on le réclame, et si ça ne suffit pas on demande au serveur de le supprimer.
local removeAsked = {}
local function removeDeadZombie(z)
    removeEnemyBlip(z)
    SetEntityAsMissionEntity(z, true, true)
    if sharedInstance and NetworkGetEntityIsNetworked(z) then
        if not NetworkHasControlOfEntity(z) then NetworkRequestControlOfEntity(z) end
        local netId = NetworkGetNetworkIdFromEntity(z)
        DeleteEntity(z)
        if DoesEntityExist(z) then
            local now = GetGameTimer()
            if not removeAsked[z] or now - removeAsked[z] > 1500 then
                removeAsked[z] = now
                TriggerServerEvent('adam_zombie:removeZombie', netId)
            end
        else
            removeAsked[z] = nil
        end
    else
        DeleteEntity(z)
    end
end

-- Boucles réservées à l'hôte : vagues, cible des zombies, récompenses/nettoyage
local function startHostThreads(sid, resumeWave, resumeTotal)
    local function alive() return eventActive and sid == sessionId and isHost end

    -- Système de vagues
    CreateThread(function()
        local function pause(ms)
            nextWaveAt = GetGameTimer() + ms
            while alive() and GetGameTimer() < nextWaveAt do Wait(250) end
            nextWaveAt = 0
        end
        local resumeQueue
        if resumeWave and resumeWave > 0 then
            -- Reprise après changement d'hôte : on reprend la vague en cours
            currentWave = resumeWave
            adoptExistingZombies()
            local full = buildWaveQueue(currentWave)
            local toSpawn = math.max(0, math.min(#full, (resumeTotal or 0) - countLivingZombies()))
            resumeQueue = {}
            for i = #full - toSpawn + 1, #full do resumeQueue[#resumeQueue + 1] = full[i] end
        else
            pause(Config.Waves.startDelay)
        end
        while alive() do
            local queue
            if resumeQueue then
                queue = resumeQueue
                resumeQueue = nil
            else
                currentWave = currentWave + 1
                queue = buildWaveQueue(currentWave)
                TriggerServerEvent('adam_zombie:waveReached', currentWave)
                local terrifiers = 0
                for _, e in ipairs(queue) do if e.terrifier then terrifiers = terrifiers + 1 end end
                if Config.WaveAnnounce and Config.WaveAnnounce.enabled then
                    announceWave(currentWave, #queue, terrifiers > 0)
                else
                    notify(('~o~Vague %d~s~ : %d ennemis !'):format(currentWave, #queue))
                    if terrifiers > 0 then notify('~r~Le Terrifier approche...') end
                end
                if sharedInstance then
                    TriggerServerEvent('adam_zombie:hostBroadcast', 'announce', currentWave, #queue, terrifiers > 0)
                end
            end
            waveRemaining = #queue

            local index = 1
            while alive() and (waveRemaining > 0 or countLivingZombies() > 0) do
                if waveRemaining > 0 and countLivingZombies() < Config.Zone.maxZombies then
                    local entry = queue[index]
                    index = index + 1
                    waveRemaining = waveRemaining - 1
                    spawnEnemy(entry.model, entry)
                    Wait(Config.Waves.spawnInterval)
                else
                    Wait(400)
                end
            end
            if not alive() then break end
            notify(('~g~Vague %d terminée !'):format(currentWave))
            if sharedInstance then TriggerServerEvent('adam_zombie:hostBroadcast', 'cleared', currentWave) end
            pause(Config.Waves.betweenWaves)
        end
    end)

    -- Réassigne régulièrement la cible : le joueur le plus proche (membres du crew inclus)
    CreateThread(function()
        while alive() do
            for _, zombie in ipairs(missionPeds) do
                if DoesEntityExist(zombie) and not IsEntityDead(zombie) then
                    -- Les PNJ en réseau doivent rester sous le contrôle de l'hôte pour recevoir des ordres
                    if sharedInstance and not NetworkHasControlOfEntity(zombie) then
                        NetworkRequestControlOfEntity(zombie)
                    end
                    local target = nearestPlayerPed(zombie)
                    if not IsPedInCombat(zombie, target) then
                        ClearPedTasks(zombie)
                        TaskCombatPed(zombie, target, 0, 16)
                        SetPedKeepTask(zombie, true)
                    end
                end
            end
            Wait(1200)
        end
    end)

    -- Zombies morts : récompense (au joueur qui a tué) puis suppression
    CreateThread(function()
        while alive() do
            for i = #missionPeds, 1, -1 do
                local z = missionPeds[i]
                if DoesEntityExist(z) and IsEntityDead(z) then
                    if not rewardedLocal[z] then
                        rewardedLocal[z] = true
                        TriggerServerEvent('adam_zombie:zombieKilled', terrifierPeds[z] == true, killerServerId(z))
                        terrifierPeds[z] = nil
                    end
                    removeDeadZombie(z)
                    if not DoesEntityExist(z) then table.remove(missionPeds, i) end
                elseif not DoesEntityExist(z) then
                    table.remove(missionPeds, i)
                end
            end
            -- Filet de sécurité (crew) : zombies morts qui traînent et ne sont plus dans la liste
            if sharedInstance then
                for _, ped in ipairs(GetGamePool('CPed')) do
                    if not IsPedAPlayer(ped) and IsEntityDead(ped) and NetworkGetEntityIsNetworked(ped)
                        and Entity(ped).state.adamZombie then
                        removeDeadZombie(ped)
                    end
                end
            end
            Wait(300)
        end
    end)
end

RegisterNetEvent('adam_zombie:joined', function(asHost, shared, wave, total)
    if eventActive then return end
    eventActive = true
    isHost = (asHost ~= false)
    sharedInstance = (shared == true)
    missionPeds = {}
    terrifierPeds = {}
    rewardedLocal = {}
    sessionId = sessionId + 1
    local sid = sessionId
    currentWave = 0
    waveRemaining = 0
    nextWaveAt = 0
    showHud()
    local c = Config.Zone.center
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoords(PlayerPedId(), c.x, c.y, c.z, false, false, false, true)
    SetEntityHeading(PlayerPedId(), 0.0)
    local collisionTimeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < collisionTimeout do
        RequestCollisionAtCoord(c.x, c.y, c.z)
        Wait(100)
    end
    if isHost then
        notify('~g~Zone zombie rejointe ! Élimine les zombies pour gagner des tickets.')
        startHostThreads(sid, 0, nil)
    else
        notify('~g~Tu as rejoint la partie de ton crew ! Mêmes vagues, mêmes zombies.')
    end
    -- Mort du joueur : revive + perte des tickets gagnés
    CreateThread(function()
        while eventActive and sid == sessionId do
            if IsEntityDead(PlayerPedId()) then handlePlayerDeath() end
            Wait(200)
        end
    end)
end)

-- Un autre membre du crew est l'hôte : on reçoit l'état des vagues pour le HUD
RegisterNetEvent('adam_zombie:syncState', function(wave, remaining, pause, nextIn)
    if not eventActive or isHost then return end
    currentWave = tonumber(wave) or 0
    SendNUIMessage({
        action = 'emitNEWSUI',
        data = {
            applicationName = 'zombiehud',
            event = 'update',
            wave = currentWave,
            remaining = tonumber(remaining) or 0,
            pause = pause == true,
            nextWaveIn = tonumber(nextIn) or 0
        }
    })
end)

RegisterNetEvent('adam_zombie:crewBroadcast', function(kind, a, b, c)
    if not eventActive or isHost then return end
    if kind == 'announce' then
        if Config.WaveAnnounce and Config.WaveAnnounce.enabled then
            announceWave(tonumber(a) or 0, tonumber(b) or 0, c == true)
        else
            notify(('~o~Vague %d~s~ : %d ennemis !'):format(tonumber(a) or 0, tonumber(b) or 0))
        end
    elseif kind == 'cleared' then
        notify(('~g~Vague %d terminée !'):format(tonumber(a) or 0))
    end
end)

-- L'hôte est parti : ce client reprend les vagues là où elles en étaient
RegisterNetEvent('adam_zombie:becomeHost', function(wave, total)
    if not eventActive or isHost then return end
    isHost = true
    notify('~y~L’hôte est parti : tu gères maintenant les vagues du crew.')
    startHostThreads(sessionId, tonumber(wave) or 0, tonumber(total) or 0)
end)

RegisterNetEvent('adam_zombie:reward', function(tickets, rare)
    notify(('~g~+%d ticket(s) Halloween !'):format(tickets))
    if rare then notify('~y~Butin rare obtenu : weapon_machinpistol !') end
end)

RegisterNetEvent('adam_zombie:denied', function(msg)
    notify('~r~' .. (msg or 'Action refusée.'))
end)

RegisterNetEvent('adam_zombie:teleportBack', function()
    local c = Config.Zone.returnCoords
    SetEntityCoords(PlayerPedId(), c.x, c.y, c.z, false, false, false, true)
    SetEntityHeading(PlayerPedId(), c.w)
end)

local function releaseZombies()
    clearAllBlips()
    if not sharedInstance then
        for _, z in ipairs(missionPeds) do
            if DoesEntityExist(z) then
                SetEntityAsMissionEntity(z, true, true)
                DeleteEntity(z)
            end
        end
    end
    missionPeds = {}
    terrifierPeds = {}
    rewardedLocal = {}
end

RegisterNetEvent('adam_zombie:forceStop', function()
    eventActive = false
    hideHud()
    releaseZombies()
    sharedInstance = false
    isHost = true
end)

RegisterNetEvent('adam_zombie:leaveClient', function()
    if not eventActive then return end
    eventActive = false
    hideHud()
    releaseZombies()
    sharedInstance = false
    isHost = true
    TriggerServerEvent('adam_zombie:leave')
    TriggerEvent('adam_zombie:teleportBack')
    notify('Tu as quitté la zone zombie.')
end)

CreateThread(function()
    math.randomseed(GetGameTimer())
    spawnContactPed()
    while true do
        local wait = 1000
        if DoesEntityExist(pedEntity) then
            local p = GetEntityCoords(PlayerPedId())
            local c = GetEntityCoords(pedEntity)
            local dist = #(p - c)
            if dist < Config.PedDrawDistance then
                wait = 0
                if dist < Config.InteractDistance then
                    helpText('Appuie sur ~INPUT_CONTEXT~ pour parler au zombie')
                    if IsControlJustReleased(0, 38) and not menuOpen then openMenu() end
                end
            end
        else
            spawnContactPed()
        end
        Wait(wait)
    end
end)

CreateThread(function()
    local lastSync = 0
    while true do
        if eventActive and isHost then
            local pause = nextWaveAt > 0
            local remaining = waveRemaining + countLivingZombies()
            local nextIn = pause and math.max(0, math.ceil((nextWaveAt - GetGameTimer()) / 1000)) or 0
            SendNUIMessage({
                action = 'emitNEWSUI',
                data = {
                    applicationName = 'zombiehud',
                    event = 'update',
                    wave = currentWave,
                    remaining = remaining,
                    pause = pause,
                    nextWaveIn = nextIn
                }
            })
            -- Crew : l'hôte partage l'état des vagues avec les autres membres
            if sharedInstance and GetGameTimer() - lastSync > 500 then
                lastSync = GetGameTimer()
                TriggerServerEvent('adam_zombie:hostState', currentWave, remaining, pause, nextIn)
            end
            Wait(300)
        else
            Wait(500)
        end
    end
end)

-- Quitter la zone : touche K (modifiable dans les paramètres FiveM > Raccourcis) avec confirmation
local leaveOpen = false

function closeLeaveDialog()
    if not leaveOpen then return end
    leaveOpen = false
    SendNUIMessage({ action = 'unloadNEWApplication', data = { applicationName = 'zombieleave' } })
    SetNuiFocus(false, false)
end

local function openLeaveDialog()
    if not eventActive or leaveOpen or menuOpen or configOpen then return end
    leaveOpen = true
    SendNUIMessage({ action = 'loadNEWApplication', data = { applicationName = 'zombieleave', color = '#ff6a2b' } })
    SetNuiFocus(true, true)
end

RegisterCommand('zombieleave', function()
    if eventActive then
        openLeaveDialog()
    end
end, false)
RegisterKeyMapping('zombieleave', 'Quitter la zone zombie', 'keyboard', 'K')

-- Fermeture automatique si la session se termine (mort/expulsion) pendant que la fenêtre est ouverte
CreateThread(function()
    while true do
        if leaveOpen and not eventActive then closeLeaveDialog() end
        Wait(500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    if DoesEntityExist(pedEntity) then DeleteEntity(pedEntity) end
    clearAllBlips()
    for _, z in ipairs(missionPeds) do if DoesEntityExist(z) then DeleteEntity(z) end end
end)


-- =====================================================================
--  Config en jeu (/configzombie) — le serveur vérifie le rôle fondateur
-- =====================================================================
RegisterNetEvent('adam_zombie:syncConfig', function(values)
    if type(values) ~= 'table' then return end
    for path, v in pairs(values) do ZConfigSet(path, v) end
end)

RegisterNetEvent('adam_zombie:openConfig', function(fields, values, refresh)
    if menuOpen and not refresh then return end
    configOpen = true
    SendNUIMessage({
        action = 'loadNEWApplication',
        data = { applicationName = 'zombieconfig', fields = fields, values = values, color = '#ff6a2b' }
    })
    SetNuiFocus(true, true)
    TriggerServerEvent('adam_zombie:crewAdminList')
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('adam_zombie:requestConfig')
end)

-- =====================================================================
--  Munitions illimitées dans la zone zombie
-- =====================================================================
local ammoTouched = {}

local function resetInfiniteAmmo()
    local ped = PlayerPedId()
    SetPedInfiniteAmmoClip(ped, false)
    for w in pairs(ammoTouched) do SetPedInfiniteAmmo(ped, false, w) end
    ammoTouched = {}
end

CreateThread(function()
    local wasActive = false
    while true do
        local active = eventActive and Config.InfiniteAmmo
        if active then
            -- Même méthode que le gunfight, mais réappliquée à chaque frame
            -- (le flag saute au changement d'arme, au respawn ou si un autre script le remet à zéro).
            local ped = PlayerPedId()
            SetPedInfiniteAmmoClip(ped, true)
            DisableControlAction(0, 45, true) -- pas de rechargement (donc aucune balle réclamée à l'inventaire)
            local has, weapon = GetCurrentPedWeapon(ped, true)
            if has and weapon ~= 0 and weapon ~= `WEAPON_UNARMED` then
                local okMax, maxAmmo = GetMaxAmmo(ped, weapon)
                if okMax then
                    SetPedInfiniteAmmo(ped, true, weapon)
                    local ammoType = GetPedAmmoTypeFromWeapon(ped, weapon)
                    if ammoType and ammoType ~= 0 then SetPedAmmoByType(ped, ammoType, 9999) end
                    ammoTouched[weapon] = true
                    -- Garde toujours des balles dans l'arme ET dans le chargeur
                    -- (certains systèmes d'inventaire bloquent le tir à 0 balle).
                    if GetAmmoInPedWeapon(ped, weapon) < 100 then
                        SetPedAmmo(ped, weapon, math.max(maxAmmo or 0, 250))
                    end
                    local okClip, clip = GetAmmoInClip(ped, weapon)
                    local clipMax = GetMaxAmmoInClip(ped, weapon, true)
                    if okClip and clipMax and clipMax > 0 and clip < clipMax then
                        SetAmmoInClip(ped, weapon, clipMax)
                    end
                end
            end
            wasActive = true
            Wait(0)
        else
            if wasActive then
                resetInfiniteAmmo()
                wasActive = false
            end
            Wait(500)
        end
    end
end)

RegisterNetEvent('adam_zombie:leaderboardData', function(boards, champion)
    if not menuOpen then return end
    SendNUIMessage({
        action = 'emitNEWSUI',
        data = { applicationName = 'zombiezone', event = 'leaderboard', boards = boards or {}, champion = champion }
    })
end)

-- ---------- Crews ----------
RegisterNetEvent('adam_zombie:crewView', function(view)
    if not menuOpen then return end
    SendNUIMessage({ action = 'emitNEWSUI', data = { applicationName = 'zombiezone', event = 'crew', view = view } })
end)

RegisterNetEvent('adam_zombie:crewAdminData', function(list, price)
    if not configOpen then return end
    SendNUIMessage({ action = 'emitNEWSUI', data = { applicationName = 'zombieconfig', event = 'crews', crews = list, price = price } })
end)

-- /crew : ouvre directement le menu sur l'onglet crew
RegisterCommand('crew', function()
    if menuOpen or configOpen then return end
    openMenu('crew')
end, false)


-- =====================================================================
--  Crew : impossible de tirer sur un mate (viseur sur un joueur de l'instance)
-- =====================================================================
local function camDirection()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local cosX = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * cosX, math.cos(rz) * cosX, math.sin(rx))
end

-- Un autre joueur est-il pile sous le viseur ? (visée libre OU tir "à la hanche")
local function mateUnderCrosshair(ped)
    local pid = PlayerId()
    local isAim, ent = GetEntityPlayerIsFreeAimingAt(pid)
    if isAim and ent and ent ~= 0 and ent ~= ped and IsEntityAPed(ent) and IsPedAPlayer(ent) then
        return true
    end
    local origin = GetGameplayCamCoord()
    local dest = origin + camDirection() * 150.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, dest.x, dest.y, dest.z, -1, ped, 7)
    local _, hit, _, _, hitEnt = GetShapeTestResult(ray)
    return hit == 1 and hitEnt ~= 0 and hitEnt ~= ped and IsEntityAPed(hitEnt) and IsPedAPlayer(hitEnt)
end

CreateThread(function()
    local othersPresent, lastCheck = false, 0
    while true do
        if eventActive then
            local now = GetGameTimer()
            if now - lastCheck > 500 then
                lastCheck = now
                othersPresent = #GetActivePlayers() > 1
            end
            if othersPresent then
                local ped = PlayerPedId()
                local pid = PlayerId()
                if IsPlayerFreeAiming(pid) or IsControlPressed(0, 24) or IsDisabledControlPressed(0, 24)
                    or IsControlPressed(0, 140) or IsControlPressed(0, 141) or IsControlPressed(0, 142) then
                    if mateUnderCrosshair(ped) then
                        DisablePlayerFiring(pid, true)
                        for _, ctrl in ipairs({ 24, 257, 140, 141, 142, 263, 264, 69, 70, 92 }) do
                            DisableControlAction(0, ctrl, true)
                        end
                    end
                end
                Wait(0)
            else
                Wait(250)
            end
        else
            Wait(500)
        end
    end
end)

-- =====================================================================
--  Crew : blips des zombies créés par l'hôte (visibles par tous les membres)
-- =====================================================================
CreateThread(function()
    while true do
        if eventActive and sharedInstance then
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) and not IsEntityDead(ped) then
                    local st = Entity(ped).state.adamZombie
                    if st then
                        local blip = GetBlipFromEntity(ped)
                        if not blip or blip == 0 or not DoesBlipExist(blip) then
                            addEnemyBlip(ped, st == 2)
                        end
                    end
                end
            end
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)


-- =====================================================================
--  /configzombie : nombre de joueurs en mode zombie (rafraîchi toutes les 3 s)
-- =====================================================================
RegisterNetEvent('adam_zombie:zoneCount', function(count, games)
    if not configOpen then return end
    SendNUIMessage({
        action = 'emitNEWSUI',
        data = { applicationName = 'zombieconfig', event = 'online', count = count, games = games }
    })
end)

CreateThread(function()
    while true do
        if configOpen then
            TriggerServerEvent('adam_zombie:zoneCountRequest')
            Wait(3000)
        else
            Wait(1000)
        end
    end
end)


-- =====================================================================
--  Concours : chrono (HUD, menu zone, /configzombie) et gagnant (fondateurs)
-- =====================================================================
RegisterNetEvent('adam_zombie:contestData', function(info)
    if type(info) ~= 'table' then return end
    local function push(app, withWinner)
        SendNUIMessage({
            action = 'emitNEWSUI',
            data = {
                applicationName = app, event = 'contest',
                enabled = info.enabled == true, ended = info.ended == true,
                secondsLeft = info.secondsLeft or 0,
                winner = withWinner and info.winner or nil, final = info.final == true
            }
        })
    end
    push('zombiehud')
    if menuOpen then push('zombiezone') end
    if configOpen then push('zombieconfig', true) end
end)

CreateThread(function()
    local last, wasActive = 0, false
    while true do
        local active = eventActive or menuOpen or configOpen
        if active and not wasActive then last = 0 end
        wasActive = active
        if active then
            local now = GetGameTimer()
            local every = (menuOpen or configOpen) and 5000 or 30000
            if now - last >= every then
                last = now
                TriggerServerEvent('adam_zombie:contestRequest')
            end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)
