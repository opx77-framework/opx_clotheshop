# opx_clotheshop

Clothing shops and barbers: at a point the player opens the creator in one scope (clothes only, hair and make-up only...) and pays when he confirms a change. A clothing point also offers his saved outfits.

## Install
- Needs: `opx_core`, `opx_menu`, a creator provider with scopes (opx_creator) and, for clothing, a skin provider (opx_skin). Load after them.
- No database.
- Two points ship in Kabuki Market: clothing at the Lower Walkway (under the market), barber at The Crossing. Add your own in `Config.points`: stand on the spot and copy your position (opx_admin `/coords`).

## In game
- E at a point (rebindable). Clothing: a menu with Fitting room and My outfits. Barber, surgery, tattoo: the creator opens at once.
- The price shows on the Confirm button. Nothing changed or cancelled: nothing to pay.
- A map pin marks each point (`Config.blips`).

## Config
`config.lua`: `Config.points` (type = creator scope, price, `society` that receives payments, `jobs` allowed), `Config.payFrom`, `Config.outfitsAtShop`. Everything else is commented in the file.

## For developers
- `GetPoints()` → copies of the valid points.
- `OpenPoint(source, name)` → `true` or `false, reason`. Opens a point for your own vendor (NPC, target option) without the point check.
- Events: `opx:clotheshop:paid (source, pointName, type, price)`.
- A free wardrobe (housing, job locker) needs no point: `exports.opx_core:OpenCreator(src, { scope = 'clothing', tag = 'mine' })`, plus the skin provider's `OpenOutfits(src)`.
- Full contract and payment flow: `types.lua`.
