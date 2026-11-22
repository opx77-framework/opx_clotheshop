-- opx_clotheshop server: the validated points, where the player stands, the job rule, opening the creator in
-- the point's scope and the payment on Confirm. The creator and the skin provider come from opx_core
-- (OpenCreator, GetProvider('skin')); money is opx_core's. No table: a pending payment lives in memory only.

local RESOURCE = GetCurrentResourceName()
local CORE = 'opx_core'

local list = {}     -- validated points, in config order
local byName = {}   -- [name] = point
local lastCall = {} -- [source] = { [kind] = GetGameTimer() of his last accepted request of that kind }
local sessions = {} -- [source] = { point, x, y, z, bucket, owner, generation } opened by the OpenPoint export
local pending = {}  -- [source] = { point, type, price, society, tag, citizenId } while his creator is open

-- Helpers ----------------------------------------------------------------------------------------

local function finite(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

-- A player id from anything (positive integer within uint32), or nil. Natives abort on anything else.
local function toSource(value)
	local id = tonumber(value)
	if not id or id ~= id or id < 1 or id > 0xFFFFFFFF or id % 1 ~= 0 then return nil end
	return math.tointeger(id)
end

-- An integer in min..max, or nil (refuses NaN, inf, decimals).
local function toInt(value, min, max)
	local n = tonumber(value)
	if not finite(n) or n % 1 ~= 0 then return nil end
	n = math.tointeger(n)
	if not n or n < min or n > max then return nil end
	return n
end

local function core(name, ...)
	local ok, a, b = pcall(Open77.exports.callSync, CORE, name, ...)
	if not ok then return nil, 'core_unavailable' end
	return a, b
end

-- A short refusal code from another resource, safe to send to a client, or `fallback`.
local function reasonCode(value, fallback)
	if type(value) == 'string' and #value >= 1 and #value <= 64 and value:match('^[%w_:%.%-]+$') then return value end
	return fallback
end

-- The Confirm text the client translated: 1..32 bytes, no control character; else nil (creator default).
local function confirmText(value)
	if type(value) ~= 'string' or #value < 1 or #value > 32 or value:find('%c') then return nil end
	return value
end

-- Config -----------------------------------------------------------------------------------------

local function load()
	for i, p in ipairs(type(Config.points) == 'table' and Config.points or {}) do
		local ok = type(p) == 'table' and type(p.name) == 'string' and p.name:match('^[a-z0-9_]+$') and #p.name <= 48
			and not byName[p.name] and type(p.type) == 'string' and p.type:match('^[a-z0-9_]+$') and #p.type <= 32
			and toInt(p.price, 0, 1000000000) and finite(p.x) and finite(p.y) and finite(p.z)
			and (p.radius == nil or (finite(p.radius) and p.radius > 0))
			and (p.bucket == nil or toInt(p.bucket, 0, 0xFFFFFFFF))
			and (p.society == nil or p.society == false or type(p.society) == 'string')
			and (p.jobs == nil or p.jobs == false or type(p.jobs) == 'table')
		if not ok then
			print(('[opx_clotheshop] point row %d ignored (name, type, price, coordinates, bucket, society or jobs)'):format(i))
		else
			local jobs = nil
			if type(p.jobs) == 'table' then
				jobs = {}
				for job, grade in pairs(p.jobs) do
					if type(job) == 'string' then jobs[job] = toInt(grade, 0, 1000) or 0 end
				end
			end
			local point = {
				name = p.name, type = p.type, price = toInt(p.price, 0, 1000000000),
				label = type(p.label) == 'string' and p.label ~= '' and p.label:gsub('%c', ' '):sub(1, 64) or p.name,
				x = p.x, y = p.y, z = p.z, radius = p.radius or 2.5, bucket = toInt(p.bucket, 0, 0xFFFFFFFF) or 0,
				society = type(p.society) == 'string' and p.society or false, jobs = jobs,
			}
			list[#list + 1] = point
			byName[point.name] = point
		end
	end
end

local function copies()
	local out = {}
	for i, p in ipairs(list) do
		local jobs = false
		if p.jobs then
			jobs = {}
			for job, grade in pairs(p.jobs) do jobs[job] = grade end
		end
		out[i] = {
			name = p.name, type = p.type, label = p.label, price = p.price, x = p.x, y = p.y, z = p.z,
			radius = p.radius, bucket = p.bucket, society = p.society, jobs = jobs,
		}
	end
	return out
end

-- Player checks ----------------------------------------------------------------------------------

local function character(source)
	local data = core('GetPlayer', source)
	if type(data) ~= 'table' or type(data.citizenId) ~= 'string' then return nil end
	local job = type(data.job) == 'table' and data.job or {}
	return { citizenId = data.citizenId, job = tostring(job.name or ''), grade = tonumber(job.grade) or 0 }
end

local function position(source)
	local ok, pos = pcall(Open77.players.position, source)
	if not ok or type(pos) ~= 'table' or not finite(pos.x) or not finite(pos.y) or not finite(pos.z) then return nil end
	return pos
end

local function near(pos, x, y, z, reach, bucket)
	local dx, dy = pos.x - x, pos.y - y
	return (tonumber(pos.bucket) or 0) == bucket and dx * dx + dy * dy <= reach * reach
		and math.abs(pos.z - z) <= Config.heightTolerance + 1.0
end

-- At the point, or inside the session another resource opened for that point.
local function atPoint(source, point)
	local pos = position(source)
	if not pos then return false end
	if near(pos, point.x, point.y, point.z, point.radius + Config.serverSlack, point.bucket) then return true end
	local s = sessions[source]
	return s ~= nil and s.point == point.name and near(pos, s.x, s.y, s.z, Config.sessionDistance, s.bucket)
end

local function jobAllowed(point, char)
	if not point.jobs then return true end
	local minGrade = point.jobs[char.job]
	return minGrade ~= nil and char.grade >= minGrade
end

local function isDead(source)
	local ok, dead = pcall(Open77.players.isDead, source)
	return ok and dead == true
end

-- Every check before a menu or the creator: char | nil, reason.
local function check(source, point, skipPosition)
	if not point then return nil, 'unknown_point' end
	local char = character(source)
	if not char then return nil, 'not_loaded' end
	if isDead(source) then return nil, 'dead' end
	if not skipPosition and not atPoint(source, point) then return nil, 'not_at_point' end
	if not jobAllowed(point, char) then return nil, 'not_allowed' end
	return char
end

-- Rate limit per kind of request: false when the player asked again too soon.
local function allow(source, kind)
	local now = GetGameTimer()
	local mine = lastCall[source]
	if not mine then
		mine = {}
		lastCall[source] = mine
	end
	local last = mine[kind]
	if last and now - last < Config.rateLimitMs then return false end
	mine[kind] = now
	return true
end

local function forget(source)
	lastCall[source], sessions[source], pending[source] = nil, nil, nil
end

-- The account that holds the whole price, or nil.
local function payingAccount(source, price)
	for _, name in ipairs(type(Config.payFrom) == 'table' and Config.payFrom or { 'money' }) do
		if type(name) == 'string' and core('HasMoney', source, name, price) == true then return name end
	end
	return nil
end

-- Client feedback ------------------------------------------------------------------------------

-- A locale key + params for the player's client, which translates it and shows it through opx_core Notify.
local function notify(source, key, kind, params)
	pcall(TriggerClientEvent, 'opx_clotheshop:notify', source, key, kind or 'info', params or {})
end

local function skinProvider()
	local name = core('GetProvider', 'skin')
	return type(name) == 'string' and name or nil
end

-- The point menu for the client: clothing shows it, other types open the creator straight away.
local function sendMenu(source, point, session)
	pcall(TriggerClientEvent, 'opx_clotheshop:menu', source, {
		name = point.name, label = point.label, type = point.type, price = point.price,
		outfits = point.type == 'clothing' and Config.outfitsAtShop == true and skinProvider() ~= nil,
		session = session == true,
	})
end

-- Requests -------------------------------------------------------------------------------------

-- Key E at a point: checks, then the menu.
local function open(source, name)
	local point = byName[name]
	local char, reason = check(source, point)
	if not char then return notify(source, reason, 'error') end
	sendMenu(source, point, false)
end

-- Fitting room / barber chair: money check, then the creator in the point's scope. Payment on saved.
local function fit(source, name, label)
	local point = byName[name]
	local char, reason = check(source, point)
	if not char then return notify(source, reason, 'error') end
	if point.price > 0 and not payingAccount(source, point.price) then
		return notify(source, 'insufficient_funds', 'error', { total = point.price })
	end
	local tag = 'clotheshop:' .. point.name
	local ok, why = core('OpenCreator', source, {
		mode = 'edit', scope = point.type, tag = tag, title = point.label, confirmLabel = confirmText(label),
	})
	if ok ~= true then
		return notify(source, reasonCode(why, 'failed'), 'error', { reason = tostring(why) })
	end
	pending[source] = {
		point = point.name, type = point.type, price = point.price, society = point.society, tag = tag,
		citizenId = char.citizenId,
	}
end

-- "My outfits" at a clothing point: the skin provider's own menu.
local function outfits(source, name)
	local point = byName[name]
	local char, reason = check(source, point)
	if not char then return notify(source, reason, 'error') end
	if point.type ~= 'clothing' or Config.outfitsAtShop ~= true then return notify(source, 'unknown_point', 'error') end
	local skin = skinProvider()
	if not skin then return notify(source, 'no_skin', 'error') end
	local called, ok, why = pcall(Open77.exports.callSync, skin, 'OpenOutfits', source, { title = point.label })
	if not called then
		print(('[opx_clotheshop] OpenOutfits of %s failed: %s'):format(skin, tostring(ok)))
		return notify(source, 'no_skin', 'error')
	end
	if ok ~= true then notify(source, reasonCode(why, 'failed'), 'error', { reason = tostring(why) }) end
end

-- Every client request: a valid source, under the rate limit of its kind, a point name that is a short string.
-- Nothing waits (opx_core and the creator answer from memory), so the handlers run inline.
local function onRequest(name, kind, handler)
	RegisterNetEvent(name, function(pointName, ...)
		local src = toSource(source)
		if not src or not allow(src, kind) then return end
		if type(pointName) ~= 'string' or #pointName > 48 then return end
		local ok, err = pcall(handler, src, pointName, ...)
		if not ok then
			print(('[opx_clotheshop] %s error for player %d: %s'):format(kind, src, tostring(err)))
			notify(src, 'failed', 'error', { reason = 'error' })
		end
	end)
end

onRequest('opx_clotheshop:open', 'open', open)
onRequest('opx_clotheshop:fit', 'fit', fit)
onRequest('opx_clotheshop:outfits', 'outfits', outfits)

-- Payment ----------------------------------------------------------------------------------------

-- Something was actually stored. A creator without info.changed (a replacement) counts as a change.
local function changedSomething(info)
	local changed = info.changed
	if type(changed) ~= 'table' then return true end
	if changed.body == true then return true end
	return type(changed.clothing) == 'table' and next(changed.clothing) ~= nil
end

-- One synchronous step: debit, society credit, notice, event. The look is already stored at this point.
local function charge(source, p)
	if p.price > 0 then
		local account = payingAccount(source, p.price)
		local paid, why = false, 'insufficient_funds'
		if account then
			paid, why = core('RemoveMoney', source, account, p.price, ('clotheshop:%s'):format(p.point))
		end
		if paid ~= true then
			print(('[opx_clotheshop] UNPAID: player %d (%s) kept a %s look at %s, %d not taken (%s)'):format(source,
				p.citizenId, p.type, p.point, p.price, tostring(why)))
			return notify(source, 'unpaid', 'error', { total = p.price })
		end
		if p.society then
			local credited, socWhy = core('AddSocietyMoney', p.society, p.price, 'clotheshop:' .. p.point)
			if credited ~= true then
				print(('[opx_clotheshop] society %s not credited for %s: %s'):format(p.society, p.point, tostring(socWhy)))
			end
		end
		notify(source, 'paid', 'success', { total = p.price })
	else
		notify(source, 'done', 'success')
	end
	TriggerEvent('opx:clotheshop:paid', source, p.point, p.type, p.price)
end

-- Ours when the session was opened by this resource with the tag we gave.
local function mine(source, info)
	local p = pending[source]
	if not p or type(info) ~= 'table' or info.opener ~= RESOURCE then return nil end
	if info.tag ~= nil and info.tag ~= p.tag then return nil end
	return p
end

AddEventHandler('opx:creator:saved', function(playerId, _, _, info)
	local src = toSource(playerId)
	local p = src and mine(src, info)
	if not p then return end
	pending[src] = nil
	local char = character(src)
	if not char or char.citizenId ~= p.citizenId then return end -- another character now: nothing to charge
	if not changedSomething(info) then return notify(src, 'unchanged', 'info') end
	local ok, err = pcall(charge, src, p)
	if not ok then print(('[opx_clotheshop] payment error for player %d: %s'):format(src, tostring(err))) end
end)

AddEventHandler('opx:creator:closed', function(playerId, reason, info)
	local src = toSource(playerId)
	if not src or not mine(src, info) then return end
	pending[src] = nil
	if reason == 'unchanged' then notify(src, 'unchanged', 'info') end
end)

-- Exports ----------------------------------------------------------------------------------------

-- SYNC: copies of the points as configured (invalid rows left out).
exports('GetPoints', function()
	return copies()
end)

-- SYNC: opens a point for a player without the point check (another resource's vendor). The fitting is then
-- accepted within Config.sessionDistance of where the player stood. true | false, reason.
exports('OpenPoint', function(source, name)
	local src = toSource(source)
	if not src then return false, 'invalid_player' end
	local point = type(name) == 'string' and byName[name] or nil
	local char, reason = check(src, point, true)
	if not char then return false, reason end
	local pos = position(src)
	if not pos then return false, 'invalid_player' end
	local owner = GetInvokingResource() or RESOURCE
	local generation = type(GetInvokingResourceGeneration) == 'function' and GetInvokingResourceGeneration() or nil
	sessions[src] = {
		point = point.name, x = pos.x, y = pos.y, z = pos.z, bucket = toInt(pos.bucket, 0, 0xFFFFFFFF) or 0,
		owner = owner, generation = generation,
	}
	sendMenu(src, point, true)
	return true
end)

-- Cleanup ----------------------------------------------------------------------------------------

AddEventHandler('onPlayerDisconnected', function(playerId)
	local src = toSource(playerId)
	if src then forget(src) end
end)

-- Character switch: a session or a pending payment belonged to the previous character.
AddEventHandler('opx:playerUnloaded', function(playerId)
	local src = toSource(playerId)
	if src then forget(src) end
end)

-- A resource that opened sessions stopped: they end (kept when its new VM already registered, hot reload).
AddEventHandler('onResourceStop', function(name)
	if type(name) ~= 'string' or name == RESOURCE then return end
	local ok, current = pcall(Open77.resource.generation, name)
	for src, s in pairs(sessions) do
		if s.owner == name and (not ok or current == nil or current ~= s.generation) then sessions[src] = nil end
	end
end)

load()
