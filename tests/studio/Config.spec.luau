--!strict
--[[
	Step 1 check, run inside Studio: every Config module loads under --!strict,
	is deep-frozen, and holds the GDD tables (row counts, key values, odds sum).
	Usage (command bar / MCP): require(game.ServerStorage.SFT_Tests["Config.spec"])()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(): string
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Config = Shared:WaitForChild("Config")
	local lines: { string } = {}
	local failures = 0
	local checks = 0

	local function check(label: string, cond: boolean, detail: string?)
		checks += 1
		if not cond then
			failures += 1
			table.insert(lines, "FAIL " .. label .. (if detail then " (" .. detail .. ")" else ""))
		end
	end

	local modules = {
		"Rarities",
		"Mutations",
		"Pity",
		"Tools",
		"Segments",
		"Potions",
		"Upgrades",
		"Rebirth",
		"Economy",
		"Plot",
		"Index",
		"Onboarding",
		"Reveal",
		"Social",
	}
	local loaded: { [string]: any } = {}
	for _, name in modules do
		local ok, result = pcall(require, Config:WaitForChild(name) :: ModuleScript)
		check(name .. " loads", ok, if ok then nil else tostring(result))
		if ok then
			loaded[name] = result
			check(name .. " frozen", table.isfrozen(result))
		end
	end

	local Rarities = loaded.Rarities
	check("10 rarities", #Rarities == 10)
	local expectOdds = { 0, 4, 12, 50, 250, 1500, 10000, 75000, 500000, 5000000 }
	local expectCps = { 1, 3, 10, 40, 200, 1500, 12000, 100000, 900000, 10000000 }
	for i, r in Rarities do
		check("rarity order " .. i, r.order == i)
		check("rarity odds " .. r.name, r.oneIn == expectOdds[i])
		check("rarity cps " .. r.name, r.baseCps == expectCps[i])
		check("rarity color " .. r.name, (pcall(Color3.fromHex, r.color)))
	end
	local p = 0
	for i = 2, 10 do
		p += 1 / Rarities[i].oneIn
	end
	check("common remainder ~64.18845%", math.abs((1 - p) - 0.6418845) < 1e-6, tostring(1 - p))

	local Mutations = loaded.Mutations
	check("mutation cap 10", Mutations.totalCap == 10)
	check("2 mutation families", #Mutations.families == 2)
	local bits = 0
	local count = 0
	for _, fam in Mutations.families do
		for _, m in fam.entries do
			count += 1
			check("mutation bit unique " .. m.id, bit32.band(bits, m.bit) == 0)
			bits = bit32.bor(bits, m.bit)
			check("mutation mult <= 10 " .. m.id, m.mult <= 10)
		end
	end
	check("9 mutations", count == 9)

	local Segments = loaded.Segments
	check("1 segment (Pets MVP)", #Segments == 1 and Segments[1].id == "pets")
	local pets = Segments[1]
	check("12 pet treasures", #pets.treasures == 12)
	check("8 whistles", #pets.tools == 8)
	local perRarity = table.create(10, 0)
	for _, t in pets.treasures do
		perRarity[t.rarity] += 1
	end
	check("2 Common, 2 Uncommon, 1 each above", perRarity[1] == 2 and perRarity[2] == 2 and perRarity[10] == 1)

	check("8 tool tiers", #loaded.Tools.tiers == 8)
	check("T2 price 1000", loaded.Tools.tiers[2].basePrice == 1000)
	check("T8 interval 1.0", loaded.Tools.tiers[8].interval == 1)
	check("4 potions", #loaded.Potions.list == 4)
	check("slots 6 -> 20", loaded.Upgrades.slots.start == 6 and loaded.Upgrades.slots.max == 20)
	check("MVP rebirth $400M x12", loaded.Rebirth.mvpBaseCost == 4e8 and loaded.Rebirth.growth == 12)
	check("rebirth keeps treasures", loaded.Rebirth.keepAllTreasures == true)
	check("luck cap 25", loaded.Economy.luckCap == 25)
	check("offline 50% / 2 h", loaded.Economy.offlineRate == 0.5 and loaded.Economy.offlineCapSeconds == 7200)
	check("3 pity floors", #loaded.Pity == 3 and loaded.Pity[2].guaranteeAt == 800)
	check("8 plots", loaded.Plot.plotsPerServer == 8)
	check("3 index milestones", #loaded.Index.milestones == 3)
	check("9 reveal tiers", #loaded.Reveal.tiers == 9)
	check("friend boost 10% cap 50%", loaded.Social.friendBoost.perFriend == 0.1 and loaded.Social.friendBoost.cap == 0.5)

	local mutated = pcall(function()
		(Rarities[1] :: any).baseCps = 999
	end)
	check("Config rejects runtime writes", not mutated)

	table.insert(lines, 1, string.format("Config.spec: %d/%d checks passed", checks - failures, checks))
	return table.concat(lines, "\n")
end
