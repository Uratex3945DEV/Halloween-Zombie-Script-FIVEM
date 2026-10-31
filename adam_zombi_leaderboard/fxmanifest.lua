fx_version 'cerulean'
game 'gta5'
lua54 'yes'

dependency 'oxmysql'

files {
    'dist/index.html',
    'dist/leaderboard/*',
    'dist/fonts/*'
}

dependency 'SpinFramework'
shared_scripts {
    '@SpinFramework/api/spin.lua',
    'config.lua'
}

client_scripts {
    'client/leaderboard.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}