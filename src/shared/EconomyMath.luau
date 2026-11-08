--!strict
--[[
	EconomyMath: pure economy formulas (GDD §5, §6, §7, §8.1). The server is the
	only caller that changes state with these; the client uses them for display.

	treasureIncome = baseCps[rarity] * segmentMult * min(10, finish * aura) * (1 + 0.15 * (level - 1))
	plotIncome     = sum(placed treasureIncome) * rebirthMult * boostMult
	totalLuck      = clamp(toolLuck * (1 + 0.10 * rebirths + indexBonus) * luckPotion, 1, 25)
]]

local Config = script.Parent.Config
local Types = require(script.Parent.Types)
local Catalog = require(script.Parent.Catalog)
local RollMath = require(script.Parent.RollMath)

local Economy = require(Config.Economy) :: Types.EconomyConfig
local Rebirth = require(Config.Rebirth) :: Types.RebirthConfig
local Upgrades = require(Config.Upgrades) :: Types.UpgradesConfig
local Tools = require(Config.Tools) :: Types.ToolsConfig
local Social = require(Config.Social) :: Types.SocialConfig
local IndexConfig = require(Config.Index) :: Types.IndexConfig

local LEVEL_STEP = 0.15

export type ItemLike = {
	id: string,
	rarity: number,
	mutation: { string },
	level: number,
}

local EconomyMath = {}

function EconomyMath.isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

--- Income/sec of one treasure before rebirth and boosts.
function EconomyMath.treasureIncome(item: ItemLike): number
	local treasure = Catalog.treasureById[item.id]
	if treasure == nil then
		return 0
	end
	local segment = Catalog.segmentById[Catalog.treasureSegment[item.id]]
	local rarity = Catalog.rarities[treasure.rarity]
	local level = math.clamp(item.level, 1, 10)
	return rarity.baseCps * segment.incomeMult * RollMath.mutationMultiplier(item.mutation) * (1 + LEVEL_STEP * (level - 1))
end

function EconomyMath.rebirthCashMult(rebirths: number): number
	return 1 + Rebirth.cashBonusPerRebirth * rebirths
end

function EconomyMath.friendMult(friendsInServer: number): number
	return 1 + math.min(Social.friendBoost.cap, Social.friendBoost.perFriend * friendsInServer)
end

--- Sum of the Index milestone luck bonuses a profile has claimed (all segments).
function EconomyMath.indexLuckBonus(indexRewards: { [string]: number }): number
	local bonus = 0
	for _, claimed in indexRewards do
		for i = 1, math.min(claimed, #IndexConfig.milestones) do
			bonus += IndexConfig.milestones[i].luckBonus
		end
	end
	return bonus
end

function EconomyMath.totalLuck(toolLuck: number, rebirths: number, indexBonus: number, luckPotion: number): number
	local luck = toolLuck * (1 + Rebirth.luckBonusPerRebirth * rebirths + indexBonus) * luckPotion
	return math.clamp(luck, 1, Economy.luckCap)
end

--- Multiplier of potion `id` at unix time `now` (1 when not active).
function EconomyMath.potionMult(potions: { [string]: number }, id: string, now: number): number
	local expiry = potions[id]
	local potion = Catalog.potionById[id]
	if potion == nil or type(expiry) ~= "number" or expiry <= now then
		return 1
	end
	return potion.multiplier
end

function EconomyMath.searchInterval(toolInterval: number, speedPotion: number): number
	return math.max(Tools.minSearchInterval, toolInterval / speedPotion)
end

--- Price of the next plot slot when the plot currently has `slots` unlocked.
function EconomyMath.slotPrice(slots: number): number
	return math.floor(Upgrades.slots.basePrice * Upgrades.slots.growth ^ (slots - Upgrades.slots.start))
end

--- Cost of the next rebirth. `segmentCount` is the number of segments in the build.
function EconomyMath.rebirthCost(rebirths: number, segmentCount: number): number
	local base = if segmentCount <= 1 then Rebirth.mvpBaseCost else Rebirth.baseCost
	return base * Rebirth.growth ^ rebirths
end

function EconomyMath.potionPrice(potion: Types.Potion, basePlotIncome: number): number
	return math.floor(math.max(potion.minPrice, potion.priceSeconds * basePlotIncome))
end

function EconomyMath.sellValue(item: ItemLike): number
	return math.floor(Economy.sellSeconds * EconomyMath.treasureIncome(item))
end

--- Offline earnings: permanent base income * min(elapsed, cap) * rate. Elapsed is clamped to [0, cap].
function EconomyMath.offlineEarnings(basePlotIncomePermanent: number, elapsedSeconds: number): number
	local elapsed = math.clamp(elapsedSeconds, 0, Economy.offlineCapSeconds)
	return math.floor(basePlotIncomePermanent * elapsed * Economy.offlineRate)
end

return table.freeze(EconomyMath)
