resource "opx_clotheshop"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

-- OPX//77 clothing shops and barbers: points where a character opens the creator in one scope (clothing,
-- barber, surgery, tattoo) and pays on Confirm. The creator and the skin provider are reached through opx_core
-- (OpenCreator, GetProvider('skin')), never named. Money is opx_core's. No table of its own.
-- opx_menu is a dependency because require('@opx_menu') only loads a declared, running one.
dependencies {
    "opx_core",
    "opx_menu",
}

permissions {
    "network.events",    -- both: requests to the server, menu and answers to the client
    "players.life.read", -- server: Open77.players.isDead (a dead player cannot shop)
    "input.actions",     -- client: RegisterKeyMapping / Open77.input.keyFor (the open key)
    "ui.vanilla.map",    -- client: Open77.blips (map pins, Config.blips)
    "http.request", -- server: Open77.http.get (update check, Config.versionCheck)
}

shared_script "config.lua"

server_script "server/main.lua"
server_script "server/version.lua"

client_script "client/main.lua"

files {
    "client/modules/*.lua",
    "locales/*.json",
}
