--!strict
--[[
	MonetizationService: the Robux shop (GDD §10, §15.5).

	Gamepasses: ownership is checked on join (UserOwnsGamePassAsync) and after
	PromptGamePassPurchaseFinished, and mirrored to Player attributes
	"Pass_<key>" = true (Boosts reads them on the server and the client).
	"SFT_PassesLoaded" is set once the join check is done (or failed).

	Developer products: ProcessReceipt is idempotent. The receipt's PurchaseId is
	stored in profile.purchases (last 100). It returns NotProcessedYet until the
	buyer's profile is loaded and writable; it grants, records, saves, and returns
	PurchaseGranted only after the save succeeded (otherwise Roblox retries; the
	in-memory record stops a second grant in this session).

	Shop_Prompt(key): the client only names an item. The server checks it exists,
	has a real Roblox id (0 = "Coming soon"), isn't an owned pass, and passes the
	paid-random policy gate for luck items, then prompts the purchase itself.

	Policy (GDD §10.3): PolicyService ArePaidRandomItemsRestricted per player,
	failing closed (restricted on error), mirrored to "SFT_LuckItemsRestricted".

	Server Luck Boost: workspace attribute SFT_ServerLuckUntil, +15 min per purchase.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Catalog = require(Shared.Catalog)
local Boosts = require(Shared.Boosts)
local Signal = require(Shared.Util.Signal)
local Monetization = require(Shared.Config.Monetization) :: Types.MonetizationConfig

local DataService = require(script.Parent.DataService)
local RemoteService = require(script.Parent.RemoteService)
local StateService = require(script.Parent.StateService)
local ShopService = require(script.Parent.ShopService)
local PlotService = require(script.Parent.PlotService)
local PotionService = require(script.Parent.PotionService)
local Guard = require(script.Parent.Parent.Util.Guard)

-- Cash pouches pay out at least this much per second of their duration, so a
-- brand-new player with no income still gets something worth the Robux.
local MIN_CASH_PER_SECOND = 5

local MonetizationService = {
	-- (player, key) when a pass becomes owned
	passOwned = Signal.new() :: Signal.Signal<Player, string>,
	-- (player, product, robuxSpent) after a product is granted and saved
	productGranted = Signal.new() :: Signal.Signal<Player, Types.ProductInfo, number>,
}

local function setPassOwned(player: Player, key: string)
	if player:GetAttribute("Pass_" .. key) == true then
		return
	end
	player:SetAttribute("Pass_" .. key, true)
	PlotService.refreshPlayer(player)
	MonetizationService.passOwned:Fire(player, key)
end

local function checkPasses(player: Player)
	for _, pass in Monetization.passes do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns == true then
				setPassOwned(player, pass.key)
			elseif not ok then
				warn(`[MonetizationService] pass check {pass.key} failed for {player.UserId}: {owns}`)
			end
		end
	end
	player:SetAttribute("SFT_PassesLoaded", true)
end

local function checkPolicy(player: Player)
	local restricted = true -- fail closed
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and type(info) == "table" then
		restricted = info.ArePaidRandomItemsRestricted == true
	end
	player:SetAttribute("SFT_LuckItemsRestricted", restricted)
end

--- Applies a product's rewards to the profile (no save).
local function grant(player: Player, profile: Types.Profile, product: Types.ProductInfo)
	local reward = product.grant
	if reward.potions then
		for potionId, count in reward.potions do
			PotionService.give(player, profile, potionId, count)
		end
	end
	if reward.diamonds then
		profile.diamonds += reward.diamonds
		StateService.markDirty(player, "diamonds")
	end
	if reward.cashSeconds then
		local perSecond = math.max(PlotService.permanentIncome(player, profile), MIN_CASH_PER_SECOND)
		local amount = math.floor(perSecond * reward.cashSeconds)
		profile.cash += amount
		profile.lifetimeEarned += amount
		StateService.markDirty(player, "cash", "lifetimeEarned")
	end
	if reward.serverLuckSeconds then
		local now = os.time()
		local current = workspace:GetAttribute(Boosts.SERVER_LUCK_ATTRIBUTE)
		local untilTime = math.max(now, if type(current) == "number" then current else 0) + reward.serverLuckSeconds
		workspace:SetAttribute(Boosts.SERVER_LUCK_ATTRIBUTE, untilTime)
		RemoteService.fireAll(Net.Notify, { kind = "server_luck", name = player.DisplayName, seconds = untilTime - now })
	end
	ShopService.notify(player, "product_granted", { key = product.key })
end

--- Remembers a receipt; keeps only the newest `purchaseHistory` entries.
local function record(profile: Types.Profile, purchaseId: string)
	profile.purchases[purchaseId] = os.time()
	local entries: { { id: string, t: number } } = {}
	for id, t in profile.purchases do
		table.insert(entries, { id = id, t = t })
	end
	if #entries <= Monetization.purchaseHistory then
		return
	end
	table.sort(entries, function(a, b)
		return a.t < b.t
	end)
	for i = 1, #entries - Monetization.purchaseHistory do
		profile.purchases[entries[i].id] = nil
	end
end

-- `testProduct` (Studio tests only) stands in for the id lookup, since products
-- without a Roblox id yet have no entry in productByRobloxId.
local function processReceipt(receipt: any, testProduct: Types.ProductInfo?): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.getProfile(player)
	if profile == nil or DataService.isReadOnly(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if profile.purchases[purchaseId] ~= nil then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted earlier
	end
	local product = testProduct or Catalog.productByRobloxId[receipt.ProductId]
	if product == nil then
		warn(`[MonetizationService] unknown product {receipt.ProductId} for {player.UserId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grant(player, profile, product)
	record(profile, purchaseId)
	local status = DataService.saveNow(player)
	if status ~= "saved" then
		warn(`[MonetizationService] receipt {purchaseId} granted but save -> {status}; Roblox will retry`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	MonetizationService.productGranted:Fire(player, product, tonumber(receipt.CurrencySpent) or product.price)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function prompt(player: Player, key: string)
	local pass = Catalog.passByKey[key]
	local product = Catalog.productByKey[key]
	local item: any = pass or product
	if item == nil then
		return
	end
	if item.id == 0 then
		ShopService.notify(player, "not_configured", { key = key })
		return
	end
	if item.luck and player:GetAttribute("SFT_LuckItemsRestricted") ~= false then
		ShopService.notify(player, "restricted", { key = key })
		return
	end
	if pass then
		if Boosts.hasPass(player, key) then
			ShopService.notify(player, "pass_owned", { key = key })
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	elseif product then
		MarketplaceService:PromptProductPurchase(player, product.id)
	end
end

function MonetizationService.init() end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = function(receipt: any): Enum.ProductPurchaseDecision
		return processReceipt(receipt, nil)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local pass = Catalog.passByRobloxId[passId]
		if purchased and pass then
			setPassOwned(player, pass.key)
			ShopService.notify(player, "pass_bought", { key = pass.key })
		end
	end)
	RemoteService.on(Net.Shop_Prompt, 1, 3, function(player, _, keyArg)
		local key = Guard.str(keyArg, 32)
		if key then
			prompt(player, key)
		end
	end)
	local function onJoin(player: Player)
		task.spawn(checkPolicy, player)
		task.spawn(checkPasses, player)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
end

--- Studio test only: give or take a pass without Robux.
function MonetizationService.testSetPass(player: Player, key: string, owned: boolean): boolean
	if not RunService:IsStudio() or Catalog.passByKey[key] == nil then
		return false
	end
	if owned then
		setPassOwned(player, key)
	else
		player:SetAttribute("Pass_" .. key, nil)
		PlotService.refreshPlayer(player)
	end
	return true
end

--- Studio test only: run a fake receipt through the real ProcessReceipt path.
--- Reusing a purchaseId must not grant twice.
function MonetizationService.testReceipt(player: Player, key: string, purchaseId: string): string
	local product = Catalog.productByKey[key]
	if not RunService:IsStudio() or product == nil then
		return "not in Studio / unknown product"
	end
	local receipt = { PlayerId = player.UserId, PurchaseId = purchaseId, ProductId = product.id, CurrencySpent = product.price }
	return tostring(processReceipt(receipt, product))
end

return MonetizationService
