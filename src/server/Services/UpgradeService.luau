--!strict
--[[
	UpgradeService: the Upgrades stall's hex tree, paid in diamonds (GDD §15.4).

	Upgrade_Buy(nodeId): the node must exist, be a diamond node, be revealed (its
	prerequisite has level >= 1) and not be maxed; the price is the node's next
	cost from Config. The Plot Slots node is cash and goes through Shop_BuySlot.

	Effects are read where they apply (SearchMath, Boosts); this service only
	pushes the ones that need an instant refresh: walk speed and income numbers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local UpgradeMath = require(Shared.UpgradeMath)
local Boosts = require(Shared.Boosts)
local Signal = require(Shared.Util.Signal)

local DataService = require(script.Parent.DataService)
local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local ShopService = require(script.Parent.ShopService)
local PlotService = require(script.Parent.PlotService)
local Guard = require(script.Parent.Parent.Util.Guard)

local UpgradeService = {
	-- (player, nodeId, newLevel, diamondCost)
	bought = Signal.new() :: Signal.Signal<Player, string, number, number>,
}

--- Sets the character's walk speed from the Swift Feet level.
function UpgradeService.applyWalkSpeed(player: Player, profile: Types.Profile)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Boosts.walkSpeed(profile)
	end
end

function UpgradeService.buy(player: Player, profile: Types.Profile, nodeId: string): boolean
	local node = UpgradeMath.nodeById[nodeId]
	if node == nil or node.currency ~= "diamonds" or not UpgradeMath.isRevealed(profile, node) then
		return false
	end
	local cost = UpgradeMath.nextCost(profile, node)
	if cost == nil then
		return false
	end
	if profile.diamonds < cost then
		ShopService.notify(player, "cant_afford_diamonds", { price = cost })
		return false
	end
	local level = UpgradeMath.level(profile, nodeId) + 1
	profile.diamonds -= cost
	profile.upgrades[nodeId] = level
	StateService.markDirty(player, "diamonds", "upgrades")
	UpgradeService.applyWalkSpeed(player, profile)
	PlotService.refreshPlayer(player)
	ShopService.notify(player, "upgrade_bought", { nodeId = nodeId, level = level })
	UpgradeService.bought:Fire(player, nodeId, level, cost)
	return true
end

function UpgradeService.init() end

function UpgradeService.start()
	RemoteService.on(Net.Upgrade_Buy, 3, 5, function(player, profile, nodeArg)
		local nodeId = Guard.oneOf(nodeArg, UpgradeMath.nodeById, 24)
		if nodeId then
			UpgradeService.buy(player, profile, nodeId)
		end
	end)

	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			local profile = DataService.getProfile(player)
			if profile then
				UpgradeService.applyWalkSpeed(player, profile)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	DataService.loaded:Connect(function(player, profile)
		UpgradeService.applyWalkSpeed(player, profile)
	end)
end

return UpgradeService
