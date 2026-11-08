--!strict
--[[
	IndexService: the Collection Index (GDD §9.3).

	Every find records index[treasureId] = { n = times found, m = bitmask of
	mutations seen }. Finding 50% / 75% / 100% of a segment's treasures grants a
	permanent luck bonus (+2% / +3% / +5%), stored as indexRewards[segment] =
	highest milestone reached (EconomyMath.indexLuckBonus applies it to luck).
	Milestones never go down, even if a later update adds treasures.
	The completion badge needs a badge created in Experience settings, so it is
	not awarded until that's approved.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Catalog = require(Shared.Catalog)
local EconomyMath = require(Shared.EconomyMath)
local Signal = require(Shared.Util.Signal)
local IndexConfig = require(Shared.Config.Index) :: Types.IndexConfig

local DataService = require(script.Parent.DataService)
local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local SearchService = require(script.Parent.SearchService)

local IndexService = {
	-- (player, segmentId, milestoneIndex)
	milestone = Signal.new() :: Signal.Signal<Player, string, number>,
}

--- Treasures of `segmentId` found at least once, and the segment's total.
function IndexService.progress(profile: Types.Profile, segmentId: string): (number, number)
	local segment = Catalog.segmentById[segmentId]
	if segment == nil then
		return 0, 0
	end
	local found = 0
	for _, treasure in segment.treasures do
		local entry = profile.index[treasure.id]
		if entry and entry.n > 0 then
			found += 1
		end
	end
	return found, #segment.treasures
end

--- Highest milestone reached for a found/total ratio (0 = none).
function IndexService.milestoneFor(found: number, total: number): number
	if total <= 0 then
		return 0
	end
	local reached = 0
	for i, milestone in IndexConfig.milestones do
		-- found * 1 >= fraction * total, in integers-safe form
		if found >= milestone.fraction * total - 1e-9 then
			reached = i
		end
	end
	return reached
end

local function checkMilestones(player: Player, profile: Types.Profile, segmentId: string)
	local found, total = IndexService.progress(profile, segmentId)
	local reached = IndexService.milestoneFor(found, total)
	local claimed = profile.indexRewards[segmentId] or 0
	if reached > claimed then
		profile.indexRewards[segmentId] = reached
		StateService.markDirty(player, "indexRewards")
		RemoteService.fire(Net.Notify, player, {
			kind = "index_milestone",
			segmentId = segmentId,
			milestone = reached,
			found = found,
			total = total,
			luckBonus = EconomyMath.indexLuckBonus(profile.indexRewards),
		})
		IndexService.milestone:Fire(player, segmentId, reached)
	end
end

function IndexService.record(player: Player, profile: Types.Profile, treasureId: string, mutation: { string })
	local entry = profile.index[treasureId]
	if entry == nil then
		entry = { n = 0, m = 0 }
		profile.index[treasureId] = entry
	end
	entry.n += 1
	for _, id in mutation do
		local m = Catalog.mutationById[id]
		if m then
			entry.m = bit32.bor(entry.m, m.bit)
		end
	end
	StateService.markDirty(player, "index")
	local segmentId = Catalog.treasureSegment[treasureId]
	if segmentId then
		checkMilestones(player, profile, segmentId)
	end
end

function IndexService.init() end

function IndexService.start()
	SearchService.found:Connect(function(player, info)
		local profile = DataService.getProfile(player)
		if profile then
			IndexService.record(player, profile, info.treasure.id, info.mutation)
		end
	end)
	-- re-check on load (e.g. after a Config change), never lowering a claim
	DataService.loaded:Connect(function(player, profile)
		for _, segment in Catalog.segments do
			checkMilestones(player, profile, segment.id)
		end
	end)
end

return IndexService
