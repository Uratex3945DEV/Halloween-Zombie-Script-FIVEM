local function loadScaleform(scaleform)
    local handle = RequestScaleformMovie(scaleform)
    local t = GetGameTimer()
    while not HasScaleformMovieLoaded(handle) do
        Wait(0)
        if GetGameTimer() - t > 5000 then print('^1[Zombie Leaderboard]^0 Scaleform toujours pas chargé après 5 s...') t = GetGameTimer() end
    end
    return handle
end

local scale = (Config.screen and Config.screen.scale) or 0.20
local sfName = 'generic_texture_renderer'
local width, height = 1920, 1080
local sfHandle, duiObj
local pos = (Config.screen and Config.screen.pos) or vec3(241.7611, -891.0092, 35.19)
local rotZ = (Config.screen and Config.screen.rotZ) or 19.5
local variant = (Config.screen and Config.screen.variant) or 'A'
local drawDist = (Config.screen and Config.screen.drawDistance) or 100.0

-- Variantes de rendu du scaleform 3D (le bon réglage dépend du serveur/build)
local VARIANTS = {
    A = { rotX = 0.0, rotY = 180.0, p = { 0.0, 0.0, 0.0 } }, -- d'origine
    B = { rotX = 0.0, rotY = 0.0,   p = { 2.0, 2.0, 1.0 } },
    C = { rotX = 0.0, rotY = 180.0, p = { 2.0, 2.0, 1.0 } },
    D = { rotX = 0.0, rotY = 0.0,   p = { 0.0, 0.0, 0.0 } },
}

local function drawBoard(v, x, y, z, rz)
    local d = VARIANTS[v] or VARIANTS.A
    DrawScaleformMovie_3dNonAdditive(
        sfHandle,
        x, y, z,
        d.rotX, d.rotY, rz,
        d.p[1], d.p[2], d.p[3],
        scale * 1.5, scale * (25/35),
        5.0, 2
    )
end

local testMode = false

local duiReady = false  -- la page HTML est chargée et peut recevoir des messages
local latest = nil      -- derniers classements reçus du serveur
local latestChampion = nil -- dernier top 1 global reçu du serveur

if not Config then
    print("^1[Leaderboard]^0 Config introuvable : vérifie que fxmanifest.lua contient shared_script 'config.lua'")
    Config = { accentColor = '#ef233c', boards = {} }
end

-- Classements vides construits depuis la config : les cartes s'affichent
-- tout de suite, même si le serveur n'a pas (encore) répondu.
local function emptyBoards()
    local list = {}
    for _, b in ipairs(Config.boards or {}) do
        list[#list + 1] = { id = b.id, title = b.title, stat = b.stat, rows = {} }
    end
    return list
end

-- Envoie les classements à la DUI (si elle est prête)
local function pushData()
    if not duiReady then return end
    SendDuiMessage(duiObj, json.encode({
        type = "updateLeaderboard",
        color = Config.accentColor,
        boards = latest or emptyBoards(),
        champion = latestChampion,
    }))
end

-- Le serveur diffuse les classements dès qu'ils changent
RegisterNetEvent('adam_zombi_lb:update', function(boards, champion)
    print(("^2[Leaderboard]^0 Classements reçus du serveur : %d"):format(type(boards) == 'table' and #boards or 0))
    latest = boards
    latestChampion = champion
    pushData()
end)

CreateThread(function()
    print("^2[Leaderboard]^0 Chargement du scaleform " .. sfName)
    sfHandle = loadScaleform(sfName)
    print("^2[Leaderboard]^0 Scaleform chargé: " .. tostring(sfHandle))

    local duiUrl = "nui://" .. GetCurrentResourceName() .. "/dist/index.html"
    print("^2[Leaderboard]^0 Création DUI à l'adresse: " .. duiUrl)

    duiObj = CreateDui(duiUrl, width, height)
    while not IsDuiAvailable(duiObj) do Wait(0) end -- la DUI doit exister avant de l'utiliser
    local dui = GetDuiHandle(duiObj)
    local txd = CreateRuntimeTxd('zlb_txd')
    CreateRuntimeTextureFromDuiHandle(txd, 'zlb_tex', dui)

    PushScaleformMovieFunction(sfHandle, 'SET_TEXTURE')
    PushScaleformMovieMethodParameterString('zlb_txd')
    PushScaleformMovieMethodParameterString('zlb_tex')
    PushScaleformMovieFunctionParameterInt(0)
    PushScaleformMovieFunctionParameterInt(0)
    PushScaleformMovieFunctionParameterInt(width)
    PushScaleformMovieFunctionParameterInt(height)
    PopScaleformMovieFunctionVoid()

    Wait(500) -- laisse la page HTML finir de charger, sinon le message est perdu

    duiReady = true
    pushData()                                      -- affiche les cartes (vides ou déjà remplies)
    TriggerServerEvent('adam_zombi_lb:request') -- puis on demande l'état actuel au serveur

    while true do
        local sleep = 500

        -- On force l'affichage pour le debug si on est proche, même si inSafe est buggé
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local dist = #(coords - pos)

        if testMode then
            -- Mode test : 4 variantes alignées devant le joueur (A B C D), il suffit de voir lesquelles s'affichent
            sleep = 0
            local right = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0)
            local heading = GetEntityHeading(ped)
            for i, key in ipairs({ 'A', 'B', 'C', 'D' }) do
                local o = GetOffsetFromEntityInWorldCoords(ped, (i - 2.5) * 5.0, 12.0, 1.5)
                drawBoard(key, o.x, o.y, o.z, heading)
                SetDrawOrigin(o.x, o.y, o.z + 3.0, 0)
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName('~r~' .. key)
                SetTextScale(1.2, 1.2)
                SetTextCentre(true)
                EndTextCommandDisplayText(0.0, 0.0)
                ClearDrawOrigin()
            end
        elseif dist < drawDist then
            sleep = 0
            drawBoard(variant, pos.x, pos.y, pos.z, rotZ)
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if duiObj then DestroyDui(duiObj) end
    if sfHandle then SetScaleformMovieAsNoLongerNeeded(sfHandle) end
end)

-- ---------- Aide au réglage (en jeu, sans restart) ----------
-- /zlbtest        : affiche 4 variantes (A B C D) devant toi : dis-moi lesquelles tu vois
-- /zlbvariant X   : choisit la variante (A, B, C ou D)
-- /zlbhere        : place le classement 4 m devant toi
-- /zlbrot <angle> : change l'angle Z
-- /zlbpos         : affiche la config à copier dans config.lua (console F8)
RegisterCommand('zlbtest', function()
    testMode = not testMode
    print(('^3[Zombie Leaderboard]^0 Test %s | scaleform=%s dui=%s prêt=%s'):format(testMode and 'ON (regarde devant toi, 12 m)' or 'OFF', tostring(sfHandle), tostring(duiObj), tostring(duiReady)))
end, false)

RegisterCommand('zlbvariant', function(_, args)
    local v = args[1] and args[1]:upper()
    if not VARIANTS[v or ''] then print('^1[Zombie Leaderboard]^0 Usage : /zlbvariant A|B|C|D') return end
    variant = v
    print('^3[Zombie Leaderboard]^0 Variante = ' .. v)
end, false)

RegisterCommand('zlbhere', function()
    local ped = PlayerPedId()
    local c = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.0, 1.2)
    pos = vec3(c.x, c.y, c.z)
    rotZ = GetEntityHeading(ped)
    print(('^3[Zombie Leaderboard]^0 Écran placé devant toi (angle Z = %.1f)'):format(rotZ))
end, false)

RegisterCommand('zlbrot', function(_, args)
    local a = tonumber(args[1])
    if not a then print('^1[Zombie Leaderboard]^0 Usage : /zlbrot <angle>') return end
    rotZ = a + 0.0
end, false)

RegisterCommand('zlbpos', function()
    print(('^3[Zombie Leaderboard]^0 À copier dans Config.screen :\n    pos     = vec3(%.4f, %.4f, %.4f),\n    rotZ    = %.1f,\n    variant = \'%s\','):format(pos.x, pos.y, pos.z, rotZ, variant))
end, false)
