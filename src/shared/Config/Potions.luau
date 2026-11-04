--!strict
--[[
	Config/Potions: GDD §5.2. Bought with cash; expiry is a wall-clock unix timestamp.
	Same type adds durationSeconds (capped at maxRemainingSeconds); different types multiply.
	Speed divides the search interval by its multiplier.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Potions: Types.PotionsConfig = {
	maxRemainingSeconds = 3600,
	list = {
		{ id = "luck", name = "Luck Potion", multiplier = 2, durationSeconds = 600, priceSeconds = 150, minPrice = 250 },
		{ id = "speed", name = "Speed Potion", multiplier = 1.5, durationSeconds = 600, priceSeconds = 150, minPrice = 250 },
		{ id = "mutation", name = "Mutation Potion", multiplier = 2, durationSeconds = 600, priceSeconds = 120, minPrice = 200 },
		{ id = "cash", name = "Cash Potion", multiplier = 2, durationSeconds = 600, priceSeconds = 240, minPrice = 400 },
	},
}

return DeepFreeze(Potions)
