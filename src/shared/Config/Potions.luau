--!strict
--[[
	Config/Potions: GDD §5.2, §15.3.

	Potions are bought with cash at the Potions stall and go into the player's
	potion bag; drinking one (hotbar) adds durationSeconds to that potion's timer
	(capped at maxRemainingSeconds remaining). Expiry is a wall-clock unix time.
	Different types multiply; Speed divides the search interval.

	The stall restocks every restockSeconds. Each restock rolls `stock` once per
	server window (same for everyone, see StockMath): a potion appears with
	probability `chance` and a stock of min..max, and each player may buy up to
	that many during the window.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Potions: Types.PotionsConfig = {
	maxRemainingSeconds = 3600,
	bagMax = 999,
	restockSeconds = 300,
	list = {
		{
			id = "luck",
			name = "Luck Potion",
			multiplier = 2,
			durationSeconds = 600,
			priceSeconds = 150,
			minPrice = 250,
			description = "Luck x2 for 10 min",
		},
		{
			id = "speed",
			name = "Speed Potion",
			multiplier = 1.5,
			durationSeconds = 600,
			priceSeconds = 150,
			minPrice = 250,
			description = "Search 1.5x faster for 10 min",
		},
		{
			id = "mutation",
			name = "Mutation Potion",
			multiplier = 2,
			durationSeconds = 600,
			priceSeconds = 120,
			minPrice = 200,
			description = "Mutation chance x2 for 10 min",
		},
		{
			id = "cash",
			name = "Cash Potion",
			multiplier = 2,
			durationSeconds = 600,
			priceSeconds = 240,
			minPrice = 400,
			description = "Plot income x2 for 10 min",
		},
		{
			id = "diamond",
			name = "Diamond Potion",
			multiplier = 2,
			durationSeconds = 600,
			priceSeconds = 300,
			minPrice = 1000,
			description = "Diamond drop chance x2 for 10 min",
		},
	},
	stock = {
		{ id = "luck", chance = 0.65, min = 1, max = 3 },
		{ id = "speed", chance = 0.65, min = 1, max = 3 },
		{ id = "cash", chance = 0.55, min = 1, max = 2 },
		{ id = "mutation", chance = 0.4, min = 1, max = 2 },
		{ id = "diamond", chance = 0.25, min = 1, max = 1 },
	},
}

return DeepFreeze(Potions)
