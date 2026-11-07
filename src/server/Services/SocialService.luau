--!strict
--[[
	SocialService: friend boost (GDD §9.7). +10% cash per friend in the server,
	capped at +50%. Friendships are checked on the server with
	Player:IsFriendsWith on join (both directions cached per pair) and the
	count is recomputed on every join/leave.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyMath = require(Shared.EconomyMath)
local Signal = require(Shared.Util.Signal)

local SocialService = {
	-- (player, friendsInServer)
	friendsChanged = Signal.new() :: Signal.Signal<Player, number>,
}

local friendPairs: { [Player]: { [Player]: boolean } } = {}
local friendCount: { [Player]: number } = {}

local function recount(player: Player)
	local n = 0
	local pairs_ = friendPairs[player]
	if pairs_ then
		for other, isFriend in pairs_ do
			if isFriend and other.Parent == Players then
				n += 1
			end
		end
	end
	if friendCount[player] ~= n then
		friendCount[player] = n
		SocialService.friendsChanged:Fire(player, n)
	end
end

local function onPlayerAdded(player: Player)
	friendPairs[player] = friendPairs[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, isFriend = pcall(player.IsFriendsWithAsync, player, other.UserId)
			if ok and player.Parent and other.Parent then
				friendPairs[player][other] = isFriend
				friendPairs[other] = friendPairs[other] or {}
				friendPairs[other][player] = isFriend
				recount(other)
			end
		end
	end
	recount(player)
end

function SocialService.friendsInServer(player: Player): number
	return friendCount[player] or 0
end

function SocialService.friendMult(player: Player): number
	return EconomyMath.friendMult(SocialService.friendsInServer(player))
end

--- Studio test seam: pretend `player` has `friends` friends in the server
--- (real friendships need two befriended accounts). No effect outside Studio.
function SocialService.testSetFriends(player: Player, friends: number)
	if not RunService:IsStudio() then
		return
	end
	friendCount[player] = friends
	SocialService.friendsChanged:Fire(player, friends)
end

function SocialService.init() end

function SocialService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local mine = friendPairs[player]
		friendPairs[player] = nil
		friendCount[player] = nil
		if mine then
			for other in mine do
				local theirs = friendPairs[other]
				if theirs then
					theirs[player] = nil
					recount(other)
				end
			end
		end
	end)
end

return SocialService
