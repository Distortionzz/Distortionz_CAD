fx_version 'cerulean'
game 'gta5'

author 'Distortionz'
description 'Distortionz CAD - Computer-Aided Dispatch / MDT for Qbox. Citizen & vehicle search, criminal records, warrants, BOLOs, incident reports, live dispatch + unit status. Central hub other scripts feed alerts into.'
version '1.6.1'
repository 'https://github.com/Distortionzz/Distortionz_CAD'

lua54 'yes'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'version_check.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql'
}
