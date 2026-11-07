--!strict
--[[
	Acceptance tests for the server roll function (GDD §2.2, §3.2).
	1. 1,000,000 rolls of RollMath.roll (the function SearchService calls) at
	   luck 1, no pity: every tier with >= 1,000 expected hits is within +-5%.
	2. Every probability table sums to 1 (luck 1, 2, 5, 10, 25).
	3. Pity floors are respected (100,000 floored rolls).
	4. No mutation combination exceeds 10x: all 30 Finish x Aura combinations,
	   corrupt lists, and 200,000 rolls at max mutation chance.
	Usage: require(game.ServerStorage.SFT_Tests["RollMath.spec"])(rolls?)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(rollCount: number?): string
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local RollMath = require(Shared:WaitForChild("RollMath") :: ModuleScript) :: any
	local EconomyMath = require(Shared:WaitForChild("EconomyMath") :: ModuleScript) :: any
	local Catalog = require(Shared:WaitForChild("Catalog") :: ModuleScript) :: any
	local Mutations = require(Shared.Config.Mutations) :: any

	local out: { string } = {}
	local failures = 0
	local function fail(msg: string)
		failures += 1
		table.insert(out, "FAIL " .. msg)
	end

	-- 1. distribution -------------------------------------------------------
	local N = rollCount or 1000000
	local rng = Random.new(20261107)
	local function rand(): number
		return rng:NextNumber()
	end
	local counts = table.create(10, 0)
	local started = os.clock()
	for i = 1, N do
		local result = RollMath.roll(rand, "pets", 1, nil, 1, 1)
		counts[result.rarity] += 1
		if i % 50000 == 0 then
			task.wait()
		end
	end
	local probs = RollMath.probTable(1)
	table.insert(out, string.format("Distribution: %d rolls of RollMath.roll, luck 1, pity off, seed 20261107 (%.1f s)", N, os.clock() - started))
	table.insert(out, "| Tier | Target p | Expected | Observed | Deviation | sigma | +-5%? |")
	table.insert(out, "|---|---|---|---|---|---|---|")
	for order = 1, 10 do
		local p = probs[order]
		local expected = p * N
		local observed = counts[order]
		local deviation = if expected > 0 then (observed - expected) / expected else 0
		local sigma = if expected > 0 then (observed - expected) / math.sqrt(expected * (1 - p)) else 0
		local verdict = "n/a"
		if expected >= 1000 then
			verdict = if math.abs(deviation) <= 0.05 then "yes" else "NO"
			if verdict == "NO" then
				fail(`tier {order} deviation {deviation}`)
			end
		end
		table.insert(
			out,
			string.format(
				"| %s | %.7f | %.1f | %d | %+.2f%% | %+.2f | %s |",
				Catalog.rarities[order].name,
				p,
				expected,
				observed,
				deviation * 100,
				sigma,
				verdict
			)
		)
	end

	-- 2. tables sum to 1 ------------------------------------------------------
	for _, luck in { 1, 2, 5, 10, 25 } do
		local sum = 0
		for _, p in RollMath.probTable(luck) do
			sum += p
		end
		if math.abs(sum - 1) > 1e-12 then
			fail(`probTable({luck}) sums to {sum}`)
		end
	end
	table.insert(out, "Probability tables at luck 1/2/5/10/25 sum to 1 (+-1e-12)")

	-- 3. pity floors ----------------------------------------------------------
	for _, floor in { 4, 5, 6 } do
		for i = 1, 100000 do
			local tier = RollMath.pickTier(rng:NextNumber(), probs, floor)
			if tier < floor then
				fail(`floor {floor} produced tier {tier}`)
				break
			end
			if i % 50000 == 0 then
				task.wait()
			end
		end
	end
	table.insert(out, "Pity floors Epic/Legendary/Mythic: 100,000 floored rolls each, none below the floor")

	-- 4. mutation cap ---------------------------------------------------------
	local finishes: { string? } = { nil }
	local auras: { string? } = { nil }
	for _, family in Mutations.families do
		for _, m in family.entries do
			table.insert(if family.id == "finish" then finishes else auras, m.id)
		end
	end
	local combos, maxMult = 0, 0
	local base = Catalog.treasureById.pets_dust_bunny
	local baseIncome = EconomyMath.treasureIncome({ id = base.id, rarity = base.rarity, mutation = {}, level = 1 })
	for fi = 1, 6 do
		for ai = 1, 5 do
			local list: { string } = {}
			if fi > 1 then
				table.insert(list, finishes[fi] :: string)
			end
			if ai > 1 then
				table.insert(list, auras[ai] :: string)
			end
			combos += 1
			local mult = RollMath.mutationMultiplier(list)
			local income = EconomyMath.treasureIncome({
				id = base.id,
				rarity = base.rarity,
				mutation = list,
				level = 1,
			})
			maxMult = math.max(maxMult, mult)
			if mult > 10 or income > 10 * baseIncome + 1e-9 then
				fail(`combo {table.concat(list, "+")} -> {mult}x`)
			end
		end
	end
	local corrupt = {
		{ "prismatic", "prismatic", "starlit" },
		{ "prismatic", "shadow", "rainbow", "starlit", "electric" },
		{ "unknown", "prismatic", "starlit", "starlit" },
	}
	for _, list in corrupt do
		if RollMath.mutationMultiplier(list) > 10 then
			fail("corrupt list " .. table.concat(list, "+"))
		end
	end
	local rolledMax = 0
	for i = 1, 200000 do
		local list = RollMath.rollMutations(rand, 2, 2) -- T8 tool x Mutation Potion
		rolledMax = math.max(rolledMax, RollMath.mutationMultiplier(list))
		if #list > 2 then
			fail("more than 2 mutations rolled")
			break
		end
		if i % 50000 == 0 then
			task.wait()
		end
	end
	if rolledMax > 10 then
		fail("rolled mutation above cap: " .. rolledMax)
	end
	table.insert(
		out,
		string.format("Mutation cap: %d combinations max %.1fx; 3 corrupt lists capped; 200,000 rolls at max chance max %.1fx", combos, maxMult, rolledMax)
	)

	table.insert(out, 1, if failures == 0 then "RollMath.spec: PASS" else `RollMath.spec: {failures} FAILURES`)
	return table.concat(out, "\n")
end
