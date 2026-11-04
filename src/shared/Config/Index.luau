--!strict
--[[
	Config/Index: GDD §9.3. Per segment, finding this fraction of its treasures grants
	a permanent luck bonus (additive with the rebirth luck bonus). Badges are backlog
	(need approval to create in Experience settings).
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Index: Types.IndexConfig = {
	milestones = {
		{ fraction = 0.5, luckBonus = 0.02 },
		{ fraction = 0.75, luckBonus = 0.03 },
		{ fraction = 1, luckBonus = 0.05 },
	},
}

return DeepFreeze(Index)
