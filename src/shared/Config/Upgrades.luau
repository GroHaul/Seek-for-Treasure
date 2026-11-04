--!strict
--[[
	Config/Upgrades: GDD §5.4. MVP has the plot-slot upgrade only.
	Next slot price = basePrice * growth ^ (currentSlots - start).
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Upgrades: Types.UpgradesConfig = {
	slots = {
		start = 6,
		max = 20,
		passExtra = 4, -- +4 Plot Slots gamepass (backlog; never sold in the MVP)
		basePrice = 1000,
		growth = 2.25,
	},
}

return DeepFreeze(Upgrades)
