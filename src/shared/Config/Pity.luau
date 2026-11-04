--!strict
--[[
	Config/Pity: GDD §9.4. Counters are global across segments, saved, and kept on
	rebirth. The guaranteeAt-th consecutive search without minRarity+ is forced to
	minRarity or better. No pity above Mythic.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Pity: { Types.PityFloor } = {
	{ id = "epic", minRarity = 4, guaranteeAt = 120 },
	{ id = "legendary", minRarity = 5, guaranteeAt = 800 },
	{ id = "mythic", minRarity = 6, guaranteeAt = 5000 },
}

return DeepFreeze(Pity)
