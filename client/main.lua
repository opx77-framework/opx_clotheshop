-- opx_clotheshop client: the help line and the key at the points, the map pins, the clothing menu. It only
-- asks; the server decides (point, position, job, money) and opens the creator.

local OPX = assert(require('@opx_core'))
local Ui = assert(require('client.modules.ui'))

local MAPPING = 'opx_clotheshop.open'
local inside = nil -- the point the player stands at (help line shown), or nil
local blips = {}   -- Open77.blips ids of the point pins

-- Calls the HUD provider (opx_core Config.providers.hud) under pcall: it may be absent or lack ShowHelp.
local function hud(name, ...)
	local provider = OPX.GetProvider('hud')
	if not provider then return end
	pcall(Open77.exports.callSync, provider, name, ...)
end

local function number(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

local function points()
	return type(Config.points) == 'table' and Config.points or {}
end

local function valid(point)
	return type(point) == 'table' and type(point.name) == 'string' and type(point.type) == 'string'
		and number(point.x) and number(point.y) and number(point.z)
end

local function nearPoint()
	local x, y, z = Open77.character.position()
	if not number(x) or not number(y) or not number(z) then return nil end
	for _, point in ipairs(points()) do
		if valid(point) then
			local dx, dy, r = x - point.x, y - point.y, tonumber(point.radius) or 2.5
			if dx * dx + dy * dy <= r * r and math.abs(z - point.z) <= Config.heightTolerance then return point end
		end
	end
	return nil
end

-- Map pins -----------------------------------------------------------------------------------------

local function clearBlips()
	for _, id in ipairs(blips) do pcall(Open77.blips.remove, id) end
	blips = {}
end

local function createBlips()
	clearBlips()
	if not Config.blips then return end
	local sprites = type(Config.blipSprites) == 'table' and Config.blipSprites or {}
	for _, point in ipairs(points()) do
		if valid(point) then
			local ok, id, reason = pcall(Open77.blips.create, {
				position = { x = point.x, y = point.y, z = point.z },
				sprite = sprites[point.type] or sprites.default or 'ServicePointClothesVariant',
				title = type(point.label) == 'string' and point.label or Ui.text('title'),
				description = Ui.typed('blip', point.type),
			})
			if ok and id then
				blips[#blips + 1] = id
			else
				print(('[opx_clotheshop] map pin refused: %s'):format(tostring(ok and reason or id)))
			end
		end
	end
end

OPX.OnPlayerLoaded(function() createBlips() end)
OPX.OnPlayerUnloaded(function()
	clearBlips()
	Ui.close()
end)

-- Cash and bank shown in the menu follow opx_core.
OPX.OnPlayerData(function(key)
	if key == 'accounts' then Ui.refreshBalances() end
end)

-- Key and help line -------------------------------------------------------------------------------

CreateThread(function()
	local ok, reason = RegisterKeyMapping(MAPPING, Ui.text('key_name'), Config.key or 'E', function()
		if inside and OPX.IsLoaded() and not Ui.isOpen() then TriggerServerEvent('opx_clotheshop:open', inside.name) end
	end)
	if not ok then print(('[opx_clotheshop] key mapping refused: %s'):format(tostring(reason))) end

	while true do
		local now = OPX.IsLoaded() and nearPoint() or nil
		if now and now ~= inside then
			hud('ShowHelp', Ui.typed('help', now.type), Open77.input.keyFor(MAPPING) or Config.key)
		elseif inside and not now then
			hud('HideHelp')
			Ui.closeIfPoint() -- walked away: the server would refuse the fitting anyway
		end
		inside = now
		Wait(inside and 250 or 750)
	end
end)

RegisterNetEvent('opx_clotheshop:menu', function(data) Ui.show(data) end)
RegisterNetEvent('opx_clotheshop:notify', function(key, kind, params) Ui.notify(key, kind, params) end)
