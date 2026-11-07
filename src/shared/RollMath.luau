--!strict
--[[
	RollMath: the pure roll algorithm (GDD §2.2 and §3). No state, no Instances.
	The server owns the Random object and calls these; the client may use
	probTable() to show odds, but never rolls.

	probTable(L): for tiers Secret down to Uncommon, p_i = min(L / N_i, 1 - sum of
	rarer tiers); Common takes the remainder. Sums to exactly 1 by construction.
]]

local Config = script.Parent.Config
local Types = require(script.Parent.Types)
local Catalog = require(script.Parent.Catalog)

local Rarities = require(Config.Rarities) :: { Types.Rarity }
local Mutations = require(Config.Mutations) :: Types.MutationsConfig

local TIERS = #Rarities
local CACHE_MAX = 256

export type RandomFn = () -> number -- uniform in [0, 1)

export type RollResult = {
	rarity: number,
	treasure: Types.Treasure,
	mutation: { string },
}

local RollMath = {}

local cache: { [number]: { number } } = {}
local cacheSize = 0

--- Probability of each rarity order (1..10) at total luck L (L >= 1).
function RollMath.probTable(luck: number): { number }
	local cached = cache[luck]
	if cached then
		return cached
	end
	local probs = table.create(TIERS, 0)
	local rarer = 0
	for order = TIERS, 2, -1 do
		local p = math.min(luck / Rarities[order].oneIn, 1 - rarer)
		if p < 0 then
			p = 0
		end
		probs[order] = p
		rarer += p
	end
	probs[1] = math.max(0, 1 - rarer)
	table.freeze(probs)
	if cacheSize >= CACHE_MAX then
		table.clear(cache)
		cacheSize = 0
	end
	cache[luck] = probs
	cacheSize += 1
	return probs
end

--- Pick a rarity order from u in [0, 1). With floor > 1, u is drawn over the
--- conditional distribution of tiers >= floor (GDD §2.2 step 3).
function RollMath.pickTier(u: number, probs: { number }, floor: number?): number
	local minTier = math.clamp(floor or 1, 1, TIERS)
	local total = 0
	for order = minTier, TIERS do
		total += probs[order]
	end
	if total <= 0 then
		-- The floor tier has zero probability (cannot happen for floor <= Mythic
		-- with L >= 1); fall back to the floor itself.
		return minTier
	end
	local target = u * total
	local cumulative = 0
	for order = TIERS, minTier, -1 do
		cumulative += probs[order]
		if target < cumulative then
			return order
		end
	end
	return minTier
end

--- Weighted pick from a list of { weight: number } entries.
function RollMath.pickWeighted<T>(u: number, entries: { T }, weightOf: (T) -> number): T
	local total = 0
	for _, entry in entries do
		total += weightOf(entry)
	end
	local target = u * total
	local cumulative = 0
	for _, entry in entries do
		cumulative += weightOf(entry)
		if target < cumulative then
			return entry
		end
	end
	return entries[#entries]
end

local function treasureWeight(t: Types.Treasure): number
	return t.weight
end

local function mutationWeight(m: Types.Mutation): number
	return m.weight
end

--- Chance of a mutation in one family for a find.
function RollMath.familyChance(family: Types.MutationFamily, toolMutation: number, potionMutation: number): number
	return math.min(family.chanceCap, family.baseChance * toolMutation * potionMutation)
end

--- Independent Finish and Aura rolls: at most one mutation per family.
function RollMath.rollMutations(rand: RandomFn, toolMutation: number, potionMutation: number): { string }
	local result: { string } = {}
	for _, family in Mutations.families do
		if rand() < RollMath.familyChance(family, toolMutation, potionMutation) then
			local entry = RollMath.pickWeighted(rand(), family.entries, mutationWeight)
			table.insert(result, entry.id)
		end
	end
	return result
end

--- min(totalCap, product of the mutation multipliers). Unknown ids and a second
--- mutation from the same family are ignored, so a corrupt list can't exceed the cap.
function RollMath.mutationMultiplier(mutation: { string }): number
	local seen: { [string]: boolean } = {}
	local mult = 1
	for _, id in mutation do
		local entry = Catalog.mutationById[id]
		if entry and not seen[entry.family] then
			seen[entry.family] = true
			mult *= entry.mult
		end
	end
	return math.min(Mutations.totalCap, mult)
end

--- One full server roll: rarity (with floor), treasure from the segment pool, mutations.
function RollMath.roll(rand: RandomFn, segmentId: string, luck: number, floor: number?, toolMutation: number, potionMutation: number): RollResult
	local rarity = RollMath.pickTier(rand(), RollMath.probTable(luck), floor)
	local pool = Catalog.poolBySegmentRarity[segmentId][rarity]
	local treasure = RollMath.pickWeighted(rand(), pool, treasureWeight)
	return {
		rarity = rarity,
		treasure = treasure,
		mutation = RollMath.rollMutations(rand, toolMutation, potionMutation),
	}
end

return table.freeze(RollMath)
