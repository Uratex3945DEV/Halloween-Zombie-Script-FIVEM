Config = {}

-- Couleur d'accent du leaderboard (envoyée à la DUI)
Config.accentColor = '#ef233c'

-- Intégration ESX : le classement utilise l'identifiant ESX du joueur (xPlayer.identifier)
-- et son nom RP (xPlayer.getName()). Si l'objet ESX est introuvable, on retombe sur
-- la licence Rockstar + le nom FiveM.
-- resource / export = ressource et export qui renvoient l'objet ESX
-- (équivalent de exports['es_extended']:getSharedObject() chez toi).
Config.esx = {
    enabled  = true,
    resource = 'es_extended',
    export   = 'getSharedObject',
}

-- Rôles autorisés à utiliser /lbreset (groupe, job ou grade ESX/Spin)
Config.adminRoles = { 'fondateur' }

-- Position de l'écran 3D (par défaut : au-dessus du PNJ de la zone zombie)
-- Règle-la en jeu avec /zlbhere, /zlbrot, /zlbvariant puis /zlbpos pour récupérer les valeurs.
Config.screen = {
    pos     = vec3(241.7611, -891.0092, 30.4921 + 4.7),
    rotZ    = 19.5,
    variant = 'A',
    scale   = 0.20,
    drawDistance = 100.0
}

-- Nombre de joueurs affichés par classement (10 tient dans 1080p)
Config.topCount = 10

-- Délai minimum (secondes) entre deux mises à jour envoyées aux joueurs.
-- Les classements ne sont recalculés/diffusés que si quelqu'un a marqué un kill.
Config.refreshDelay = 15

-- Classements affichés (dans cet ordre, de gauche à droite).
-- id  : identifiant utilisé par l'export AddStat(src, id, valeur)
-- agg : 'sum' = cumul, 'max' = meilleur score
Config.boards = {
    { id = 'zombies',   title = 'Zombies tués',    stat = 'Zombies', agg = 'sum' },
    { id = 'terrifier', title = 'Terrifier tués',  stat = 'Kills',   agg = 'sum' },
    { id = 'wave',      title = 'Meilleure vague', stat = 'Vague',   agg = 'max' },
    { id = 'tickets',   title = 'Tickets gagnés',  stat = 'Tickets', agg = 'sum' },
    -- Classement des crews : alimenté par adam_zombi (somme des kills des membres), pas par la base
    { id = 'crews',     title = 'Top Crews',       stat = 'Kills',   agg = 'sum', external = true },
}

-- Le "meilleur chasseur" de la bannière = le n°1 de ce classement
Config.championBoard = 'zombies'
Config.championLabel = 'zombies tués'
