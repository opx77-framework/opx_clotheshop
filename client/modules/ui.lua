-- The clothing menu (opx_menu) and the Confirm text of the creator. Shows and asks; the server decides (the
-- price comes from the server, the client only displays it).

local OPX = assert(require('@opx_core'))
local Menu = assert(require('@opx_menu'))

local Ui = {}

local T = OPX.Locale()
local main = nil      -- the open clothing menu, or nil
local session = false -- the open menu came from the OpenPoint export (not from a point)

-- Translated text; money params formatted the player's way.
local MONEY = { price = true, total = true, cash = true, bank = true }
function Ui.text(key, params)
	local shown = {}
	for k, v in pairs(type(params) == 'table' and params or {}) do
		shown[k] = (MONEY[k] and type(v) == 'number') and OPX.FormatMoney(v) or v
	end
	return T(key, shown)
end

-- '<prefix>_<type>' (help_barber, blip_clothing...), else '<prefix>' for a type added by the server owner.
function Ui.typed(prefix, kind)
	local key = ('%s_%s'):format(prefix, tostring(kind))
	local text = T(key)
	if text == key then return T(prefix) end
	return text
end

-- A server answer: locale key + kind + params. An unknown key reads as a generic failure.
function Ui.notify(key, kind, params)
	if type(key) ~= 'string' then return end
	local text = Ui.text(key, params)
	if text == key then text = Ui.text('failed', { reason = key }) end
	OPX.Notify(text, kind, nil, Ui.text('title'))
end

local function balances()
	return Ui.text('balances', { cash = OPX.GetMoney('money'), bank = OPX.GetMoney('bank') })
end

-- The creator's Confirm text ("Pay €$ 150"); nil when it would pass 32 bytes (the creator keeps its own).
local function confirmLabel(price)
	local text = (type(price) == 'number' and price > 0) and Ui.text('confirm_pay', { price = price })
		or Ui.text('confirm_free')
	return #text <= 32 and text or nil
end

local function fit(data)
	TriggerServerEvent('opx_clotheshop:fit', data.name, confirmLabel(data.price))
end

-- The server answered a point: { name, label, type, price, outfits, session }. A clothing point shows the menu,
-- any other type opens the creator at once.
function Ui.show(data)
	if type(data) ~= 'table' or type(data.name) ~= 'string' or type(data.type) ~= 'string' then return end
	if data.type ~= 'clothing' then return fit(data) end

	local price = type(data.price) == 'number' and data.price or 0
	local elements = {
		{ label = Ui.text('fitting'), value = 'fit', icon = 'bag', description = Ui.text('fitting_desc'),
		  rightLabel = price > 0 and OPX.FormatMoney(price) or Ui.text('free') },
	}
	if data.outfits == true then
		elements[#elements + 1] = { label = Ui.text('outfits'), value = 'outfits', icon = 'list',
			description = Ui.text('outfits_desc') }
	end
	elements[#elements + 1] = { label = Ui.text('close'), value = 'close', icon = 'close' }

	Ui.close()
	main = Menu.open({
		id = 'opx_clotheshop', title = type(data.label) == 'string' and data.label or Ui.text('title'),
		subtitle = balances(), elements = elements,
		onSelect = function(element, menu)
			menu:close()
			if element.value == 'fit' then
				fit(data)
			elseif element.value == 'outfits' then
				TriggerServerEvent('opx_clotheshop:outfits', data.name)
			end
		end,
		onClose = function(menu)
			if main == menu then main = nil end
		end,
	})
	session = data.session == true
end

function Ui.isOpen() return main ~= nil and main:isOpen() end

function Ui.close()
	if main then main:close() end
	main = nil
end

-- Walked away from a point: a menu opened there closes (one opened by another resource stays).
function Ui.closeIfPoint()
	if not session then Ui.close() end
end

-- Cash and bank changed: the subtitle follows.
function Ui.refreshBalances()
	if Ui.isOpen() then main:setTitle(main.title or Ui.text('title'), balances()) end
end

return Ui
