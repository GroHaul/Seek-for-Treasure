--!strict
--[[
	RemoteService: creates every RemoteEvent from Shared.Net and is the single
	entry point for client requests (GDD §12.1).

	on(name, rate, burst, handler): each request goes through
	  rate limit -> loaded & writable profile -> handler(player, profile, ...)
	The handler validates every argument with Guard and returns silently on bad
	input. Dropped requests are only counted (stats()), never punished.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)

local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local DataService = require(script.Parent.DataService)

export type Handler = (player: Player, profile: Types.Profile, ...any) -> ()

local RemoteService = {}

local folder: Folder
local remotes: { [string]: RemoteEvent } = {}
local limiters: { RateLimiter.Limiter } = {}
local dropped: { [string]: number } = {}
local handled: { [string]: number } = {}

local function count(map: { [string]: number }, name: string)
	map[name] = (map[name] or 0) + 1
end

function RemoteService.init()
	folder = Instance.new("Folder")
	folder.Name = Net.folderName
	for _, name in Net.all do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
end

function RemoteService.start()
	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:forget(player)
		end
	end)
end

--- Adds a remote that isn't in Net.all (e.g. the Studio-only Dev_Command).
function RemoteService.create(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	remotes[name] = remote
	return remote
end

function RemoteService.on(name: string, rate: number, burst: number, handler: Handler)
	local remote = remotes[name]
	assert(remote, "unknown remote " .. name)
	local limiter = RateLimiter.new(rate, burst)
	table.insert(limiters, limiter)
	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not limiter:allow(player) then
			count(dropped, name)
			return
		end
		local profile = DataService.getProfile(player)
		if profile == nil or DataService.isReadOnly(player) then
			count(dropped, name)
			return
		end
		local ok, err = pcall(handler :: any, player, profile, ...)
		if not ok then
			count(dropped, name)
			warn(`[RemoteService] {name} handler error for {player.UserId}: {err}`)
			return
		end
		count(handled, name)
	end)
end

function RemoteService.fire(name: string, player: Player, ...: any)
	remotes[name]:FireClient(player, ...)
end

function RemoteService.fireAll(name: string, ...: any)
	remotes[name]:FireAllClients(...)
end

function RemoteService.stats(): { dropped: { [string]: number }, handled: { [string]: number } }
	return { dropped = table.clone(dropped), handled = table.clone(handled) }
end

return RemoteService
