---@meta

-- opx_clotheshop server exports and events. Not loaded by the manifest (LuaLS annotations only).
-- A replacement keeps these names and shapes. No table: a pending payment lives in memory only.
-- Both exports are SYNCHRONOUS: nothing waits. Call them as exports.opx_clotheshop:Name(...) or
-- Open77.exports.callSync('opx_clotheshop', 'Name', ...).
--
-- How a point works (the reference caller of the creator scopes, see opx_creator README):
-- 1. The money check comes first: a priced point refuses 'insufficient_funds' before anything opens.
-- 2. exports.opx_core:OpenCreator(source, { mode = 'edit', scope = point.type, tag = 'clotheshop:<name>',
--    title = point.label, confirmLabel = 'Pay €$ 150' (translated by the player's client) }).
-- 3. opx:creator:saved for that session (info.opener == 'opx_clotheshop', info.tag) with something changed
--    (info.changed.body or a non-empty info.changed.clothing; a creator without info.changed counts as a
--    change): the price is taken from the first account of Config.payFrom that holds it whole
--    (opx_core reason 'clotheshop:<name>'), the society is credited, opx:clotheshop:paid is raised.
-- 4. opx:creator:closed (cancelled, unchanged, dropped...): nothing was stored, nothing is paid.
-- Clothing is stored only at Confirm (the skin provider previews with a temporary outfit), so charging on saved
-- is safe. Body scopes (barber, surgery, tattoo) keep the creator's known limitation: a body preview is
-- published while editing, so a player who disconnects mid-edit keeps it unpaid.
-- If the money is gone at Confirm (it was checked at opening), the look stays and the server prints UNPAID.
-- A creator left open while opx_clotheshop restarts is not charged (the pending payment was in memory).
--
-- Members used: opx_core GetPlayer, GetProvider ('creator' via OpenCreator, 'skin'), OpenCreator, HasMoney,
-- RemoveMoney, AddSocietyMoney; skin provider OpenOutfits(source, { title }) (optional, "My outfits").

---@class OpxClotheshopPoint
---@field name string unique id ([a-z0-9_], 1..48)
---@field type string the creator scope opened there: 'clothing'|'barber'|'surgery'|'tattoo'|your own
---@field label string
---@field price integer taken at Confirm when something changed; 0 = free
---@field x number
---@field y number
---@field z number
---@field radius number metres (horizontal)
---@field bucket integer routing bucket
---@field society string|false registered job whose society receives the payments
---@field jobs table<string, integer>|false job name -> minimum grade; false = everybody

---@alias OpxClotheshopError
---| 'invalid_player' source is not a player id (or has no position)
---| 'unknown_point' no point with that name
---| 'not_loaded' no character loaded
---| 'dead' the player is down
---| 'not_allowed' the point's job rule refuses the character

---@class OpxClotheshopExports
local opx_clotheshop = {}

--- SYNC. Copies of the valid points, in config order (invalid rows are left out and logged at start).
---@return OpxClotheshopPoint[]
function opx_clotheshop.GetPoints() end

--- SYNC. Opens a point for a player without the point check (your own vendor NPC or target option): the
--- clothing menu, or the creator at once for other types. The job rule and the price still apply. The fitting
--- is accepted within Config.sessionDistance (4 m) of where the player stood, in the same routing bucket;
--- the session ends on unload, disconnect, or when the calling resource stops.
---@param source integer
---@param name string point name
---@return boolean ok
---@return OpxClotheshopError|nil reason
function opx_clotheshop.OpenPoint(source, name) end

-- Server host event (AddEventHandler), raised after every completed purchase (price 0 included):
-- TriggerEvent('opx:clotheshop:paid', source, pointName, type, price)
---@alias OpxClotheshopPaidEvent fun(source: integer, point: string, type: string, price: integer)

-- Net events (internal): client -> server opx_clotheshop:open (name), opx_clotheshop:fit (name, confirmLabel?),
-- opx_clotheshop:outfits (name); server -> client opx_clotheshop:menu ({ name, label, type, price, outfits,
-- session }), opx_clotheshop:notify (key, kind, params).
