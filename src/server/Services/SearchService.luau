--!strict
--[[
	SearchService: auto-search (GDD §1.1, §2.2, §9.4, §9.5).

	Every Heartbeat, for each player whose character ZoneService reports inside
	an unlocked segment's search zone, progress += dt. When progress reaches the
	search interval, the server rolls (rarity with pity/onboarding floor ->
	treasure -> mutations), updates pity and stats, stores the find, and sends
	Search_Reveal. Leaving the zone resets progress to 0 immediately.

	Modifiers: tool luck/interval/mutation from the highest owned tier, rebirth
	and Index luck, Luck/Speed/Mutation potions, upgrade-tree levels, gamepasses
	and the Server Luck Boost; total luck capped at 25.

	Diamonds (GDD §15.1): each find also has SearchMath.diamondChance to drop
	SearchMath.diamondAmount diamonds, added to the profile and sent in the reveal.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local RollMath = require(Shared.RollMath)
local SearchMath = require(Shared.SearchMath)
local Catalog = require(Shared.Catalog)
local Signal = require(Shared.Util.Signal)
local Config = Shared.Config
local Pity = require(Config.Pity) :: { Types.PityFloor }
local Onboarding = require(Config.Onboarding) :: Types.OnboardingConfig

local DataService = require(script.Parent.DataService)
local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local ZoneService = require(script.Parent.ZoneService)
local InventoryService = require(script.Parent.InventoryService)

export type FindInfo = {
	uid: string?,
	soldFor: number?,
	treasure: Types.Treasure,
	rarity: number,
	mutation: { string },
	floor: number,
	luck: number,
	segmentId: string,
	searchNumber: number,
	diamonds: number, -- diamonds this find dropped (0 = none)
}

type State = {
	segmentId: string?,
	progress: number,
	interval: number,
}

local SearchService = {
	found = Signal.new() :: Signal.Signal<Player, FindInfo>,
	-- fires with (player, segmentId?) when searching starts/stops
	activeChanged = Signal.new() :: Signal.Signal<Player, string?>,
}

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local states: { [Player]: State } = {}

function SearchService.luckFor(profile: Types.Profile, segmentId: string, now: number, player: Player?): number
	return SearchMath.luck(profile, segmentId, now, player)
end

function SearchService.intervalFor(profile: Types.Profile, segmentId: string, now: number, player: Player?): number
	return SearchMath.interval(profile, segmentId, now, player)
end

--- Highest rarity floor forced on the next search (1 = none).
function SearchService.floorFor(profile: Types.Profile): number
	local floor = 1
	for _, pity in Pity do
		local counter = (profile.pity :: any)[pity.id] or 0
		if counter >= pity.guaranteeAt - 1 then
			floor = math.max(floor, pity.minRarity)
		end
	end
	if profile.rebirths == 0 then
		local forced = Onboarding.forcedMinRarity[profile.stats.searches + 1]
		if forced then
			floor = math.max(floor, forced)
		end
	end
	return floor
end

--- Nearest pity floor: the one with the fewest searches left.
function SearchService.nearestPity(profile: Types.Profile): { id: string, remaining: number }
	local best = { id = Pity[1].id, remaining = math.huge }
	for _, pity in Pity do
		local remaining = pity.guaranteeAt - ((profile.pity :: any)[pity.id] or 0)
		if remaining < best.remaining then
			best = { id = pity.id, remaining = remaining }
		end
	end
	return best
end

export type Force = { rarity: number, mutation: { string }? }

--- One search for `player` in `segmentId`: roll, book-keeping, store, notify.
--- `force` (Studio tests only; ignored live) fixes the rarity and mutations.
function SearchService.doSearch(player: Player, profile: Types.Profile, segmentId: string, force: Force?): FindInfo
	local now = os.time()
	local luck = SearchService.luckFor(profile, segmentId, now, player)
	local floor = SearchService.floorFor(profile)
	local result = RollMath.roll(rand, segmentId, luck, floor, SearchMath.mutation(profile, segmentId, now), 1)
	if force and RunService:IsStudio() then
		local pool = Catalog.poolBySegmentRarity[segmentId][force.rarity]
		result = { rarity = force.rarity, treasure = pool[1], mutation = force.mutation or {} }
	end

	for _, pity in Pity do
		local pityTable = profile.pity :: any
		if result.rarity >= pity.minRarity then
			pityTable[pity.id] = 0
		else
			pityTable[pity.id] = (pityTable[pity.id] or 0) + 1
		end
	end
	profile.stats.searches += 1

	local rarest = profile.stats.rarest
	local newMult = RollMath.mutationMultiplier(result.mutation)
	if rarest == nil or result.rarity > rarest.rarity or (result.rarity == rarest.rarity and newMult > RollMath.mutationMultiplier(rarest.mutation)) then
		profile.stats.rarest = { id = result.treasure.id, rarity = result.rarity, mutation = result.mutation }
	end

	local uid, soldFor = InventoryService.add(player, profile, result.treasure, result.mutation)
	StateService.markDirty(player, "pity", "stats")

	-- the second currency: a chance on every find, more for rarer finds
	local diamonds = 0
	if rand() < SearchMath.diamondChance(profile, now) then
		diamonds = SearchMath.diamondAmount(profile, result.rarity)
		profile.diamonds += diamonds
		StateService.markDirty(player, "diamonds")
	end

	local info: FindInfo = {
		uid = uid,
		soldFor = soldFor,
		treasure = result.treasure,
		rarity = result.rarity,
		mutation = result.mutation,
		floor = floor,
		luck = luck,
		segmentId = segmentId,
		searchNumber = profile.stats.searches,
		diamonds = diamonds,
	}
	local payload: Types.RevealPayload = {
		uid = uid,
		treasureId = result.treasure.id,
		rarity = result.rarity,
		mutation = result.mutation,
		soldFor = soldFor,
		pity = SearchService.nearestPity(profile),
		diamonds = if diamonds > 0 then diamonds else nil,
	}
	RemoteService.fire(Net.Search_Reveal, player, payload)
	SearchService.found:Fire(player, info)
	return info
end

local function sendState(player: Player, state: State)
	local payload: Types.SearchStatePayload = {
		active = state.segmentId ~= nil,
		segmentId = state.segmentId,
		interval = state.interval,
		startedAt = workspace:GetServerTimeNow() - state.progress,
	}
	RemoteService.fire(Net.Search_State, player, payload)
end

local function step(dt: number)
	local now = os.time()
	for _, player in Players:GetPlayers() do
		local state = states[player]
		if state == nil then
			state = { segmentId = nil, progress = 0, interval = 0 }
			states[player] = state
		end
		local segmentId = ZoneService.getSearchSegment(player)
		local profile = DataService.getProfile(player)
		local canSearch = segmentId ~= nil and profile ~= nil and not DataService.isReadOnly(player) and profile.segments[segmentId] == true

		if not canSearch or profile == nil or segmentId == nil then
			if state.segmentId ~= nil then
				state.segmentId = nil
				state.progress = 0
				sendState(player, state)
				SearchService.activeChanged:Fire(player, nil)
			end
			continue
		end

		local interval = SearchService.intervalFor(profile, segmentId, now, player)
		if state.segmentId ~= segmentId then
			state.segmentId = segmentId
			state.progress = 0
			state.interval = interval
			sendState(player, state)
			SearchService.activeChanged:Fire(player, segmentId)
		elseif interval ~= state.interval then
			state.interval = interval
			sendState(player, state)
		end

		state.progress += dt
		if state.progress >= interval then
			-- carry the remainder, but never bank more than one extra search
			state.progress = math.min(state.progress - interval, interval * 0.5)
			local ok, err = pcall(SearchService.doSearch, player, profile, segmentId)
			if not ok then
				warn(`[SearchService] search failed for {player.UserId}: {err}`)
			end
		end
	end
end

--- Searches done by this player while in a zone, for tests (reads the profile).
function SearchService.isSearching(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.segmentId ~= nil
end

function SearchService.init() end

function SearchService.start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return SearchService
