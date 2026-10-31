fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Adam'
description 'Zone Zombie Halloween - instance 238, PvP bloqué et zombies agressifs'
version '1.2.0'
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'html/fonts/*', 'html/sounds/*' }
dependencies { 'SpinFramework', 'oxmysql' }
shared_scripts {
    '@SpinFramework/api/spin.lua',
    'config.lua'
}
client_script 'client.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}
