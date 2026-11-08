--!strict
--[[
	Config/Economy: GDD §6, §8.1, §11.2 constants.
	offline = basePlotIncomePermanent * min(elapsed, offlineCapSeconds) * offlineRate
	sell value = sellSeconds * the treasure's income before rebirth/boosts
	inventory overflow: finds below autoSellBelowRarity are auto-sold; otherwise the
	lowest-income unplaced item is sold instead.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Economy: Types.EconomyConfig = {
	luckCap = 25,
	startingCash = 0,
	sellSeconds = 10,
	offlineRate = 0.5,
	offlineCapSeconds = 7200,
	inventoryCap = 300,
	autoSellBelowRarity = 5, -- Legendary
	vaultTickSeconds = 1,
	migrationCompensationSeconds = 60,
}

return DeepFreeze(Economy)
