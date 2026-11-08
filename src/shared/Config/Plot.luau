--!strict
--[[
	Config/Plot: GDD §6. 8 plots per server (one per player), a 4 x 5 pedestal grid.
	pedestalByRarity[rarityOrder] picks the pedestal model band.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Plot: Types.PlotConfig = {
	plotsPerServer = 8,
	gridColumns = 4,
	gridRows = 5,
	pedestalByRarity = { "stone", "stone", "bronze", "bronze", "gold", "gold", "crystal", "crystal", "cosmic", "cosmic" },
}

return DeepFreeze(Plot)
