--!strict
--[[
	DevService: test commands (GDD §12). The Dev_Command remote is created ONLY
	when RunService:IsStudio(), and only UserId 422765950 may use it.
	Commands: cash <n>, search <n>, potion <1..4>, pity <n>, status.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Potions = require(Shared.Config.Potions) :: Types.PotionsConfig

local DataService = require(script.Parent.DataService)
local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local SearchService = require(script.Parent.SearchService)
local PlotService = require(script.Parent.PlotService)
local Guard = require(script.Parent.Parent.Util.Guard)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local DEV_USER_ID = 422765950

local DevService = {}

local commands: { [string]: (Player, Types.Profile, number?) -> string } = {
	cash = function(player, profile, n)
		local amount = Guard.finite(n) or 1e6
		profile.cash = math.max(0, profile.cash + amount)
		StateService.markDirty(player, "cash")
		return "cash = " .. profile.cash
	end,
	search = function(player, profile, n)
		local count = Guard.int(n, 1, 10000) or 1
		for _ = 1, count do
			SearchService.doSearch(player, profile, "pets")
		end
		return `did {count} searches`
	end,
	potion = function(player, profile, n)
		local index = Guard.int(n, 1, #Potions.list) or 1
		local potion = Potions.list[index]
		local potions = profile.potions :: any
		potions[potion.id] = os.time() + potion.durationSeconds
		StateService.markDirty(player, "potions")
		return potion.name .. " active"
	end,
	pity = function(player, profile, n)
		local value = Guard.int(n, 0, 5000) or 0
		profile.pity.epic, profile.pity.legendary, profile.pity.mythic = value, value, value
		StateService.markDirty(player, "pity")
		return "pity counters = " .. value
	end,
	status = function(_, profile)
		return `cash {profile.cash} searches {profile.stats.searches} store {DataService.storeKind}`
	end,
}

function DevService.isDev(player: Player): boolean
	return RunService:IsStudio() and player.UserId == DEV_USER_ID
end

function DevService.init()
	if not RunService:IsStudio() then
		return
	end
	local remote = RemoteService.create(Net.Dev_Command)
	local limiter = RateLimiter.new(5, 10)
	remote.OnServerEvent:Connect(function(player: Player, cmd: unknown, arg: unknown)
		if not DevService.isDev(player) or not limiter:allow(player) then
			return
		end
		local name = Guard.str(cmd, 20)
		local handler = if name then commands[name] else nil
		local profile = DataService.getProfile(player)
		if handler == nil or profile == nil or DataService.isReadOnly(player) then
			return
		end
		local ok, result = pcall(handler, player, profile, Guard.finite(arg))
		print(`[Dev] {player.Name} {name} -> {result}`)
		if not ok then
			warn(result)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
	end)
end

-- Studio-only test hook: a BindableFunction in ServerStorage that Studio
-- tests (run through the MCP in the Server datamodel) invoke to read live
-- server state. Clients can't reach ServerStorage, and it doesn't exist live.
local function copy(value: any): any
	return HttpService:JSONDecode(HttpService:JSONEncode(value))
end

local hookCommands: { [string]: (...any) -> any } = {
	profile = function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		local profile = if player then DataService.getProfile(player) else nil
		return if profile then copy(profile) else nil
	end,
	searching = function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		return player ~= nil and SearchService.isSearching(player)
	end,
	moveTo = function(userId: number, x: number, y: number, z: number)
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		if character == nil then
			return false
		end
		character:PivotTo(CFrame.new(x, y, z))
		return true
	end,
	dev = function(userId: number, cmd: string, arg: number?)
		local player = Players:GetPlayerByUserId(userId)
		local profile = if player then DataService.getProfile(player) else nil
		local handler = commands[cmd]
		if player == nil or profile == nil or handler == nil then
			return "no player/profile/command"
		end
		return handler(player, profile, arg)
	end,
	rejoin = function(userId: number, offlineSeconds: number)
		local player = Players:GetPlayerByUserId(userId)
		return if player then DataService.testRejoin(player, offlineSeconds) else "no player"
	end,
	mock = function(action: string, a: any)
		local store = DataService.testMockStore()
		if store == nil then
			return "no mock store"
		end
		if action == "failAlways" then
			store:setFailAlways(a == true)
			return true
		elseif action == "raw" then
			return store:rawGet(a)
		elseif action == "writes" then
			return store.writes
		end
		return "unknown mock action"
	end,
	saveNow = function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		return if player then DataService.saveNow(player) else "no player"
	end,
	remoteStats = function()
		return RemoteService.stats()
	end,
	plot = function(userId: number, action: string, a: any, b: any)
		local player = Players:GetPlayerByUserId(userId)
		local profile = if player then DataService.getProfile(player) else nil
		if player == nil or profile == nil then
			return nil
		end
		if action == "income" then
			return {
				income = PlotService.plotIncome(player, profile),
				base = PlotService.basePlotIncome(profile),
			}
		elseif action == "placeBest" then
			PlotService.placeBest(player, profile)
		elseif action == "place" then
			return PlotService.place(player, profile, a, b)
		elseif action == "remove" then
			return PlotService.remove(player, profile, a)
		elseif action == "index" then
			return PlotService.plotIndex(player)
		elseif action == "setLastOnline" then
			-- simulate having been offline: next load sees this lastOnline
			profile.lastOnline = a
			return true
		end
		return copy(profile)
	end,
	storeKind = function()
		return DataService.storeKind
	end,
}

function DevService.start()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "SFT_TestHook"
	hook.OnInvoke = function(cmd: string, ...: any): any
		local handler = hookCommands[cmd]
		if handler == nil then
			return "unknown hook command " .. tostring(cmd)
		end
		return handler(...)
	end
	hook.Parent = ServerStorage
end

return DevService
