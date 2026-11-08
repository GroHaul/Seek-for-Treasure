--!strict
--[[
	Config/Diamonds: the second currency (GDD §15.1).

	Every find has a chance to also drop diamonds:
	  chance = min(chanceCap, baseChance x Diamond Potion (x2) x (1 + Diamond Nose upgrade))
	  amount = byRarity[rarity] x (1 + Gem Hoard upgrade), at least 1
	Diamonds buy upgrade-tree levels at the Upgrades stall; Robux diamond packs add more.
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Diamonds: Types.DiamondsConfig = {
	baseChance = 0.08,
	chanceCap = 0.5,
	--          Common Uncommon Rare Epic Legendary Mythic Divine Celestial Cosmic Secret
	byRarity = { 1, 2, 3, 5, 10, 25, 50, 100, 175, 250 },
}

return DeepFreeze(Diamonds)
