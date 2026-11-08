--!strict
--[[
	ShopController: the Robux shop (GDD §10, §15.5). The HUD's Shop button opens
	it; tools, potions and upgrades are sold at the market stalls instead.

	Tabs: Featured, Passes, Potions, Boosts, Diamonds. Each card has an icon,
	name, description and a green Robux price button. Buying sends Shop_Prompt
	(the server checks the item and prompts the purchase). Items without a Roblox
	id yet show "Coming soon"; owned passes show "Owned". Items that change luck
	have an "Odds" button (rarity odds now vs with the boost) and are hidden
	for players whose policy restricts paid random items (GDD §10.3).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local RollMath = require(Shared:WaitForChild("RollMath"))
local SearchMath = require(Shared:WaitForChild("SearchMath"))
local Boosts = require(Shared:WaitForChild("Boosts"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = Shared:WaitForChild("Config")
local Monetization = require(Config:WaitForChild("Monetization")) :: any
local Economy = require(Config:WaitForChild("Economy")) :: any

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Root = require(UI.Root)
local Remotes = require(script.Parent.Parent.Remotes)
local State = require(script.Parent.StateController)

local C = Theme.colors
local SEGMENT = "pets"
local ROBUX = utf8.char(0xE002) -- Roblox's Robux glyph
local TABS = { "Featured", "Passes", "Potions", "Boosts", "Diamonds" }
local TAB_COLOR: { [string]: Color3 } = {
	Passes = C.grape,
	Potions = C.sky,
	Boosts = C.coral,
	Diamonds = C.skyDeep,
}

local Shop = {}

type Item = {
	key: string,
	name: string,
	description: string,
	icon: string,
	id: number,
	price: number,
	luck: boolean?,
	pass: boolean,
	tab: string,
	featured: boolean?,
}

local modal: any
local grid: ScrollingFrame
local oddsPanel: Frame
local oddsList: Frame
local oddsTitle: TextLabel
local currentTab = "Featured"
local tabButtons: { [string]: any } = {}
local livePrice: { [string]: number } = {}

local items: { Item } = {}
for _, pass in Monetization.passes do
	table.insert(items, {
		key = pass.key,
		name = pass.name,
		description = pass.description,
		icon = pass.icon,
		id = pass.id,
		price = pass.price,
		luck = pass.luck,
		pass = true,
		tab = "Passes",
		featured = pass.key == "vip" or pass.key == "luck2x",
	})
end
for _, product in Monetization.products do
	table.insert(items, {
		key = product.key,
		name = product.name,
		description = product.description,
		icon = product.icon,
		id = product.id,
		price = product.price,
		luck = product.luck,
		pass = false,
		tab = product.tab,
		featured = product.featured,
	})
end

local function restricted(): boolean
	-- unknown (not checked yet) counts as restricted: fail closed
	return (Players.LocalPlayer :: Player):GetAttribute("SFT_LuckItemsRestricted") ~= false
end

--- Fetch the live Robux price once per item (falls back to the Config price).
local function fetchPrice(item: Item)
	if item.id == 0 or livePrice[item.key] ~= nil then
		return
	end
	livePrice[item.key] = item.price
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(item.id, if item.pass then Enum.InfoType.GamePass else Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			livePrice[item.key] = info.PriceInRobux
			Shop.render()
		end
	end)
end

local function showOdds(item: Item)
	for _, child in oddsList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local profile = State.profile
	local now = os.time()
	local luck = if profile.tools then SearchMath.luck(profile, SEGMENT, now, Players.LocalPlayer) else 1
	local mult = if item.key == "serverLuck" then Monetization.serverLuckMult else Monetization.luck2xMult
	local boosted = math.min(Economy.luckCap, luck * mult)
	oddsTitle.Text = string.format("%s: luck x%.2f -> x%.2f", item.name, luck, boosted)
	local before = RollMath.probTable(luck)
	local after = RollMath.probTable(boosted)
	for order = 2, #Catalog.rarities do
		local rarity = Catalog.rarities[order]
		local function oneIn(p: number): string
			return if p > 0 then Format.oneIn(math.floor(1 / p + 0.5)) else "-"
		end
		local row = Kit.new("Frame", { Name = rarity.id, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order, Parent = oddsList })
		Kit.label(rarity.name, {
			Size = UDim2.fromScale(0.34, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Kit.readable(Color3.fromHex(rarity.color)),
			Parent = row,
		}, 1.5)
		Kit.label(oneIn(before[order]) .. "  ->  " .. oneIn(after[order]), {
			Position = UDim2.fromScale(0.34, 0),
			Size = UDim2.fromScale(0.66, 1),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		}, 1.5)
	end
	oddsPanel.Visible = true
end

local function card(item: Item, order: number)
	local color = TAB_COLOR[item.tab] or C.sky
	local frame = Kit.panel({ Name = item.key, LayoutOrder = order, BackgroundColor3 = color, Parent = grid }, UDim.new(0, 16))
	local icon = Kit.icon(item.icon, 52)
	icon.Position = UDim2.fromOffset(10, 10)
	icon.Parent = frame
	Kit.label(item.name, {
		Name = "Title",
		Position = UDim2.fromOffset(68, 10),
		Size = UDim2.new(1, -(if item.luck then 128 else 78), 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, 2)
	Kit.text(item.description, {
		Name = "Desc",
		Position = UDim2.fromOffset(68, 36),
		Size = UDim2.new(1, -78, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		FontFace = Theme.fonts.body,
		TextColor3 = C.white,
		Parent = frame,
	})
	if item.luck then
		local odds = Kit.button("Odds", "neutral", function()
			showOdds(item)
		end, { Name = "Odds", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(56, 48) })
		odds.instance.Parent = frame
	end

	local owned = item.pass and Boosts.hasPass(Players.LocalPlayer, item.key)
	local text: string
	local kind = "success"
	local enabled = true
	if owned then
		text, enabled = "Owned ✓", false
	elseif item.id == 0 then
		text, kind, enabled = "Coming soon", "neutral", false
	else
		fetchPrice(item)
		text = ROBUX .. " " .. Format.number(livePrice[item.key] or item.price)
	end
	local buy = Kit.button(text, kind, function()
		Remotes.fire(Net.Shop_Prompt, item.key)
	end, { Name = "Buy", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -20, 0, 48) })
	buy.setEnabled(enabled)
	buy.instance.Parent = frame
end

function Shop.render()
	if modal == nil or not Root.isOpen("Shop") then
		return
	end
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local hideLuck = restricted()
	local order = 0
	for _, item in items do
		local inTab = if currentTab == "Featured" then item.featured == true else item.tab == currentTab
		if inTab and not (item.luck and hideLuck) then
			order += 1
			card(item, order)
		end
	end
	for name, button in tabButtons do
		button.setColor(if name == currentTab then C.sun else C.white)
	end
end

function Shop.init()
	modal = Root.modal("Shop", "Shop", Vector2.new(720, 440))
	local tabs = Kit.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 50),
		Parent = modal.content,
	}, { Kit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left) })
	for i, name in TABS do
		local button = Kit.button(name, "neutral", function()
			currentTab = name
			oddsPanel.Visible = false
			Shop.render()
		end, { Name = name, Size = UDim2.fromOffset(124, 48), LayoutOrder = i })
		button.instance.Parent = tabs
		tabButtons[name] = button
	end
	grid = Kit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.ink,
		Parent = modal.content,
	}, {
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(216, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		Kit.padding(6),
	}) :: ScrollingFrame

	-- odds overlay for luck items
	oddsPanel = Kit.panel({
		Name = "Odds",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(380, 300),
		BackgroundColor3 = Color3.fromHex("#2B3150"),
		Visible = false,
		ZIndex = 5,
		Parent = modal.content,
	}, UDim.new(0, 16))
	oddsTitle =
		Kit.label("", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -80, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = oddsPanel }, 2)
	oddsList = Kit.new("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -28, 1, -46),
		Parent = oddsPanel,
	}, { Kit.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) }) :: Frame
	local close = Kit.button("X", "danger", function()
		oddsPanel.Visible = false
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(48, 48) })
	close.instance.Parent = oddsPanel

	modal.onOpen = Shop.render
	modal.onClose = function()
		oddsPanel.Visible = false
	end
end

function Shop.start()
	local player = Players.LocalPlayer :: Player
	player:GetAttributeChangedSignal("SFT_LuckItemsRestricted"):Connect(Shop.render)
	for _, pass in Monetization.passes do
		player:GetAttributeChangedSignal("Pass_" .. pass.key):Connect(Shop.render)
	end
end

return Shop
