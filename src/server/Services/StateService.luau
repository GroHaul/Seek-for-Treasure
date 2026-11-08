--!strict
--[[
	StateService: replicates the public part of each profile to its owner.

	State_Snapshot { profile = <public fields>, derived = {...} }  on load
	State_Delta    { set = {key = value}, inv = {uid = entry | false}, derived = {...} }
	               batched, at most 4 per second per player

	Services call markDirty(player, "cash") after changing a top-level field,
	invChanged(player, uid) after adding/removing one inventory entry (so a find
	never resends the whole 300-entry inventory), and setDerived for computed
	numbers the UI shows (income/sec, luck, friend boost...).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local RemoteService = require(script.Parent.RemoteService)

local FLUSH_SECONDS = 0.25
local PRIVATE = {
	_lock = true,
	_legacy = true,
	purchases = true,
	codes = true,
	schema = true,
	nextUid = true,
	lastOnline = true,
}

type Pending = {
	set: { [string]: boolean },
	inv: { [string]: boolean },
	derived: { [string]: any },
	any: boolean,
}

local StateService = {}

local pending: { [Player]: Pending } = {}
local derivedCache: { [Player]: { [string]: any } } = {}

local function pendingFor(player: Player): Pending
	local p = pending[player]
	if p == nil then
		p = { set = {}, inv = {}, derived = {}, any = false }
		pending[player] = p
	end
	return p
end

local function publicView(profile: Types.Profile): { [string]: any }
	local view = {}
	for key, value in profile :: any do
		if not PRIVATE[key] then
			view[key] = value
		end
	end
	return view
end

function StateService.markDirty(player: Player, ...: string)
	local p = pendingFor(player)
	for _, key in { ... } do
		if not PRIVATE[key] then
			p.set[key] = true
			p.any = true
		end
	end
end

function StateService.invChanged(player: Player, uid: string)
	local p = pendingFor(player)
	p.inv[uid] = true
	p.any = true
end

function StateService.setDerived(player: Player, key: string, value: any)
	local cache = derivedCache[player]
	if cache == nil then
		cache = {}
		derivedCache[player] = cache
	end
	if cache[key] == value then
		return
	end
	cache[key] = value
	local p = pendingFor(player)
	p.derived[key] = value
	p.any = true
end

function StateService.sendSnapshot(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	pending[player] = nil
	RemoteService.fire(Net.State_Snapshot, player, {
		profile = publicView(profile),
		derived = derivedCache[player] or {},
	})
end

local function flush()
	for player, p in pending do
		if not p.any then
			continue
		end
		local profile = DataService.getProfile(player)
		if profile == nil or player.Parent == nil then
			pending[player] = nil
			continue
		end
		local payload: { [string]: any } = {}
		if next(p.set) then
			local set = {}
			for key in p.set do
				set[key] = (profile :: any)[key]
			end
			payload.set = set
		end
		if next(p.inv) then
			local inv = {}
			for uid in p.inv do
				local entry = profile.inventory[uid]
				inv[uid] = if entry then entry else false
			end
			payload.inv = inv
		end
		if next(p.derived) then
			payload.derived = p.derived
		end
		pending[player] = nil
		RemoteService.fire(Net.State_Delta, player, payload)
	end
end

function StateService.init() end

function StateService.start()
	DataService.loaded:Connect(function(player)
		StateService.sendSnapshot(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		derivedCache[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			flush()
		end
	end)
end

return StateService
