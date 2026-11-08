--!strict
--[[
	SearchMath: search modifiers from a profile (GDD §2.4, §5.1, §5.2, §15). The
	server uses these to roll; the HUD uses the same functions to display luck,
	search interval, mutation and diamond chance, so the numbers always agree.
	Tool stats come from the highest owned tier (equipping a lower one is cosmetic).
	`player` (optional) adds gamepass and Server Luck Boost modifiers (Boosts).
]]

local Types = require(script.Parent.Types)
local EconomyMath = require(script.Parent.EconomyMath)
local UpgradeMath = require(script.Parent.UpgradeMath)
local Boosts = require(script.Parent.Boosts)
local Config = script.Parent.Config
local Tools = require(Config.Tools) :: Types.ToolsConfig
local Diamonds = require(Config.Diamonds) :: Types.DiamondsConfig

-- Accepts the full server profile or the client's public view.
type ProfileLike = {
	tools: { [string]: { owned: number, equipped: number } },
	rebirths: number,
	indexRewards: { [string]: number },
	potions: any,
	upgrades: any,
}

local SearchMath = {}

function SearchMath.toolStats(profile: ProfileLike, segmentId: string): Types.ToolTier
	local tool = profile.tools[segmentId]
	local tier = if tool then tool.owned else 1
	return Tools.tiers[math.clamp(tier, 1, #Tools.tiers)]
end

function SearchMath.luck(profile: ProfileLike, segmentId: string, now: number, player: Player?): number
	return EconomyMath.totalLuck(
		SearchMath.toolStats(profile, segmentId).luck,
		profile.rebirths,
		EconomyMath.indexLuckBonus(profile.indexRewards) + UpgradeMath.value(profile, "luck"),
		EconomyMath.potionMult(profile.potions, "luck", now),
		Boosts.luckMult(player, now)
	)
end

function SearchMath.interval(profile: ProfileLike, segmentId: string, now: number, player: Player?): number
	local mult = (1 - UpgradeMath.value(profile, "interval")) * Boosts.intervalMult(player)
	return EconomyMath.searchInterval(SearchMath.toolStats(profile, segmentId).interval, EconomyMath.potionMult(profile.potions, "speed", now), mult)
end

--- Combined multiplier on both mutation chances (tool x Mutation Potion x upgrade).
function SearchMath.mutation(profile: ProfileLike, segmentId: string, now: number): number
	return SearchMath.toolStats(profile, segmentId).mutation
		* EconomyMath.potionMult(profile.potions, "mutation", now)
		* (1 + UpgradeMath.value(profile, "mutation"))
end

--- Chance that a find also drops diamonds.
function SearchMath.diamondChance(profile: ProfileLike, now: number): number
	local chance = Diamonds.baseChance * EconomyMath.potionMult(profile.potions, "diamond", now) * (1 + UpgradeMath.value(profile, "diamondChance"))
	return math.min(Diamonds.chanceCap, chance)
end

--- Diamonds dropped by a find of rarity order `rarity` (when it drops any).
function SearchMath.diamondAmount(profile: ProfileLike, rarity: number): number
	local base = Diamonds.byRarity[math.clamp(rarity, 1, #Diamonds.byRarity)]
	return math.max(1, math.floor(base * (1 + UpgradeMath.value(profile, "diamondAmount"))))
end

return table.freeze(SearchMath)
