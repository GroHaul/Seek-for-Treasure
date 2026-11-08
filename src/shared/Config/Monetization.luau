--!strict
--[[
	Config/Monetization: the Robux shop (GDD §10, §15.5). Owner-approved list
	(2026-11-08): the GDD gamepasses and developer products plus three diamond packs.

	`id` is the Roblox gamepass / developer product id. 0 means the owner hasn't
	created it in Creator Hub yet: the shop shows "Coming soon" and the server
	refuses to prompt it. Fill the ids in after creating the products.

	Items marked `luck` change the odds of free searches, so they're hidden for
	players whose policy restricts paid random items (GDD §10.3).
]]

local Types = require(script.Parent.Parent.Types)
local DeepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Monetization: Types.MonetizationConfig = {
	passes = {
		{ key = "cash2x", name = "2x Cash", description = "Plot income x2, offline earnings too", icon = "potion_cash", id = 0, price = 249 },
		{ key = "luck2x", name = "2x Luck", description = "Luck x2 on every search", icon = "luck", id = 0, price = 299, luck = true },
		{ key = "autoCollect", name = "Auto-Collect", description = "Your vault goes straight to your cash", icon = "autoCollect", id = 0, price = 149 },
		{ key = "plotSlots", name = "+4 Plot Slots", description = "Unlocks 4 more pedestals (20 -> 24)", icon = "slot", id = 0, price = 199 },
		{
			key = "vip",
			name = "VIP",
			description = "+25% cash, offline earnings up to 6 h at 75%, VIP chat tag",
			icon = "vip",
			id = 0,
			price = 399,
		},
		{ key = "fastSearch", name = "Fast Search", description = "Searches 20% faster", icon = "fastSearch", id = 0, price = 199 },
	},
	products = {
		{
			key = "megaPotions",
			name = "Mega Potion Pack",
			description = "3 of every potion",
			icon = "codes",
			id = 0,
			price = 129,
			tab = "Potions",
			grant = { potions = { luck = 3, speed = 3, mutation = 3, cash = 3, diamond = 3 } },
			luck = true,
			featured = true,
		},
		{
			key = "luckPotions3",
			name = "Luck Potion x3",
			description = "3 Luck Potions for your bag",
			icon = "potion_luck",
			id = 0,
			price = 39,
			tab = "Potions",
			grant = { potions = { luck = 3 } },
			luck = true,
		},
		{
			key = "diamondPotions3",
			name = "Diamond Potion x3",
			description = "3 Diamond Potions for your bag",
			icon = "potion_diamond",
			id = 0,
			price = 59,
			tab = "Potions",
			grant = { potions = { diamond = 3 } },
		},
		{
			key = "serverLuck",
			name = "Server Luck Boost",
			description = "Luck x2 for everyone in the server for 15 min",
			icon = "serverLuck",
			id = 0,
			price = 99,
			tab = "Boosts",
			grant = { serverLuckSeconds = 900 },
			luck = true,
			featured = true,
		},
		{
			key = "cashPouch",
			name = "Cash Pouch",
			description = "30 min of your plot income, instantly",
			icon = "potion_cash",
			id = 0,
			price = 49,
			tab = "Boosts",
			grant = { cashSeconds = 1800 },
		},
		{
			key = "cashChest",
			name = "Cash Chest",
			description = "2 h of your plot income, instantly",
			icon = "cashChest",
			id = 0,
			price = 149,
			tab = "Boosts",
			grant = { cashSeconds = 7200 },
		},
		{
			key = "diamondsS",
			name = "Diamond Pouch",
			description = "250 diamonds",
			icon = "diamond",
			id = 0,
			price = 49,
			tab = "Diamonds",
			grant = { diamonds = 250 },
		},
		{
			key = "diamondsM",
			name = "Diamond Chest",
			description = "1,000 diamonds",
			icon = "diamond",
			id = 0,
			price = 149,
			tab = "Diamonds",
			grant = { diamonds = 1000 },
			featured = true,
		},
		{
			key = "diamondsL",
			name = "Diamond Vault",
			description = "3,000 diamonds",
			icon = "diamond",
			id = 0,
			price = 399,
			tab = "Diamonds",
			grant = { diamonds = 3000 },
		},
	},
	vip = { cashMult = 1.25, offlineCapBonusSeconds = 14400, offlineRate = 0.75 },
	cash2xMult = 2,
	luck2xMult = 2,
	fastSearchMult = 0.8,
	serverLuckMult = 2,
	purchaseHistory = 100,
}

return DeepFreeze(Monetization)
