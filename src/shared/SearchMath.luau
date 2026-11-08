--!strict
--[[
	SearchMath: search modifiers from a profile (GDD §2.4, §5.1, §5.2). The server
	uses these to roll; the HUD uses the same functions to display luck, search
	interval and mutation chance, so the numbers always agree.
	Tool stats come from the highest owned tier (equipping a lower one is cosmetic).
]]

local Types = require(script.Parent.Types)
local EconomyMath = require(script.Parent.EconomyMath)
local Tools = require(script.Parent.Config.Tools) :: Types.ToolsConfig

-- Accepts the full server profile or the client's public view.
type ProfileLike = {
	tools: { [string]: { owned: number, equipped: number } },
	rebirths: number,
	indexRewards: { [string]: number },
	potions: any,
}

local SearchMath = {}

function SearchMath.toolStats(profile: ProfileLike, segmentId: string): Types.ToolTier
	local tool = profile.tools[segmentId]
	local tier = if tool then tool.owned else 1
	return Tools.tiers[math.clamp(tier, 1, #Tools.tiers)]
end

function SearchMath.luck(profile: ProfileLike, segmentId: string, now: number): number
	return EconomyMath.totalLuck(
		SearchMath.toolStats(profile, segmentId).luck,
		profile.rebirths,
		EconomyMath.indexLuckBonus(profile.indexRewards),
		EconomyMath.potionMult(profile.potions, "luck", now)
	)
end

function SearchMath.interval(profile: ProfileLike, segmentId: string, now: number): number
	return EconomyMath.searchInterval(SearchMath.toolStats(profile, segmentId).interval, EconomyMath.potionMult(profile.potions, "speed", now))
end

--- Combined multiplier on both mutation chances (tool x Mutation Potion).
function SearchMath.mutation(profile: ProfileLike, segmentId: string, now: number): number
	return SearchMath.toolStats(profile, segmentId).mutation * EconomyMath.potionMult(profile.potions, "mutation", now)
end

return table.freeze(SearchMath)
