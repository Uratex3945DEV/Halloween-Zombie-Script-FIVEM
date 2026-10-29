local eventActive = false
local missionPeds = {}
local pedEntity = nil
local menuOpen = false
local rewardedLocal = {}
local sessionId = 0
local currentWave = 0
local waveRemaining = 0 -- ennemis de la vague pas encore apparus
local nextWaveAt = 0

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

local function openMenu()
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
            color = '#ff6a2b'
        }
    })
    SetNuiFocus(true, true)
end

-- Callback unique UI -> Lua (liste blanche : aucun évènement arbitraire n'est relayé)
RegisterNUICallback('eventNEWUI', function(data, cb)
    local name = data and data.event and data.event.name
    if name == 'ui:new:focus' then
        SetNuiFocus(true, true)
    elseif name == 'ui:new:unfocus' then
        menuOpen = false
        SetNuiFocus(false, false)
    elseif name == 'ui:onUnloadApplication' then
        menuOpen = false
    elseif name == 'adam_zombie:join' then
        menuOpen = false
        SetNuiFocus(false, false)
        if not eventActive then TriggerServerEvent('adam_zombie:requestJoin') end
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

local function spawnEnemy(model, opts)
    opts = opts or {}
    if not eventActive then return false end
    local hash = loadModel(model)
    if not hash then
        print(('[adam_zombie_halloween] Modèle impossible à charger : %s'):format(tostring(model)))
        return false
    end
    local c = randomSpawn()
    -- Création locale pour que la horde se comporte de façon cohérente côté joueur.
    local zombie = CreatePed(4, hash, c.x, c.y, c.z, math.random(0, 359) + 0.0, false, true)
    if not DoesEntityExist(zombie) then
        SetModelAsNoLongerNeeded(hash)
        return false
    end
    local health = opts.health or 250
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
    SetPedMoveRateOverride(zombie, opts.moveRate or 1.20)
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
    addEnemyBlip(zombie, opts.terrifier)
    TaskCombatPed(zombie, PlayerPedId(), 0, 16)
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

RegisterNetEvent('adam_zombie:joined', function()
    if eventActive then return end
    eventActive = true
    missionPeds = {}
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
    notify('~g~Zone zombie rejointe ! Élimine les zombies pour gagner des tickets.')
    -- Système de vagues
    CreateThread(function()
        local function alive() return eventActive and sid == sessionId end
        local function pause(ms)
            nextWaveAt = GetGameTimer() + ms
            while alive() and GetGameTimer() < nextWaveAt do Wait(250) end
            nextWaveAt = 0
        end
        pause(Config.Waves.startDelay)
        while alive() do
            currentWave = currentWave + 1
            local queue = buildWaveQueue(currentWave)
            local terrifiers = 0
            for _, e in ipairs(queue) do if e.terrifier then terrifiers = terrifiers + 1 end end
            waveRemaining = #queue
            if Config.WaveAnnounce and Config.WaveAnnounce.enabled then
                announceWave(currentWave, #queue, terrifiers > 0)
            else
                notify(('~o~Vague %d~s~ : %d ennemis !'):format(currentWave, #queue))
                if terrifiers > 0 then notify('~r~Le Terrifier approche...') end
            end

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
            pause(Config.Waves.betweenWaves)
        end
    end)
    -- Mort du joueur : revive + perte des tickets gagnés
    CreateThread(function()
        while eventActive and sid == sessionId do
            if IsEntityDead(PlayerPedId()) then handlePlayerDeath() end
            Wait(200)
        end
    end)
    -- Réassigne régulièrement la cible : certains modèles abandonnent sinon le combat.
    CreateThread(function()
        while eventActive do
            local player = PlayerPedId()
            for _, zombie in ipairs(missionPeds) do
                if DoesEntityExist(zombie) and not IsEntityDead(zombie) and not IsPedInCombat(zombie, player) then
                    ClearPedTasks(zombie)
                    TaskCombatPed(zombie, player, 0, 16)
                    SetPedKeepTask(zombie, true)
                end
            end
            Wait(1200)
        end
    end)
    CreateThread(function()
        while eventActive do
            for i = #missionPeds, 1, -1 do
                local z = missionPeds[i]
                if DoesEntityExist(z) and IsEntityDead(z) then
                    if not rewardedLocal[z] then
                        rewardedLocal[z] = true
                        TriggerServerEvent('adam_zombie:zombieKilled')
                    end
                    removeEnemyBlip(z)
                    SetEntityAsMissionEntity(z, true, true)
                    DeleteEntity(z)
                    table.remove(missionPeds, i)
                elseif not DoesEntityExist(z) then
                    table.remove(missionPeds, i)
                end
            end
            Wait(300)
        end
    end)
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

RegisterNetEvent('adam_zombie:forceStop', function()
    eventActive = false
    hideHud()
    clearAllBlips()
    for _, z in ipairs(missionPeds) do
        if DoesEntityExist(z) then DeleteEntity(z) end
    end
    missionPeds = {}
end)

RegisterNetEvent('adam_zombie:leaveClient', function()
    if not eventActive then return end
    eventActive = false
    hideHud()
    clearAllBlips()
    for _, z in ipairs(missionPeds) do
        if DoesEntityExist(z) then
            SetEntityAsMissionEntity(z, true, true)
            DeleteEntity(z)
        end
    end
    missionPeds = {}
    rewardedLocal = {}
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
    while true do
        if eventActive then
            local pause = nextWaveAt > 0
            SendNUIMessage({
                action = 'emitNEWSUI',
                data = {
                    applicationName = 'zombiehud',
                    event = 'update',
                    wave = currentWave,
                    remaining = waveRemaining + countLivingZombies(),
                    pause = pause,
                    nextWaveIn = pause and math.max(0, math.ceil((nextWaveAt - GetGameTimer()) / 1000)) or 0
                }
            })
            Wait(300)
        else
            Wait(500)
        end
    end
end)

RegisterCommand('zombie', function()
    if eventActive then
        TriggerEvent('adam_zombie:leaveClient')
    else
        notify('Tu n’es pas dans la zone zombie.')
    end
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    if DoesEntityExist(pedEntity) then DeleteEntity(pedEntity) end
    clearAllBlips()
    for _, z in ipairs(missionPeds) do if DoesEntityExist(z) then DeleteEntity(z) end end
end)
