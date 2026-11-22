Config = {}

-- Default key that opens a point (players rebind it: Settings > Key bindings).
Config.key = 'E'

-- Accounts tried in this order at Confirm: the first one that holds the WHOLE price pays (opx_core accounts).
Config.payFrom = { 'money', 'bank' }

-- true: the clothing menu also offers "My outfits" (the skin provider's saved outfits), when a skin provider runs.
Config.outfitsAtShop = true

-- true: a map pin on each point while a character is loaded.
Config.blips = true

-- Map pin variant per point type (exact Open77.blips sprite names of the 2.31 list). Other types: 'default'.
Config.blipSprites = {
	clothing = 'ServicePointClothesVariant',
	barber = 'ServicePointClothesVariant',
	surgery = 'ServicePointRipperdocVariant',
	tattoo = 'ServicePointRipperdocVariant',
	default = 'ServicePointClothesVariant',
}

-- Minimum milliseconds between two requests of the same kind from one player (anything faster is ignored).
Config.rateLimitMs = 500

-- Vertical tolerance (metres) between the player and a point's z (the server allows 1 m more). Kept small: the
-- Lower Walkway point lies right under the market floor.
Config.heightTolerance = 1.5

-- Extra metres the server accepts on top of a radius (its position snapshot can lag a tick behind).
Config.serverSlack = 2.5

-- A point opened by another resource (export OpenPoint) works only within this many metres of where it opened.
Config.sessionDistance = 4.0

-- The points. name: unique id ([a-z0-9_], 1..48). type: the creator scope opened there ('clothing', 'barber',
-- 'surgery', 'tattoo' or a scope you added to the creator's Config.scopes). price: integer >= 0, taken at
-- Confirm and only when something changed (0 = free, e.g. a wardrobe). radius in metres (horizontal),
-- bucket = routing bucket. society: a registered job whose society account receives the payments; false =
-- nobody. jobs: false = everybody; { traumateam = 0 } = only these jobs, at this minimum grade.
-- Coordinates are walked spots of the official packs that no other OPX point uses: Lower Walkway (rp_shops)
-- and The Crossing (rp_housing agency spot), both in Kabuki Market.
Config.points = {
	{ name = 'kabuki_lower_walkway', type = 'clothing', label = 'Clothing - Lower Walkway', price = 150,
	  x = -1201.07, y = 2035.60, z = 5.60, radius = 2.5, bucket = 0, society = false, jobs = false },
	{ name = 'kabuki_crossing_barber', type = 'barber', label = 'Barber - The Crossing', price = 80,
	  x = -1218.65, y = 2022.93, z = 7.82, radius = 2.5, bucket = 0, society = false, jobs = false },
}
