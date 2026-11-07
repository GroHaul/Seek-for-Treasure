--!strict
--[[
	Catalog: read-only lookups built once from Config (treasure by id, segment by
	id, tool by id, mutation by id, potion by id). Every system uses these
	instead of scanning Config lists.
]]

local Config = script.Parent.Config
local Types = require(script.Parent.Types)
local DeepFreeze = require(script.Parent.Util.DeepFreeze)

local Rarities = require(Config.Rarities) :: { Types.Rarity }
local Mutations = require(Config.Mutations) :: Types.MutationsConfig
local Segments = require(Config.Segments) :: { Types.Segment }
local Potions = require(Config.Potions) :: Types.PotionsConfig
local Tools = require(Config.Tools) :: Types.ToolsConfig

export type ToolInfo = {
	id: string,
	name: string,
	segmentId: string,
	tier: number,
	stats: Types.ToolTier,
	price: number,
}

local treasureById: { [string]: Types.Treasure } = {}
local treasureSegment: { [string]: string } = {}
local segmentById: { [string]: Types.Segment } = {}
local poolBySegmentRarity: { [string]: { [number]: { Types.Treasure } } } = {}
local toolById: { [string]: ToolInfo } = {}
local mutationById: { [string]: Types.Mutation } = {}
local potionById: { [string]: Types.Potion } = {}

for _, segment in Segments do
	segmentById[segment.id] = segment
	local pools: { [number]: { Types.Treasure } } = {}
	for order = 1, #Rarities do
		pools[order] = {}
	end
	for _, treasure in segment.treasures do
		assert(treasureById[treasure.id] == nil, "duplicate treasure id " .. treasure.id)
		treasureById[treasure.id] = treasure
		treasureSegment[treasure.id] = segment.id
		table.insert(pools[treasure.rarity], treasure)
	end
	for order, pool in pools do
		assert(#pool > 0, `segment {segment.id} has no treasure for rarity {order}`)
	end
	poolBySegmentRarity[segment.id] = pools
	for _, tool in segment.tools do
		local stats = Tools.tiers[tool.tier]
		toolById[tool.id] = {
			id = tool.id,
			name = tool.name,
			segmentId = segment.id,
			tier = tool.tier,
			stats = stats,
			price = stats.basePrice * segment.toolPriceMult,
		}
	end
end

for _, family in Mutations.families do
	for _, mutation in family.entries do
		mutationById[mutation.id] = mutation
	end
end

for _, potion in Potions.list do
	potionById[potion.id] = potion
end

local Catalog = {
	rarities = Rarities,
	segments = Segments,
	treasureById = treasureById,
	treasureSegment = treasureSegment,
	segmentById = segmentById,
	poolBySegmentRarity = poolBySegmentRarity,
	toolById = toolById,
	mutationById = mutationById,
	potionById = potionById,
}

--- The tool id for a segment's tier ("pets", 3 -> "pets_t3").
function Catalog.toolIdFor(segmentId: string, tier: number): string?
	local segment = segmentById[segmentId]
	if segment == nil then
		return nil
	end
	local entry = segment.tools[tier]
	return if entry then entry.id else nil
end

return DeepFreeze(Catalog)
