--!strict
--[[
	StockMath: the Potions stall's stock (GDD §15.3).

	The stock is a pure function of the restock window number
	(floor(unix time / restockSeconds)), seeded per window. Every server and every
	client computes the same stock for the same window, so nothing has to be sent
	or stored server-side, and a server restart can't reroll it. The server still
	validates every purchase against this stock and the player's own counts.
]]

local Types = require(script.Parent.Types)
local Potions = require(script.Parent.Config.Potions) :: Types.PotionsConfig

local StockMath = {}

local cache: { [number]: { [string]: number } } = {}
local cached = 0

--- Restock window number at unix time `now`.
function StockMath.cycle(now: number): number
	return math.floor(now / Potions.restockSeconds)
end

--- Seconds until the next restock.
function StockMath.secondsToRestock(now: number): number
	return (StockMath.cycle(now) + 1) * Potions.restockSeconds - now
end

--- Potion id -> stock for window `cycle` (potions that didn't appear are absent).
--- At least one potion is always in stock.
function StockMath.stock(cycle: number): { [string]: number }
	local hit = cache[cycle]
	if hit then
		return hit
	end
	local rng = Random.new(cycle * 7919 + 104729)
	local stock: { [string]: number } = {}
	local any = false
	for _, entry in Potions.stock do
		if rng:NextNumber() < entry.chance then
			stock[entry.id] = rng:NextInteger(entry.min, entry.max)
			any = true
		end
	end
	if not any then
		local first = Potions.stock[1]
		stock[first.id] = first.min
	end
	if cached >= 8 then
		table.clear(cache)
		cached = 0
	end
	cache[cycle] = stock
	cached += 1
	return stock
end

return table.freeze(StockMath)
