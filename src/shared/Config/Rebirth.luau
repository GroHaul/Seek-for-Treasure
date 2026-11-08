--!strict
--[[
	Config/Rebirth: GDD §7. Cost of the next rebirth = base * growth ^ rebirthsDone,
	where base = mvpBaseCost while the build has a single segment, else baseCost.
	Resets: cash, vault, tools, segment unlocks, plot slots. Keeps: all treasures
	(Checkpoint 1 decision), Index, pity, potions, codes, streak, stats.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Rebirth: Types.RebirthConfig = {
	baseCost = 2500000000,
	mvpBaseCost = 400000000,
	growth = 12,
	cashBonusPerRebirth = 0.5,
	luckBonusPerRebirth = 0.1,
	keepAllTreasures = true,
}

return DeepFreeze(Rebirth)
