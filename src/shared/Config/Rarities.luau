--!strict
--[[
	Config/Rarities: GDD §2.1. Ten tiers, ordered Common (1) to Secret (10).
	Must match tools/economy_sim.py RARITIES (checked by tests/verify_config.py).
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Rarities: { Types.Rarity } = {
	{ id = "common", name = "Common", order = 1, oneIn = 0, baseCps = 1, color = "#B8C0CC", revealTier = 0 },
	{ id = "uncommon", name = "Uncommon", order = 2, oneIn = 4, baseCps = 3, color = "#5BD66B", revealTier = 0 },
	{ id = "rare", name = "Rare", order = 3, oneIn = 12, baseCps = 10, color = "#49A8FF", revealTier = 1 },
	{ id = "epic", name = "Epic", order = 4, oneIn = 50, baseCps = 40, color = "#A25CFF", revealTier = 2 },
	{ id = "legendary", name = "Legendary", order = 5, oneIn = 250, baseCps = 200, color = "#FFB52E", revealTier = 3 },
	{ id = "mythic", name = "Mythic", order = 6, oneIn = 1500, baseCps = 1500, color = "#FF3E7A", revealTier = 4 },
	{ id = "divine", name = "Divine", order = 7, oneIn = 10000, baseCps = 12000, color = "#FFF3B0", revealTier = 5 },
	{ id = "celestial", name = "Celestial", order = 8, oneIn = 75000, baseCps = 100000, color = "#6EF2FF", revealTier = 6 },
	{ id = "cosmic", name = "Cosmic", order = 9, oneIn = 500000, baseCps = 900000, color = "#7B2FFF", colorEnd = "#FF4FD8", revealTier = 7 },
	{ id = "secret", name = "Secret", order = 10, oneIn = 5000000, baseCps = 10000000, color = "#111111", rainbowEdge = true, revealTier = 8 },
}

return DeepFreeze(Rarities)
