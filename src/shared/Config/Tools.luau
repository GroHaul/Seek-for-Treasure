--!strict
--[[
	Config/Tools: GDD §5.1 tier template, shared by every segment's tool line.
	Price in a segment = basePrice * segment.toolPriceMult. Names live in the segment config.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Tools: Types.ToolsConfig = {
	minSearchInterval = 0.5,
	tiers = {
		{ tier = 1, interval = 3.00, luck = 1.00, mutation = 1.00, basePrice = 0 },
		{ tier = 2, interval = 2.60, luck = 1.10, mutation = 1.00, basePrice = 1000 },
		{ tier = 3, interval = 2.25, luck = 1.25, mutation = 1.10, basePrice = 2500 },
		{ tier = 4, interval = 1.95, luck = 1.45, mutation = 1.25, basePrice = 15000 },
		{ tier = 5, interval = 1.65, luck = 1.70, mutation = 1.40, basePrice = 70000 },
		{ tier = 6, interval = 1.40, luck = 2.00, mutation = 1.60, basePrice = 250000 },
		{ tier = 7, interval = 1.20, luck = 2.30, mutation = 1.80, basePrice = 900000 },
		{ tier = 8, interval = 1.00, luck = 2.60, mutation = 2.00, basePrice = 3000000 },
	},
}

return DeepFreeze(Tools)
