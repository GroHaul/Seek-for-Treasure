--!strict
--[[
	UpgradeMath: levels, prices and effect totals of the upgrade tree (GDD §15.4).
	Used by the server (purchases, gameplay effects) and the Upgrades stall UI.

	The Plot Slots node has no stored level: its level is plot.slots - start, and
	its price is EconomyMath.slotPrice. Every other node's level lives in
	profile.upgrades[nodeId].
]]

local Types = require(script.Parent.Types)
local EconomyMath = require(script.Parent.EconomyMath)
local Config = script.Parent.Config
local Upgrades = require(Config.Upgrades) :: Types.UpgradesConfig
local UpgradeTree = require(Config.UpgradeTree) :: Types.UpgradeTreeConfig

local nodeById: { [string]: Types.UpgradeNode } = {}
for _, node in UpgradeTree.nodes do
	nodeById[node.id] = node
end

local UpgradeMath = {
	nodeById = table.freeze(nodeById),
}

--- Current level of `nodeId` (0 = not bought). Accepts a full or public profile.
function UpgradeMath.level(profile: any, nodeId: string): number
	if nodeId == "slots" then
		local slots = if type(profile.plot) == "table" then tonumber(profile.plot.slots) else nil
		return math.max(0, (slots or Upgrades.slots.start) - Upgrades.slots.start)
	end
	local upgrades = profile.upgrades
	local level = if type(upgrades) == "table" then tonumber(upgrades[nodeId]) else nil
	return math.max(0, math.floor(level or 0))
end

function UpgradeMath.maxLevel(node: Types.UpgradeNode, hasSlotPass: boolean?): number
	if node.effect == "slots" then
		return Upgrades.slots.max - Upgrades.slots.start + (if hasSlotPass then Upgrades.slots.passExtra else 0)
	end
	return #node.costs
end

--- True when the node is shown and buyable (its prerequisite has level >= 1).
function UpgradeMath.isRevealed(profile: any, node: Types.UpgradeNode): boolean
	if node.comingSoon then
		return false
	end
	return node.requires == nil or UpgradeMath.level(profile, node.requires) >= 1
end

--- Price of the next level, or nil when maxed / not for sale.
function UpgradeMath.nextCost(profile: any, node: Types.UpgradeNode, hasSlotPass: boolean?): number?
	if node.currency == "none" then
		return nil
	end
	local level = UpgradeMath.level(profile, node.id)
	if level >= UpgradeMath.maxLevel(node, hasSlotPass) then
		return nil
	end
	if node.effect == "slots" then
		return EconomyMath.slotPrice(Upgrades.slots.start + level)
	end
	return node.costs[level + 1]
end

--- Sum of perLevel x level over every node with this effect.
function UpgradeMath.value(profile: any, effect: Types.UpgradeEffect): number
	local total = 0
	for _, node in UpgradeTree.nodes do
		if node.effect == effect then
			total += node.perLevel * UpgradeMath.level(profile, node.id)
		end
	end
	return total
end

--- Node description with its per-level value filled in.
function UpgradeMath.describe(node: Types.UpgradeNode): string
	local v = node.perLevel
	local shown = if node.effect == "offlineCap"
		then tostring(v / 3600)
		elseif node.effect == "walkSpeed" or node.effect == "slots" then tostring(v)
		else tostring(math.floor(v * 100 + 0.5))
	return (string.gsub(node.description, "{v}", shown))
end

return table.freeze(UpgradeMath)
